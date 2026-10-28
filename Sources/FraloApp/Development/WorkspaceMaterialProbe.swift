#if FRALO_DEV
import AppKit

/// Controlled native backdrop for desktop-compositing checks, never artwork.
@MainActor
final class WorkspaceMaterialProbe: NSObject {
    private let backdrop: NSWindow
    private weak var testedWindow: NSWindow?
    private(set) var isOpaqueReference = false
    private var closeObserver: NSObjectProtocol?
    init(window: NSWindow) {
        backdrop = NSWindow(contentRect: window.frame.insetBy(dx: -12, dy: -12), styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        testedWindow = window
        reportState()
        backdrop.isReleasedWhenClosed = false; backdrop.ignoresMouseEvents = true
        backdrop.title = "Fralo · 材质验证底板"
        backdrop.contentView = ContrastView(frame: NSRect(origin: .zero, size: backdrop.frame.size))
        backdrop.order(.below, relativeTo: window.windowNumber)
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.backdrop.orderOut(nil) }
        }
    }
    func toggleOpaqueReference() {
        isOpaqueReference.toggle()
        testedWindow?.isOpaque = isOpaqueReference
        testedWindow?.backgroundColor = isOpaqueReference ? .windowBackgroundColor : .clear
        reportState()
    }
    private func reportState() {
        guard let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--workspace-material-report=") }) else { return }
        let path = String(argument.dropFirst("--workspace-material-report=".count))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let window = self?.testedWindow, let root = window.contentView as? WorkbenchView else { return }
            let data: [String: Any] = ["appActive": NSApp.isActive, "windowKey": window.isKeyWindow,
                "windowOpaque": window.isOpaque, "backgroundAlpha": window.backgroundColor.alphaComponent,
                "workspaceMaterial": root.workspace.material.rawValue, "effectState": root.workspace.effect.state.rawValue,
                "effectHidden": root.workspace.effect.isHidden, "fallback": root.workspace.isUsingOpaqueFallback,
                "clipsWorkspace": root.workspace.layer?.masksToBounds ?? false,
                "backdropVisible": self?.backdrop.isVisible ?? false,
                "reduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency]
            if let bytes = try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys, .prettyPrinted]) { try? bytes.write(to: URL(fileURLWithPath: path), options: .atomic) }
        }
    }
    func stop() {
        if isOpaqueReference { toggleOpaqueReference() }
        backdrop.orderOut(nil)
    }
    deinit { if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) } }
    private final class ContrastView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            NSColor(srgbRed: 0.75, green: 0.28, blue: 0.36, alpha: 1).setFill(); bounds.fill()
            NSColor(srgbRed: 0.25, green: 0.44, blue: 0.79, alpha: 1).setFill()
            NSRect(x: bounds.midX, y: bounds.minY, width: bounds.width / 2, height: bounds.height).fill()
        }
    }
}
#endif
