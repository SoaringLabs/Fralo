# Changelog

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
