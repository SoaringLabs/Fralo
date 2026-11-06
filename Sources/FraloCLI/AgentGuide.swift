// Embedded offline docs; verified against docs/cli.md and examples/cli by verify_agent_cli.py.
enum AgentGuide {
    static let text = #"""
# Fralo CLI for people and agents

Run `fralo guide` for this offline guide. No App window, network, model API, or
source checkout is needed. macOS 14 or later is required.

## Find the executable

The [terminal installer](https://github.com/SoaringLabs/Fralo/blob/main/INSTALL.md#从终端安装--install-from-terminal)
installs the app to `~/Applications` and a `fralo` launcher to `/usr/local/bin`, so
commands below work directly. The command directory must already be on PATH;
writing the default directory may require an administrator password. Use
`--bin-dir` for another directory already on PATH. The installer never edits shell
profiles and still prints the absolute bundled CLI path for automation.
If you installed only by dragging Fralo to Applications, replace `fralo` below
with `/Applications/Fralo.app/Contents/MacOS/fralo`; DMG installation does not
register a shell command. After a source build, use the path returned by
`swift build --build-system native -c release --show-bin-path` followed by `/fralo`.
A copied standalone CLI still prints its guide, examples and schema. Rendering
with built-in image backgrounds additionally needs the matching
`Fralo_FraloCore.bundle` beside the binary (or in the App's Contents/Resources).
Keep the localization bundle alongside it for translated renderer errors.

## Discover, configure, check, render

These commands do not launch the GUI:

```sh
fralo --version
fralo capabilities --json
fralo schema --json
fralo example browser > browser.json
fralo compose ./screenshots --output ./framed --config browser.json --dry-run --json
fralo compose ./screenshots --output ./framed --config browser.json --json
```

The three shipped recipes are `phone`, `tablet`, and `browser`. Obtain one with
`fralo example NAME`; their JSON is also shipped in the App's
Contents/Resources/CLI/examples directory. Recipes are examples of implemented
features, not additional saved-preset or platform-size features.

`capabilities` is a short versioned directory of implemented commands, formats,
models and discovery commands. Request the larger JSON Schema only when needed.
Discovery/config/example commands emit JSON without requiring `--json`.
`guide` emits Markdown. Help for an individual new command is `COMMAND --help`.

## Configuration and reproducibility

`compose` uses the SAME `CompositionSettings` schema and `CompositionRenderer`
as GUI export. Its configuration is independent of the legacy `render` command.
With no configuration option, `compose` uses built-in defaults and ignores App
preferences. Select exactly one source:

```sh
fralo config --defaults > recipe.json
fralo config --app > app-snapshot.json
fralo compose ./screenshots --output ./framed --config app-snapshot.json --json
```

Alternatively, `compose --app-settings` reads the current saved workbench settings
once. This is the App's last saved state, not a live connection to an open window.
A snapshot file is preferable for repeatable automation. No CLI option writes
back to App settings. Reports include the effective full configuration and source.

A configuration is a JSON object with `schemaVersion: 1`. Omitted properties use
built-in defaults; they NEVER inherit App preferences. Unknown fields, invalid
types/enums/ranges and unsupported versions fail before creating output.
RGB colors must provide red, green and blue numbers from 0 to 1.
Use `fralo schema` for every field, enum, default and range. Example:

```json
{"schemaVersion":1,"display":"browser","browser":"safari","browserAppearance":"dark","mode":"background","canvas":"16:9","background":"gradient","format":"jpeg"}
```

Available settings cover phone/tablet/browser, phone model and orientation,
Safari/Chrome artwork and light/dark appearance, browser window ratio, transparent
or background mode, canvas ratio, device scale/position/opacity, solid/gradient/
built-in/local background and its transform/opacity, both shadow choices,
PNG lossless/palette quality, JPEG quality and fill color.
Coordinates follow the GUI: device X/Y are fractions of canvas width/height;
positive X moves right and positive Y moves up. Background X/Y pan across its
excess width/height. In transparent mode the device is opaque, output is PNG,
and background/canvas/position controls do not affect output. The full stored
choices remain in the configuration. Output format is reported separately.

`localBackgroundPath` is resolved relative to the configuration FILE, independent
of the invocation's working directory. Tilde paths are expanded. App snapshots
use the App's saved background path. A recipe referencing a local background must
travel with that image; it does not embed the bytes. Each batch loads background
bytes once. Record Fralo's version and keep inputs/background bytes unchanged
when reproducing output. Future versions can change artwork/encoding.

## Inputs, output and preflight

```sh
fralo compose one.png two.jpg --output ./framed --config recipe.json --json
fralo compose --input ./screenshots --output ./framed --config recipe.json --json
fralo compose --output ./framed --config recipe.json -- --filename-starting-with-dash.png
```

Inputs accept PNG/JPEG files or the immediate PNG/JPEG files in a directory.
Directory scans exclude hidden files and do not recurse. Canonical paths are
deduplicated and sorted by UTF-8 path for stable duplicate-name allocation.
Outputs are `<stem>-fralo.png` or `.jpg`; duplicate stems in one invocation gain
`-2`, `-3`, etc. The output directory is explicit; its missing parents are created
only for a real export. Existing outputs are skipped unless `--overwrite` is
explicit. Original input paths (including symlink aliases) are protected even
with overwrite. Fralo never deletes old outputs for you.

`--dry-run` resolves configuration, checks background decoding, checks the output
directory/nearest existing ancestor, decodes small input thumbnails and lists
planned paths with ready/skipped/failed status. It creates NO directories or
files. Skipped existing outputs are not decoded. A preflight cannot guarantee
future permissions, free space, full-resolution decoding or absence of races;
export rechecks source protection and uses atomic collision-safe writes.

A real batch continues after an individual image fails. A configuration,
background or output-directory startup error stops the batch. SIGINT/Ctrl-C or
SIGTERM requests cooperative cancellation: the current image may finish, finished
files survive, and remaining images are counted as unprocessed. Cancellation
handling begins after startup/preflight has completed.

## Results and errors

Use `--json` on compose: stdout contains exactly ONE JSON document; progress is
plain text on stderr. Without it, compose prints tab-separated entry/path/code
lines followed by a summary. Startup errors from all NEW commands always emit
JSON on stdout and exit 2, including errors while parsing arguments.

Compose results have `schemaVersion`, application `version`, `command`, `status`,
`dryRun`, `configurationSource`, full `configuration`, `outputFormat`,
`outputDirectory`, `total` and `entries`. Every entry includes `input`, canonical
`inputPath`, planned/actual `output`, and `status`. Failed/skipped entries include
a stable `code`; a localized human `reason` can also be present. Do not parse
human messages to decide what to do. Export results additionally include
`succeeded`, `skipped`, `failed`, `unprocessed`, `cancelled` and `durationSeconds`.
Preflight results include `failed`; their top-level status is ready or failed.
Export status is completed, partial_failure, failed or cancelled. A batch with
only skipped files is completed, so inspect counts to confirm new files exist.

Startup errors use this shape (no output was started):

```json
{"schemaVersion":1,"version":"...","status":"error","error":{"code":"config_unknown_field","message":"Unknown fields: displayy"}}
```

Stable startup codes: invalid_arguments, config_unreadable, config_invalid,
config_unknown_field, config_version_missing, config_version_unsupported,
input_unreadable, input_empty, background_invalid, output_unavailable,
internal_error. Internal errors indicate unexpected command failures.
Stable per-entry codes: input_invalid, render_failed, output_write_failed,
source_protected, output_exists. Successful/ready entries omit code.

Exit codes: 0 finished (possibly skipped), 1 one or more entries failed,
2 invalid arguments/configuration/startup error, 130 cooperative cancellation.
Schema version 1 permits additive result fields; clients should ignore unknown
result fields. Configuration fields are deliberately strict. CLI contracts are
independent of the application's marketing version.

## Legacy compatibility

`fralo render INPUT... --output DIR [--model ID] [--orientation VALUE] [--json]`
retains the six legacy iPhone 16/17/18 Pro/Pro Max models, original crop/mismatch
rules, stable PNG names and legacy saved settings precedence. `models` and
`settings` describe THAT legacy interface, not the full workbench. Old commands
have their original output/error shapes. Use compose/capabilities/schema/config
for new automation; use render when maintaining an existing script.
"""#
    static let examples: [String: String] = [
        "phone": #"""
{
  "schemaVersion": 1,
  "display": "phone",
  "mode": "background",
  "canvas": "9:16",
  "background": "warm",
  "deviceScale": 0.74
}
"""#,
        "tablet": #"""
{
  "schemaVersion": 1,
  "display": "tablet",
  "orientation": "landscape",
  "mode": "transparent",
  "transparentShadow": "soft"
}
"""#,
        "browser": #"""
{
  "schemaVersion": 1,
  "display": "browser",
  "browser": "safari",
  "browserAppearance": "dark",
  "mode": "background",
  "canvas": "16:9",
  "background": "gradient",
  "format": "jpeg"
}
"""#
    ]
}
