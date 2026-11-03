#!/usr/bin/env python3
"""Exercise the shipped agent CLI, offline docs and safety contracts (stdlib only)."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import selectors
import shutil
import signal
import struct
import subprocess
import tempfile
import time
import zlib

ROOT = Path(__file__).resolve().parents[1]


def fixture(path):
    width, height = 64, 32
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    rows = b''.join(
        b'\0' + b''.join(bytes((x * 3 % 256, y * 7 % 256, 90)) for x in range(width)) for y in range(height))
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
                     + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))


def verify(binary, root):
    checks = []
    settings = root / 'settings.json'
    settings.write_text('{"schemaVersion":1,"model":"iphone-16-pro","orientation":"landscape"}')
    env = dict(os.environ, FRALO_SETTINGS_PATH=str(settings))

    def run(*arguments, code=0, executable=binary):
        result = subprocess.run([str(executable), *map(str, arguments)], cwd=root, env=env,
                                capture_output=True, text=True, timeout=90)
        assert result.returncode == code, (arguments, result.returncode, result.stdout, result.stderr)
        return result

    def document(*arguments, code=0, executable=binary):
        return json.loads(run(*arguments, code=code, executable=executable).stdout)

    # These are the exact discovery and recipe commands published in the offline guide.
    assert run('guide').stdout == (ROOT / 'docs/cli.md').read_text()
    schema = document('schema', '--json')
    capabilities = document('capabilities', '--json')
    assert capabilities['configurationSchemaVersion'] == schema['properties']['schemaVersion']['const'] == 1
    defaults = document('config', '--defaults')
    assert set(schema['properties']) == set(defaults) | {'localBackgroundPath'}
    assert capabilities['displays'] == schema['properties']['display']['enum']
    for name in capabilities['examples']:
        assert document('example', name) == json.loads((ROOT / f'examples/cli/{name}.json').read_text())
    checks.append('Embedded guide/examples match shipped docs and schema covers GUI fields')

    copied = root / 'standalone'
    copied.mkdir()
    shutil.copy2(binary, copied / 'fralo')
    for command in [('guide',), ('schema',), ('capabilities',), ('example', 'browser')]:
        assert run(*command, executable=copied / 'fralo').stdout == run(*command).stdout
    checks.append('Copied binary discovers capabilities offline without resources/source cwd')

    source = root / 'input space.png'
    fixture(source)
    original_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    recipe = root / 'browser.json'
    recipe.write_text(run('example', 'browser').stdout)
    out = root / 'framed'
    base = ['compose', source, '--output', out, '--config', recipe]
    plan = document(*base, '--dry-run', '--json')
    assert not out.exists() and plan['status'] == 'ready' and plan['entries'][0]['inputPath'] == str(source)
    rendered = document(*base, '--json')
    assert rendered['succeeded'] == 1 and rendered['outputFormat'] == 'jpeg'
    image = Path(rendered['entries'][0]['output'])
    assert image.suffix == '.jpg' and image.read_bytes().startswith(b'\xff\xd8')
    assert document(*base, '--json')['skipped'] == 1
    assert document(*base, '--overwrite', '--json')['succeeded'] == 1
    checks.append('Documented preflight/render commands, JPEG, spaces and explicit overwrite')

    # Every shipped recipe is executable, including the phone's bundled background.
    for name in capabilities['examples']:
        path = root / f'{name}.json'
        path.write_text(run('example', name).stdout)
        result = document('compose', source, '--output', root / f'recipe-{name}', '--config', path, '--json')
        assert result['succeeded'] == 1
    checks.append('All shipped recipes render real outputs')

    # A distinguishable copied asset proves the relocated CLI uses its companion bundle,
    # rather than accidentally succeeding via SwiftPM's absolute build-directory fallback.
    core_bundle = copied / 'Fralo_FraloCore.bundle'
    source_bundle = binary.parent / core_bundle.name
    if not source_bundle.exists() and binary.parent.name == 'MacOS':
        source_bundle = binary.parent.parent / 'Resources' / core_bundle.name
    shutil.copytree(source_bundle, core_bundle)
    warm = next(core_bundle.rglob('warm-gray.png'))
    fixture(warm)
    relocated_recipe = root / 'relocated.json'
    relocated_recipe.write_text(json.dumps(dict(defaults, mode='background', background='warm')))
    relocated = document('compose', source, '-o', root / 'relocated', '--config', relocated_recipe,
                         '--json', executable=copied / 'fralo')
    relocated_recipe.write_text(json.dumps(dict(defaults, mode='background', background='local', localBackgroundPath=str(warm))))
    local_reference = document('compose', source, '-o', root / 'relocated-reference', '--config', relocated_recipe, '--json')
    assert Path(relocated['entries'][0]['output']).read_bytes() == Path(local_reference['entries'][0]['output']).read_bytes()
    checks.append('Relocated CLI renders using its own companion assets without source lookup')

    app = dict(defaults, display='browser', mode='background', canvas='1:1', background='solid')
    workbench = settings.with_suffix('.workbench.json')
    workbench.write_text(json.dumps(app))
    before = {p: p.read_bytes() for p in (settings, workbench)}
    assert document('config', '--app') == app
    inherited = document('compose', source, '--output', root / 'app', '--app-settings', '--json')
    assert inherited['configuration'] == app
    isolated = document('compose', source, '--output', root / 'defaults', '--json')
    assert isolated['configuration'] == defaults
    checks.append('App snapshot opt-in; default/explicit config independent of user state')

    recipe_directory = root / 'relative-config'
    recipe_directory.mkdir()
    fixture(recipe_directory / 'backdrop.png')
    relative = recipe_directory / 'local.json'
    relative.write_text(json.dumps(dict(app, background='local', localBackgroundPath='backdrop.png')))
    local = document('compose', source, '--output', root / 'local', '--config', relative, '--json')
    assert local['succeeded'] == 1
    assert local['configuration']['localBackgroundPath'] == str(recipe_directory / 'backdrop.png')
    checks.append('Local backgrounds resolved relative to config file and rendered')

    invalid_cases = [({}, 'config_version_missing'), ({'schemaVersion': 2}, 'config_version_unsupported'),
                     ({'schemaVersion': 1, 'displayy': 'phone'}, 'config_unknown_field'),
                     ({'schemaVersion': 1, 'display': 'watch'}, 'config_invalid'),
                     ({'schemaVersion': True}, 'config_invalid'),
                     ({'schemaVersion': 1, 'deviceX': 99}, 'config_invalid')]
    for value, expected in invalid_cases:
        invalid = root / 'invalid.json'
        invalid.write_text(json.dumps(value))
        destination = root / 'never-created'
        error = document('compose', source, '--output', destination, '--config', invalid, '--json', code=2)
        assert error['error']['code'] == expected and not destination.exists()
    for arguments, expected in [(['compose'], 'invalid_arguments'),
                                (['compose', source, '-o', root / 'never-created', '--bogus'], 'invalid_arguments'),
                                (['compose', source, '-o', source], 'output_unavailable'),
                                (['compose', source, '-o', out, '--config', recipe, '--app-settings'], 'invalid_arguments'),
                                (['compose', source, '-o', out, '--config', '--json'], 'invalid_arguments'),
                                (['schema', '--typo'], 'invalid_arguments'),
                                (['config', '--app', '--defaults'], 'invalid_arguments')]:
        assert document(*arguments, code=2)['error']['code'] == expected
    empty = root / 'empty'
    empty.mkdir()
    assert document('compose', empty, '-o', out, '--json', code=2)['error']['code'] == 'input_empty'
    checks.append('Strict schema and parse/startup failures have stable JSON codes without writes')

    bad = root / 'bad.png'
    bad.write_bytes(b'not a PNG')
    mixed = ['compose', source, bad, '-o', root / 'partial', '--json']
    failed_plan = document(*mixed, '--dry-run', code=1)
    assert failed_plan['failed'] == 1 and not (root / 'partial').exists()
    partial = document(*mixed, code=1)
    assert partial['succeeded'] == partial['failed'] == 1 and partial['status'] == 'partial_failure'
    assert next(e for e in partial['entries'] if e['status'] == 'failed')['code'] == 'input_invalid'
    checks.append('Corrupt input preflight and real batch partial failure')

    protected = root / 'input space-fralo.png'
    fixture(protected)
    protection_hash = hashlib.sha256(protected.read_bytes()).hexdigest()
    for option in ['--dry-run', '--overwrite']:
        protection = document('compose', source, protected, '-o', root, '--json', option, code=1)
        assert any(e.get('code') == 'source_protected' for e in protection['entries'])
        assert hashlib.sha256(protected.read_bytes()).hexdigest() == protection_hash
    symlink_dir = root / 'alias-output'
    symlink_dir.mkdir()
    (symlink_dir / 'input space-fralo.png').symlink_to(source)
    protection = document('compose', source, '-o', symlink_dir, '--overwrite', '--json', code=1)
    assert protection['entries'][0]['code'] == 'source_protected'
    checks.append('Source protection in preflight/export, including symlink aliases')

    duplicates = root / 'duplicates'
    for name in ('a', 'b'):
        (duplicates / name).mkdir(parents=True)
        fixture(duplicates / name / 'same.png')
    names = document('compose', duplicates / 'b', duplicates / 'a', '-i', duplicates / 'a', '-o', root / 'dedup', '--dry-run', '--json')
    assert names['total'] == 2
    assert [Path(e['output']).name for e in names['entries']] == ['same-fralo.png', 'same-fralo-2.png']
    checks.append('Canonical input deduplication and stable duplicate-stem names')

    occupied = root / 'occupied'
    occupied.mkdir()
    output_name = occupied / 'input space-fralo.png'
    output_name.symlink_to(root / 'absent.png')
    assert document('compose', source, '-o', occupied, '--dry-run', '--json')['entries'][0]['code'] == 'output_exists'
    assert document('compose', source, '-o', occupied, '--json')['skipped'] == 1
    bad_output = occupied / 'bad-fralo.png'
    bad_output.symlink_to(root / 'absent.png')
    assert document('compose', bad, '-o', occupied, '--dry-run', '--json')['entries'][0]['code'] == 'output_exists'
    assert document('compose', bad, '-o', occupied, '--json')['skipped'] == 1
    output_name.unlink()
    output_name.mkdir()
    for flags in (['--dry-run', '--overwrite'], ['--overwrite']):
        failure = document('compose', source, '-o', occupied, *flags, '--json', code=1)
        assert failure['entries'][0]['code'] == 'output_write_failed'
    output_name.rmdir()
    output_name.symlink_to(empty, target_is_directory=True)
    assert document('compose', source, '-o', occupied, '--overwrite', '--dry-run', '--json')['entries'][0]['status'] == 'ready'
    assert document('compose', source, '-o', occupied, '--overwrite', '--json')['succeeded'] == 1
    assert empty.is_dir() and not output_name.is_symlink()
    checks.append('Dangling symlink collisions and occupied directory names agree with preflight')

    # Coordinate cancellation on actual progress, not an arbitrary sleep.
    many = root / 'many'
    many.mkdir()
    for index in range(12):
        shutil.copy2(source, many / f'{index:02}.png')
    for sig in (signal.SIGINT, signal.SIGTERM):
        with subprocess.Popen([str(binary), 'compose', str(many), '-o', str(root / f'cancel-{sig}'), '--json'],
                              cwd=root, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as process:
            try:
                with selectors.DefaultSelector() as selector:
                    selector.register(process.stderr, selectors.EVENT_READ)
                    deadline, buffered, triggered = time.monotonic() + 45, b'', False
                    while not triggered and process.poll() is None:
                        assert time.monotonic() < deadline, 'No cancellation progress within 45 seconds'
                        if not selector.select(0.25):
                            continue
                        data = os.read(process.stderr.fileno(), 4096)
                        if not data:
                            break
                        buffered += data
                        if b'[1/' in buffered:
                            process.send_signal(sig)
                            triggered = True
                stdout, stderr = process.communicate(timeout=45)
                report = json.loads(stdout)
                assert triggered and process.returncode == 130 and report['status'] == 'cancelled', (stdout, stderr)
                assert report['succeeded'] > 0 and report['unprocessed'] > 0
                assert all(Path(e['output']).is_file() for e in report['entries'] if e['status'] == 'success')
            finally:
                if process.poll() is None:
                    process.kill()
                    process.communicate()
    checks.append('SIGINT/SIGTERM preserve completed outputs and report unprocessed count')

    assert hashlib.sha256(source.read_bytes()).hexdigest() == original_hash
    assert all(path.read_bytes() == data for path, data in before.items())
    checks.append('Input bytes and both App/legacy settings unchanged')
    return {'passed': len(checks), 'checks': checks}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', type=Path)
    args = parser.parse_args()
    binary = args.binary.resolve()
    if not binary.is_file():
        parser.error(f'CLI not found: {binary}')
    with tempfile.TemporaryDirectory(prefix='fralo-agent-cli-') as temporary:
        report = verify(binary, Path(temporary))
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
