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

The selected neutral native capsule artwork is now shared by content and parameter selectors. All use native tabs drawing on macOS 27 with a macOS 27 SDK build; large mode/device controls and small shadow/background/format/compression controls retain their hierarchy. Dark mode uses the matching native neutral gray rather than a fixed white color. The [design system](design-system.md#native-capsule-segments-fralo-10) records Apple HIG/API references and compatibility behavior.

Accessibility is explicit for both purposes. Content exposes a tab group with the system tab-button subrole; parameters expose a radio group and radio children without the tab subrole. Owned elements report localized roles/descriptions, labels, values/selected/enabled state, press actions, parent/window/frame and focus. They remain stable across value restoration. Selection updates notify old/new elements and the group's selected children; focus notifications are restricted to enabled options in the key window.

Two regressions caught during real-app verification were corrected and covered: delegating content AX getters to NSView super lost the cell's tab semantics, so content now owns an explicit tab tree too; native key-view eligibility excluded the selectors from the automatic window loop, so enabled/visible/attached selectors now register as key views. Hidden/disabled selectors are excluded. Both content and parameter semantics plus automatic key-loop participation have regression tests.

Final Debug suite: 126 executed, one opt-in desktop performance probe skipped, zero failures. The focused selector/focus tests passed. Debug preview packaging and Release build passed, with macOS 14.0 minimum in both executable load commands. This confirms deployment metadata rather than physical legacy-system runtime behavior. Local final test/build logs are `/tmp/fralo-10-neutral-final-tests-recheck.log` and `/tmp/fralo-10-neutral-release-verified.log`.

One earlier full-suite run failed the existing JPEG-preview/raw-PNG copy comparison (278022 versus 277951 bytes). Preserved images decode to the same 1444 × 2964 size but differ in 22286 RGBA channels, with maximum delta 76; this was a real output discrepancy, not metadata-only. The isolated test and subsequent entire suite passed without renderer/export changes or relaxed assertions. Cause remains undiagnosed. Buffers are preserved at `/var/folders/8r/xdsf4nhn2cj4yb9030z85w900000gn/T/fralo-copy-mismatch-D2EA0CEC-4702-4F15-AEDB-CC1165ADA63B`; do not treat this pass as resolving that intermittent output issue.

Actual GUI checks on macOS 27.0.1 used light/dark 1200 × 800 and 1030 × 640 windows with repository fixtures. All inspected segments have matching neutral native artwork. Minimum-window scrolling reaches format/compression while the export footer stays visible. AX clicks after scrolling reach the intended option. One-step undo/redo updates AX selection/value. In the lab Components page, the disabled shadow group and all three radio children are disabled and ignore activation.

With system Keyboard Navigation already on, real Tab traversed list → canvas → output mode → device category → shadow → format → list, and reached shadow again on another loop. Shift-Tab reversed through shadow → device → mode. Mouse then arrows stayed in the focused parameter and did not switch the source image. PNG/JPEG's conditional form rebuild preserved focus; AX focus on an unselected option does not edit it, and Space activates it. Automated checks additionally cover skipped disabled options, silent restoration, dynamic frames after window movement/resizing, and clipped hit testing after scrolling.

Targeted VoiceOver speech was attempted. VoiceOver could be enabled, but the current CUA tool could not bind the independent caption panel or capture its text; screenshots of a selected app window do not include that separate panel. No actual speech/caption pass is claimed. VoiceOver was restored to its original off state. Caption-panel preference remained at its original on value, and Keyboard Navigation remained at its original on value. `voiceover-restored-off.png` and `keyboard-navigation-original.png` record these observations. Full VoiceOver traversal/speech remains pending, as do physical macOS 14–26, a real Xcode 26 CI run, global reduced-motion/transparency/contrast changes, and the transient Find My glass lens.

Evidence is outside the checkout in `/tmp/fralo-10-neutral-preview/`: `final-light.png`, `dark-background.png`, `min-dark-top.png`, `min-dark-export.png`, and `min-light-export.png`. The capsule-verification preview `.build/workbench-preview/session-8_jcsynj/Fralo Workbench Preview.app` used isolated settings and a repository fixture; its executable UUID matched the final Debug build. No manual export or release was performed. Renderer/Core/CLI source is unchanged.

Both Workbench Preview and Design Lab now compile the existing layered app icon with the same flags as production, merge the generated icon metadata, then sign the bundle. Both packages contain nonempty `Assets.car` and `Fralo.icns`, expose `CFBundleIconName` and `CFBundleIconFile`, and pass deep/strict signature verification. The icons returned for the actual running applications were visually checked as the Fralo artwork; a Dock desktop screenshot was not available through the current UI tool. Both app windows were inspected successfully.

The launch scripts now build first, stop only the matching kind of preview under the exact current workspace path, verify exit, and launch the replacement. They request termination, escalate unresponsive processes to a forced kill, and abort if cleanup fails. `--build-only` leaves current previews running. Four Python regression tests cover workspace/kind isolation, graceful termination, forced escalation with PID-path revalidation, and failure propagation; CI includes them. Actual build-only checks preserved all three old previews, then normal launches terminated those three and left exactly one new Workbench and one new Design Lab process, each with a usable window. Logs and process-path snapshots are retained as `/tmp/fralo-process-launch-*.log` and `/tmp/fralo-process-handoff-*.json`. The project rules require this handoff for subsequent debug launches too.
