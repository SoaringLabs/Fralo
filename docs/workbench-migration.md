# Production workbench migration — FRALO-6

Design basis: the selected FRALO-5 native lab and the approved 2026-10-26 design specification. The user authorized creating and implementing this task; merge and release remain separate.

## Delivery stages

1. Real workbench: shared material surfaces, aligned floating panels, expanding source viewport, compact rail, shared actions and independent artwork. Connect real import, append, remove, clear, preview, copy and batch output. Keep native menus and file dialogs.
2. Composition: one phone and one tablet, Safari/Chrome, transparent/background modes, complete source containment, canvas ratios, independent device/background scale/opacity/position, shadows and preset/local backgrounds. No content inference or corrective crop.
3. Output: PNG/JPEG and explicit JPEG fill, unified preview/export/copy, stable export-all action, snapshot/cancellation/partial failure/source protection, old settings and CLI compatibility, local native review and Release isolation.

## Current evidence

Stage 1 is implemented. The production window composes `FloatingPanel`, `BatchList`, `CollapsedRail`, `CanvasSurface`, `ViewToolbar`, `ActionButton` and `ValuePicker` directly. The source list shows source thumbnails. Refreshing entries preserves selection without re-emitting an edit; this avoids repeated preview requests when thumbnails arrive. Delete continues through the shared native list. The existing business renderer/output are still the legacy implementation at this checkpoint.

All 37 Debug tests passed, including an actual production-window test that imports two distinct source files, deduplicates identity, waits for real rendering, collapses the sidebar without changing artwork, checks two window sizes, removes/clears the batch and verifies original bytes/settings preservation. No constraint diagnostics appeared. Live native inspection and the later composition/output stages remain outstanding; this is not a claim that the complete migration is finished.

FRALO-5 foundations were locally cherry-picked into this base-derived task branch to reuse the exact shared implementation. The source worktree remains intact. FRALO-4 was not merged. No push, PR, merge or release performed.

## Composition and output now connected

The production inspector has device/background/export pages and a shared mode selector. Phone, tablet and Safari/Chrome shells use the same deterministic composition route for preview, export and copy. A single source is completely contained in the chosen screen; the GUI no longer rejects aspect mismatch or crops to fill. Necessary shell corner/camera masks remain. Shell artwork is original; the tablet/browser drawings are first-version appearances, not claims of pixel-exact hardware reproduction.

Transparent mode has tight device bounds, optional shadow extent and no manual padding/canvas controls. Background mode offers device scale/position/opacity, independent background scale/pan/opacity, center snapping with editing-only guides, five canvas ratios, three shadow levels and three built-in layout combinations. Backgrounds include solid, gradient, three generated neutral images and local PNG/JPEG. Image-background panning is bounded by actual overflow so it cannot reveal an accidental empty border. Returning to the device page resets the background drag target. Small device-drag deltas accumulate before snapping; positions persist on gesture completion.

Canvas output presets are 2400×2400, 2400×1800, 2400×1350, 1800×2400 and 1350×2400 for 1:1, 4:3, 16:9, 3:4 and 9:16. Browser window ratios are independent of the output canvas. Transparent output follows source pixel density and shell geometry; viewing reduction preserves the full output dimensions.

JPEG preview uses the same encoded JPEG/fill settings as output. Copy uses the unflattened composition as PNG even when JPEG is selected. Export-all stays the primary action, with current-image export in the adjacent native menu. Export snapshots composition values and background bytes before processing; source protection, collision policy, cancellation and per-image failure handling reuse `BatchExporter`. Error recovery clears stale failure state and has an explicit retry action.

GUI preferences use a separate `settings.workbench.json` beside the existing settings path. Initial migration inherits the old orientation; GUI choices intentionally converge to one phone and tight transparent bounds. The old CLI configuration, six model identifiers and old crop/mismatch contract remain unchanged. New GUI options are not silently added to CLI parsing. Legacy reports omit the optional composition field; GUI reports include its snapshot.

## Verification and handoff

- 45 Debug tests and 39 Release tests passed (14 shared controls, 18 Core, 13/7 application tests). The six new composition tests exercise all shell kinds/directions, both browser styles, three browser ratios, five canvas ratios, source-edge preservation, shadow extent, independent alpha, JPEG fill, source protection, skip/cancel/failure, migration and reduced preview dimensions. Three production-window tests cover real batches, shared geometry, incremental drag escape from snapping, drag-target reset, failure/retry recovery and exact PNG clipboard bytes under JPEG settings. Clipboard tests use an isolated pasteboard.
- The existing ten CLI integration checks passed on the packaged binary, using generated inputs and isolated configuration.
- The retained lab probe passed all 22 checks and produced 13 captures. Debug/Release symbol isolation, package/executable identity, production background checksums and exclusion of Dev screenshot fixtures passed. Production backgrounds are intentionally packaged separately from the lab fixtures.
- Native CUA inspection covered the real phone/browser workbench, independent canvas, local background file selection, keyboard Down changing the current input, clean preview and Escape recovery. Real file panels exported all three sample images as PNG and JPEG: each batch succeeded 3/3 at 2400×1800. PNG files expose alpha; JPEG files do not. This is actual app output, not gallery simulation.
- Final code review found and repaired sticky center snapping, stale failure marks after recovery, and hidden background-drag targeting. Native export evidence preceded the later clipboard injection/gesture/error-state fixes; the reviewed delta does not change composition/encoding/export execution. Final tests and package/probe checks cover that delta. Final preview is rebuilt from the committed source.

Run `scripts/run-workbench-preview.sh /absolute/input.png` for an isolated Debug trial. It uses a separate bundle identity, temporary settings, the real production controller, production background resources and the Debug lab menu. It skips updater initialization in this preview only. The installed application is not replaced.

Human acceptance of the complete workbench styling/motion and a full VoiceOver traversal remains pending. The tested OS is the local Apple Silicon machine; macOS 14 runtime and alternate desktops/system accessibility transitions have not been established. The migration has not been pushed, merged or released. These limits do not redefine the remaining acceptance as complete.


## Workspace translucency correction

The first production window still had AppKit's opaque-window declaration and a fully opaque background color. The window-level regression test failed for both values. Disabling `isOpaque` alone still failed the background-alpha check; setting the window's base color to clear made it pass. The window alpha remains 1, and the original semantic behind-window workspace material is retained. Artwork/controls are not faded to achieve the effect. Reduced-transparency fallback remains covered.

A Debug-only native backdrop probe provides a red/blue field behind the real workbench and an opaque-reference toggle. It is enabled only by `--workspace-material-check`, with optional `--workspace-material-report=/absolute/path.json` for public AppKit state metadata. Its controls, temporary backdrop and state writer are absent from Release. Temporary material/state/clipping selectors used during diagnosis were removed; they did not become stable defaults.

The user directly observed red/blue transmission when the window was focused and a more opaque appearance on focus loss. This matches the retained `followsWindowActiveState` policy; the user was told this native behavior is the default. Diagnostic window screenshots looked considerably flatter than that direct observation, so they do not independently prove desktop transmission. No global accessibility setting was changed. The test backdrop is stopped before the normal preview handoff; the user's composition configuration is retained.

Apple's state contract: https://developer.apple.com/documentation/appkit/nsvisualeffectview/state-swift.enum . Material appearance follows window activity unless explicitly forced active/inactive; opacity strength itself is supplied by the system material recipe.
# Reference-image calibration (2026-10-27)

The supplied approved mock (`exec-b907247d-57e2-4c7e-aa43-be366eac941d.png`) is the visual target for this pass. Comparison uses the same Safari / background mode / 16:10 shell / 4:3 output / 74% device / soft shadow state. User screenshot 2 instead used transparent iPad mode and a portrait source; that content/state difference is kept separate from UI drift.

Changes consolidate responsive panel widths/insets, same-height elevated panels, full-width mode/action groups, softly styled popups and rectangular parameter choices, icon navigation without a boxed form, larger contained thumbnails and restrained selection, a centred document title and concise toolbar actions, and a floating viewing toolbar with actual canvas-ratio editing. Persistent controls stay outside scrolling forms. Source image containment, composition/export pixels and the default native workspace effect remain unchanged.

Native reference captures use the Debug-only `--preview-window=1400x876` flag with `--workbench-preview` (the full-size-content window includes its titlebar in this geometry). It neither changes installed-app settings nor enters Release. Reference density and generated-mock aspect inconsistencies are normalized before judging fidelity; real output rectangles preserve their exact ratio rather than stretching to match a generated illustration.

Full comparison history, native captures and focused comparisons are retained outside the checkout in the local `fralo-ui-fidelity/` acceptance bundle (its full path is recorded in the private task receipt). Its `design-qa.md` records the observed result and residual differences. Desktop blur/tint varies with backdrop, focus and OS; a screenshot alone cannot prove the desktop composite. Human preference review remains separate from automated checks.

## Glass inspector reference follow-up

The user rejected the previous visual refinement as insufficient and supplied a dark native glass inspector as the new panel/control reference. The user explicitly retained workspace material opacity 100% and overlay 0%; the reference's stronger blue/purple desktop transmission is not adopted. The device/source content, available models and image-handling contract remain unchanged.

The follow-up replaces the panel recipe with native glass where supported, moves foreground content into the correct glass content host, tightens typography and shared control density, and introduces actual rendered thumbnail choices for device orientation, Safari/Chrome and neutral background presets. The fixed one-model phone/tablet row stays neutral; genuine alternatives use fine accent outlines and selected checkmarks. A current-input thumbnail cache runs outside the main thread and invalidates stale work even when returning to a cached input. Rebuilding direction controls preserves parameter focus. The production window offers system/light/dark application appearance without changing OS settings, saved composition or output pixels.

Transparent-shell editing no longer paints an obtrusive checkerboard rectangle behind the device. This is viewing chrome only; export alpha and geometry are unchanged. Background mode still displays the exact output rectangle and ratio. Both expanded panels retain aligned full-height bounds, independent scrolling, persistent tabs and export actions. The reference's extra device/color/orientation options are not simulated as product capabilities.

The new local evidence bundle is named `fralo-glass-inspector`. Native captures, source/build provenance, comparison notes and refreshed checks are recorded there. Automated checks establish behavior and build isolation; they do not establish user acceptance or a pixel match to the reference. The darker reference also uses different source artwork and a colored desktop, which are not substituted into the user's upload or system wallpaper.

## Light appearance and a separate settings window

The user requested a light version and an independent settings window with at least light/dark switching. The new **Fralo 设置** window exposes system/light/dark cards through the shared design system, reachable from the toolbar gear, app menu or Command-comma. A single typed appearance value keeps the workbench, settings window and quick menu selections synchronized. Changes save immediately through the existing preference key and restore on relaunch. The setting affects product window chrome; composition values, source bytes and existing artwork remain unchanged.

Targeted actual-controller tests cover settings selection in both directions, system inheritance, menu consistency, window close/reopen reuse, persisted relaunch, ignored invalid values, nonpersistent preview overrides, byte-identical composition/source files and retained artwork identity. Native light/dark screenshots and final build evidence are retained in the local `fralo-appearance-settings` bundle. A settings-window focus halo found in native review was removed while retaining its selected-card outline and keyboard behavior. The intermittent panel-edge investigation remains deferred at the user's explicit request and is not reopened by this appearance work.

## Rounded render-boundary correction

The user later supplied a camera photo showing an unrounded dark perimeter outside the bottom viewing toolbar, reopening the panel-edge investigation. The toolbar shares `MaterialSurface` with both floating panels. Public AppKit state showed the configured radius remained correct after hosting, and earlier event traces confirmed interactive glass was disabled during the user's B trial. The bottom toolbar has no added panel shadow, so disabling that shadow cannot address this example.

The native-glass branch had explicitly disabled backing-layer masking. The shared surface now enforces both AppKit clipping and rounded layer masking, retaining the existing radius, material, foreground and workspace 100% / 0% recipe. A modeled effect-child perimeter test fails on the old container with 2288 outside pixels plus square-corner paint and passes after the correction with zero outside pixels, transparent corners and retained foreground content across light/dark/light. It uses public test layers to exercise the clipping seam; the original transient GPU/compositor frame has not been automatically reproduced. The local `fralo-rounded-boundary` bundle retains the supplied photo, red/green checks and native candidate evidence. Physical confirmation that the intermittent flash is completely gone remains separate.
