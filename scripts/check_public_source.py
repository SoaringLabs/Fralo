#!/usr/bin/env python3
"""Check the Git publication candidate without reading ignored private files."""
from pathlib import Path
import re
import subprocess
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]
paths = subprocess.check_output(
    ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=ROOT
).decode().split("\0")
paths = sorted(set(path for path in paths if path))
errors = []
private_prefixes = (".build/", ".swiftpm/", "dist/", "artifacts/", "design/", "docs/adr/")
private_files = {
    "CONTEXT.md", "design-qa.md", "docs/product-brief.md",
    "docs/implementation-plan.md", "docs/functional-scope.md", "docs/ui-guidelines.md",
    "scripts/compare-design.swift", "scripts/read-pasteboard.swift", "scripts/verify-pixels.swift",
}
secret = re.compile(
    r"gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|"
    r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"
)
personal_path = re.compile(r"/(?:Users|home)/[^/\s]+/")
for name in paths:
    path = ROOT / name
    if name.startswith(private_prefixes) or name in private_files or Path(name).name.startswith(".env"):
        errors.append(f"Private or generated file in publication candidate: {name}")
    if path.stat().st_size > 10 * 1024 * 1024:
        errors.append(f"File larger than 10 MiB: {name}")
    if path.suffix in {".md", ".swift", ".py", ".yml", ".yaml", ".json", ".html"}:
        content = path.read_text()
        # Authored project rules are public; generated personal memory stays private.
        if name == "AGENTS.md" and "<claude-mem-context>" in content:
            errors.append("Generated private memory in project rules: AGENTS.md")
        if secret.search(content) or personal_path.search(content):
            errors.append(f"Secret-like value or personal absolute path: {name}")
        if path.suffix == ".md":
            for target in re.findall(r"!?\[[^\]]*\]\(([^)\s]+)\)", content):
                if target.startswith(("https://", "http://", "#", "mailto:")):
                    continue
                local = (path.parent / unquote(target.split("#")[0])).resolve()
                if not local.exists():
                    errors.append(f"Broken local Markdown link in {name}: {target}")
                elif local.is_relative_to(ROOT) and local.is_file() and str(local.relative_to(ROOT)) not in paths:
                    errors.append(f"Markdown link points outside publication candidate in {name}: {target}")
for required in ("README.md", "LICENSE", "AUTHORS.md", "INSTALL.md", "CONTRIBUTING.md",
                 "CHANGELOG.md", ".github/workflows/ci.yml", "release/v0.1.0.md"):
    if required not in paths:
        errors.append(f"Missing public file: {required}")
if errors:
    raise SystemExit("\n".join(errors))
print(f"Public source checks passed: {len(paths)} files, "
      f"{sum((ROOT / name).stat().st_size for name in paths):,} bytes.")
print("This checks the current source candidate, not Git history or image contents.")
