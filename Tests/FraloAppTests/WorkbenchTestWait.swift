import AppKit
import XCTest
@testable import FraloApp

/// Yield the main actor between observations; a timeout fails at the call site
/// and stops dependent assertions instead of reading unfinished AppKit layout.
@MainActor
func waitForWorkbenchState(
    _ description: String,
    timeout: Duration = .seconds(3),
    file: StaticString = #filePath,
    line: UInt = #line,
    diagnostics: () -> String = { "" },
    until condition: () -> Bool
) async throws {
    let clock = ContinuousClock(), deadline = clock.now.advanced(by: timeout)
    while !condition() {
        guard clock.now < deadline else {
            XCTFail("Timed out waiting for \(description). \(diagnostics())", file: file, line: line)
            throw WorkbenchWaitTimeout()
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}

private struct WorkbenchWaitTimeout: Error {}

@MainActor
func waitForSidebar(_ root: WorkbenchView, collapsed: Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
    try await waitForWorkbenchState("sidebar \(collapsed ? "collapse" : "expansion")", file: file, line: line,
                                    diagnostics: { workbenchState(root) }) {
        root.layoutSubtreeIfNeeded()
        let items = root.window?.toolbar?.items ?? []
        let boundaries = items.filter { $0 is NSTrackingSeparatorToolbarItem }.count
        let geometryReady = collapsed
            ? abs(root.content.frame.width - root.splitView.bounds.width) < 1
            : root.left.frame.width >= root.sidebarItem.minimumThickness - 1
                // AppKit may overlay the divider instead of allocating its width.
                && abs(root.content.frame.width + root.left.frame.width - root.splitView.bounds.width) <= root.splitView.dividerThickness + 1
        return !root.movingSidebar && root.collapsed == collapsed && root.sidebarItem.isCollapsed == collapsed && geometryReady
            && items.first?.itemIdentifier == (collapsed ? .init("add") : .flexibleSpace)
            && boundaries == (collapsed ? 0 : 1)
    }
}

@MainActor
func waitForInspector(_ root: WorkbenchView, hidden: Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
    let target: CGFloat = hidden ? 24 : 24 + WorkbenchView.inspectorWidth + WorkbenchView.inspectorInset
    try await waitForWorkbenchState("inspector \(hidden ? "hide" : "reveal")", file: file, line: line,
                                    diagnostics: { workbenchState(root) }) {
        root.layoutSubtreeIfNeeded()
        return root.inspectorAnimation == nil && root.inspectorHidden == hidden
            && root.right.isHidden == hidden && abs(root.viewingInsets.right - target) < 0.01
    }
}

@MainActor
func workbenchState(_ root: WorkbenchView) -> String {
    let items = root.window?.toolbar?.items.map { $0.itemIdentifier.rawValue } ?? []
    return "requestedCollapsed=\(root.collapsed), nativeCollapsed=\(root.sidebarItem.isCollapsed), movingSidebar=\(root.movingSidebar), sidebar=\(root.left.frame), content=\(root.content.frame), inspectorHidden=\(root.inspectorHidden)/\(root.right.isHidden), animatingInspector=\(root.inspectorAnimation != nil), inset=\(root.viewingInsets.right), toolbar=\(items)"
}
