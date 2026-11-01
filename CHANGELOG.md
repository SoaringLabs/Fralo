# Changelog

## Unreleased

- Reorganized the settings panel into Device, Appearance, Composition, Background and Export,
  with plainer labels; group headers no longer repeat the current values.
- Transparent output is always PNG with an opaque device; JPEG, its fill color and device
  opacity apply only to images with a background.
- Gradient backgrounds have adjustable start and end colors.
- Removed composition templates. Device size settles on 100% (the device just fills the
  canvas) and warns when larger sizes crop it.
- In the preview, dragging the device moves it and dragging empty canvas pans an image
  background; the separate background-dragging switch is gone.
- A custom background image is a fourth image tile next to the presets: it shows as
  selected, and after trying a preset you can switch back without choosing the file again.
- Removed the Show Transparent Area toggle from the canvas bar and the View menu.
- Removed transparent padding. Exports always fit the complete device; the CLI no longer
  accepts `--padding`, and a `padding` value in older settings files is ignored.

## 0.1.0 — 2026-10-17

First public release.

- Native macOS App and a CLI sharing the same Core Graphics renderer.
- Batch, folder, and clipboard import of PNG / JPEG screenshots.
- Six iPhone Pro / Pro Max frames with portrait and landscape output.
- Transparent PNG export with configurable padding and original-resolution rendering.
- Live preview, zoom, full-resolution copy, single export, and batch export.
- Saved settings shared by the App and CLI; CLI overrides apply only to the current run.
- Existing-file protection, explicit overwrite, cancellation, and per-image error reports.
- Layered App icon, MIT license, generated demo assets, and reproducible CLI checks.

The release DMG is Developer ID signed, notarized by Apple, and has its ticket stapled;
local source builds default to ad-hoc signing. Runtime acceptance currently covers
Apple Silicon on macOS 27.0.1. Older macOS and Intel runtime acceptance are pending.
