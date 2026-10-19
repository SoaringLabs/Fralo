#!/usr/bin/env python3
"""Generate a signed Sparkle feed from the final notarized Fralo DMG; never publish it."""
from pathlib import Path
import argparse
import plistlib
import re
import shutil
import subprocess
import tempfile
from urllib.parse import quote
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def run(*args):
    return subprocess.check_output(args, stderr=subprocess.PIPE)


def release_identity():
    return dict(re.findall(r'public static let (\w+) = "([^"\n]+)"',
                          (ROOT / "Sources/FraloCore/FraloInfo.swift").read_text()))


def validate_release(info, identity, previous_build):
    if info.get("CFBundleIdentifier") != "app.fralo.desktop":
        raise ValueError("The archive must contain the production Fralo application")
    for plist_key, source_key in (("CFBundleVersion", "build"), ("CFBundleShortVersionString", "version"),
                                  ("SUFeedURL", "updateFeed"), ("SUPublicEDKey", "updatePublicKey")):
        if info.get(plist_key) != identity[source_key]:
            raise ValueError(f"Archive {plist_key} differs from FraloInfo.swift; rebuild the release")
    build = info["CFBundleVersion"]
    if not re.fullmatch(r"[1-9][0-9]*", build) or int(build) <= previous_build:
        raise ValueError("Increment the numeric build above the previously published build")
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", info["CFBundleShortVersionString"]):
        raise ValueError("Expected a stable major.minor.patch release version")


def validate_appcast(path, info, download_url, size):
    items = ET.parse(path).findall("./channel/item")
    if len(items) != 1:
        raise ValueError("Expected exactly one update in the generated feed")
    item = items[0]
    for key, value in (("version", info["CFBundleVersion"]),
                       ("shortVersionString", info["CFBundleShortVersionString"])):
        if item.findtext(f"{{{SPARKLE}}}{key}") != value:
            raise ValueError(f"Generated feed {key} differs from the archive")
    enclosure = item.find("enclosure")
    if enclosure is None or enclosure.get("url") != download_url or enclosure.get("length") != str(size):
        raise ValueError("Generated feed does not reference the final archive URL and size")
    signature = enclosure.get(f"{{{SPARKLE}}}edSignature")
    if not signature:
        raise ValueError("Generated feed has no EdDSA archive signature")
    return signature


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True, help="Final signed, stapled DMG")
    parser.add_argument("--notes", type=Path, required=True, help="Public UTF-8 Markdown release notes")
    parser.add_argument("--previous-build", type=int, required=True)
    parser.add_argument("--account", default="app.fralo.desktop", help="Sparkle signing keychain account")
    parser.add_argument("--tools", type=Path, default=ROOT / ".build/artifacts/sparkle/Sparkle/bin")
    parser.add_argument("--output", type=Path, default=ROOT / "dist/appcast.xml")
    args = parser.parse_args()
    archive = args.archive.resolve()
    if archive.suffix != ".dmg" or not archive.is_file():
        parser.error("--archive must be an existing DMG")
    if args.previous_build < 0:
        parser.error("--previous-build must be non-negative")
    notes = args.notes.read_text(encoding="utf-8")
    if not notes.strip():
        parser.error("Release notes must not be empty")
    identity = release_identity()
    tools = args.tools.resolve()
    public_key = run(str(tools / "generate_keys"), "--account", args.account, "-p").decode().strip()
    if public_key != identity["updatePublicKey"]:
        parser.error("Keychain signing key does not match the public key embedded in Fralo")
    run("codesign", "--verify", "--strict", str(archive))
    run("xcrun", "stapler", "validate", str(archive))
    mounted = plistlib.loads(run("hdiutil", "attach", "-readonly", "-nobrowse", "-plist", str(archive)))
    volume = next(Path(i["mount-point"]) for i in mounted["system-entities"] if "mount-point" in i)
    try:
        app = volume / "Fralo.app"
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        validate_release(info, identity, args.previous_build)
        run("codesign", "--verify", "--deep", "--strict", str(app))
        signing = subprocess.run(["codesign", "-dv", "--verbose=2", str(app)],
                                 check=True, capture_output=True, text=True).stderr
        if "Authority=Developer ID Application: " not in signing:
            raise ValueError("Production updates require Developer ID signing")
    finally:
        run("hdiutil", "detach", str(volume))
    base = f"https://github.com/SoaringLabs/Fralo/releases/download/v{info['CFBundleShortVersionString']}/"
    with tempfile.TemporaryDirectory(prefix="fralo-appcast-") as temporary:
        directory = Path(temporary)
        shutil.copy2(archive, directory / archive.name)
        (directory / (archive.stem + ".md")).write_text(notes, encoding="utf-8")
        feed = directory / "appcast.xml"
        subprocess.run([str(tools / "generate_appcast"), "--account", args.account,
                        "--maximum-deltas", "0", "--embed-release-notes", "--versions", info["CFBundleVersion"],
                        "--download-url-prefix", base, "--link", f"https://github.com/SoaringLabs/Fralo/releases/tag/v{info['CFBundleShortVersionString']}",
                        "-o", str(feed), str(directory)], check=True)
        signature = validate_appcast(feed, info, base + quote(archive.name), archive.stat().st_size)
        run(str(tools / "sign_update"), "--account", args.account, "--verify", str(archive), signature)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(feed, args.output)
    print(f"Validated signed update feed: {args.output}")
    print("No files were uploaded. Publish appcast.xml alongside this exact final DMG after release approval.")


if __name__ == "__main__":
    main()
