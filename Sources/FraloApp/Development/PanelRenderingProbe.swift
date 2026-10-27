#if FRALO_DEV
import AppKit
import QuartzCore
import FraloDesignSystem

/// Single-variable compositor comparisons. Enabled only by an explicit Debug launch flag.
/// Event metadata is diagnostic evidence, not proof that an intermittent visual artifact is fixed.
@MainActor
final class PanelRenderingProbe: NSObject {
    enum Mode: Int, CaseIterable {
        case baseline, staticGlass, nativeShadow, clipped
        var title: String { ["A 原样", "B 静态玻璃", "C 无额外阴影", "D 圆角裁切"][rawValue] }
    }
    private weak var window: NSWindow?
    private let report: URL?
    private var restore: [() -> Void] = []
    private var surfaces: [MaterialSurface] = []
    private var panels: [FloatingPanel] = []
    private let bar = NSStackView()
    private var buttons: [NSButton] = []
    private var monitor: Any?
    private var events: [[String: Any]] = []
    private(set) var mode = Mode.baseline

    init(window: NSWindow, initial: Mode = .baseline, report: URL? = nil, showsControls: Bool = true) {
        self.window = window; self.report = report
        super.init()
        guard let root = window.contentView else { return }
        let views = Self.descendants(root)
        surfaces = views.compactMap { $0 as? MaterialSurface }.filter { $0.role == .panel }
        panels = views.compactMap { $0 as? FloatingPanel }
        for surface in surfaces {
            let clips = surface.layer?.masksToBounds ?? false
            restore.append { [weak surface] in surface?.layer?.masksToBounds = clips }
        }
        for panel in panels {
            let opacity = panel.layer?.shadowOpacity ?? 0
            restore.append { [weak panel] in panel?.layer?.shadowOpacity = opacity }
        }
        if #available(macOS 27.0, *) {
            for glass in views.compactMap({ $0 as? NSGlassEffectView }) {
                let interactive = glass.effectIsInteractive
                restore.append { [weak glass] in glass?.effectIsInteractive = interactive }
            }
        }
        if showsControls {
            bar.orientation = .horizontal; bar.spacing = 6; bar.alignment = .centerY
            let label = NSTextField(labelWithString: "面板诊断"); label.font = .systemFont(ofSize: 11)
            bar.addArrangedSubview(label)
            for choice in Mode.allCases {
                let button = NSButton(title: choice.title, target: self, action: #selector(choose(_:)))
                button.tag = choice.rawValue; button.setButtonType(.pushOnPushOff); button.bezelStyle = .rounded
                button.controlSize = .small; button.font = .systemFont(ofSize: 11)
                bar.addArrangedSubview(button); buttons.append(button)
            }
            bar.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(bar)
            NSLayoutConstraint.activate([bar.centerXAnchor.constraint(equalTo: root.centerXAnchor),
                bar.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 4),
                bar.heightAnchor.constraint(equalToConstant: 28)])
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated {
                if let self, event.window === self.window { self.record(event.type == .leftMouseDown ? "mouseDown" : "mouseUp") }
            }
            return event
        }
        select(initial)
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    private static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
    @objc private func choose(_ sender: NSButton) { if let mode = Mode(rawValue: sender.tag) { select(mode) } }
    func select(_ value: Mode) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        restore.forEach { $0() }; mode = value
        switch value {
        case .baseline: break
        case .staticGlass:
            if #available(macOS 27.0, *), let root = window?.contentView {
                Self.descendants(root).compactMap { $0 as? NSGlassEffectView }.forEach { $0.effectIsInteractive = false }
            }
        case .nativeShadow: panels.forEach { $0.layer?.shadowOpacity = 0 }
        case .clipped: surfaces.forEach { $0.layer?.masksToBounds = true }
        }
        CATransaction.commit()
        for button in buttons { button.state = button.tag == value.rawValue ? .on : .off }
        record("variant")
    }
    func stop() {
        select(.baseline); bar.removeFromSuperview()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }
    private func record(_ phase: String) {
        guard let report else { return }
        var glassState: [Bool] = []
        if #available(macOS 27.0, *), let root = window?.contentView {
            glassState = Self.descendants(root).compactMap { ($0 as? NSGlassEffectView)?.effectIsInteractive }
        }
        events.append(["phase": phase, "uptime": ProcessInfo.processInfo.systemUptime, "mode": mode.rawValue,
            "windowKey": window?.isKeyWindow ?? false, "appActive": NSApp.isActive,
            "interactiveGlass": glassState, "panelClipping": surfaces.map { $0.layer?.masksToBounds ?? false },
            "extraShadowOpacity": panels.map { $0.layer?.shadowOpacity ?? 0 }])
        if events.count > 100 { events.removeFirst(events.count - 100) }
        let payload: [String: Any] = ["mode": mode.rawValue, "events": events,
            "limits": "Public layer/event metadata only. No visual failure or fix is inferred."]
        if let bytes = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? bytes.write(to: report, options: .atomic)
        }
    }
}
#endif
