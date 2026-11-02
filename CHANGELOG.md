# Changelog

All notable changes to Fralo are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and Fralo uses
[Semantic Versioning](https://semver.org/). While the major version is 0, minor
releases may include breaking changes; they are marked **Breaking** below.

## Unreleased

### Changed

- Settings (⌘,) is now a System Settings–style window with Appearance and Updates
  categories. Choose the App appearance from thumbnails, and turn daily update checks
  on or off next to the current version, the last check time, and Check Now.
- Choose Fralo's interface language in Settings › Appearance; Fralo switches
  immediately and keeps your batch. It is the same setting as Fralo's language in
  System Settings › General › Language & Region.
- Search Settings from the sidebar (⌘F): matching categories stay listed and matching
  settings are highlighted, in your language or in English.
- The View › Appearance submenu and the Fralo › Check for Updates Automatically
  (Daily) menu item moved into Settings, so each preference has one place to change
  it. Existing choices carry over.

## 0.2.0 — 2026-11-01

A rebuilt native workbench with new compositions: frame screenshots as a phone,
tablet, or browser window, on a transparent canvas or over a background.
Installs from 0.1.1 update in the App; 0.1.0 users install the DMG once.

### Added

- Phone, tablet, and browser shells. Browser windows come in Safari and Chrome styles,
  16:10, 16:9, or 4:3 ratios, and light or dark colors independent of the App theme.
- Background compositions on 1:1, 4:3, 16:9, 3:4, or 9:16 canvases, with a solid color,
  a two-stop gradient with adjustable start and end colors, three preset images, or your
  own image. Your image stays selectable after you try a preset.
- Device size, position, and shadow (none, soft, strong), plus device opacity over a
  background. Device size snaps at 100% and warns when larger sizes crop the device.
- Direct manipulation in the preview: drag the device to move it, drag empty canvas to
  pan an image background, or press ⌥ and an arrow key to nudge by 1 px.
- JPEG export with quality and fill color for background compositions, and PNG
  file-size presets (original quality, balanced, smallest).
- Undo and redo (⌘Z / ⇧⌘Z) for settings and batch edits, including image removal.
- Output preview (⌥⌘P), settings panel toggle (⌥⌘I), previous and next image
  (⌘[ / ⌘]), and zoom in and out (⌘+ / ⌘−).
- An Appearance menu and settings window (system, light, or dark) that applies to every
  window, including About, Settings, alerts, and the updater.
- An empty batch shows an outline of the selected device as the drop target, with
  feedback for accepted, rejected, and appended files.
- Copy feedback in a native capsule that VoiceOver announces. Success dismisses itself
  (hovering keeps it open); failures stay until closed.
- SF Symbols icons and keyboard shortcuts in the More, batch, and image-list menus.

### Changed

- The workbench is rebuilt on native macOS components: the system sidebar and toolbar,
  a floating settings panel, thin overlay scrollbars, and a header backdrop that fades in
  over artwork.
- The zoom controls are a Liquid Glass capsule (− / percentage menu / +) that switches
  between light and dark foregrounds to stay legible over the artwork beneath it.
- The settings panel is grouped into Device, Appearance, Composition, Background, and
  Export, with plainer labels.
- Transparent output is always PNG with an opaque device; JPEG, its fill color, and
  device opacity apply only to compositions with a background.
- The App offers iPhone 18 Pro and iPhone 18 Pro Max. The CLI still renders all six
  iPhone 16, 17, and 18 Pro and Pro Max frames.
- Fit to Window shows every phone model at a consistent size. 100% zoom and exported
  pixels are unchanged.
- Faster thumbnails for large batches: rapidly switching through 500 images dropped from
  24.4 s to 8.5 s in our benchmark, and the sidebar keeps its scroll position.
- Sidebar batch actions are clearer, and the sidebar shows keyboard navigation hints.
- Motion and material respect Reduce Motion, Reduce Transparency, and Increase Contrast.

### Removed

- **Breaking:** transparent padding. Exports always fit the complete device. The CLI no
  longer accepts `--padding`, and a `padding` value in older settings files is ignored.
- Composition templates.
- The Show Transparent Area toggle in the canvas bar and the View menu.

### Fixed

- Tinted and clear App icon variants keep the shape of all three layers.
- The mounted DMG volume shows the Fralo icon.
- Drag-and-drop no longer flickers or leaves a stuck drop highlight.
- The image list no longer collapses to zero height after the sidebar re-expands.
- The settings panel and canvas move together while showing or hiding, including when
  interrupted and with Reduce Motion on.

## 0.1.1 — 2026-10-20

- In-app updates powered by Sparkle 2: check manually from the Fralo menu, or let Fralo
  check once a day. Updates are never downloaded or installed silently.
- Release notes, download progress, and install-and-relaunch, with Ed25519-verified
  update archives.
- Installing waits for running exports and open file dialogs to finish.
- Failed checks and downloads can be retried; downloads can be canceled.

0.1.0 has no updater, so 0.1.0 users install 0.1.1 from the DMG once.

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
