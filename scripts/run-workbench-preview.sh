#!/bin/bash
set -euo pipefail

# Always builds Debug, with a separate bundle identity and isolated settings.
project_root="$(cd "$(dirname "$0")/.." && pwd)"
build_only=false
if [[ "${1:-}" == "--build-only" ]]; then build_only=true; shift; fi
swift build --package-path "$project_root" --product FraloApp
binary_directory="$(swift build --package-path "$project_root" --show-bin-path)"
preview_bundle="$(python3 - "$project_root" "$binary_directory" <<'PY'
from pathlib import Path
import plistlib, shutil, subprocess, sys, tempfile
root, binary = map(Path, sys.argv[1:])
parent = root / '.build/workbench-preview'
parent.mkdir(parents=True, exist_ok=True)
session = Path(tempfile.mkdtemp(prefix='session-', dir=parent))
app = session / 'Fralo Workbench Preview.app'
executables = app / 'Contents/MacOS'
resources = app / 'Contents/Resources'
executables.mkdir(parents=True)
resources.mkdir(parents=True)
shutil.copy2(binary / 'FraloApp', executables / 'FraloApp')
frameworks = list((root / '.build/artifacts').rglob('Sparkle.framework'))
if len(frameworks) != 1:
    raise SystemExit('Expected exactly one resolved Sparkle.framework')
shutil.copytree(frameworks[0], app / 'Contents/Frameworks/Sparkle.framework', symlinks=True)
shutil.copytree(root / 'Sources/FraloApp/Development/Fixtures', resources / 'DesignLabFixtures')
shutil.copytree(binary / 'Fralo_FraloCore.bundle', resources / 'Fralo_FraloCore.bundle')
info = {
    'CFBundleName': 'Fralo Workbench Preview', 'CFBundleDisplayName': 'Fralo Workbench Preview',
    'CFBundleIdentifier': 'app.fralo.workbench.local', 'CFBundleExecutable': 'FraloApp',
    'CFBundlePackageType': 'APPL', 'NSPrincipalClass': 'NSApplication',
    'NSHighResolutionCapable': True, 'LSMinimumSystemVersion': '14.0',
    'CFBundleVersion': '1', 'CFBundleShortVersionString': '0.1',
    'CFBundleDevelopmentRegion': 'zh_CN',
}
with (app / 'Contents/Info.plist').open('wb') as file:
    plistlib.dump(info, file)
subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(app)], check=True, stdout=subprocess.DEVNULL)
print(app)
PY
)"
printf '%s\n' "$preview_bundle"
if $build_only; then exit 0; fi
settings_directory="$(mktemp -d "${TMPDIR:-/tmp}/fralo-workbench.XXXXXX")"
exec env FRALO_SETTINGS_PATH="$settings_directory/settings.json" \
  "$preview_bundle/Contents/MacOS/FraloApp" --workbench-preview "$@"
