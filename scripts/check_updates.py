#!/usr/bin/env python3
"""Read-only, on-demand dependency/toolchain report. Python 3.10+, stdlib only."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from html.parser import HTMLParser
from http.client import HTTPException
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SWIFT_RELEASES = "https://www.swift.org/api/v1/install/releases.json"
APPLE_RELEASES = "https://developer.apple.com/news/releases/rss/releases.rss"
XCODE_SUPPORT = "https://developer.apple.com/support/xcode/"
LABELS = {"update": "有新版", "current": "版本一致", "ahead": "当前版本较新",
          "review": "需核对", "error": "检测失败"}


def version(value):
    """Only final numeric releases; never treat beta/RC/dev as a stable version."""
    match = re.fullmatch(r"v?(\d+(?:\.\d+)*)", value)
    if not match:
        raise ValueError(f"无法识别稳定版本号：{value}")
    parts = [int(part) for part in match[1].split(".")]
    while len(parts) > 1 and parts[-1] == 0:
        parts.pop()
    return tuple(parts)


def is_stable(value):
    try:
        version(value)
        return True
    except ValueError:
        return False


def comparison(current, latest):
    old, new = version(current), version(latest)
    return "update" if old < new else "ahead" if old > new else "current"


def python_version(value):
    """PyPI's normalized final versions may also contain an epoch or post release."""
    match = re.fullmatch(r"(?:(\d+)!)?(\d+(?:\.\d+)*)(?:\.post(\d+))?", value)
    if not match:
        raise ValueError(f"非受支持的 Python 稳定版本：{value}")
    return int(match[1] or 0), version(match[2]), int(match[3]) if match[3] is not None else -1


class Client:
    def __init__(self, timeout):
        self.timeout = timeout

    def get(self, url, *, as_json=True):
        headers = {"User-Agent": "Fralo-Update-Check/1.0"}
        if url.startswith("https://api.github.com/"):
            headers["Accept"] = "application/vnd.github+json"
            token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
            if token:
                headers["Authorization"] = f"Bearer {token}"
        try:
            with urlopen(Request(url, headers=headers), timeout=self.timeout) as response:
                content = response.read().decode("utf-8")
            return json.loads(content) if as_json else content
        except HTTPError as exc:
            hint = "；GitHub 可能限流，可设置 GITHUB_TOKEN 后重试" if exc.code in (403, 429) and "api.github.com" in url else ""
            raise ValueError(f"HTTP {exc.code}{hint}：{url}") from None
        except (URLError, TimeoutError, HTTPException, UnicodeError, json.JSONDecodeError) as exc:
            # Do not include request headers, tokens, or server response bodies.
            raise ValueError(f"请求或解析失败（{type(exc).__name__}）：{url}") from None


def result(name, current, latest, source, *, note="", **extra):
    return dict(name=name, current=current, latest=latest, status=comparison(current, latest),
                source=source, note=note, **extra)


def checked(name, operation):
    try:
        return operation()
    except (ValueError, OSError, KeyError, TypeError, IndexError, AttributeError, ET.ParseError,
            subprocess.SubprocessError) as exc:
        return dict(name=name, status="error", error=str(exc))


def github_repo(url):
    match = re.fullmatch(r"https://github\.com/([\w.-]+/[\w.-]+?)(?:\.git)?/?", url)
    if not match:
        raise ValueError(f"暂不支持此 Swift 包来源：{url}")
    return match[1]


def github_latest(client, repo):
    release = client.get(f"https://api.github.com/repos/{repo}/releases/latest")
    if release.get("draft") or release.get("prerelease"):
        raise ValueError(f"上游 latest 不是稳定版本：{repo}")
    tag = release["tag_name"]
    version(tag)
    return tag, release["html_url"]


def check_package(client, pin):
    current = pin["state"]["version"]
    latest, source = github_latest(client, github_repo(pin["location"]))
    return result(pin["identity"], current, latest, source, category="swift-package")


def check_python(client, name, current):
    data = client.get(f"https://pypi.org/pypi/{quote(name, safe='')}/json")
    candidates = []
    for number, files in data["releases"].items():
        try:
            python_version(number)
        except ValueError:
            continue
        if any(not item.get("yanked", False) for item in files):
            candidates.append(number)
    if not candidates:
        raise ValueError(f"PyPI 未返回可用的稳定版：{name}")
    latest = max(candidates, key=python_version)
    requirements = sorted({item["requires_python"] for item in data["releases"][latest]
                           if not item.get("yanked", False) and item.get("requires_python")})
    old, new = python_version(current), python_version(latest)
    state = "update" if old < new else "ahead" if old > new else "current"
    return dict(name=name, current=current, latest=latest, status=state,
                source=f"https://pypi.org/project/{name}/{latest}/", category="python-build",
                note="仅打包工具；新版 Python 要求：" + (" / ".join(requirements) or "未声明"))


def check_action(client, repo, ref, locations):
    latest, source = github_latest(client, repo)
    # Resolve against the actual pinned commit, not the human-written version comment.
    diff = client.get(f"https://api.github.com/repos/{repo}/compare/{quote(latest, safe='')}...{quote(ref, safe='')}?per_page=1")
    state = {"identical": "current", "behind": "update", "ahead": "ahead",
             "diverged": "review"}.get(diff["status"])
    if state is None:
        raise ValueError(f"GitHub 返回未知提交关系：{diff['status']}")
    return dict(name=repo, current=ref, latest=latest, status=state, source=source,
                category="github-action", locations=locations,
                note="按固定提交与上游稳定标签的历史关系判断；分叉历史需人工核对")


class Tables(HTMLParser):
    def __init__(self):
        super().__init__()
        self.rows, self.row, self.cell = [], None, None

    def handle_starttag(self, tag, attrs):
        if tag == "tr":
            self.row = []
        elif tag in ("td", "th") and self.row is not None:
            self.cell = []
        elif tag == "br" and self.cell is not None:
            self.cell.append(" ")

    def handle_data(self, data):
        if self.cell is not None:
            self.cell.append(data)

    def handle_endtag(self, tag):
        if tag in ("td", "th") and self.cell is not None:
            self.row.append(" ".join("".join(self.cell).split()))
            self.cell = None
        elif tag == "tr" and self.row is not None:
            self.rows.append(self.row)
            self.row = None


def apple_latest(client):
    feed = ET.fromstring(client.get(APPLE_RELEASES, as_json=False))
    releases = []
    for item in feed.findall("./channel/item"):
        # Full title match excludes beta, RC, and other preview releases.
        match = re.fullmatch(r"Xcode (\d+(?:\.\d+)*)(?: \([\w.]+\))?", item.findtext("title", "").strip())
        if match:
            published = parsedate_to_datetime(item.findtext("pubDate", ""))
            if published <= datetime.now(timezone.utc):
                releases.append((match[1], item.findtext("link", "")))
    if not releases:
        raise ValueError("Apple RSS 中没有稳定版 Xcode；需要核对官方发布源")
    latest, source = max(releases, key=lambda item: version(item[0]))
    return latest, source


def apple_sdk(client, xcode):
    parser = Tables()
    parser.feed(client.get(XCODE_SUPPORT, as_json=False))
    for row in parser.rows:
        if len(row) >= 3 and row[0] == f"Xcode {xcode}":
            match = re.search(r"\bmacOS (\d+(?:\.\d+)*)\b", row[2])
            if match:
                return match[1]
    raise ValueError(f"Apple SDK 表中找不到稳定版 Xcode {xcode} 对应的 macOS SDK")


def command(args):
    run = subprocess.run(args, capture_output=True, text=True, timeout=20, check=False)
    if run.returncode:
        raise ValueError(f"本地工具读取失败：{' '.join(args)}（退出码 {run.returncode}）")
    return run.stdout.strip()


def local_version(args, pattern):
    output = command(args)
    match = re.search(pattern, output)
    if not match:
        raise ValueError(f"无法解析本地工具版本：{' '.join(args)}")
    return match[1]


def check_swift(client):
    current = local_version(["xcrun", "swift", "--version"], r"Swift version (\d+(?:\.\d+)*)")
    releases = client.get(SWIFT_RELEASES)
    stable = [item for item in releases if is_stable(item["name"])
              and item.get("tag", "").endswith("-RELEASE")
              and item["date"] <= datetime.now(timezone.utc).date().isoformat()]
    if not stable:
        raise ValueError("Swift 官方接口未返回稳定版")
    latest = max(stable, key=lambda item: version(item["name"]))
    return result("Swift 编译器（本机 / 上游）", current, latest["name"],
                  "https://www.swift.org/download/", category="toolchain",
                  note="Apple Swift 与上游 Swift 分别发布，此处仅提示版本差异；语言模式迁移需另行决定",
                  metadata_source=SWIFT_RELEASES, release_date=latest["date"])


def check_xcode(client, ci_versions):
    latest, source = apple_latest(client)
    rows = [checked("Xcode（本机）", lambda: result(
        "Xcode（本机）", local_version(["xcodebuild", "-version"], r"Xcode (\d+(?:\.\d+)*)"),
        latest, source, category="toolchain"))]
    for current, locations in sorted(ci_versions.items()):
        rows.append(result("Xcode（CI 配置）", current, latest, source, category="toolchain",
                           locations=locations, note="读取工作流中固定的 Xcode 路径；未执行远程 runner"))
    rows.append(checked("macOS SDK（本机）", lambda: result(
        "macOS SDK（本机）", local_version(["xcrun", "--sdk", "macosx", "--show-sdk-version"], r"^(\d+(?:\.\d+)*)$"),
        apple_sdk(client, latest), XCODE_SUPPORT, category="toolchain",
        note=f"比较稳定版 Xcode {latest} 随附的 SDK；不改变最低系统要求")))
    return rows


def inventory(root):
    manifest = (root / "Package.swift").read_text()
    tools = re.search(r"//\s*swift-tools-version:\s*([\d.]+)", manifest)
    if not tools:
        raise ValueError("Package.swift 缺少 swift-tools-version")
    minimum = re.search(r"\.macOS\(\.v(\d+(?:_\d+)*)\)", manifest)
    modes = re.findall(r"swiftLanguage(?:Modes|Versions)\s*:\s*\[([^\]]+)\]|\.swiftLanguageMode\(([^)]+)\)", manifest)
    context = dict(swift_tools_version=tools[1], minimum_macos=minimum[1].replace("_", ".") if minimum else "未识别",
                   swift_language_mode="; ".join(a or b for a, b in modes) if modes else
                   f"未显式指定；tools version 默认 Swift {'6' if version(tools[1]) >= (6,) else '5'}")
    declared = re.findall(r'\.package\(\s*url:\s*"([^"]+)"', manifest)
    pins = json.loads((root / "Package.resolved").read_text())["pins"] if declared else []
    normalized = lambda url: url.removesuffix("/").removesuffix(".git")
    locations = {normalized(pin["location"]) for pin in pins}
    if any(normalized(url) not in locations for url in declared):
        raise ValueError("Package.swift 的依赖尚未完整记录在 Package.resolved 中")
    for url, exact in re.findall(r'\.package\(\s*url:\s*"([^"]+)"\s*,\s*exact:\s*"([^"]+)"', manifest):
        pin = next(pin for pin in pins if normalized(pin["location"]) == normalized(url))
        if pin["state"].get("version") != exact:
            raise ValueError(f"Package.swift 与 Package.resolved 的固定版本不一致：{url}")
    requirements = []
    for line in (root / "scripts/requirements-dmg.txt").read_text().splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            match = re.fullmatch(r"([\w.-]+)==([^\s]+)", line)
            if not match:
                raise ValueError(f"暂不支持此 Python 版本声明：{line}")
            python_version(match[2])
            requirements.append((match[1], match[2]))
    actions, ci = {}, {}
    for path in sorted((root / ".github/workflows").glob("*")):
        if path.suffix not in (".yml", ".yaml"):
            continue
        for number, line in enumerate(path.read_text().splitlines(), 1):
            location = f"{path.relative_to(root)}:{number}"
            use = re.match(r"\s*(?:-\s*)?uses:\s*['\"]?([^\s'\"#]+)", line)
            if use and not use[1].startswith("./"):
                match = re.fullmatch(r"([\w.-]+/[\w.-]+)(?:/[\w./-]+)?@([\w./-]+)", use[1])
                if not match:
                    raise ValueError(f"暂不支持此工作流依赖：{use[1]}（{location}）")
                actions.setdefault((match[1], match[2]), []).append(location)
            for xcode in re.findall(r"/Applications/Xcode_([\d.]+)\.app", line.split("#", 1)[0]):
                ci.setdefault(xcode, []).append(location)
    return context, pins, requirements, actions, ci


def report(root, client):
    context, pins, requirements, actions, ci = inventory(root)
    jobs = [(pin["identity"], lambda pin=pin: check_package(client, pin)) for pin in pins]
    jobs += [(name, lambda name=name, current=current: check_python(client, name, current)) for name, current in requirements]
    jobs += [(repo, lambda repo=repo, ref=ref, locations=locations: check_action(client, repo, ref, locations))
             for (repo, ref), locations in actions.items()]
    jobs += [("Swift 编译器", lambda: check_swift(client)), ("Xcode / SDK", lambda: check_xcode(client, ci))]
    with ThreadPoolExecutor(max_workers=6) as pool:
        outcomes = list(pool.map(lambda job: checked(*job), jobs))
    checks = [row for outcome in outcomes for row in (outcome if isinstance(outcome, list) else [outcome])]
    counts = {state: sum(row["status"] == state for row in checks) for state in LABELS}
    return dict(checked_at=datetime.now(timezone.utc).isoformat(timespec="seconds"),
                repository=str(root), context=context, checks=checks, summary=counts,
                complete=not counts["error"] and not counts["review"])


def render(data):
    print(f"Fralo 手动更新检测 · {data['checked_at']}")
    context = data["context"]
    print(f"包工具要求 {context['swift_tools_version']}；最低 macOS {context['minimum_macos']}；语言模式：{context['swift_language_mode']}")
    print("以上为项目配置，不作为待升级依赖。只查询稳定发布，不安装、不构建、不修改文件。\n")
    for row in data["checks"]:
        print(f"[{LABELS[row['status']]}] {row['name']}")
        if row["status"] == "error":
            print(f"  {row['error']}")
            continue
        print(f"  当前 {row['current']} → 上游稳定版 {row['latest']}")
        print(f"  来源 / 发布说明：{row['source']}")
        if row.get("note"):
            print(f"  {row['note']}")
        if row.get("locations"):
            print(f"  配置位置：{', '.join(row['locations'])}")
    counts = data["summary"]
    print(f"\n有新版 {counts['update']} 项；版本一致 {counts['current']} 项；当前较新 {counts['ahead']} 项；需核对 {counts['review']} 项；失败 {counts['error']} 项。")
    if not data["complete"]:
        print("检测未完整确认，不能据此判断所有依赖均为最新。")
    print("是否升级由维护者决定。")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=ROOT, help="Fralo checkout (default: script's repository)")
    parser.add_argument("--json", action="store_true", help="JSON output for agent consumption")
    parser.add_argument("--timeout", type=float, default=15, help="per-request timeout in seconds (default: 15)")
    args = parser.parse_args(argv)
    if not 0 < args.timeout <= 120:
        parser.error("--timeout must be between 0 and 120 seconds")
    try:
        data = report(args.repo.resolve(), Client(args.timeout))
    except (ValueError, OSError, KeyError, TypeError) as exc:
        if args.json:
            print(json.dumps(dict(complete=False, error=str(exc)), ensure_ascii=False))
        else:
            print(f"检测失败：{exc}", file=sys.stderr)
        return 2
    if args.json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
    else:
        render(data)
    return 0 if data["complete"] else 2


if __name__ == "__main__":
    sys.exit(main())
