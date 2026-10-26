# Fralo Design System

The shared AppKit module `FraloDesignSystem` defines the application chrome used by the development lab and future workbench. It compiles in Debug and Release. The development gallery is a separate, Debug-only consumer.

## Scope and roles

This phase supplies reusable controls and experiments before the product workbench is rebuilt. It does not replace the current window or add production iPad/browser/background rendering.

| Role | Meaning |
| --- | --- |
| Workspace | Standard macOS material, allowing restrained desktop color blending |
| Floating panel | Denser system material with consistent insets and boundaries |
| Artwork | An independent, accurate output image, never tinted by desktop material |
| Preview backing | A neutral checkerboard under transparent artwork; never part of export |

`FraloStyle` owns typography and structural spacing. System colors keep text, controls and selection compatible with effective appearance. The current spacing steps are 4/8/12/16/24/32 pt. These are Fralo specifications, not Apple-mandated dimensions. Native controls keep their intrinsic sizing and behavior.

## Components

| Family | Shared implementation |
| --- | --- |
| Text and structure | `FraloStyle.text`, `paragraph`, `stack`, `FormRow`, `InfoRow`, `FormSection` |
| Actions | `ActionButton`, `IconButton`, `ExportAction` |
| Value selection | `ValuePicker`, `ChoiceMenu`, `ToggleControl`, `ValueField` |
| Content navigation | `InspectorTabs` backed by `NSTabView` |
| Continuous and color input | `SliderRow`, `ColorChoice` |
| Background selection | `BackgroundSwatch`, `SwatchPicker` |
| Batch browsing | `BatchEntry`, `ThumbnailRow`, `BatchList` |
| Surfaces and layout | `NeutralSurface`, `MaterialSurface`, `FloatingPanel`, `CollapsedRail`, `ScrollContent` |
| Viewing | `CanvasSurface`, `ViewToolbar` |
| Feedback | `StateView` with empty/loading/failure/progress states and relevant actions |

Custom keyboard controls route Tab/Shift-Tab through the window key-view loop, respecting macOS keyboard-navigation eligibility. The lab recalculates the loop after rebuilding its content. The canvas exposes an image role, name, size and keyboard help.

Parameter choices use radio-group semantics and one shared selected indicator. Tabs use actual content-navigation semantics. Restoring a value does not emit an edit. Disabled controls do not emit edits; invalid or nonfinite numeric values do not propagate. Primary export always means the whole batch; the dropdown's current-image action does not change it.

## States and accessibility

Native buttons, popups, color wells and sliders provide their system press, hover, focus and accessibility behavior. Custom choices expose named radio groups and values. Lists expose rows and selection. New controls need all applicable default, selected, disabled, focused, busy and error states in the real gallery.

`DesignPreferences` is per-preview state. Preview requests can strengthen reduced transparency, reduced motion and increased contrast, but cannot turn off a user's active system setting. `MaterialSurface` observes accessibility display changes and follows window activity. Reduced transparency selects an opaque system-color fallback. `FraloMotion` uses 180/220/160 ms for selection/structure/preview, or zero under reduced motion.

Production uses semantic roles. Artwork colors, user-selected backgrounds and deterministic rendering fixtures are explicit exceptions; they must not become application control colors. Material and motion experiments cannot silently change stable defaults.

## Reuse policy

- Import the shared module instead of copying gallery controls or restyling individual business pages.
- Add a named role/variant and a gallery example when a real shared need emerges.
- Keep candidate material parameters in the lab until selected and promoted to stable roles.
- Prefer configuring/combining AppKit controls over reimplementing menus, dialogs or color pickers.
- Keep selection, input validation, focus routing and state propagation in the shared implementation.

Existing FRALO-4 style and orientation-choice work was inspected for reuse. The generalized picker reuses its approach to native buttons, a moving indicator, keyboard input and radio semantics. The old branch was not merged, and its fixed-column/padding layout is not adopted.

See [the development lab](development-lab.md) for running and [acceptance evidence](design-system-acceptance.md) for verification limits.

## Experimental button skin

The Debug lab offers a **soft-button candidate** next to the current native styles. Its `NSButton` implementation and gallery live in `Development`, guarded by `FRALO_DEV`, while the default `ActionButton` remains unchanged. Candidate drawing uses a restrained accent fill, rounded neutral surfaces, light highlights and semantic action roles. These geometry/color treatments are Fralo design choices.

This separation keeps an unaccepted experiment out of production dependencies. Human visual approval is required before promoting the skin into a shared stable variant. See [the lab](development-lab.md#soft-button-candidate) for the working comparison and state examples.

## Apple references

- [Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [NSVisualEffectView](https://developer.apple.com/documentation/appkit/nsvisualeffectview)
- [Window-background material](https://developer.apple.com/documentation/appkit/nsvisualeffectview/material-swift.enum/underwindowbackground)
- [Reduced transparency](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducetransparency)

The deployment target remains macOS 14. Newer visual treatments are not a reason to raise that target without a separate decision.
