import AppKit
import UniformTypeIdentifiers
import FraloCore
import FraloDesignSystem

@MainActor
final class CompositionInspector: NSView {
    private(set) var settings: CompositionSettings
    var onChange: ((CompositionSettings) -> Void)?
    let mode: ValuePicker
    let sourceInfo = FraloStyle.text("尚未选择图片", role: .detail, secondary: true)
    let outputInfo = FraloStyle.text("—", role: .detail, secondary: true)
    var dragBackground = false
    private weak var dragToggle: ToggleControl?
    private var tabs: InspectorTabs!
    private var selectedTab = 0

    init(settings: CompositionSettings) {
        self.settings = settings
        mode = ValuePicker(["透明套壳", "背景成图"], label: "出图模式", selected: settings.mode == .transparent ? 0 : 1)
        super.init(frame: NSRect(x: 0, y: 0, width: 250, height: 500))
        mode.onChange = { [weak self] index in self?.edit(rebuild: true) { $0.mode = index == 0 ? .transparent : .background } }
        rebuild()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func set(_ value: CompositionSettings) { settings = value; mode.selectedIndex = value.mode == .transparent ? 0 : 1 }
    func setEditingEnabled(_ enabled: Bool) {
        func visit(_ view: NSView) { (view as? NSControl)?.isEnabled = enabled; view.subviews.forEach(visit) }
        visit(self); mode.isEnabled = enabled
    }
    private func edit(rebuild: Bool = false, _ change: (inout CompositionSettings) -> Void) {
        change(&settings); if rebuild { self.rebuild() }; onChange?(settings)
    }
    private func rebuild() {
        if settings.mode != .background || settings.background == .solid || settings.background == .gradient { dragBackground = false }
        tabs?.removeFromSuperview()
        tabs = InspectorTabs([("设备", ScrollContent.make(devicePage(), inset: 10)),
                              ("背景", ScrollContent.make(backgroundPage(), inset: 10)),
                              ("导出", ScrollContent.make(exportPage(), inset: 10))])
        tabs.translatesAutoresizingMaskIntoConstraints = false; addSubview(tabs)
        NSLayoutConstraint.activate([tabs.leadingAnchor.constraint(equalTo: leadingAnchor), tabs.trailingAnchor.constraint(equalTo: trailingAnchor), tabs.topAnchor.constraint(equalTo: topAnchor), tabs.bottomAnchor.constraint(equalTo: bottomAnchor)])
        tabs.selectTabViewItem(at: selectedTab); tabs.onSelection = { [weak self] index in
            self?.selectedTab = index
            if index != 1 { self?.dragBackground = false; self?.dragToggle?.value = false }
        }
        window?.recalculateKeyViewLoop()
    }
    private func column(_ views: [NSView]) -> NSView {
        let stack = FraloStyle.stack(views, spacing: 18)
        for view in views { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return stack
    }
    private func picker(_ titles: [String], label: String, selected: Int, change: @escaping (Int) -> Void) -> NSView {
        let control = ValuePicker(titles, label: label, selected: selected, onChange: change)
        return column([FraloStyle.text(label, role: .detail, secondary: true), control])
    }
    private func slider(_ title: String, range: ClosedRange<Double>, value: Double, change: @escaping (Double) -> Void) -> SliderRow {
        SliderRow(title, range: range, value: value, onChange: change)
    }
    private func devicePage() -> NSView {
        var views: [NSView] = [picker(["手机", "平板", "浏览器"], label: "展示类型", selected: DisplayKind.allCases.firstIndex(of: settings.display)!) { [weak self] index in self?.edit(rebuild: true) { $0.display = DisplayKind.allCases[index] } }]
        if settings.display == .browser {
            views.append(ChoiceMenu(["Safari", "Chrome"], label: "浏览器外观", selected: settings.browser == .safari ? 0 : 1) { [weak self] index in self?.edit { $0.browser = index == 0 ? .safari : .chrome } })
            views.append(ChoiceMenu(WindowRatio.allCases.map(\.rawValue), label: "浏览器窗口比例", selected: WindowRatio.allCases.firstIndex(of: settings.windowRatio)!) { [weak self] index in self?.edit { $0.windowRatio = WindowRatio.allCases[index] } })
        } else {
            views.append(ChoiceMenu([settings.display == .phone ? "iPhone" : "iPad"], label: "设备外框"))
            views.append(picker(["竖屏", "横屏"], label: "方向", selected: settings.orientation == .portrait ? 0 : 1) { [weak self] index in self?.edit { $0.orientation = index == 0 ? .portrait : .landscape } })
        }
        if settings.mode == .background {
            views.append(slider("设备缩放", range: 10...150, value: settings.deviceScale * 100) { [weak self] v in self?.edit { $0.deviceScale = v / 100 } })
            views.append(ActionButton("设备居中", symbol: "scope") { [weak self] in self?.edit { $0.deviceX = 0; $0.deviceY = 0 } })
        }
        views.append(slider("设备透明度", range: 0...100, value: settings.deviceOpacity * 100) { [weak self] v in self?.edit { $0.deviceOpacity = v / 100 } })
        views.append(picker(["无", "柔和", "明显"], label: "阴影", selected: ShadowStyle.allCases.firstIndex(of: settings.shadow)!) { [weak self] index in self?.edit { if $0.mode == .transparent { $0.transparentShadow = ShadowStyle.allCases[index] } else { $0.backgroundShadow = ShadowStyle.allCases[index] } } })
        if settings.mode == .background { views.append(FraloStyle.paragraph("可在成品上拖动设备；居中不改变设备大小。")) }
        return column(views)
    }
    private func backgroundPage() -> NSView {
        guard settings.mode == .background else {
            return column([FraloStyle.paragraph("透明套壳导出紧凑透明素材。切换到背景成图后可设置背景和画布。"), ActionButton("切换到背景成图") { [weak self] in
                self?.mode.selectedIndex = 1; self?.edit(rebuild: true) { $0.mode = .background }
            }])
        }
        let names = ["纯色", "渐变", "暖灰", "雾蓝", "灰绿", "本地图片"]
        var views: [NSView] = [ChoiceMenu(names, label: "背景来源", selected: BackgroundKind.allCases.firstIndex(of: settings.background)!) { [weak self] index in
            guard let self else { return }
            if BackgroundKind.allCases[index] == .local && self.settings.localBackgroundPath == nil { self.chooseBackground() }
            else { self.edit(rebuild: true) { $0.background = BackgroundKind.allCases[index] } }
         }]
        if settings.background == .solid || settings.background == .gradient {
            let c = settings.backgroundColor
            views.append(ColorChoice(label: "背景颜色", color: NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)) { [weak self] value in
                if let rgb = value.usingColorSpace(.sRGB) { self?.edit { $0.backgroundColor = ArtworkColor(rgb.redComponent, rgb.greenComponent, rgb.blueComponent) } }
            })
        }
        if settings.background == .local {
            views.append(ActionButton("选择本地图片…", symbol: "folder") { [weak self] in self?.chooseBackground() })
            views.append(FraloStyle.text(settings.localBackgroundPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "尚未选择", role: .caption, secondary: true))
        }
        if settings.background != .solid && settings.background != .gradient {
            views.append(slider("背景缩放", range: 100...400, value: settings.backgroundScale * 100) { [weak self] value in self?.edit { $0.backgroundScale = value / 100 } })
            let toggle = ToggleControl("拖动背景取景", value: dragBackground) { [weak self] in self?.dragBackground = $0 }; dragToggle = toggle; views.append(toggle)
            views.append(ActionButton("重置背景取景") { [weak self] in self?.edit(rebuild: true) { $0.backgroundX = 0; $0.backgroundY = 0; $0.backgroundScale = 1 } })
        }
        views.append(slider("背景透明度", range: 0...100, value: settings.backgroundOpacity * 100) { [weak self] value in self?.edit { $0.backgroundOpacity = value / 100 } })
        views.append(ChoiceMenu(CanvasRatio.allCases.map(\.rawValue), label: "画布比例", selected: CanvasRatio.allCases.firstIndex(of: settings.canvas)!) { [weak self] index in self?.edit { $0.canvas = CanvasRatio.allCases[index] } })
        views.append(FraloStyle.text("构图模板", role: .detail, secondary: true))
        views.append(ChoiceMenu(["选择模板…", "暖灰 · 居中", "雾蓝 · 宽幅", "灰绿 · 竖幅"], label: "内置构图模板") { [weak self] index in
            guard index > 0 else { return }
            self?.edit(rebuild: true) { s in
                s.background = [.warm, .mist, .sage][index - 1]; s.canvas = [.landscape, .wide, .portrait][index - 1]
                s.deviceScale = index == 2 ? 0.68 : 0.74; s.deviceX = 0; s.deviceY = 0; s.backgroundShadow = .soft
                s.backgroundScale = 1; s.backgroundX = 0; s.backgroundY = 0
            }
        })
        return column(views)
    }
    private func exportPage() -> NSView {
        var views: [NSView] = [picker(["PNG", "JPEG"], label: "文件格式", selected: settings.format == .png ? 0 : 1) { [weak self] index in self?.edit(rebuild: true) { $0.format = index == 0 ? .png : .jpeg } }]
        if settings.format == .jpeg {
            views.append(slider("JPEG 质量", range: 10...100, value: settings.jpegQuality * 100) { [weak self] v in self?.edit { $0.jpegQuality = v / 100 } })
            let c = settings.jpegFill
            views.append(FraloStyle.text("透明区域填充颜色", role: .detail, secondary: true))
            views.append(ColorChoice(label: "JPEG 透明区域填色", color: NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)) { [weak self] v in
                if let rgb = v.usingColorSpace(.sRGB) { self?.edit { $0.jpegFill = ArtworkColor(rgb.redComponent, rgb.greenComponent, rgb.blueComponent) } }
            })
            views.append(FraloStyle.paragraph("JPEG 不支持透明度。预览显示填色后的成品，复制当前图片仍保留 PNG 透明信息。"))
        } else { views.append(FraloStyle.paragraph("PNG 保留成品的透明区域。")) }
        views += [FraloStyle.divider(), FraloStyle.text("原始图片", role: .detail, secondary: true), sourceInfo,
                  FraloStyle.text("实际输出", role: .detail, secondary: true), outputInfo]
        return column(views)
    }
    private func chooseBackground() {
        guard let window else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg]; panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { self?.rebuild(); return }
            self?.edit(rebuild: true) { $0.localBackgroundPath = url.path; $0.background = .local; $0.backgroundScale = 1; $0.backgroundX = 0; $0.backgroundY = 0 }
        }
    }
}
