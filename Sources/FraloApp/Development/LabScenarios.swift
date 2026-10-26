#if FRALO_DEV
import AppKit
import FraloDesignSystem

struct ScenarioState {
    var device = 0
    var transparent = false
    var background = 0
    var scale = 74.0
    var opacity = 100.0
    var backgroundScale = 100.0
    var backgroundOpacity = 100.0
    var ratio = 1
    var format = 0
    var quality = 90.0
    var selected = 0
    var count = 3
    var longNames = false
    var collapsed = false
    var preview = false
    var displayState = 0
}

@MainActor
final class ScenarioWorkbench: NSView {
    let state: DesignLabState
    let workspace = MaterialSurface(.workspace, radius: 12)
    let canvas = CanvasSurface()
    let toolbar = ViewToolbar()
    let rail = CollapsedRail()
    let list: BatchList
    let sidebarContainer = NSView()
    private(set) var leftPanel: FloatingPanel!
    private(set) var rightPanel: FloatingPanel!
    private(set) var modePicker: ValuePicker!
    private(set) var devicePicker: ValuePicker!
    private(set) var fixtureLabel = FraloStyle.text("", role: .caption, secondary: true)
    private let feedback = FraloStyle.text("导出按钮在此验证动作，不写入用户目录", role: .caption, secondary: true)
    private var statusView: NSView?
    private var controls: NSView!
    private var restoreFocus: NSResponder?
    private var inspectorIndex = 0
    override var isFlipped: Bool { true }

    init(state: DesignLabState) {
        self.state = state
        list = BatchList(entries: state.samples.entries(count: state.scenario.count, longNames: state.scenario.longNames))
        // The host will resize this preview. Start with valid geometry so AppKit
        // never solves fixed header/footer insets against zero-sized manual frames.
        super.init(frame: NSRect(x: 0, y: 0, width: 1100, height: 650))
        wantsLayer = true; sidebarContainer.wantsLayer = true; sidebarContainer.layer?.masksToBounds = true
        workspace.preferences = state.preferences; rail.surface.preferences = state.preferences
        addSubview(workspace); addSubview(sidebarContainer); addSubview(canvas); addSubview(toolbar); addSubview(fixtureLabel)
        controls = FraloStyle.stack([
            FraloStyle.text("布局夹具", role: .heading),
            ChoiceMenu(["3 张样例", "空批次", "100 张样例"], label: "样例数量", selected: state.scenario.count == 0 ? 1 : state.scenario.count == 100 ? 2 : 0) { [weak self] index in
                guard let self else { return }; self.state.scenario.count = [3, 0, 100][index]; self.state.scenario.selected = 0; self.refreshList()
            },
            ToggleControl("长文件名", value: state.scenario.longNames) { [weak self] value in
                self?.state.scenario.longNames = value; self?.refreshList()
            },
            ChoiceMenu(["正常", "加载", "失败"], label: "预览状态", selected: state.scenario.displayState) { [weak self] index in
                self?.state.scenario.displayState = index; self?.render()
            }, NSView(), feedback
        ], axis: .horizontal, spacing: 12)
        addSubview(controls)
        let collapse = IconButton("sidebar.left", label: "收起图片列表") { [weak self] in self?.toggleSidebar() }
        let header = FraloStyle.stack([FraloStyle.text("图片样例", role: .heading), NSView(), collapse], axis: .horizontal)
        let footer = FraloStyle.stack([ActionButton("添加样例") { [weak self] in
            guard let self else { return }; self.state.scenario.count += 1; self.refreshList()
        }, FraloStyle.text("↑ ↓ 切换 · Esc 返回预览", role: .caption, secondary: true)], spacing: 8)
        // The list is the panel viewport, with no second scroll view around it.
        leftPanel = FloatingPanel(header: header, body: list, footer: footer)
        leftPanel.surface.preferences = state.preferences
        sidebarContainer.addSubview(leftPanel); sidebarContainer.addSubview(rail)
        rail.expand.onPress = { [weak self] in self?.toggleSidebar() }
        rail.add.onPress = { [weak self] in guard let self else { return }; self.state.scenario.count += 1; self.refreshList() }
        rail.previous.onPress = { [weak self] in self?.moveSelection(-1) }
        rail.next.onPress = { [weak self] in self?.moveSelection(1) }
        list.onSelection = { [weak self] index in self?.state.scenario.selected = index; self?.render() }
        canvas.onPrevious = { [weak self] in self?.moveSelection(-1) }
        canvas.onNext = { [weak self] in self?.moveSelection(1) }
        canvas.onEscape = { [weak self] in if self?.state.scenario.preview == true { self?.togglePreview() } }
        toolbar.zoom.onChange = { [weak self] index in self?.canvas.zoom = index == 0 ? nil : index == 1 ? 1 : 0.5 }
        toolbar.preview.onPress = { [weak self] in self?.togglePreview() }
        toolbar.surface.preferences = state.preferences
        refreshInspector(); setSidebarVisibility(); render()
        sidebarContainer.isHidden = state.scenario.preview; controls.isHidden = state.scenario.preview
        toolbar.preview.title = state.scenario.preview ? "返回编辑 · Esc" : "成品预览"
        applyLayout(animated: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func layout() { super.layout(); applyLayout(animated: false) }

    private func applyLayout(animated: Bool) {
        let area = NSRect(x: 0, y: 48, width: bounds.width, height: max(0, bounds.height - 48))
        workspace.frame = area
        controls.frame = NSRect(x: 16, y: 4, width: max(0, bounds.width - 32), height: 36)
        let preview = state.scenario.preview
        let leftWidth: CGFloat = state.scenario.collapsed ? 56 : 218
        let rightWidth: CGFloat = 282
        let panelHeight = max(120, area.height - 32)
        let side = NSRect(x: 16, y: area.minY + 16, width: leftWidth, height: panelHeight)
        let right = NSRect(x: max(16, bounds.width - rightWidth - 16), y: side.minY, width: rightWidth, height: panelHeight)
        let start = preview ? 24 : side.maxX + 12
        let end = preview ? bounds.width - 24 : right.minX - 12
        let main = NSRect(x: start, y: area.minY + 12, width: max(0, end - start), height: max(0, area.height - 86))
        let toolWidth = min(main.width, 440)
        let tool = NSRect(x: main.midX - toolWidth / 2, y: area.maxY - 52, width: toolWidth, height: 36)
        func frame(_ view: NSView, _ rect: NSRect) { if animated { view.animator().frame = rect } else { view.frame = rect } }
        frame(sidebarContainer, side); frame(rightPanel, right); frame(canvas, main); frame(toolbar, tool)
        leftPanel.frame = NSRect(x: 0, y: 0, width: 218, height: panelHeight)
        rail.frame = NSRect(x: 0, y: 0, width: 56, height: panelHeight)
        fixtureLabel.frame = NSRect(x: main.minX + 8, y: area.maxY - 75, width: max(0, main.width - 16), height: 18)
        statusView?.frame = main
    }
    func toggleSidebar() {
        state.scenario.collapsed.toggle()
        leftPanel.isHidden = false; rail.isHidden = false
        let target = state.scenario.collapsed
        let duration = FraloMotion.duration(.structure, preferences: state.preferences)
        if duration == 0 || window == nil { setSidebarVisibility(); applyLayout(animated: false); return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            leftPanel.animator().alphaValue = target ? 0 : 1
            rail.animator().alphaValue = target ? 1 : 0
            applyLayout(animated: true)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { if self?.state.scenario.collapsed == target { self?.setSidebarVisibility() } }
        })
    }
    private func setSidebarVisibility() {
        leftPanel.isHidden = state.scenario.collapsed
        rail.isHidden = !state.scenario.collapsed
        leftPanel.alphaValue = state.scenario.collapsed ? 0 : 1; rail.alphaValue = state.scenario.collapsed ? 1 : 0
    }
    func togglePreview() {
        state.scenario.preview.toggle()
        let preview = state.scenario.preview
        if preview { restoreFocus = window?.firstResponder }
        sidebarContainer.isHidden = preview; rightPanel.isHidden = preview; controls.isHidden = preview
        toolbar.preview.title = preview ? "返回编辑 · Esc" : "成品预览"
        NSAnimationContext.runAnimationGroup { context in
            context.duration = FraloMotion.duration(.preview, preferences: state.preferences)
            applyLayout(animated: context.duration > 0 && window != nil)
        }
        if preview { window?.makeFirstResponder(canvas) } else { window?.makeFirstResponder(restoreFocus) }
    }
    func moveSelection(_ delta: Int) { list.moveSelection(by: delta) }
    private func refreshList() {
        list.update(state.samples.entries(count: state.scenario.count, longNames: state.scenario.longNames))
        refreshInspector(); render()
    }
    func refreshInspector() {
        rightPanel?.removeFromSuperview()
        let mode = ValuePicker(["透明套壳", "背景成图"], label: "样例出图模式", selected: state.scenario.transparent ? 0 : 1) { [weak self] index in
            self?.state.scenario.transparent = index == 0; self?.refreshInspector(); self?.render()
        }
        mode.preferences = state.preferences; modePicker = mode
        let heading = FraloStyle.stack([mode, FraloStyle.text("样式应用于全部 \(state.scenario.count) 张样例", role: .caption, secondary: true)], spacing: 10)
        let pages: [(String, NSView)] = [("设备", deviceControls()), ("背景", backgroundControls()), ("导出", exportControls())]
        let tabs = InspectorTabs(pages.map { ($0.0, ScrollContent.make($0.1, inset: 0)) })
        tabs.selectTabViewItem(at: inspectorIndex)
        tabs.onSelection = { [weak self] in self?.inspectorIndex = $0 }
        let action = ExportAction(count: state.scenario.count)
        action.onExportAll = { [weak self] in self?.feedback.stringValue = "样例动作：导出全部；不写文件" }
        action.onExportCurrent = { [weak self] in self?.feedback.stringValue = "样例动作：导出当前；主按钮仍导出全部" }
        let footer = FraloStyle.stack([FraloStyle.text("布局样例 · \(state.scenario.format == 0 ? "PNG" : "JPEG")", role: .caption, secondary: true), action], spacing: 8)
        rightPanel = FloatingPanel(header: heading, body: tabs, footer: footer)
        rightPanel.surface.preferences = state.preferences
        applyLayout(animated: false); addSubview(rightPanel)
        rightPanel.isHidden = state.scenario.preview
        needsLayout = true
    }
    private func deviceControls() -> NSView {
        let type = ValuePicker(["手机", "平板", "浏览器"], label: "样例展示类型", selected: state.scenario.device) { [weak self] index in
            self?.state.scenario.device = index; self?.refreshInspector(); self?.render()
        }
        type.preferences = state.preferences; devicePicker = type
        let titles = state.scenario.device == 0 ? ["iPhone · 现有渲染"] : state.scenario.device == 1 ? ["iPad · 布局夹具"] : ["Safari · 布局夹具", "Chrome · 控件样例"]
        var rows: [NSView] = [type, ChoiceMenu(titles, label: "样例外框")]
        if !state.scenario.transparent {
            rows.append(SliderRow("设备缩放", range: 20...100, value: state.scenario.scale) { [weak self] value in self?.state.scenario.scale = value; self?.render() })
        }
        rows.append(SliderRow("设备透明度", range: 0...100, value: state.scenario.opacity) { [weak self] value in self?.state.scenario.opacity = value; self?.render() })
        rows.append(FraloStyle.paragraph("手机使用现有 Core 渲染；平板与浏览器是布局夹具，新外框业务尚未实现。"))
        return inset(FraloStyle.stack(rows, spacing: 20, fillWidth: true))
    }
    private func backgroundControls() -> NSView {
        guard !state.scenario.transparent else {
            return inset(FraloStyle.stack([FraloStyle.paragraph("透明套壳不使用背景、固定画布比例或构图缩放。"), ActionButton("切换背景成图") { [weak self] in
                self?.state.scenario.transparent = false; self?.refreshInspector(); self?.render()
            }]))
        }
        let preset = ChoiceMenu(["暖灰", "雾蓝", "灰绿"], label: "样例背景", selected: state.scenario.background) { [weak self] index in self?.state.scenario.background = index; self?.render() }
        let ratio = ChoiceMenu(["1:1", "4:3", "16:9", "3:4", "9:16"], label: "样例画布比例", selected: state.scenario.ratio) { [weak self] index in self?.state.scenario.ratio = index; self?.render() }
        return inset(FraloStyle.stack([
            preset,
            SliderRow("背景缩放", range: 100...180, value: state.scenario.backgroundScale) { [weak self] value in self?.state.scenario.backgroundScale = value; self?.render() },
            SliderRow("背景透明度", range: 0...100, value: state.scenario.backgroundOpacity) { [weak self] value in self?.state.scenario.backgroundOpacity = value; self?.render() },
            ratio, FraloStyle.paragraph("预设图片仅为开发夹具。该区研究布局和独立图层，不代表完整背景编辑已接入产品。")
        ], spacing: 20, fillWidth: true))
    }
    private func exportControls() -> NSView {
        let format = ValuePicker(["PNG", "JPEG"], label: "样例导出格式", selected: state.scenario.format) { [weak self] value in
            self?.state.scenario.format = value; self?.refreshInspector()
        }
        format.preferences = state.preferences
        var rows: [NSView] = [format]
        if state.scenario.format == 1 {
            rows += [SliderRow("图片质量", range: 1...100, value: state.scenario.quality) { [weak self] in self?.state.scenario.quality = $0 },
                     FormRow("透明填底", content: ColorChoice(label: "样例填底颜色", color: .white)), FraloStyle.paragraph("条件控件演示：这里不执行正式 JPEG 导出。")]
        }
        rows += [InfoRow("输入来源", value: "独立开发夹具"), InfoRow("输出用途", value: "布局与状态验证")]
        return inset(FraloStyle.stack(rows, spacing: 20, fillWidth: true))
    }
    private func inset(_ view: NSView) -> NSView {
        let wrapper = NSView(); view.translatesAutoresizingMaskIntoConstraints = false; wrapper.addSubview(view)
        NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 10), view.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -10),
                                     view.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 14), view.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -14)])
        return wrapper
    }
    func render() {
        rail.update(index: state.scenario.count > 0 ? state.scenario.selected : nil, count: state.scenario.count)
        statusView?.removeFromSuperview(); statusView = nil
        let empty = state.scenario.count == 0
        canvas.isHidden = empty || state.scenario.displayState != 0
        if canvas.isHidden {
            let mode: StateView.State = empty ? .empty : state.scenario.displayState == 1 ? .loading : .failure
            let status = StateView(mode, title: empty ? "暂无图片样例" : state.scenario.displayState == 1 ? "正在生成预览" : "无法读取样例",
                                   detail: "这是开发状态夹具，不会修改真实批次。", action: mode == .loading ? nil : { [weak self] in
                self?.state.scenario.count = 3; self?.state.scenario.displayState = 0; self?.refreshList()
            })
            statusView = status; addSubview(status)
        } else { canvas.image = sampleImage() }
        if let image = canvas.image { toolbar.dimensions.stringValue = "\(Int(image.size.width)) × \(Int(image.size.height)) · 样例" }
        fixtureLabel.stringValue = state.samples.missingFixtures ? "开发素材未找到，请使用 scripts/run-design-lab.sh 启动" : state.scenario.device == 0 ? "现有 Core 手机样例 · 窗口材质不进入图片" : "布局夹具 · 外框为示意，不代表新渲染业务已完成"
        needsLayout = true
    }
    func sampleImage() -> NSImage? {
        let config = state.scenario
        if config.transparent && config.device == 0 && config.opacity == 100 { return state.samples.phone(at: config.selected) }
        let sizes = [NSSize(width: 720, height: 720), NSSize(width: 960, height: 720), NSSize(width: 960, height: 540), NSSize(width: 720, height: 960), NSSize(width: 540, height: 960)]
        let natural = config.device == 0 ? NSSize(width: 430, height: 880) : config.device == 1 ? NSSize(width: 820, height: 620) : NSSize(width: 860, height: 540)
        let size = config.transparent ? natural : sizes[config.ratio]
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        let bounds = NSRect(origin: .zero, size: size)
        context.cgContext.clear(bounds)
        if !config.transparent, state.samples.backgrounds.indices.contains(config.background) {
            let background = state.samples.backgrounds[config.background]
            let factor = max(size.width / background.size.width, size.height / background.size.height) * config.backgroundScale / 100
            let destination = NSRect(x: (size.width - background.size.width * factor) / 2, y: (size.height - background.size.height * factor) / 2,
                                     width: background.size.width * factor, height: background.size.height * factor)
            background.draw(in: destination, from: .zero, operation: .sourceOver, fraction: config.backgroundOpacity / 100)
        }
        let factor = config.transparent ? 1 : min(size.width / natural.width, size.height / natural.height) * config.scale / 100
        let device = NSRect(x: (size.width - natural.width * factor) / 2, y: (size.height - natural.height * factor) / 2,
                            width: natural.width * factor, height: natural.height * factor)
        context.cgContext.saveGState(); context.cgContext.setAlpha(config.opacity / 100)
        if config.device == 0, let phone = state.samples.phone(at: config.selected) {
            phone.draw(in: device)
        } else {
            // Deterministic layout fixture only; it is deliberately not a product frame renderer.
            NSColor(srgbRed: 0.12, green: 0.13, blue: 0.14, alpha: 1).setFill()
            NSBezierPath(roundedRect: device, xRadius: 14 * factor, yRadius: 14 * factor).fill()
            let content = device.insetBy(dx: 18 * factor, dy: 18 * factor)
            NSColor(srgbRed: 0.96, green: 0.95, blue: 0.91, alpha: 1).setFill(); content.fill()
            let title = config.device == 1 ? "iPad · 布局夹具" : "Safari · 布局夹具"
            (title as NSString).draw(at: NSPoint(x: content.minX + 16 * factor, y: content.maxY - 32 * factor), withAttributes: [.font: NSFont.systemFont(ofSize: max(9, 18 * factor)), .foregroundColor: NSColor.black])
            if !state.samples.sources.isEmpty {
                let source = state.samples.sources[config.selected % state.samples.sources.count]
                let available = content.insetBy(dx: 16 * factor, dy: 40 * factor)
                let contain = min(available.width / source.size.width, available.height / source.size.height)
                source.draw(in: NSRect(x: available.midX - source.size.width * contain / 2, y: available.midY - source.size.height * contain / 2,
                                      width: source.size.width * contain, height: source.size.height * contain))
            }
        }
        context.cgContext.restoreGState()
        let image = NSImage(size: size); image.addRepresentation(rep); return image
    }
}
#endif
