import AppKit
import UniformTypeIdentifiers
import FraloCore
import FraloDesignSystem

@MainActor
final class CompositionInspector: NSView {
    private(set) var settings: CompositionSettings
    var onChange: ((CompositionSettings) -> Void)?
    let mode: ValuePicker
    let devicePicker: ValuePicker
    let formatPicker: ValuePicker
    let exportSettings = NSStackView()
    let sourceInfo = FraloStyle.text("尚未选择图片", role: .detail, secondary: true)
    let outputInfo = FraloStyle.text("—", role: .detail, secondary: true)
    let outputSize = FraloStyle.text("尚未计算文件大小", role: .detail, secondary: true)
    let calculateSize = ActionButton("计算当前大小", role: .quiet)
    var onContinuousEditing: ((Bool) -> Void)?
    var onDragTargetChange: (() -> Void)?
    var dragBackground = false { didSet { if oldValue != dragBackground { onDragTargetChange?() } } }
    private weak var dragToggle: ToggleControl?
    private let deviceDetails = NSView(), backgroundDetails = NSView(), exportDetails = NSView()
    private let backgroundSection = NSStackView()
    private let backgroundType: ValuePicker
    private let pngCompression: ValuePicker
    private let artwork = InspectorArtwork()
    private weak var modelCards: VisualChoiceGroup?
    private weak var orientationCards: VisualChoiceGroup?
    private weak var backgroundCards: VisualChoiceGroup?
    private var editingEnabled = true
    private var previewReady = false

    init(settings: CompositionSettings) {
        self.settings = settings
        mode = ValuePicker(["透明套壳", "背景成图"], label: "出图模式", selected: settings.mode == .transparent ? 0 : 1)
        devicePicker = ValuePicker(["手机", "平板", "浏览器"], label: "展示类型", selected: DisplayKind.allCases.firstIndex(of: settings.display)!)
        formatPicker = ValuePicker(["PNG", "JPEG"], label: "文件格式", selected: settings.format == .png ? 0 : 1)
        backgroundType = ValuePicker(["纯色", "渐变", "图片"], label: "背景类型")
        pngCompression = ValuePicker(["无损", "减色压缩"], label: "PNG 压缩", selected: settings.pngLossless ? 0 : 1)
        mode.controlHeight = 36
        super.init(frame: NSRect(x: 0, y: 0, width: 250, height: 500))
        mode.onChange = { [weak self] index in
            self?.edit { $0.mode = index == 0 ? .transparent : .background }
            self?.stopBackgroundDrag(); self?.rebuildDevice(); self?.rebuildBackground()
        }
        devicePicker.onChange = { [weak self] index in
            self?.editDevice { $0.display = DisplayKind.allCases[index] }; self?.rebuildDevice()
        }
        formatPicker.onChange = { [weak self] index in
            self?.edit { $0.format = index == 0 ? .png : .jpeg }; self?.rebuildExport()
        }
        backgroundType.onChange = { [weak self] index in
            self?.edit { $0.background = index == 0 ? .solid : index == 1 ? .gradient : .warm }
            self?.stopBackgroundDrag(); self?.rebuildBackground()
        }
        pngCompression.onChange = { [weak self] index in
            self?.edit { $0.pngLossless = index == 0 }; self?.rebuildExport()
        }
        configure(backgroundSection, views: [FraloStyle.text("背景与画布", role: .heading), backgroundType, backgroundDetails])
        let deviceSection = FormSection("设备", views: [devicePicker, deviceDetails])
        let sizeRow = FraloStyle.stack([outputSize, calculateSize], axis: .horizontal, spacing: 8)
        configure(exportSettings, views: [FraloStyle.text("导出", role: .heading), formatPicker, exportDetails, outputInfo, sizeRow])
        outputInfo.alignment = .center
        let body = FraloStyle.stack([deviceSection, backgroundSection, FraloStyle.divider(), exportSettings], spacing: 24, fillWidth: true)
        let scroll = ScrollContent.make(body, inset: 0)
        scroll.translatesAutoresizingMaskIntoConstraints = false; addSubview(scroll)
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
                                     scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor)])
        rebuildDevice(); rebuildBackground(); rebuildExport()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func showOutputSize(_ count: Int?, busy: Bool = false) {
        outputSize.stringValue = count.map { "预计 " + ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? (busy ? "正在计算…" : "尚未计算文件大小")
        calculateSize.isBusy = busy; calculateSize.isHidden = count != nil
    }
    func setPreviewReady(_ ready: Bool) {
        previewReady = ready; calculateSize.isEnabled = editingEnabled && ready
    }
    func set(_ value: CompositionSettings) {
        // Artwork dragging updates positions only; selection controls keep their identity and focus.
        settings = value; mode.selectedIndex = value.mode == .transparent ? 0 : 1
    }
    func restore(_ value: CompositionSettings) {
        settings = value; mode.selectedIndex = value.mode == .transparent ? 0 : 1
        devicePicker.selectedIndex = DisplayKind.allCases.firstIndex(of: value.display) ?? 0
        formatPicker.selectedIndex = value.format == .png ? 0 : 1
        stopBackgroundDrag(); rebuildDevice(); rebuildBackground(); rebuildExport()
    }
    func chooseCanvas(_ value: CanvasRatio) { edit { $0.canvas = value }; rebuildBackground() }
    private func refreshArtwork() {
        artwork.load(display: settings.display) { [weak self] result in
            guard let self else { return }
            let frames = result.frames.map { cg in cg.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) } }
            self.modelCards?.setImages(frames)
            self.orientationCards?.setImages(frames)
            self.backgroundCards?.setImages(result.backgrounds.map { cg in cg.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) } })
        }
    }
    func setEditingEnabled(_ enabled: Bool) {
        editingEnabled = enabled
        func visit(_ view: NSView) { (view as? NSControl)?.isEnabled = enabled; view.subviews.forEach(visit) }
        visit(self); visit(exportSettings); mode.isEnabled = enabled
        calculateSize.isEnabled = enabled && previewReady
    }
    private func edit(_ change: (inout CompositionSettings) -> Void) {
        guard editingEnabled else { return }; change(&settings); onChange?(settings)
    }
    private func editDevice(_ change: (inout CompositionSettings) -> Void) { stopBackgroundDrag(); edit(change) }
    private func stopBackgroundDrag() { dragBackground = false; dragToggle?.value = false }
    private func configure(_ stack: NSStackView, views: [NSView]) {
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        for view in views { stack.addArrangedSubview(view); view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    }
    private func install(_ views: [NSView], in host: NSView) {
        let focused = window?.firstResponder as? NSView
        let focusLabel = focused.flatMap { $0.isDescendant(of: host) ? $0.accessibilityLabel() : nil }
        host.subviews.forEach { $0.removeFromSuperview() }
        let content = FraloStyle.stack(views, spacing: 14, fillWidth: true)
        func wire(_ view: NSView) {
            if let row = view as? SliderRow { row.onEditingChanged = { [weak self] in self?.onContinuousEditing?($0) } }
            view.subviews.forEach(wire)
        }
        wire(content)
        content.translatesAutoresizingMaskIntoConstraints = false; host.addSubview(content)
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: host.leadingAnchor), content.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                                     content.topAnchor.constraint(equalTo: host.topAnchor), content.bottomAnchor.constraint(equalTo: host.bottomAnchor)])
        setEditingEnabled(editingEnabled); window?.recalculateKeyViewLoop()
        if let focusLabel {
            func replacement(_ view: NSView) -> NSView? {
                if view.acceptsFirstResponder, view.accessibilityLabel() == focusLabel { return view }
                return view.subviews.lazy.compactMap { replacement($0) }.first
            }
            if let control = replacement(host) { window?.makeFirstResponder(control) }
        }
    }
    private func labeled(_ title: String, _ control: NSView) -> NSView {
        FraloStyle.stack([FraloStyle.text(title, role: .detail, secondary: true), control], spacing: 6, fillWidth: true)
    }
    private func rebuildDevice() {
        modelCards = nil; orientationCards = nil
        var views: [NSView] = []
        if settings.display == .browser {
            let cards = VisualChoiceGroup([.init("Safari", symbol: "safari"), .init("Chrome", symbol: "globe")], label: "浏览器外观", selected: settings.browser == .safari ? 0 : 1, captionsBelow: true) { [weak self] index in self?.editDevice { $0.browser = index == 0 ? .safari : .chrome } }
            modelCards = cards; views.append(cards)
            views.append(labeled("窗口比例", ChoiceMenu(WindowRatio.allCases.map(\.rawValue), label: "浏览器窗口比例", selected: WindowRatio.allCases.firstIndex(of: settings.windowRatio)!) { [weak self] index in self?.editDevice { $0.windowRatio = WindowRatio.allCases[index] } }))
        } else {
            views.append(FraloStyle.text(settings.display == .phone ? "iPhone · 标准外框" : "iPad · 标准外框", role: .detail, secondary: true))
            let orientation = VisualChoiceGroup([.init("竖屏", symbol: "rectangle.portrait"), .init("横屏", symbol: "rectangle")], label: "方向", selected: settings.orientation == .portrait ? 0 : 1, captionsBelow: true) { [weak self] index in
                self?.editDevice { $0.orientation = index == 0 ? .portrait : .landscape }; self?.refreshArtwork()
            }
            orientationCards = orientation; views.append(labeled("方向", orientation))
        }
        if settings.mode == .background {
            views.append(SliderRow("设备缩放", range: 10...150, value: settings.deviceScale * 100) { [weak self] v in self?.editDevice { $0.deviceScale = v / 100 } })
        }
        views.append(SliderRow("设备透明度", range: 0...100, value: settings.deviceOpacity * 100) { [weak self] v in self?.editDevice { $0.deviceOpacity = v / 100 } })
        let shadow = ValuePicker(["无", "柔和", "明显"], label: "阴影", selected: ShadowStyle.allCases.firstIndex(of: settings.shadow)!) { [weak self] index in
            self?.editDevice { if $0.mode == .transparent { $0.transparentShadow = ShadowStyle.allCases[index] } else { $0.backgroundShadow = ShadowStyle.allCases[index] } }
        }
        views.append(labeled("阴影", shadow))
        if settings.mode == .background {
            views.append(ActionButton("设备居中", symbol: "arrow.up.and.down.and.arrow.left.and.right") { [weak self] in self?.editDevice { $0.deviceX = 0; $0.deviceY = 0 } })
        }
        install(views, in: deviceDetails); refreshArtwork()
    }
    private func rebuildBackground() {
        backgroundSection.isHidden = settings.mode != .background
        backgroundType.selectedIndex = settings.background == .solid ? 0 : settings.background == .gradient ? 1 : 2
        backgroundCards = nil
        var views: [NSView] = []
        if settings.background == .solid || settings.background == .gradient {
            stopBackgroundDrag()
            let c = settings.backgroundColor
            views.append(labeled("背景颜色", ColorChoice(label: "背景颜色", color: NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)) { [weak self] value in
                if let rgb = value.usingColorSpace(.sRGB) { self?.edit { $0.backgroundColor = ArtworkColor(rgb.redComponent, rgb.greenComponent, rgb.blueComponent) } }
            }))
        } else {
            let presets: [BackgroundKind] = [.warm, .mist, .sage]
            let backgrounds = VisualChoiceGroup([.init("暖灰"), .init("雾蓝"), .init("灰绿")], label: "背景预设", selected: presets.firstIndex(of: settings.background), layout: .tiles(columns: 3, height: 86)) { [weak self] index in
                self?.edit { $0.background = presets[index]; $0.backgroundScale = 1; $0.backgroundX = 0; $0.backgroundY = 0 }; self?.rebuildBackground()
            }
            backgroundCards = backgrounds; views.append(labeled("图片来源", backgrounds))
            views.append(ActionButton(settings.background == .local ? "更换本地图片…" : "选择本地图片…", symbol: "folder") { [weak self] in self?.chooseBackground() })
            if settings.background == .local {
                views.append(FraloStyle.text(settings.localBackgroundPath.map { "当前：" + URL(fileURLWithPath: $0).lastPathComponent } ?? "尚未选择", role: .detail, secondary: true))
            }
            views.append(SliderRow("背景缩放", range: 100...400, value: settings.backgroundScale * 100) { [weak self] value in self?.edit { $0.backgroundScale = value / 100 } })
            let toggle = ToggleControl("拖动背景取景", value: dragBackground) { [weak self] in self?.dragBackground = $0 }; dragToggle = toggle; views.append(toggle)
            views.append(ActionButton("重置背景取景") { [weak self] in
                self?.edit { $0.backgroundX = 0; $0.backgroundY = 0; $0.backgroundScale = 1 }; self?.rebuildBackground()
            })
        }
        views.append(SliderRow("背景透明度", range: 0...100, value: settings.backgroundOpacity * 100) { [weak self] value in self?.edit { $0.backgroundOpacity = value / 100 } })
        views.append(labeled("画布比例", ChoiceMenu(CanvasRatio.allCases.map(\.rawValue), label: "画布比例", selected: CanvasRatio.allCases.firstIndex(of: settings.canvas)!) { [weak self] index in self?.edit { $0.canvas = CanvasRatio.allCases[index] } }))
        views.append(labeled("构图模板", ChoiceMenu(["选择模板…", "暖灰 · 居中", "雾蓝 · 宽幅", "灰绿 · 竖幅"], label: "内置构图模板") { [weak self] index in
            guard index > 0 else { return }
            self?.edit { s in
                s.background = [.warm, .mist, .sage][index - 1]; s.canvas = [.landscape, .wide, .portrait][index - 1]
                s.deviceScale = index == 2 ? 0.68 : 0.74; s.deviceX = 0; s.deviceY = 0; s.backgroundShadow = .soft
                s.backgroundScale = 1; s.backgroundX = 0; s.backgroundY = 0
            }
            self?.stopBackgroundDrag(); self?.rebuildDevice(); self?.rebuildBackground()
        }))
        install(views, in: backgroundDetails); refreshArtwork()
    }
    private func rebuildExport() {
        var views: [NSView] = []
        if settings.format == .jpeg {
            views.append(SliderRow("JPEG 质量", range: 10...100, value: settings.jpegQuality * 100) { [weak self] v in self?.edit { $0.jpegQuality = v / 100 } })
            let c = settings.jpegFill
            let color = ColorChoice(label: "JPEG 透明区域填色", color: NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)) { [weak self] v in
                if let rgb = v.usingColorSpace(.sRGB) { self?.edit { $0.jpegFill = ArtworkColor(rgb.redComponent, rgb.greenComponent, rgb.blueComponent) } }
            }
            views.append(FraloStyle.stack([FraloStyle.text("透明区域填色", role: .detail), color], axis: .horizontal, spacing: 12))
            views.append(FraloStyle.paragraph("JPEG 会填充透明区域；复制图片仍使用透明 PNG。"))
        } else {
            pngCompression.selectedIndex = settings.pngLossless ? 0 : 1
            views.append(pngCompression)
            if !settings.pngLossless {
                views.append(SliderRow("PNG 品质", range: 10...100, value: settings.pngQuality * 100) { [weak self] v in self?.edit { $0.pngQuality = v / 100 } })
            }
            views.append(FraloStyle.paragraph(settings.pngLossless ? "保留全部颜色与透明度。" : "减少颜色以减小体积，可能改变细节；透明区域保留。"))
        }
        install(views, in: exportDetails)
    }
    private func chooseBackground() {
        guard let window else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg]; panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.edit { $0.localBackgroundPath = url.path; $0.background = .local; $0.backgroundScale = 1; $0.backgroundX = 0; $0.backgroundY = 0 }
            self?.stopBackgroundDrag(); self?.rebuildBackground()
        }
    }
}
