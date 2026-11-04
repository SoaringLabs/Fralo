<div align="center">

**English** · [简体中文](README.zh-CN.md)

<img src="docs/assets/icon.png" width="128" height="128" alt="Fralo app icon">

# Fralo

**Batch screenshot mockups for macOS. Set the style once and export the whole batch.**

[![Latest release](https://img.shields.io/github/v/release/SoaringLabs/Fralo?label=release&color=0a84ff)](https://github.com/SoaringLabs/Fralo/releases/latest)
[![CI](https://github.com/SoaringLabs/Fralo/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/SoaringLabs/Fralo/actions/workflows/ci.yml)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey?logo=apple)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-5.10-F05138?logo=swift&logoColor=white)](Package.swift)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Contact @peekbomb on X](https://img.shields.io/badge/%40peekbomb-000000?logo=x&logoColor=white)](https://x.com/peekbomb)

[**Download the macOS App**](https://github.com/SoaringLabs/Fralo/releases/latest) ·
[**CLI quickstart**](#command-line-interface) ·
[**AI agent**](#with-an-ai-agent) ·
[Changelog](CHANGELOG.md) ·
[Install guide](INSTALL.md) ·
[Contributing](CONTRIBUTING.md)

</div>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/workbench-en-dark.png">
  <img src="docs/assets/workbench-en-light.png" width="1200" alt="The complete English Fralo workbench with native window shadow, three generated Field Notes screenshots, an iPhone 18 Pro Max frame, and a warm background">
</picture>

Make a consistent set of mockups for an App Store listing, release post, or documentation. Drop in PNG or JPEG screenshots, choose a phone, tablet, or browser frame, and preview the same composition across the batch. Export transparent PNGs or finished images with a background.

## Features

| What you want to do | What Fralo offers |
| --- | --- |
| Choose a frame | Use an iPhone 18 Pro, iPhone 18 Pro Max, or tablet in portrait or landscape. Safari and Chrome frames come in light or dark, with 16:10, 16:9, and 4:3 window ratios. |
| Build a composition | Keep the frame transparent or place it on a 1:1, 4:3, 16:9, 3:4, or 9:16 canvas. Use a solid color, gradient, preset texture, or your own image. |
| Fine-tune the layout | Drag the device or pan the background in the preview. Adjust size, shadow, and opacity, or hold ⌥ and press an arrow key to move the device by 1 px. |
| Choose a format | Use lossless PNG, smaller PNG presets, or JPEG with adjustable quality and fill color. Transparent exports use PNG. |
| Automate repeat work | The app and `fralo compose` share a renderer. Reuse the app's saved composition or supply a separate JSON recipe. |

The workbench supports light and dark appearance, undo and redo, and the system settings for Reduce Motion, Reduce Transparency, and Increase Contrast.

## Installation

Download `Fralo-<version>-arm64.dmg` from the [latest release](https://github.com/SoaringLabs/Fralo/releases/latest). Open the disk image and drag Fralo into Applications. Release builds are signed with Developer ID and notarized by Apple. See the [install guide](INSTALL.md) for checksum verification, first launch, and uninstall steps.

### Install from Terminal

On an Apple silicon Mac, paste this command into Terminal:

```sh
curl -fsSL https://fralo.app/install.sh | sh
```

The script installs the same release in `~/Applications` and prints the bundled CLI path. See the [install guide](INSTALL.md#从终端安装--install-from-terminal) to pin a version or verify the CLI.

This README describes the current source tree. See the [changelog](CHANGELOG.md) for changes by version.

### Requirements

- **Mac:** Apple silicon.
- **macOS:** Minimum deployment target is macOS 14 Sonoma. Runtime testing covers macOS 27. Earlier versions have yet to be verified.
- **Languages:** English, Simplified Chinese, Traditional Chinese, and Japanese. Choose a language in **Fralo → Settings… → Appearance → Language**, or follow the system preference. Fralo falls back to English when no supported language matches.

### Updating

In Fralo 0.1.1 and later, choose **Fralo → Check for Updates…**. Fralo checks daily by default and can be set to check manually. Sparkle verifies update archives. Installation requires confirmation and waits for any active export to finish. If you use 0.1.0, install a newer DMG manually.

## Usage

1. **Add screenshots.** Drag in PNG or JPEG files, choose files with ⌘O, import a folder with ⇧⌘O, or paste with ⌘V. Folder import scans the top level only.
2. **Set up the composition.** Pick a frame and orientation, then choose transparent output or add a background. Use ⌘[ and ⌘] to check how the same settings look across the batch.
3. **Export.** Press ⇧⌘E for the whole batch, ⌘E for the current image, or ⌘C to copy the current result at full resolution.

Fralo creates a timestamped `fralo-YYYYMMDD-HHmmss` folder for each export and can open it when the export finishes. It adds a number when a name is taken, preserves originals, and continues the batch if an individual image fails. You can cancel a running export.

<details>
<summary><b>Keyboard shortcuts</b></summary>

| Action | Shortcut |
| --- | --- |
| Add images · Import folder | ⌘O · ⇧⌘O |
| Paste images · Copy current result | ⌘V · ⌘C |
| Export all · Export current image | ⇧⌘E · ⌘E |
| New batch | ⌘N |
| Remove selected image | ⌫ |
| Undo · Redo | ⌘Z · ⇧⌘Z |
| Previous · Next image | ⌘[ · ⌘] |
| Fit to window · Actual pixels | ⌘0 · ⌘1 |
| Zoom in · Zoom out | ⌘+ · ⌘− |
| Nudge device by 1 px | ⌥ + arrow keys |
| Toggle sidebar · Settings panel · Output preview | ⌃⌘S · ⌥⌘I · ⌥⌘P |
| Settings | ⌘, |

</details>

## Showcase

| Warm preset | Gradient | Sage preset | Transparent PNG |
| :---: | :---: | :---: | :---: |
| <img src="docs/assets/background-1.jpg" width="200" alt="Phone frame on a warm textured background"> | <img src="docs/assets/background-2.jpg" width="200" alt="Phone frame on a peach-to-blue gradient"> | <img src="docs/assets/background-3.jpg" width="200" alt="Phone frame on a sage textured background"> | <img src="docs/assets/framed.png" width="103" alt="Transparent phone frame exported by the CLI"> |

All examples use the fictional *Field Notes* screens in [`examples/`](examples), generated by
[`scripts/generate-demo.swift`](scripts/generate-demo.swift). They contain no personal data.

## Command-line interface

Use a build that includes `fralo compose`. Set up a representative screenshot in Fralo, then reuse that saved composition for a batch from the terminal or a coding agent. Replace the example directories with your own paths.

### From the terminal

Run the preflight first and review the planned output paths before exporting. Keep the `FRALO` path returned by the terminal installer, or use the path for a drag-and-drop install shown below. If `fralo` is on your PATH, use it in place of `"$FRALO"`.

```bash
FRALO=${FRALO:-/Applications/Fralo.app/Contents/MacOS/fralo}
"$FRALO" compose ./screenshots --output ./framed --app-settings --dry-run --json
"$FRALO" compose ./screenshots --output ./framed --app-settings --json
```

`--app-settings` reads the last saved workbench settings. `--dry-run` checks the configuration and inputs without creating files or folders. The CLI names outputs `<name>-fralo.png` or `.jpg` and skips existing outputs unless you pass `--overwrite`.

### With an AI agent

Copy this prompt into a coding agent that can run commands on your Mac.

```text
Use Fralo to export ./screenshots to ./framed with my saved composition.
Read fralo guide first, using the CLI bundled in Fralo.app if needed.
Preflight the batch and stop if there are errors. If it's ready, export it
and report the output paths, skipped files, and any failures.
```

### Reproduce the sample with a recipe

From the repository root, run these commands with the same `FRALO` variable.

```bash
"$FRALO" example phone > phone.json
"$FRALO" compose examples/01-today.png --output ./framed --config phone.json --json
```

<p align="center">
  <img src="docs/assets/cli-compose.png" width="270" alt="Actual Fralo CLI output showing the Field Notes screenshot in an iPhone frame on a warm textured background">
</p>

The example exports `framed/01-today-fralo.png` at 1350 × 2400 pixels.

### Scripting and discovery

`fralo guide` prints the offline guide. Use `fralo capabilities --json` to discover supported commands and formats, and `fralo schema --json` for configuration fields, defaults, and ranges. For batch results, `--json` reports each file's path, status, and any error code. Progress goes to stderr.

See the [CLI guide](docs/cli.md) for configuration, exit codes, and legacy `fralo render` compatibility.

## Privacy

Fralo renders screenshots locally. It requires no account or image uploads and collects no usage analytics. The app checks GitHub for updates. You can turn off automatic checks in Settings.

## Scope and limitations

- Fralo uses original, parametric frames. Use Apple's own resources when you need official device artwork.
- The workbench fits the whole screenshot without stretching it. Use screenshots that match the orientation you choose. Legacy `fralo render` has separate [cropping and aspect-ratio rules](docs/cli.md#legacy-compatibility).
- Fralo handles framing and composition. Edit screenshot content, correct orientation, or add captions before importing.

## Building from source

Use Xcode 26.3 or later. Packaging a DMG also requires Python 3.10 or later, and compiling the layered app icon requires Xcode 27's `actool`.

```bash
git clone https://github.com/SoaringLabs/Fralo.git
cd Fralo
swift test --build-system native
swift build --build-system native -c release
```

See the [install guide](INSTALL.md#源码构建) for DMG packaging and the [signing](docs/signing.md) and [update](docs/updates.md) guides for maintainer releases. Run `python3 -B scripts/check_updates.py --help` for dependency and toolchain check options.

## Contributing

Bug reports and pull requests are welcome. Read the [contributing guide](CONTRIBUTING.md) before submitting, and use the [generated screenshots](examples) to reproduce issues where possible.

## License

Fralo is released under the [MIT License](LICENSE). It is developed by
[Soaring Labs](https://github.com/SoaringLabs) and maintained by
[Ethan (@Peek-A-Booo)](https://github.com/Peek-A-Booo); see [AUTHORS.md](AUTHORS.md).

In-app updates use [Sparkle](https://github.com/sparkle-project/Sparkle), whose license is
bundled with the App. iPhone and Safari are trademarks of Apple Inc., and Chrome is a
trademark of Google LLC. Fralo is not affiliated with or endorsed by either company.
