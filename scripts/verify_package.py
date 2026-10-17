#!/usr/bin/env python3
"""Verify a local DMG against dist without changing security settings."""
from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    return subprocess.check_output(args, cwd=ROOT, stderr=subprocess.PIPE)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def manifest(directory):
    return {str(path.relative_to(directory)): digest(path)
            for path in directory.rglob("*") if path.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=ROOT / "artifacts/pre-release/package-verification.json")
    parser.add_argument("--require-notarized", action="store_true",
                        help="Require Developer ID, hardened runtime, timestamps, ticket and Gatekeeper acceptance")
    args = parser.parse_args()
    try:
        from ds_store import DSStore
    except ImportError:
        parser.error("Use .venv/bin/python after installing scripts/requirements-dmg.txt")
    identity = dict(re.findall(r'public static let (\w+) = "([^"]+)"',
                              (ROOT / "Sources/FraloCore/FraloInfo.swift").read_text()))
    dist = ROOT / "dist"
    version = identity["version"]
    architecture = run("uname", "-m").decode().strip()
    dmg = dist / f"Fralo-{version}-{architecture}.dmg"
    expected_checksum = (dist / "SHA256SUMS.txt").read_text().strip()
    assert expected_checksum == f"{digest(dmg)}  {dmg.name}"
    run("hdiutil", "verify", str(dmg))
    mounted = plistlib.loads(run("hdiutil", "attach", "-readonly", "-nobrowse", "-plist", str(dmg)))
    entity = next(item for item in mounted["system-entities"] if "mount-point" in item)
    volume = Path(entity["mount-point"])
    try:
        app = volume / "Fralo.app"
        assert manifest(app) == manifest(dist / "Fralo.app"), "Mounted App differs from dist"
        visible = sorted(path.name for path in volume.iterdir() if not path.name.startswith("."))
        assert visible == ["Applications", "Fralo.app"], visible
        assert (volume / ".DS_Store").is_file(), "Missing saved Finder layout"
        assert any(path.name.startswith(".background") for path in volume.iterdir()), "Missing installer background"
        background = volume / ".background.tiff"
        dimensions = run("sips", "-g", "pixelWidth", "-g", "pixelHeight", str(background)).decode()
        assert re.search(r"pixelWidth: 1320\b", dimensions)
        assert re.search(r"pixelHeight: 800\b", dimensions)
        with DSStore.open(str(volume / ".DS_Store"), "r") as layout:
            assert layout["Fralo.app"]["Iloc"] == (180, 219)
            assert layout["Applications"]["Iloc"] == (480, 219)
            window = layout["."]["bwsp"]
            view = layout["."]["icvp"]
            assert window["WindowBounds"] == "{{200, 200}, {660, 460}}"
            assert not any(window[key] for key in ("ShowStatusBar", "ShowToolbar", "ShowSidebar", "ShowPathbar"))
            assert view["iconSize"] == 128 and view["backgroundType"] == 2
            assert view["gridSpacing"] < 100, "Finder rejects larger grid spacing"
        assert digest(dist / "fralo") == digest(app / "Contents/MacOS/fralo")
        for name in ("INSTALL.md", "AUTHORS.md", "LICENSE"):
            assert digest(app / "Contents/Resources" / name) == digest(ROOT / name)
        assert (volume / "Applications").is_symlink()
        assert (volume / "Applications").readlink() == Path("/Applications")
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        assert info["CFBundleShortVersionString"] == version
        assert info["CFBundleVersion"] == identity["build"]
        assert info["NSHumanReadableCopyright"] == identity["copyright"]
        for name in ("Assets.car", "Fralo.icns"):
            assert (app / "Contents/Resources" / name).stat().st_size > 0
        run("codesign", "--verify", "--deep", "--strict", str(app))
        signing = subprocess.run(["codesign", "-dv", "--verbose=2", str(app)],
                                 check=True, capture_output=True, text=True).stderr
        developer_id = "Authority=Developer ID Application: " in signing
        team = None
        dmg_assessment_output = None
        if args.require_notarized:
            assert developer_id, "Expected Developer ID Application signature"
        else:
            assert developer_id or "Signature=adhoc" in signing
        if developer_id:
            team = re.search(r"^TeamIdentifier=(\w+)$", signing, re.MULTILINE).group(1)
            for code in (app, app / "Contents/MacOS/fralo", dist / "fralo"):
                run("codesign", "--verify", "--strict", str(code))
                details = subprocess.run(["codesign", "-dv", "--verbose=2", str(code)],
                                         check=True, capture_output=True, text=True).stderr
                assert "Authority=Developer ID Application: " in details
                assert f"TeamIdentifier={team}" in details
                assert re.search(r"^CodeDirectory .*flags=.*\bruntime\b", details, re.MULTILINE)
                assert "Timestamp=" in details
            run("codesign", "--verify", "--strict", str(dmg))
            dmg_signing = subprocess.run(["codesign", "-dv", "--verbose=2", str(dmg)],
                                        check=True, capture_output=True, text=True).stderr
            assert "Authority=Developer ID Application: " in dmg_signing
            assert f"TeamIdentifier={team}" in dmg_signing and "Timestamp=" in dmg_signing
        for binary in (app / "Contents/MacOS/FraloApp", app / "Contents/MacOS/fralo"):
            assert run("lipo", "-archs", str(binary)).decode().strip() == architecture
        assert run(str(app / "Contents/MacOS/fralo"), "--version").decode().strip() == f"fralo {version}"
        assessment = subprocess.run(["spctl", "--assess", "--type", "execute", str(app)],
                                    text=True, capture_output=True, timeout=60)
        if args.require_notarized:
            run("xcrun", "stapler", "validate", str(dmg))
            dmg_assessment = subprocess.run(
                ["spctl", "--assess", "--type", "open", "--context", "context:primary-signature", str(dmg)],
                check=True, text=True, capture_output=True, timeout=60)
            dmg_assessment_output = (dmg_assessment.stdout + dmg_assessment.stderr).replace(str(dmg), dmg.name).strip()
            assert assessment.returncode == 0, assessment.stdout + assessment.stderr
        report = {
            "version": version, "build": identity["build"], "developer": identity["developer"],
            "architecture": architecture, "dmg": dmg.name, "sha256": digest(dmg),
            "mountedReadOnly": True, "entireAppMatchesDist": True, "cliMatches": True,
            "visibleRootItems": visible, "finderLayoutPresent": True,
            "windowSize": [660, 460], "iconSize": 128,
            "backgroundSourceSHA256": digest(ROOT / "Resources/DMG/background.png"),
            "backgroundPixels": [1320, 800],
            "bundledDocumentsMatch": True, "iconAssetsPresent": True,
            "signature": ("Developer ID" if developer_id else "ad-hoc") + "; strict verification passed",
            "notarizationRequiredAndVerified": args.require_notarized,
            "signingTeamID": team,
            "dmgGatekeeperOutput": dmg_assessment_output,
            "volumeCLIExecuted": True,
            "gatekeeperAssessment": "accepted" if assessment.returncode == 0 else "not accepted",
            "gatekeeperOutput": (assessment.stdout + assessment.stderr).replace(str(app), "Fralo.app").strip(),
            "browserDownloadAcceptance": "Not performed; requires real quarantined download",
        }
    finally:
        run("diskutil", "eject", str(volume))
    report["volumeEjected"] = True
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
