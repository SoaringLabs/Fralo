# Fralo Design System

The shared AppKit module `FraloDesignSystem` defines the application chrome used by the development lab and production workbench. It compiles in Debug and Release. The development gallery is a separate, Debug-only consumer.

## Scope and roles

This phase supplies reusable controls and experiments before the product workbench is rebuilt. The original FRALO-5 stage provided the foundation. FRALO-6 now applies it to the production workbench and composition inspector; see [migration evidence](workbench-migration.md).

| Role | Meaning |
| --- | --- |
| Workspace | Standard macOS material, allowing restrained desktop color blending |
| Floating panel | Denser system material with consistent insets and boundaries |
| Artwork | An independent, accurate output image, never tinted by desktop material |
| Preview backing | Optional checkerboard; the tight transparent-shell editing view uses the workspace behind it. Neither backing enters export |

`FraloStyle` owns typography and structural spacing. System colors keep text, controls and selection compatible with effective appearance. The current spacing steps are 4/8/12/16/24/32 pt. These are Fralo specifications, not Apple-mandated dimensions. Native controls keep their intrinsic sizing and behavior.

## Components

| Family | Shared implementation |
| --- | --- |
| Text and structure | `FraloStyle.text`, `paragraph`, `stack`, `FormRow`, `InfoRow`, `FormSection` |
| Actions | `ActionButton`, `IconButton`, `ExportAction` |
| Value selection | `ValuePicker`, `VisualChoiceGroup`, `ChoiceMenu`, `ToggleControl`, `ValueField` |
| Content navigation | `InspectorTabs` backed by `NSTabView` |
| Continuous and color input | `SliderRow`, `ColorChoice` |
| Background selection | `BackgroundSwatch`, `SwatchPicker` |
| Batch browsing | `BatchEntry`, `ThumbnailRow`, `BatchList` |
| Surfaces and layout | `NeutralSurface`, `MaterialSurface`, `FloatingPanel`, `CollapsedRail`, `ScrollContent` |
| Viewing | `CanvasSurface`, `ViewToolbar` |
| Feedback | `StateView` with empty/loading/failure/progress states and relevant actions |

Custom keyboard controls route Tab/Shift-Tab through the window key-view loop, respecting macOS keyboard-navigation eligibility. The lab recalculates the loop after rebuilding its content. The canvas exposes an image role, name, size and keyboard help.

`FloatingPanel` arranges its header, body and footer; the supplied body owns scrolling. Pin the body to the available middle space and avoid wrapping a `BatchList` in another scroll view. `ScrollContent` configures native overlay, automatically hidden scrollers with a transparent backing and no border. Short forms keep their natural content height; long forms scroll within the available viewport. Inspector tabs stay outside each page's scroll view.

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

## Default action buttons

The selected soft style is the shared `ActionButton` default in Debug and Release. Its implementation lives in `Sources/FraloDesignSystem/ActionButton.swift`; there is no separate Dev copy. `IconButton`, `ExportAction`, state actions, preview tools and the lab reuse it. The production workbench now consumes these shared implementations directly.

`FraloStyle.Button` owns regular/compact heights (34/28 pt), corner radii (10/7 pt), content insets and symbol sizes. These are Fralo choices. Use regular buttons for panel actions and compact controls for toolbars. Keep an icon-only button's explicit accessibility label.

The current calibration uses 24 pt floating-panel radii, 18 pt panel insets, a 30 pt rounded value picker (36 pt for output mode), 32 pt soft native popups, 88 pt batch rows and 72 × 66 pt proportionally contained thumbnails. `InspectorTabs(style: .floating)` retains an actual borderless `NSTabView` with a persistent, 34 pt icon-labelled navigation bar above the scrollable page; the lab's five-section navigation may use the standard style. `ExportAction` is a full-width 40 pt split action with separate whole-batch and current-image callbacks, press/hover feedback and keyboard focus. `ViewToolbar` can expose a real canvas-ratio popup alongside viewing scale and clean preview.

`VisualChoiceGroup` supplies literal thumbnail radio choices with restrained accent fill, fine selected outlines and checkmarks. Its single-model row uses a neutral surface rather than a large accent banner. Mouse, arrow keys and accessibility use the same selection path; value restoration and asynchronous artwork updates do not emit edits. Inspector rebuilds restore the focused parameter so arrow keys remain local. The development Components page includes enabled/disabled card samples. Product thumbnails render the complete current input off the main thread; stale requests cannot replace a newer or cached selection. No recognition, corrective cropping or original-file writes are involved.

Panel surfaces use `NSGlassEffectView` on macOS 26 and later. All foreground children must be added to `MaterialSurface.contentView`, which is hosted as the native glass content view; arbitrary glass siblings are not a supported foreground arrangement. Earlier systems retain the `NSVisualEffectView` panel recipe. Reduced transparency adds an opaque semantic backing without hiding controls, and the workspace remains on its existing visual-effect recipe. Application appearance can follow the system or select light/dark through the View menu; this does not change composition pixels or system appearance.

Panel elevation and a restrained semantic tint belong to panel chrome only. Workspace material remains the complete native effect with no additional workspace tint (100% / 0% in the Dev experiment). `CanvasSurface.showsElevation` adds a viewing-only edge/shadow around background compositions, never changes artwork pixels or output aspect ratio. Batch selection uses a restrained accent fill with normal dark/light semantic text in both active and inactive windows.

The four roles are primary, secondary, quiet and destructive. Busy state preserves width and requested availability; title changes update default accessibility labels and tooltips. Explicit icon labels and custom tooltips are retained. System accessibility changes refresh the button; reduced motion uses a static hourglass for busy feedback, while increased contrast strengthens the border.

`NativeActionButton` is reserved for the labelled native comparison and image-choice cells such as `BackgroundSwatch`. Ordinary action UI uses `ActionButton`; avoid selecting different skins per page. `SoftButtonGallery` is a Debug-only consumer of the shared implementation. See [the lab](development-lab.md#shared-button-style) for comparison and state examples.

## Apple references

- [Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [NSVisualEffectView](https://developer.apple.com/documentation/appkit/nsvisualeffectview)
- [NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview)
- [Native glass content view](https://developer.apple.com/documentation/appkit/nsglasseffectview/contentview)
- [Window-background material](https://developer.apple.com/documentation/appkit/nsvisualeffectview/material-swift.enum/underwindowbackground)
- [Reduced transparency](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducetransparency)

The deployment target remains macOS 14. Newer visual treatments are not a reason to raise that target without a separate decision.

## Application appearance settings

The independent **Fralo 设置** window reuses `VisualChoiceGroup` for system/light/dark appearance. Its small fixed-appearance workbench illustrations are decorative UI previews, not user artwork or screenshots. The selected card has a fine outline/checkmark without an extra focus halo; keyboard selection remains available. The settings window uses a native semantic window background.

Open settings with the toolbar gear, **Fralo → 设置…**, or Command-comma. One typed `AppAppearance` value synchronizes the workbench, settings selection, both window appearances and existing quick menus. It retains the previous `workbenchAppearance` preference key and saves immediately; reopening settings reuses its window and restarting restores the stored choice. System mode clears both window overrides so they inherit macOS appearance. The Dev lab retains its independent appearance experiments.

Changing appearance does not rerender artwork, rewrite composition/CLI settings or change export pixels. The workspace material recipe remains 100% native effect with no added overlay. Debug preview launch overrides are temporary and do not replace a user choice in storage; ordinary preview handoffs omit those overrides.
