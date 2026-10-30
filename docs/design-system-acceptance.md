# Design-system acceptance — FRALO-5

Implementation scope: Debug-only native development lab and the shared AppKit design system. The existing product workbench and production renderer remain the baseline.

## Executed checks

Verified locally on 2026-10-27 on Apple Silicon. The minimum supported target remains macOS 14; this run does not establish runtime compatibility on every supported OS version.

| Check | Observed result |
| --- | --- |
| Debug build and `swift test` | Passed: 36 tests — 14 shared-control tests, 12 core tests, 6 development tests, 4 updater tests |
| Release shared-control tests and local package | All 14 shared-control tests passed in Release; ad-hoc packaging passed, no publication |
| `scripts/verify_cli.py` | Passed all 10 checks, including isolated settings, partial failure, cancellation and source preservation |
| `scripts/verify_design_system.py` | Debug contains Dev symbols; Release excludes them; shared module compiles for Release; packaged binary matches verified Release code; no Dev fixture resources |
| Runtime probe | All 22 observations passed, with 13 view-cache captures; report bound to the current Debug executable |
| Native window inspection | Five pages reachable; real radio/tab accessibility roles; scenario sliders use full form width; aligned panel edges; local appearance changes and opaque fallback visible; native Tab moves from a parameter to the numeric field and Shift-Tab leaves it; canvas name/size/help exposed |
| Source checks | `git diff --check` and `scripts/check_public_source.py` passed |

The shared-control tests cover no-edit restoration, single selection, disabled/busy behavior, value validation, available slider width, focus transfer from canvas to parameter controls, forward/reverse Tab navigation, export action separation, list identity, viewing geometry and reduced-transparency fallback. Development tests cover unchanged isolated product settings, real sample changes, artwork independence from appearance, and motion-page state independence.

The runtime probe covers the developer menu, absence of product import/export actions in the lab menu, fixtures/five pages, collapse geometry and image-size preservation, preview focus/Escape, canvas arrow routing, control arrow isolation, Tab leaving a live parameter, transparent output, accessibility fallback and minimum-window layout. It is an in-process native probe, not a replacement for user input testing.

The follow-up keyboard fix was verified in the real gallery: forward Tab selects the numeric field and reverse Tab reaches the list under the current system key-view policy. The lab recalculates its focus chain after rebuilding pages. No global keyboard-navigation preference was changed.

Native screenshots and process/build provenance are retained outside the source tree with the task's local verification evidence. View-cache captures are layout evidence only: macOS compositing can omit material layers from those images.

## Selected button style adopted

The user selected the soft style and authorized its promotion. The implementation now lives in the shared module as the default `ActionButton`, with centralized regular/compact metrics. `IconButton`, export/status actions and the entire lab use it. The Dev-only duplicate was removed; the native row remains an explicitly labelled comparison. The production workbench rewrite remains a later phase.

- All 34 Debug tests and all 14 shared-control tests in Release passed. Button tests now belong to the shared test target. They cover busy width/callback suppression/availability restoration, dynamic labels/tooltips, role and Tab navigation.
- The native probe checks shared controls, button semantics and busy-width preservation, alongside existing five-page/minimum-window/focus/image-isolation checks. Default and pressed captures exercise the actual shared button.
- Native Scenarios inspection covered light/dark appearances, regular export/add actions and compact preview/sidebar controls. No layout-constraint diagnostics appeared in the probe run. A stale export-count tooltip found during inspection was corrected and covered by the shared export-action test.
- Release packaging excludes the lab/gallery/fixtures while retaining a Release-compilable and tested shared design system. The earlier CLI checks remain applicable: no Core/CLI, saved-settings, package-manifest or CLI-verifier source changed.
- Button visual direction is selected. A complete keyboard traversal, VoiceOver speech, diverse-desktop material perception and final full-stage human review remain separate.

## Scroll layout follow-up

The reported source list was constrained to 240 pt inside a second scroll view; the inspector inherited a fixed 540 pt tab height. Two actual-window regression tests reproduced the empty panel space, unchanged viewport after resizing, nested scrolling and unnecessary short-form overflow before the fix. Both now pass: the list grows by 300 pt when its window grows by 300 pt, and short device settings fit without forced overflow. Headers, inspector tabs and footers stay fixed while only their middle content scrolls.

Native overlay scrollers replace the persistent white gutter. A live 100-image Scenarios window was inspected and scrolled through CUA; visible rows advanced from 1–7 to 7–13. The runtime probe additionally reaches row 100. Final full Debug tests, Release shared tests, packaging and binary/probe isolation checks passed; no layout-constraint diagnostics appeared in the final targeted layout run. Earlier CLI evidence is reused after confirming Core/CLI and its verifier are unchanged. Full human styling/material/motion acceptance remains pending.

## Remaining manual acceptance

- Compare Materials over varied desktop colors and with the window active/inactive. The inspected desktop was neutral; no global wallpaper or accessibility preferences were changed.
- Review selection, sidebar collapse and preview motion in the real window. Compare the local reduced-motion preview.
- Confirm the component styling and the 0/3/100-image scenarios feel suitable for the next workbench stage.
- VoiceOver speech and a complete keyboard traversal have not been accepted. Native roles, canvas name/size/help and selected/disabled values were inspected. Targeted arrow routing plus real forward/reverse Tab navigation were exercised; these do not establish a complete keyboard traversal.
- Actual OS accessibility setting changes and macOS 14 runtime behavior remain untested on this machine. Local stronger-setting previews are not proof of those system transitions.

The implementation is ready for full-stage manual review. The soft-button direction is selected; final acceptance of the complete lab appearance/motion is still pending; no acceptance, merge, release or subsequent workbench-rewrite authorization is inferred from automated checks.

## How to review

Run `scripts/run-design-lab.sh`, or use **开发 → 设计实验室…** in a Debug build. The shortcut is Command-Option-Shift-D.

1. Browse Components, checking enabled/disabled controls, parameter choices and native tabs.
2. In Materials, compare system materials and local appearance/accessibility previews. The center image should keep its own colors.
3. In Motion and Scenarios, collapse the list and enter/leave clean preview. Use Escape to return and arrow keys to switch images when the canvas/list has focus.
4. In Scenarios, inspect empty/loading/failure states, 100 entries, long names and the export page's PNG/JPEG conditional controls.

Phone examples use the existing core renderer. iPad/browser are labelled layout fixtures. Export actions demonstrate interaction only and write no product files; new production renderers and JPEG export belong to the next task.

## Native capsule segments — FRALO-10 (2026-10-30)

The user selected the native `automatic / tabs / capsule / large` reference and authorized implementation. Production output-mode/device-category switches now use large native capsule tabs; background type, format, compression and shadow use small native capsule value selection. The development lab consumes the same implementation. Apple HIG references and compatibility/toolchain behavior are recorded in [the design system](design-system.md#native-capsule-segments-fralo-10).

Local verification used macOS 27.0.1 / Xcode 27. Debug tests reported 122 executed, one opt-in desktop-performance probe skipped and zero failures. A final targeted run covers native commit/restore/disable behavior, target/action delivery, focus, undo/redo and development consumers after removing the obsolete custom-motion preview settings. Debug preview packaging and Release build passed. Both executable load commands retain a macOS 14.0 minimum; this is deployment metadata, not proof of running on every supported OS.

The real packaged workbench was inspected with a repository fixture at 1200 × 800 and 1030 × 640, in light and dark. The 312 pt inspector keeps all segment labels readable. Its content scrolls to format/compression at minimum size while the export footer stays visible. Empty-state behavior is unchanged: an explicitly opened inspector permits preconfiguration, while export/copy remain disabled.

Actual pointer input verified horizontal mode-drag submission and upward/downward/diagonal drag-out cancellation, followed by one-step undo and redo. After pointer selection, arrows changed device or shadow within the focused control; Tab/Shift-Tab left it. PNG/JPEG changed the corresponding settings and summary. The accessibility tree exposed mode/category choices as tabs and parameter choices as radio buttons. This does not establish full VoiceOver speech coverage.

Local captures are outside the checkout at `/tmp/fralo-10-preview/`: `final-light-1200.png`, `sample-dark-1200.png`, `sample-light-1030.png`, `sample-dark-1030-top.png`, `sample-dark-1030-export.png`, and `empty-light-1200.png`. The kept preview bundle is under this task worktree's `.build/workbench-preview/session-qkocpcvd/`; its executable UUID matches the final Debug build. Its settings file is isolated from the installed product.

Not verified: physical macOS 14–26 behavior, a real Xcode 26 CI run, full VoiceOver traversal/speech, global accessibility-setting changes, or the transient Find My glass-lens effect. The lab was compiled/tested but not manually inspected in this pass. No export was performed during UI verification; renderer/export source was unchanged. No merge or release is included.
