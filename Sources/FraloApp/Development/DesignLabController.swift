#if FRALO_DEV
import AppKit
import FraloDesignSystem

@MainActor
final class DesignLabState {
    enum Page: String, CaseIterable { case foundations = "Foundations", components = "Components", materials = "Materials", motion = "Motion", scenarios = "Scenarios" }
    var preferences = DesignPreferences()
    var appearance = 0
    var selectedPage = 0
    var materialIndex = 0
    var blendingIndex = 0
    var scenario = ScenarioState()
    let samples: LabSamples
    init(samples: LabSamples? = nil) { self.samples = samples ?? LabSamples() }
}

@MainActor
final class DesignLabController: NSWindowController {
    let state = DesignLabState()
    private(set) var tabs: InspectorTabs!
    private(set) var scenarioView: ScenarioWorkbench!
    private(set) var materialView: MaterialExperiment!
    private(set) var motionView: MotionExperiment!
    private let systemStatus = FraloStyle.text("", role: .caption, secondary: true)
    private var observer: NSObjectProtocol?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1380, height: 900),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Fralo · 设计实验室"
        window.identifier = .init("FraloDesignLab")
        window.contentMinSize = NSSize(width: 1040, height: 680)
        window.isReleasedWhenClosed = false; window.autorecalculatesKeyViewLoop = true; window.center()
        rebuild()
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                                                      object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit { if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) } }

    func rebuild() {
        guard let window else { return }
        window.appearance = state.appearance == 1 ? NSAppearance(named: .aqua) : state.appearance == 2 ? NSAppearance(named: .darkAqua) : nil
        let root = NeutralSurface(); root.setAccessibilityIdentifier("design-lab-root")
        let title = FraloStyle.text("设计实验室", role: .title)
        let subtitle = FraloStyle.text("开发构建 · 稳定组件与实验候选分开验证 · 不修改用户批次或设置", role: .detail, secondary: true)
        let heading = FraloStyle.stack([title, subtitle], spacing: 4)
        let appearance = ChoiceMenu(["跟随系统", "浅色", "深色"], label: "实验室外观", selected: state.appearance) { [weak self] index in
            self?.state.appearance = index; self?.rebuild()
        }
        let top = FraloStyle.stack([heading, NSView(), appearance], axis: .horizontal, spacing: 16)
        let preferences = FraloStyle.stack([
            toggle("模拟降低透明度", value: state.preferences.reduceTransparency) { $0.preferences.reduceTransparency = $1 },
            toggle("模拟减少动态效果", value: state.preferences.reduceMotion) { $0.preferences.reduceMotion = $1 },
            toggle("模拟增强对比度", value: state.preferences.increaseContrast) { $0.preferences.increaseContrast = $1 },
            NSView(), ActionButton("重置实验", role: .quiet) { [weak self] in
                self?.state.preferences = .init(); self?.state.appearance = 0; self?.state.scenario = .init()
                self?.state.materialIndex = 0; self?.state.blendingIndex = 0; self?.rebuild()
            }
        ], axis: .horizontal, spacing: 16)
        scenarioView = ScenarioWorkbench(state: state)
        materialView = MaterialExperiment(state: state)
        motionView = MotionExperiment(state: state)
        let pages: [(String, NSView)] = [
            ("Foundations", LabPages.foundations(state: state)), ("Components", LabPages.components(state: state)),
            ("Materials", materialView), ("Motion", motionView), ("Scenarios", scenarioView)
        ]
        tabs = InspectorTabs(pages)
        tabs.selectTabViewItem(at: state.selectedPage)
        tabs.onSelection = { [weak self] in self?.state.selectedPage = $0 }
        refreshStatus()
        for view in [top, preferences, tabs!, systemStatus] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: root.topAnchor, constant: 18), top.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24), top.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            preferences.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 14), preferences.leadingAnchor.constraint(equalTo: top.leadingAnchor), preferences.trailingAnchor.constraint(equalTo: top.trailingAnchor),
            tabs.topAnchor.constraint(equalTo: preferences.bottomAnchor, constant: 14), tabs.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16), tabs.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            tabs.bottomAnchor.constraint(equalTo: systemStatus.topAnchor, constant: -8), systemStatus.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            systemStatus.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24), systemStatus.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10)
        ])
        window.contentView = root
        window.recalculateKeyViewLoop()
        if state.scenario.preview {
            if state.selectedPage == 4 { window.makeFirstResponder(scenarioView.canvas) }
            else if state.selectedPage == 3 { window.makeFirstResponder(motionView.workbench.canvas) }
        }
    }
    private func toggle(_ title: String, value: Bool, update: @escaping (DesignLabState, Bool) -> Void) -> NSButton {
        let button = ToggleControl(title, value: value) { [weak self] value in
            guard let self else { return }; update(self.state, value); self.rebuild()
        }
        return button
    }
    private func refreshStatus() {
        let workspace = NSWorkspace.shared
        systemStatus.stringValue = "系统实际设置：降低透明度 \(workspace.accessibilityDisplayShouldReduceTransparency ? "开" : "关") · 减少动态效果 \(workspace.accessibilityDisplayShouldReduceMotion ? "开" : "关") · 增强对比度 \(workspace.accessibilityDisplayShouldIncreaseContrast ? "开" : "关")。模拟仅加强当前设置，正式材质随系统变化。"
    }
    func selectPage(_ index: Int) { tabs.selectTabViewItem(at: index); window?.contentView?.layoutSubtreeIfNeeded() }
}

#endif
