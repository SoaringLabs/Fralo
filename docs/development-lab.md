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

Materials includes a Debug-only **背景通透感** experiment. **材质层不透明度** fades only the native background effect (100% retains the original native material; 0% removes its blur/tint). **背景遮罩浓度** adds a semantic window-background tint above that effect (0–100%). These percentages are not a native blur-radius or transparency-strength API. Quick comparisons are 更通透 (65/0), 更柔实 (100/35), 实色参考 (100/100), and 恢复原生效果 (100/0). Values survive tab/appearance changes during this lab session; global reset restores 100/0. Nothing is saved to product settings or exported artwork.

The lab window has a clear nonopaque base. Only Materials removes its neutral root/tab fill so the experimental region can composite with the actual desktop; other pages retain their neutral surface. The image and inspector do not inherit the effect layer's opacity. Reduced-transparency settings disable the sliders, hide the experimental tint and restore the opaque fallback, while retaining the selected values for later comparison. Use a varied desktop backdrop and compare focused/unfocused states; native desktop composition still needs direct observation.

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


## Transient panel-edge comparison

Use `scripts/run-workbench-preview.sh --panel-render-check` only when investigating the reported intermittent square black edge around floating panels. Its small diagnostic bar provides A (original rendering), B (disable whole-glass interaction feedback), C (disable the extra panel-layer shadow), and D (clip panel surfaces to their rounded bounds). Each choice first restores the captured baseline, then changes one factor. B is initially selected in this explicit diagnostic session. The normal Debug app and Release defaults remain unchanged.

On systems with interactive glass, compare A and B using the same repeated menu/list clicks. B retains glass material, workspace translucency, control input and the existing control feedback. C is only informative when the baseline extra-shadow opacity is nonzero; otherwise it is equivalent to A for that factor. D is a separate clipping experiment, not a combined fix. Stop/restart without the flag to leave the experiment. No image settings are saved by these controls.

Optional `--panel-render-report=/absolute/path.json` records a bounded event history with the actual variant, window activity and public layer properties. It does not capture pixels or identify a visual failure. The report's parent directory must already exist. Discrete single-window captures did not reproduce the user's brief intermittent artifact; the current comparison therefore needs direct human observation. Passing comparison-isolation tests or build checks does not mean the artifact is fixed. The diagnostic type and flags are excluded from Release and checked by the binary-isolation verifier.
