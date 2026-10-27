# Fralo development lab

The lab is an independent native window for examining shared controls, system materials, motion and layout cases before rebuilding the product workbench.

## Open the lab

From a Debug build, choose **开发 → 设计实验室…**. The shortcut is Command-Option-Shift-D. Reopening reuses the same window.

For an isolated preview, run from the repository root:

```sh
scripts/run-design-lab.sh
```

This builds Debug, creates a separate `Fralo Design Lab.app` with bundle identifier `app.fralo.designlab.local`, includes development fixtures, and runs with a temporary `FRALO_SETTINGS_PATH`. It does not replace an installed Fralo or use its saved preferences domain. Bundles are under `.build/design-lab-preview/`; the script prints the exact path. `--build-only` prepares a bundle without launching it.

## Areas

| Area | Purpose |
| --- | --- |
| Foundations | Stable typography, surface roles, spacing and motion rules |
| Components | Shared controls, native/soft-button comparison, disabled/busy states, long names and status views |
| Materials | Live native material candidates and blending modes around an independent image |
| Motion | Replay choice, list collapse and clean preview; compare reduced motion |
| Scenarios | Phone/iPad/browser layouts, transparent/background modes, inspector pages, 0/3/100 inputs, long names and loading/failure cases |

The appearance selector changes this window only. Preview checkboxes strengthen accessibility behavior locally; the footer separately reports actual OS settings. System-setting changes also refresh the lab. Reset restores local experiment values, not user product settings.

In Scenarios, the image list fills the space between the fixed panel header and footer and grows with the window. Each inspector page owns one scroll view; the mode selector, tabs and export footer remain visible. Native overlay scrollers hide automatically without a persistent white gutter. Short settings pages do not force overflow.

## Shared button style

Components starts with **按钮规范 · 柔和定制**. The user-selected soft style now comes directly from `FraloDesignSystem.ActionButton`; the labelled native row remains a comparison. Roles, disabled/busy examples, processing replay, focus check and the panel example all use the shared implementation.

The same style appears in Scenarios, Motion, preview tools, export actions and status/retry actions. Regular and compact metrics are centralized in `FraloStyle.Button`. Try both light/dark appearance and the local accessibility previews. Busy state preserves width and prevents duplicate activation; default labels/tooltips follow title updates.

The gallery is Debug-only. The selected reusable button is available to Debug and Release consumers. FRALO-6 now uses these controls in the real production workbench; see [migration evidence](workbench-migration.md).

## Isolation

The entire `Sources/FraloApp/Development` implementation is guarded by Debug-only `FRALO_DEV`. Release has no registered development menu, flags, lab window, probe or fixture loader. `Development/Fixtures` is excluded from SwiftPM resources and copied only by the Debug launcher. Normal packaging does not copy it.

The shared `FraloDesignSystem` remains a Release-compilable library. The production workbench now imports the same module. The gallery remains an independent Debug consumer.

While the lab is key, it uses a separate menu bar with standard responder-chain editing and no product import/export actions. The product menu returns when its window becomes key. This prevents lab actions from changing the user's batch. Standalone preview skips update-check initialization and isolates its settings file.

## Sample boundaries

Phone samples use the existing core renderer and fictional example inputs. Selecting a different source changes sample content. iPad/browser outputs are deliberately labelled **layout fixtures**, not new production renderers. Background compositing studies layer isolation and layout only.

Scenario export buttons report their action without writing product output. JPEG settings demonstrate conditional controls, not implemented production JPEG export. Those capabilities are now implemented in the FRALO-6 production workbench; the lab deliberately remains an isolated demonstration.

The background fixtures were generated for the approved exploration; see [fixture sources](../Sources/FraloApp/Development/Fixtures/README.md). No private screenshots are bundled.

## Verify

```sh
swift test
swift build -c release
scripts/run-design-lab.sh --design-lab-probe=/absolute/temporary/directory/probe.json
python3 scripts/verify_design_system.py --probe-report /absolute/temporary/directory/probe.json
```

The probe exercises its live process, writes a report and view-cache images, then exits. Add `--design-lab-keep-open` to restore default experiment settings and retain Components at the normal window size for review. Evidence binds to the running executable's checksum; the verifier compares its Mach-O sections and UUID with the current build, allowing packaging signatures to differ. Rerun after rebuilding.

The verifier checks actual Debug/Release Mach-O symbols, the Release shared module, required runtime observations and snapshot presence. `--release-app dist/Fralo.app` also checks the packaged binary and exclusion of development fixtures.

View-cache captures can omit native composited surfaces. Use actual window screenshots for material/contrast review. VoiceOver speech and human animation/material review remain separate. See [acceptance evidence](design-system-acceptance.md).


## Whole-window material verification

For a controlled desktop-composite check, start the isolated production preview with `--workspace-material-check`. This Debug-only flag places a red/blue native window immediately behind the real workbench. The development menu offers an opaque-window reference and **结束材质底板验证** to remove the test backdrop. Optional `--workspace-material-report=/absolute/path.json` records window/material/accessibility state without modifying settings or artwork. This probe requires direct native observation; single-window captures may look flatter than the desktop composite. The normal preview has no backdrop or probe menu items.
