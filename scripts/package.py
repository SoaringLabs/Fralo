#!/usr/bin/env python3
"""Build the native App + shared-core CLI and optionally an installation DMG."""
from pathlib import Path
import argparse
import hashlib
import plistlib
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
IDENTITY_SOURCE = (ROOT / "Sources/FraloCore/FraloInfo.swift").read_text()


def identity(key):
    match = re.search(r'public static let ' + re.escape(key) + r' = "([^"\n]+)"', IDENTITY_SOURCE)
    if not match:
        raise ValueError(f"Missing release identity: {key}")
    return match.group(1)


VERSION = identity("version")


def run(*args):
    subprocess.run(args, cwd=ROOT, check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--configuration", choices=("debug", "release"), default="release")
    parser.add_argument("--dmg", action="store_true")
    parser.add_argument("--sign", metavar="IDENTITY",
                        help="Developer ID Application certificate name or SHA-1 fingerprint")
    args = parser.parse_args()
    signing_identity = "-"
    if args.sign:
        identities = subprocess.check_output(
            ["security", "find-identity", "-v", "-p", "codesigning"], text=True)
        matches = [(fingerprint, name) for fingerprint, name in
                   re.findall(r'\b([A-Fa-f0-9]{40}) "([^"]+)"', identities)
                   if name.startswith("Developer ID Application: ")
                   and args.sign in (fingerprint, name)]
        if len(matches) != 1:
            parser.error("--sign must match one valid Developer ID Application identity exactly")
        signing_identity = matches[0][0]
    if args.dmg:
        try:
            import dmgbuild
        except ImportError:
            parser.error("DMG layout requires dmgbuild. Run: python3 -m venv .venv; "
                         ".venv/bin/python -m pip install -r scripts/requirements-dmg.txt; "
                         "then use .venv/bin/python scripts/package.py --dmg")
    run("swift", "build", "--build-system", "native", "-c", args.configuration)
    binary_dir = Path(subprocess.check_output(["swift", "build", "--build-system", "native", "-c", args.configuration, "--show-bin-path"], cwd=ROOT, text=True).strip())
    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    app = dist / "Fralo.app"
    with tempfile.TemporaryDirectory(prefix="fralo-package-") as temporary:
        staged = Path(temporary) / "Fralo.app"
        executables = staged / "Contents/MacOS"
        resources = staged / "Contents/Resources"
        executables.mkdir(parents=True)
        resources.mkdir(parents=True)
        shutil.copy2(binary_dir / "FraloApp", executables / "FraloApp")
        shutil.copy2(binary_dir / "fralo", executables / "fralo")
        shutil.copytree(binary_dir / "Fralo_FraloCore.bundle", resources / "Fralo_FraloCore.bundle")
        shutil.copytree(binary_dir / "Fralo_FraloApp.bundle", resources / "Fralo_FraloApp.bundle")
        frameworks = list((ROOT / ".build/artifacts").rglob("Sparkle.framework"))
        if len(frameworks) != 1:
            raise RuntimeError("Expected one resolved Sparkle.framework in .build/artifacts")
        sparkle = staged / "Contents/Frameworks/Sparkle.framework"
        shutil.copytree(frameworks[0], sparkle, symlinks=True)
        # Fralo is not sandboxed; Sparkle's optional XPC services are unnecessary.
        shutil.rmtree(sparkle / "Versions/B/XPCServices")
        # Compile the layered Icon Composer document, including the .icns fallback.
        icon_info = Path(temporary) / "icon-info.plist"
        run("xcrun", "actool", str(ROOT / "Resources/Fralo.icon"),
            "--compile", str(resources), "--platform", "macosx",
            "--minimum-deployment-target", "14.0", "--app-icon", "Fralo",
            "--output-partial-info-plist", str(icon_info),
            "--output-format", "human-readable-text")
        info = {
            "CFBundleName": "Fralo",
            "CFBundleDisplayName": "Fralo",
            "CFBundleIdentifier": "app.fralo.desktop",
            "CFBundleExecutable": "FraloApp",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": VERSION,
            "CFBundleVersion": identity("build"),
            "LSMinimumSystemVersion": "14.0",
            "NSHighResolutionCapable": True,
            "NSPrincipalClass": "NSApplication",
            "NSHumanReadableCopyright": identity("copyright"),
            "CFBundleDevelopmentRegion": "zh_CN",
            "CFBundleLocalizations": ["zh_CN"],
            "SUFeedURL": identity("updateFeed"),
            "SUPublicEDKey": identity("updatePublicKey"),
            "SUEnableAutomaticChecks": True,
            "SUScheduledCheckInterval": 86400,
            "SUAutomaticallyUpdate": False,
            "SUAllowsAutomaticUpdates": False,
            "SUEnableSystemProfiling": False,
            "SUVerifyUpdateBeforeExtraction": True,
            "CFBundleDocumentTypes": [{
                "CFBundleTypeName": "Screenshot Image",
                "CFBundleTypeRole": "Viewer",
                "LSHandlerRank": "Alternate",
                "LSItemContentTypes": ["public.png", "public.jpeg"],
            }],
        }
        info.update(plistlib.loads(icon_info.read_bytes()))
        (staged / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        for filename in ("LICENSE", "INSTALL.md", "AUTHORS.md"):
            shutil.copy2(ROOT / filename, resources / filename)
        shutil.copy2(ROOT / ".build/artifacts/sparkle/Sparkle/LICENSE", resources / "Sparkle-LICENSE")
        signing_options = ["--options", "runtime", "--timestamp"] if args.sign else []
        # Sign the update helper before its enclosing framework and application.
        for code in (sparkle / "Versions/B/Autoupdate", sparkle / "Versions/B/Updater.app", sparkle):
            run("codesign", "--force", "--sign", signing_identity, *signing_options, str(code))
        # Sign nested code first; the bundle signing pass covers FraloApp.
        run("codesign", "--force", "--sign", signing_identity, *signing_options,
            str(executables / "fralo"))
        run("codesign", "--force", "--sign", signing_identity, *signing_options, str(staged))
        if app.exists():
            shutil.rmtree(app)
        shutil.copytree(staged, app, symlinks=True)
    # The App signing pass can update the embedded executable's signature.
    # Ship exactly that signed CLI in both locations.
    shutil.copy2(app / "Contents/MacOS/fralo", dist / "fralo")
    run("codesign", "--verify", "--deep", "--strict", str(app))
    print(f"App: {app}")
    print(f"CLI: {dist / 'fralo'}")
    if args.dmg:
        architecture = subprocess.check_output(["uname", "-m"], text=True).strip()
        dmg = dist / f"Fralo-{VERSION}-{architecture}.dmg"
        with tempfile.TemporaryDirectory(prefix="fralo-dmg-") as temporary:
            background = Path(temporary) / "background.tiff"
            run("swift", str(ROOT / "scripts/generate-dmg-background.swift"), str(background))
            candidate = Path(temporary) / dmg.name
            dmgbuild.build_dmg(str(candidate), "Fralo", settings={
                "format": "UDZO", "filesystem": "HFS+",
                "files": [str(app)],
                "symlinks": {"Applications": "/Applications"},
                # Keep the signed bundle's FinderInfo untouched; Finder hides .app normally.
                "background": str(background),
                "default_view": "icon-view",
                # Leave room for Finder chrome around the 660 x 400 artwork.
                "window_rect": ((200, 200), (660, 460)),
                "icon_locations": {"Fralo.app": (180, 219), "Applications": (480, 219)},
                "icon_size": 128, "text_size": 15, "label_pos": "bottom",
                "grid_spacing": 80,
                "show_status_bar": False, "show_tab_view": False,
                "show_toolbar": False, "show_pathbar": False, "show_sidebar": False,
            })
            shutil.copy2(candidate, dmg)
        if args.sign:
            run("codesign", "--force", "--sign", signing_identity, "--timestamp", str(dmg))
            run("codesign", "--verify", "--strict", str(dmg))
        checksum = dist / "SHA256SUMS.txt"
        checksum.write_text(f"{hashlib.sha256(dmg.read_bytes()).hexdigest()}  {dmg.name}\n")
        print(f"DMG: {dmg}")
        print(f"Checksums: {checksum}")


if __name__ == "__main__":
    main()
