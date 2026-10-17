#!/usr/bin/env python3
"""Integration checks with generated fixtures and isolated settings; Python stdlib only."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import selectors
import signal
import struct
import subprocess
import tempfile
import time
import zlib

ROOT = Path(__file__).resolve().parents[1]


def write_fixture(path, index):
    """Valid full-resolution RGB PNG, unique per input; no captured user data."""
    width, height = 1320, 2868

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    rows = []
    for y in range(height):
        rgb = bytes(((35 + index * 17 + y // 40) % 256, 90 if y < height // 2 else 180, 140))
        rows.append(b"\0" + rgb * width)
    path.write_bytes(b"\x89PNG\r\n\x1a\n"
                     + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(b"".join(rows)))
                     + chunk(b"IEND", b""))


def verify(binary, base):
    inputs = base / "input"
    inputs.mkdir()
    for index in range(10):
        write_fixture(inputs / f"sample-{index + 1:02}.png", index)
    settings = base / "settings.json"
    settings.write_text(json.dumps({"schemaVersion": 1, "model": "iphone-17-pro", "orientation": "portrait", "padding": 11}))
    environment = dict(os.environ, FRALO_SETTINGS_PATH=str(settings))
    originals = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs.glob("*.png")}
    checks = []

    def run(arguments, code=0):
        result = subprocess.run([str(binary), *map(str, arguments)], env=environment,
                                cwd=base, text=True, capture_output=True, timeout=60)
        assert result.returncode == code, (result.returncode, result.stderr)
        return result

    version = re.search(r'let version = "([^"]+)"', (ROOT / "Sources/FraloCore/FraloInfo.swift").read_text()).group(1)
    assert run(["--version"]).stdout.strip() == f"fralo {version}"
    assert "Soaring Labs" in run(["--help"]).stdout
    checks.append("Version and developer identity")

    models = json.loads(run(["models", "--json"]).stdout)
    assert len(models) == 6 and len({model["id"] for model in models}) == 6
    checks.append("All six model IDs exposed")

    inherited = json.loads(run(["render", inputs, "--output", base / "inherited", "--json"]).stdout)
    assert inherited["succeeded"] == 10 and inherited["failed"] == 0
    assert inherited["settings"]["model"] == "iphone-17-pro" and inherited["settings"]["padding"] == 11
    checks.append("Saved settings inherited for all ten inputs")

    before = settings.read_bytes()
    arguments = ["render", inputs, "--output", base / "normal", "--model", "iphone-18-pro-max",
                 "--padding", "0", "--orientation", "portrait", "--json"]
    normal = json.loads(run(arguments).stdout)
    assert normal["succeeded"] == 10 and settings.read_bytes() == before
    checks.append("Explicit overrides do not rewrite settings")

    skipped = json.loads(run(arguments).stdout)
    assert skipped["skipped"] == 10 and skipped["succeeded"] == 0
    checks.append("Existing files skipped by default")

    original_output = Path(normal["entries"][0]["output"])
    output_hash = hashlib.sha256(original_output.read_bytes()).hexdigest()
    overwritten = json.loads(run(["render", inputs, "--output", base / "normal", "--padding", "24",
                                  "--overwrite", "--json"]).stdout)
    assert overwritten["succeeded"] == 10
    assert hashlib.sha256(original_output.read_bytes()).hexdigest() != output_hash
    checks.append("Explicit overwrite replaces outputs")

    bad = base / "invalid.png"
    bad.write_bytes(b"not an image")
    partial = json.loads(run(["render", inputs, bad, "--output", base / "partial", "--json"], code=1).stdout)
    assert partial["succeeded"] == 10 and partial["failed"] == 1
    checks.append("Corrupt image returns exit 1 while valid inputs finish")

    run(["render", inputs, "--output", base / "bad-padding", "--padding", "-1"], code=2)
    run(["render", inputs, "--output", base / "bad-orientation", "--orientation", "auto"], code=2)
    checks.append("Invalid arguments return exit 2")

    with subprocess.Popen([str(binary), "render", str(inputs), "--output", str(base / "cancelled"), "--json"],
                          env=environment, cwd=base, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as process:
        try:
            with selectors.DefaultSelector() as selector:
                selector.register(process.stderr, selectors.EVENT_READ)
                deadline, buffered, triggered = time.monotonic() + 30, b"", False
                while not triggered and process.poll() is None:
                    if time.monotonic() >= deadline:
                        raise TimeoutError("CLI did not report progress within 30 seconds")
                    if not selector.select(timeout=0.25):
                        continue
                    data = os.read(process.stderr.fileno(), 4096)
                    if not data:
                        break
                    buffered += data
                    if b"[1/" in buffered:
                        process.send_signal(signal.SIGINT)
                        triggered = True
            out, err = process.communicate(timeout=30)
            assert triggered, "CLI finished before cancellation was exercised"
            report = json.loads(out)
            assert process.returncode == 130 and report["cancelled"] and report["unprocessed"] > 0
            assert report["succeeded"] > 0
            assert all(Path(entry["output"]).exists() for entry in report["entries"] if entry["status"] == "success")
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()
    checks.append("SIGINT returns exit 130 and preserves completed files")

    assert originals == {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs.glob("*.png")}
    assert settings.read_bytes() == before
    checks.append("Source images and isolated settings unchanged")
    return {"passed": len(checks), "checks": checks, "inputCount": 10,
            "normalDurationSeconds": normal["durationSeconds"], "version": version,
            "fixtureSource": "Generated RGB PNGs; no personal screenshots"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", nargs="?", type=Path, default=ROOT / "dist/fralo")
    parser.add_argument("--report", type=Path, help="Optional JSON report")
    args = parser.parse_args()
    binary = args.binary.resolve()
    if not binary.is_file():
        parser.error(f"CLI not found: {binary}; build it first")
    with tempfile.TemporaryDirectory(prefix="fralo-cli-check-") as directory:
        report = verify(binary, Path(directory))
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
