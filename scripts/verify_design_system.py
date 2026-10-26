#!/usr/bin/env python3
"""Verify build-time Dev isolation against actual Mach-O binaries and runtime evidence."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import struct

ROOT = Path(__file__).resolve().parents[1]
DEV_SYMBOLS = ('DesignLabController', 'DevelopmentEntry', 'LabProbe', 'LabSamples', 'ScenarioWorkbench')


def code_identity(binary):
    """Hash Mach-O sections + UUID, excluding the signature rewritten during packaging."""
    data = binary.read_bytes()
    if struct.unpack_from('<I', data)[0] != 0xFEEDFACF:
        raise RuntimeError(f'Expected a little-endian 64-bit Mach-O binary: {binary}')
    commands = struct.unpack_from('<I', data, 16)[0]
    cursor = 32
    sections = {}
    for _ in range(commands):
        command, length = struct.unpack_from('<II', data, cursor)
        if length < 8 or cursor + length > len(data):
            raise RuntimeError('Invalid Mach-O load command')
        if command == 0x1B:  # LC_UUID
            sections['uuid'] = data[cursor + 8:cursor + 24].hex()
        elif command == 0x19:  # LC_SEGMENT_64
            count = struct.unpack_from('<I', data, cursor + 64)[0]
            for index in range(count):
                entry = cursor + 72 + 80 * index
                name = data[entry:entry + 32].replace(b'\0', b'').decode()
                size = struct.unpack_from('<Q', data, entry + 40)[0]
                offset = struct.unpack_from('<I', data, entry + 48)[0]
                flags = struct.unpack_from('<I', data, entry + 64)[0] & 0xFF
                if flags not in (1, 12, 18):  # Zero-fill sections have no file payload.
                    if offset + size > len(data):
                        raise RuntimeError('Invalid Mach-O section')
                    sections[name] = hashlib.sha256(data[offset:offset + size]).hexdigest()
        cursor += length
    if 'uuid' not in sections or len(sections) < 2:
        raise RuntimeError('Incomplete Mach-O identity')
    return sections


def binary_path(configuration):
    path = subprocess.check_output(['swift', 'build', '-c', configuration, '--show-bin-path'], cwd=ROOT, text=True).strip()
    return Path(path) / 'FraloApp'


def verify(debug, release, probe=None, release_app=None):
    checks = {}
    for label, binary in [('debug', debug), ('release', release)]:
        symbols = subprocess.check_output(['nm', '-j', str(binary)], text=True, stderr=subprocess.DEVNULL)
        found = {name: name in symbols for name in DEV_SYMBOLS}
        checks[f'{label}_dev_symbols'] = all(found.values()) if label == 'debug' else not any(found.values())
        if not checks[f'{label}_dev_symbols']:
            raise RuntimeError(f'{label}: unexpected development symbols: {found}')
    # Stable design-system code must compile for Release too, independent of the Dev gallery.
    stable_modules = list(release.parent.rglob('FraloDesignSystem.swiftmodule'))
    checks['release_shared_module_compiled'] = bool(stable_modules)
    if not stable_modules:
        raise RuntimeError('Release FraloDesignSystem module was not found')
    if release_app:
        packaged = release_app / 'Contents/MacOS/FraloApp'
        checks['package_matches_verified_release'] = code_identity(packaged) == code_identity(release)
        names = [p.name for p in (release_app / 'Contents/Resources').rglob('*')]
        checks['no_packaged_dev_fixtures'] = not any(name in names for name in ['DesignLabFixtures', 'warm-gray.png', 'mist-blue.png', 'sage-gray.png', '01-today.png'])
    if probe:
        report = json.loads(probe.read_text())
        required = {
            'developer_menu', 'lab_menu_has_no_product_import_or_export', 'fixtures_available', 'five_live_pages',
            'collapse_preserves_artwork_size', 'collapsed_panel_alignment', 'preview_hides_tools', 'preview_focus',
            'escape_restores_editing', 'canvas_arrow_changes_selection', 'parameter_arrows_stay_in_control', 'tab_leaves_live_parameter',
            'transparent_mode_has_image', 'opaque_accessibility_fallback', 'reduced_motion',
            'minimum_window_has_canvas', 'minimum_window_panels_align',
        }
        observed = report.get('checks', {})
        checks['runtime_probe'] = report.get('passed') is True and all(observed.get(name) is True for name in required)
        executable = Path(report['executable_path'])
        checks['probe_matches_debug_binary'] = report.get('binary_sha256') == hashlib.sha256(executable.read_bytes()).hexdigest() and code_identity(executable) == code_identity(debug)
        checks['probe_snapshots_exist'] = len(report.get('snapshots', [])) >= 9 and all((probe.parent / name).is_file() for name in report.get('snapshots', []))
    if not all(checks.values()):
        raise RuntimeError(json.dumps(checks, indent=2))
    return checks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--probe-report', type=Path)
    parser.add_argument('--release-app', type=Path)
    args = parser.parse_args()
    checks = verify(binary_path('debug'), binary_path('release'), args.probe_report, args.release_app)
    print(json.dumps({'passed': True, 'checks': checks, 'limits': 'Does not replace native desktop-composite, VoiceOver speech or human animation review.'}, indent=2))


if __name__ == '__main__':
    main()
