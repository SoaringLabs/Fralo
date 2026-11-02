#!/usr/bin/env python3
"""Generate and check reviewed, four-language Fralo release notes. Never publish."""
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = ("en", "zh-Hans", "zh-Hant", "ja")
LANGUAGE_NAMES = ("English", "简体中文", "繁體中文", "日本語")
# Already published before this policy; new versions never inherit this exemption.
LEGACY_VERSIONS = frozenset(("0.1.0", "0.1.1", "0.2.0"))
VERSION = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
HEADINGS = {
    "added": ("New", "新增", "新增", "新機能"),
    "changed": ("Improvements", "改进", "改進", "改善"),
    "fixed": ("Fixes", "修复", "修正", "修正"),
    "breaking": ("Breaking changes", "不兼容变更", "不相容變更", "互換性に関する変更"),
    "notes": ("Notes", "注意事项", "注意事項", "注意事項"),
}
PLACEHOLDER = re.compile(r"\b(?:TODO|TBD|FIXME|TRANSLATE_ME)\b|待翻译|待翻譯|待补充|待補充|要翻訳", re.I)


def validate_version(version):
    if not isinstance(version, str) or not re.fullmatch(VERSION, version):
        raise ValueError("Expected a stable major.minor.patch release version")
    return version


def localized_text(value, label):
    if not isinstance(value, dict) or set(value) != set(LANGUAGES):
        raise ValueError(f"{label} must contain exactly: {', '.join(LANGUAGES)}")
    for language, text in value.items():
        if not isinstance(text, str) or not text.strip() or PLACEHOLDER.search(text):
            raise ValueError(f"{label}.{language} is empty or contains a placeholder")


def validate_source(source, version):
    validate_version(version)
    if not isinstance(source, dict) or set(source) != {"version", "summary", "changes", "reviewed_sha256"}:
        raise ValueError("Release source needs version, summary, changes and reviewed_sha256")
    if source["version"] != version:
        raise ValueError("Release source version differs from its filename or the application")
    localized_text(source["summary"], "summary")
    if not isinstance(source["changes"], list) or not source["changes"]:
        raise ValueError("Record at least one release change")
    ids = set()
    for change in source["changes"]:
        if not isinstance(change, dict) or set(change) != {"id", "type", "text"}:
            raise ValueError("Each change needs id, type and text")
        identifier = change["id"]
        if not isinstance(identifier, str) or not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", identifier) or identifier in ids:
            raise ValueError("Change IDs must be unique lowercase words separated by hyphens")
        ids.add(identifier)
        if not isinstance(change["type"], str) or change["type"] not in HEADINGS:
            raise ValueError(f"Unknown change type for {identifier}")
        localized_text(change["text"], identifier)
    review = source["reviewed_sha256"]
    if review is not None and (not isinstance(review, str) or not re.fullmatch(r"[0-9a-f]{64}", review)):
        raise ValueError("reviewed_sha256 must be null or a SHA-256 digest")


def content_digest(source):
    content = {key: value for key, value in source.items() if key != "reviewed_sha256"}
    reviewed = {"source": content, "generated": generated_files(source)}
    return hashlib.sha256(json.dumps(reviewed, ensure_ascii=False, sort_keys=True).encode()).hexdigest()


def read_source(directory, version):
    validate_version(version)
    path = directory / f"v{version}.json"
    source = json.loads(path.read_text(encoding="utf-8"))
    validate_source(source, version)
    return source


def render_notes(source):
    """Every language renders the same ordered IDs, sections and version."""
    validate_source(source, source.get("version"))
    notes = {}
    for index, language in enumerate(LANGUAGES):
        lines = [f"# Fralo {source['version']}", "", source["summary"][language].strip()]
        for kind, headings in HEADINGS.items():
            changes = [change for change in source["changes"] if change["type"] == kind]
            if changes:
                lines.extend(("", f"## {headings[index]}", ""))
                for change in changes:
                    text = change["text"][language].strip().replace("\n", "\n  ")
                    lines.append(f"- {text}")
        notes[language] = "\n".join(lines) + "\n"
    return notes


def generated_files(source):
    version = source["version"]
    notes = render_notes(source)
    files = {f"v{version}.{language}.md": text for language, text in notes.items()}
    body = [f"# Fralo {version}"]
    for language, name in zip(LANGUAGES, LANGUAGE_NAMES):
        text = notes[language].split("\n", 2)[2].strip()
        text = re.sub(r"^## ", "### ", text, flags=re.M)
        body.extend((f"## {name}", text))
    files[f"v{version}.md"] = "\n\n".join(body) + "\n"
    return files


def check_generated(directory, source):
    for name, expected in generated_files(source).items():
        path = directory / name
        if not path.is_file() or path.read_bytes() != expected.encode("utf-8"):
            raise ValueError(f"Missing or stale generated notes: {name}; run release_notes.py render {source['version']}")


def check_release(directory, version):
    source = read_source(directory, version)
    check_generated(directory, source)
    if source["reviewed_sha256"] != content_digest(source):
        raise ValueError("Notes need review for the current content; proofread all four languages, then run mark-reviewed")
    return render_notes(source)


def check_all(directory, current_version):
    versions = {validate_version(current_version)}
    for path in directory.glob("v*.*"):
        if path.suffix not in {".json", ".md"}:
            continue
        match = re.fullmatch(rf"v({VERSION})(?:\.(?:en|zh-Hans|zh-Hant|ja))?\.(?:json|md)", path.name)
        if not match:
            raise ValueError(f"Unexpected release notes filename: {path.name}")
        versions.add(match[1])
    checked = 0
    for version in sorted(versions):
        has_source = (directory / f"v{version}.json").exists()
        has_localized = any((directory / f"v{version}.{language}.md").exists() for language in LANGUAGES)
        if version in LEGACY_VERSIONS and not has_source and not has_localized:
            continue
        check_release(directory, version)
        checked += 1
    return checked


def current_version():
    source = (ROOT / "Sources/FraloCore/FraloInfo.swift").read_text(encoding="utf-8")
    return re.search(r'public static let version = "([^"]+)"', source)[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("new", "render", "mark-reviewed", "check", "check-all"))
    parser.add_argument("version", nargs="?")
    parser.add_argument("--directory", type=Path, default=ROOT / "release")
    args = parser.parse_args()
    try:
        if args.command == "check-all":
            if args.version:
                raise ValueError("check-all reads the current application version automatically")
            checked = check_all(args.directory, current_version())
            print(f"Release notes checks passed: {checked} four-language releases; published legacy versions preserved.")
            return
        version = validate_version(args.version)
        path = args.directory / f"v{version}.json"
        if args.command == "new":
            source = {"version": version, "summary": dict.fromkeys(LANGUAGES, ""), "changes": [
                {"id": "change-1", "type": "fixed", "text": dict.fromkeys(LANGUAGES, "")}
            ], "reviewed_sha256": None}
            args.directory.mkdir(parents=True, exist_ok=True)
            with path.open("x", encoding="utf-8") as file:
                file.write(json.dumps(source, ensure_ascii=False, indent=2) + "\n")
            print(f"Created {path}. Fill the shared changes and all translations before rendering.")
            return
        source = read_source(args.directory, version)
        if args.command == "render":
            for name, text in generated_files(source).items():
                (args.directory / name).write_text(text, encoding="utf-8")
            print("Generated four localized Markdown files and one multilingual GitHub Release body.")
        elif args.command == "mark-reviewed":
            check_generated(args.directory, source)
            source["reviewed_sha256"] = content_digest(source)
            path.write_text(json.dumps(source, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            print("Recorded proofreading for this exact content. Further content edits invalidate it.")
        else:
            check_release(args.directory, version)
            print(f"Reviewed four-language release notes verified: {version}")
    except (ValueError, OSError) as error:
        parser.exit(1, f"release notes: {error}\n")


if __name__ == "__main__":
    main()
