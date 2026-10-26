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
