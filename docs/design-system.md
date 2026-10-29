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

Production uses a docked 230–280 pt left sidebar with no exterior radius or shadow, and a standard leading navigation toolbar toggle. Full collapse removes the sidebar entirely; the compact thumbnail rail remains a lab-only experiment. The right inspector has a fixed 360 pt width and retains 24 pt floating-panel radii, 18 pt panel insets, a 30 pt rounded value picker (36 pt for output mode), 32 pt soft native popups, 88 pt batch rows and 72 × 66 pt proportionally contained thumbnails. `InspectorTabs(style: .floating)` retains an actual borderless `NSTabView` with a persistent, 34 pt icon-labelled navigation bar above the scrollable page; the lab's five-section navigation may use the standard style. `ExportAction` is a full-width 40 pt split action with separate whole-batch and current-image callbacks, press/hover feedback and keyboard focus. `ViewToolbar` can expose a real canvas-ratio popup alongside viewing scale and clean preview.

`VisualChoiceGroup` supplies literal thumbnail radio choices with restrained accent fill, fine selected outlines and checkmarks. The phone inspector offers iPhone 18 Pro and 18 Pro Max as two cards per row, each showing its screen size. Mouse, arrow keys and accessibility use the same selection path; value restoration and asynchronous artwork updates do not emit edits. Inspector rebuilds restore the focused parameter so arrow keys remain local. The development Components page includes enabled/disabled card samples. Product thumbnails render the complete current input off the main thread; stale requests cannot replace a newer or cached selection. No recognition, corrective cropping or original-file writes are involved.

Panel surfaces use `NSGlassEffectView` on macOS 26 and later. All foreground children must be added to `MaterialSurface.contentView`, which is hosted as the native glass content view; arbitrary glass siblings are not a supported foreground arrangement. Earlier systems retain the `NSVisualEffectView` panel recipe. Reduced transparency adds an opaque semantic backing without hiding controls, and the workspace remains on its existing visual-effect recipe. Application appearance can follow the system or select light/dark through the View menu; this does not change composition pixels or system appearance.

The shared surface also clips its entire render subtree to its own rounded bounds. A native glass radius shapes the glass effect but is not a fence for every descendant layer. Keep `clipsToBounds` and backing-layer masking enabled for native glass as well as the legacy recipe. A pixel regression guard checks modeled rectangular child-layer overrun, transparent corners and retained foreground content through light/dark appearance changes. This is a boundary contract test, not proof of reproducing an intermittent system compositor artifact.

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


## Column-aware native header

The production header follows the window's column ownership. A full-height native `NSSplitViewController` sidebar and `NSTrackingSeparatorToolbarItem` align the left titlebar region with the sidebar divider. Add Images and the sidebar toggle stay in that region. The content region owns the current filename/count, adjacent native toolbar buttons for Copy/Export Current sharing a glass group, an independent Inspector button, and `NSMenuToolbarItem` for More. Window chrome is transparent and has no full-width bottom separator. When the sidebar is hidden, its toolbar separator is removed while Add/Toggle remain reachable. The sidebar is a system `NSSplitViewItem(sidebarWithViewController:)` that supplies its own material and edges; the sidebar toggle keeps the same bordered glass button in both states. The window background is standard (opaque), and the stage behind the content column keeps its own behind-window `.underWindowBackground` material (not the sidebar material), so the columns read apart while the floating inspector keeps its contrast.

The previous full-width header and duplicate full-width sidebar Add action are superseded. Native toolbar items own titlebar sizing, hover, menus and hit areas; shared Fralo components continue to own the workbench controls. The right inspector remains 360 pt wide. Its production surface uses native visual-effect material instead of native glass hosting because the latter showed displaced content when a containing split pane moved. Radius, tint, shadow and accessibility fallbacks are retained. The explicit Debug compositor probe may still opt into glass.

The implementation follows [Apple's sectioned toolbar API](https://developer.apple.com/documentation/appkit/nstrackingseparatortoolbaritem) and [full-height sidebar guidance](https://developer.apple.com/videos/play/wwdc2020/10104/). The runnable result and local verification are recorded in workbench-migration.md.

Toolbar groups follow actions rather than proximity: Copy and Export Current share
a native output group; Inspector and More each have their own round native button.
Fixed spaces keep Add and Sidebar independent too. Filename/count explicitly use
`isBordered = false`. Build/preview scripts select the native SwiftPM backend to
record the actual SDK and allow AppKit to render these shapes; see CONTRIBUTING.md.

The output pair uses native toolbar-style NSButtons with 44 pt width and 36 pt
height. This follows an observed Notes toolbar reference (approximately 44 pt
between icon centers). Adjacent toolbar items merge into one system glass
surface, without the divider or tighter spacing produced by NSToolbarItemGroup's
segmented representation. Tooltip, accessibility label, enabled state and target
action remain native and independent for each button.


### Sidebar scrolling

The production batch sidebar opts into native vertical scrollbars, with the current
`NSScroller.preferredScrollerStyle`; the inspector and lab panels retain their
existing hidden indicators. The scroll viewport fills the sidebar, while 10 pt
horizontal row insets keep thumbnails, selection and keyboard focus aligned
independently of overlay or legacy scrollbar gutters.

On macOS 26 the fixed image heading is a split-item top accessory, which supplies
safe-area insets and the system scroll edge effect. macOS 26.1 and later use the
native soft edge to match the supplied reference: automatic produced a hard edge
for the unboxed title. The count uses full label contrast to stay readable
on the material. macOS 14/15 use a fixed `headerView` material with within-window
blending and explicit content/scroller insets; Reduce Transparency makes this
compatibility header opaque. Both paths keep the first and keyboard-selected
rows below the heading, and include the heading in sidebar focus ownership.

This follows [Apple's scroll-edge guidance](https://developer.apple.com/design/human-interface-guidelines/scroll-views)
and [split item accessory guidance](https://developer.apple.com/videos/play/wwdc2025/310/).
The soft edge is a deliberate choice based on the user reference and requires
legibility checks in light/dark appearances; it is not a claim that Find My uses
the same internal implementation.
