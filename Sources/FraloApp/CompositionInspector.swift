import AppKit
import UniformTypeIdentifiers
import FraloCore
import FraloDesignSystem

/// Native slider that reports the start and end of one drag, so a drag becomes one undo step.
@MainActor
final class CompactSlider: NSSlider {
    var onEditingChanged: ((Bool) -> Void)?
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        onEditingChanged?(true)
        defer { onEditingChanged?(false) }
        super.mouseDown(with: event)
    }
}

/// Inspector row: label on the leading edge, slider and a tabular percentage on the trailing edge.
@MainActor
final class CompactSliderField: NSStackView {
    let slider: CompactSlider
    let valueLabel = FraloStyle.text("", role: .detail)
    var onEditingChanged: ((Bool) -> Void)? { didSet { slider.onEditingChanged = onEditingChanged } }
    private let onChange: (Double) -> Void
    init(_ title: String, range: ClosedRange<Double>, value: Double, onChange: @escaping (Double) -> Void) {
        slider = CompactSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound, target: nil, action: nil)
        self.onChange = onChange
        super.init(frame: .zero)
        orientation = .horizontal; alignment = .centerY; spacing = 8
        slider.controlSize = .small; slider.isContinuous = true; slider.target = self; slider.action = #selector(changed(_:))
        slider.setAccessibilityLabel(title)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .regular); valueLabel.alignment = .right
        let label = FraloStyle.text(title, role: .detail, secondary: true); label.font = .systemFont(ofSize: 12.5)
        for view in [label, NSView(), slider, valueLabel] { addArrangedSubview(view) }
        slider.widthAnchor.constraint(equalToConstant: 118).isActive = true
        valueLabel.widthAnchor.constraint(equalToConstant: 42).isActive = true
        heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
        update()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    private func update() { valueLabel.stringValue = "\(Int(slider.doubleValue.rounded()))%"; slider.setAccessibilityValueDescription(valueLabel.stringValue) }
    @objc private func changed(_ sender: Any?) { update(); if slider.isEnabled { onChange(slider.doubleValue) } }
}

@MainActor
final class CompositionInspector: NSView {
    private(set) var settings: CompositionSettings
    var onChange: ((CompositionSettings) -> Void)?
    let mode: ValuePicker
    let devicePicker: ValuePicker
    let formatPicker: ValuePicker
    let exportSettings = NSStackView()
    /// Output pixel size, shown once in the fixed footer.
    let outputInfo = FraloStyle.text("—", role: .body)
    let outputSize = FraloStyle.text("—", role: .body, secondary: true)
    let outputSummary = FraloStyle.text("", role: .caption, secondary: true)
    var onContinuousEditing: ((Bool) -> Void)?
    var onDragTargetChange: (() -> Void)?
    var dragBackground = false { didSet { if oldValue != dragBackground { onDragTargetChange?() } } }
    var batchCount = 0 { didSet { refreshSummaries() } }
    private weak var dragToggle: ToggleControl?
    private let deviceDetails = NSView(), appearanceDetails = NSView(), backgroundDetails = NSView(), exportDetails = NSView()
    private let deviceSummary = CompositionInspector.summaryLabel()
    private let appearanceSummary = CompositionInspector.summaryLabel()
    private let backgroundSummary = CompositionInspector.summaryLabel()
    private let exportSummary = CompositionInspector.summaryLabel()
    private let backgroundSection = NSStackView()
    private let backgroundType: ValuePicker
    private let pngCompression: ValuePicker
    private let artwork = InspectorArtwork()
    private weak var modelCards: VisualChoiceGroup?
    private weak var phoneModelCards: VisualChoiceGroup?
    private weak var orientationCards: VisualChoiceGroup?
    private weak var backgroundCards: VisualChoiceGroup?
    private var editingEnabled = true

    /// A small unfolded-device sketch for the not-yet-available folding card.
    private static let foldingArtwork = NSImage(size: NSSize(width: 54, height: 60), flipped: true) { rect in
        let body = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9)
        NSGradient(starting: NSColor(srgbRed: 0.91, green: 0.92, blue: 0.93, alpha: 1), ending: NSColor(srgbRed: 0.55, green: 0.57, blue: 0.59, alpha: 1))?.draw(in: body, angle: 45)
        NSColor(srgbRed: 0.05, green: 0.06, blue: 0.08, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: 4, dy: 4), xRadius: 7, yRadius: 7).fill()
        NSColor.white.withAlphaComponent(0.18).setFill(); NSRect(x: rect.midX - 0.5, y: 4, width: 1, height: rect.height - 8).fill()
        return true
    }
    /// PNG size presets; 均衡 keeps the previous default palette quality.
    private static let pngPresets: [Double] = [0.85, 0.4]

    init(settings: CompositionSettings) {
        self.settings = settings
        mode = ValuePicker(["透明套壳", "背景成图"], label: "出图模式", selected: settings.mode == .transparent ? 0 : 1, purpose: .tabs, size: .large)
        devicePicker = ValuePicker(["手机", "平板", "浏览器"], label: "展示类型", selected: DisplayKind.allCases.firstIndex(of: settings.display)!, purpose: .tabs, size: .large)
        formatPicker = ValuePicker(["PNG", "JPEG"], label: "文件格式", selected: settings.format == .png ? 0 : 1)
        backgroundType = ValuePicker(["纯色", "渐变", "图片"], label: "背景类型")
        pngCompression = ValuePicker(["无损", "均衡", "最小"], label: "PNG 体积", selected: Self.pngPreset(settings))
        for picker in [backgroundType, formatPicker, pngCompression] { picker.controlSize = .small }
        super.init(frame: NSRect(x: 0, y: 0, width: 276, height: 500))
        mode.onChange = { [weak self] index in
            self?.edit { $0.mode = index == 0 ? .transparent : .background }
            self?.stopBackgroundDrag(); self?.rebuildDevice(); self?.rebuildAppearance(); self?.rebuildBackground()
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
            self?.edit { $0.pngLossless = index == 0; if index > 0 { $0.pngQuality = Self.pngPresets[index - 1] } }
        }
        let deviceSection = section("设备", summary: deviceSummary, views: [devicePicker, deviceDetails])
        let appearanceSection = section("外观", summary: appearanceSummary, views: [appearanceDetails])
        configure(backgroundSection, views: [header("背景", summary: backgroundSummary), backgroundType, backgroundDetails])
        configure(exportSettings, views: [header("导出", summary: exportSummary), field("格式", formatPicker, width: 172), exportDetails])
        let body = FraloStyle.stack([deviceSection, FraloStyle.divider(), appearanceSection, backgroundSection, FraloStyle.divider(), exportSettings],
                                    spacing: 16, fillWidth: true)
        let scroll = ScrollContent.make(body, inset: 0)
        scroll.translatesAutoresizingMaskIntoConstraints = false; addSubview(scroll)
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
                                     scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor)])
        outputInfo.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .regular)
        outputSize.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .regular); outputSize.alignment = .right
        outputSummary.font = .systemFont(ofSize: 11.5); outputSummary.textColor = .tertiaryLabelColor
        rebuildDevice(); rebuildAppearance(); rebuildBackground(); rebuildExport()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    /// Fixed export specification and the primary action; it never scrolls with the settings.
    func makeFooter(action: NSView) -> NSView {
        let specs = FraloStyle.stack([outputInfo, NSView(), outputSize], axis: .horizontal, spacing: 8)
        let column = FraloStyle.stack([FraloStyle.divider(), specs, outputSummary, action], spacing: 4, fillWidth: true)
        column.setCustomSpacing(12, after: column.arrangedSubviews[0]); column.setCustomSpacing(12, after: outputSummary)
        return column
    }
    func showOutputSize(_ count: Int?, busy: Bool = false) {
        outputSize.stringValue = count.map { "约 " + ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) + " / 张" } ?? (busy ? "正在估算…" : "—")
    }
    func set(_ value: CompositionSettings) {
        // Artwork dragging updates positions only; selection controls keep their identity and focus.
        settings = value; mode.selectedIndex = value.mode == .transparent ? 0 : 1
    }
    func restore(_ value: CompositionSettings) {
        settings = value; mode.selectedIndex = value.mode == .transparent ? 0 : 1
        devicePicker.selectedIndex = DisplayKind.allCases.firstIndex(of: value.display) ?? 0
        formatPicker.selectedIndex = value.format == .png ? 0 : 1
        stopBackgroundDrag(); rebuildDevice(); rebuildAppearance(); rebuildBackground(); rebuildExport()
    }
    func chooseCanvas(_ value: CanvasRatio) { edit { $0.canvas = value }; rebuildBackground() }
    private func refreshArtwork() {
        artwork.load(display: settings.display) { [weak self] result in
            guard let self else { return }
            let frames = result.frames.map { cg in cg.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) } }
            self.modelCards?.setImages(frames)
            // Both phone sizes share one silhouette; the caption carries the size difference.
            self.phoneModelCards?.setImages(CompositionSettings.phoneModels.map { _ in frames.first ?? nil })
            self.backgroundCards?.setImages(result.backgrounds.map { cg in cg.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) } })
        }
    }
    func setEditingEnabled(_ enabled: Bool) {
        editingEnabled = enabled
        func visit(_ view: NSView) { (view as? NSControl)?.isEnabled = enabled; view.subviews.forEach(visit) }
        visit(self); visit(exportSettings); mode.isEnabled = enabled
    }
    private func edit(_ change: (inout CompositionSettings) -> Void) {
        guard editingEnabled else { return }; change(&settings); refreshSummaries(); onChange?(settings)
    }
    private func editDevice(_ change: (inout CompositionSettings) -> Void) { stopBackgroundDrag(); edit(change) }
    private func stopBackgroundDrag() { dragBackground = false; dragToggle?.value = false }

    // MARK: Layout

    private static func summaryLabel() -> NSTextField {
        let label = FraloStyle.text("", role: .detail, secondary: true)
        label.textColor = .tertiaryLabelColor; label.alignment = .right; label.lineBreakMode = .byTruncatingTail
        return label
    }
    private func header(_ title: String, summary: NSTextField) -> NSView {
        let label = FraloStyle.text(title); label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return FraloStyle.stack([label, NSView(), summary], axis: .horizontal, spacing: 8)
    }
    private func section(_ title: String, summary: NSTextField, views: [NSView]) -> NSStackView {
        let stack = NSStackView(); configure(stack, views: [header(title, summary: summary)] + views); return stack
    }
    /// Label on the leading edge, a fixed-width control on the trailing edge.
    private func field(_ title: String, _ control: NSView, width: CGFloat? = nil) -> NSView {
        let label = FraloStyle.text(title, role: .detail, secondary: true); label.font = .systemFont(ofSize: 12.5)
        if let width { control.widthAnchor.constraint(equalToConstant: width).isActive = true }
        let row = FraloStyle.stack([label, NSView(), control], axis: .horizontal, spacing: 8)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
        return row
    }
    private func slider(_ title: String, range: ClosedRange<Double>, value: Double, onChange: @escaping (Double) -> Void) -> CompactSliderField {
        CompactSliderField(title, range: range, value: value, onChange: onChange)
    }
    private func configure(_ stack: NSStackView, views: [NSView]) {
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        for view in views { stack.addArrangedSubview(view); view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    }
    private func install(_ views: [NSView], in host: NSView, spacing: CGFloat = 10) {
        let focused = window?.firstResponder as? NSView
        let focusLabel = focused.flatMap { $0.isDescendant(of: host) ? $0.accessibilityLabel() : nil }
        host.subviews.forEach { $0.removeFromSuperview() }
        let content = FraloStyle.stack(views, spacing: spacing, fillWidth: true)
        func wire(_ view: NSView) {
            if let row = view as? SliderRow { row.onEditingChanged = { [weak self] in self?.onContinuousEditing?($0) } }
            if let row = view as? CompactSliderField { row.onEditingChanged = { [weak self] in self?.onContinuousEditing?($0) } }
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
        refreshSummaries()
    }

    // MARK: Summaries

    private static func pngPreset(_ settings: CompositionSettings) -> Int {
        settings.pngLossless ? 0 : settings.pngQuality >= 0.6 ? 1 : 2
    }
    private func refreshSummaries() {
        switch settings.display {
        case .phone: deviceSummary.stringValue = settings.phoneModel.title
        case .tablet: deviceSummary.stringValue = "iPad · " + settings.orientation.title
        case .browser: deviceSummary.stringValue = (settings.browser == .safari ? "Safari" : "Chrome") + " · " + settings.windowRatio.rawValue
        }
        let shadow = ["无阴影", "柔和阴影", "明显阴影"][ShadowStyle.allCases.firstIndex(of: settings.shadow) ?? 0]
        appearanceSummary.stringValue = settings.deviceOpacity < 1 ? "\(shadow) · \(Int((settings.deviceOpacity * 100).rounded()))%" : shadow
        backgroundSummary.stringValue = settings.canvas.rawValue
        let format = settings.format == .png ? "PNG" : "JPEG"
        exportSummary.stringValue = settings.format == .png ? "PNG · " + ["无损", "均衡", "最小"][Self.pngPreset(settings)]
            : "JPEG · \(Int((settings.jpegQuality * 100).rounded()))%"
        var parts = ["\(batchCount) 张", (settings.mode == .transparent && settings.format == .png ? "透明 " : "") + format]
        let includes = [settings.display == .phone ? "侧键" : nil, settings.shadow == .none ? nil : "阴影"].compactMap { $0 }
        if !includes.isEmpty { parts.append("包含" + includes.joined(separator: "与")) }
        outputSummary.stringValue = parts.joined(separator: " · ")
    }

    // MARK: Groups

    private func rebuildDevice() {
        modelCards = nil; phoneModelCards = nil; orientationCards = nil
        var views: [NSView] = []
        switch settings.display {
        case .browser:
            let cards = VisualChoiceGroup([.init("Safari", symbol: "safari"), .init("Chrome", symbol: "globe")], label: "浏览器外观", selected: settings.browser == .safari ? 0 : 1, captionsBelow: true) { [weak self] index in self?.editDevice { $0.browser = index == 0 ? .safari : .chrome } }
            modelCards = cards; views.append(cards)
            views.append(field("窗口比例", ChoiceMenu(WindowRatio.allCases.map(\.rawValue), label: "浏览器窗口比例", selected: WindowRatio.allCases.firstIndex(of: settings.windowRatio)!) { [weak self] index in self?.editDevice { $0.windowRatio = WindowRatio.allCases[index] } }))
        case .phone, .tablet:
            let phone = settings.display == .phone
            if phone {
                let models = CompositionSettings.phoneModels
                var items: [VisualChoiceItem] = models.map { .init($0.title.replacingOccurrences(of: "iPhone ", with: ""), detail: $0.isMax ? "6.9″" : "6.3″", symbol: "iphone") }
                // Folding form factor: listed so the lineup reads as planned, not selectable yet.
                items.append(.init("Duo", detail: "即将支持", image: Self.foldingArtwork, available: false))
                let cards = VisualChoiceGroup(items, label: "机型", selected: models.firstIndex(of: settings.phoneModel)) { [weak self] index in
                    guard models.indices.contains(index) else { return }
                    self?.editDevice { $0.phoneModel = models[index] }
                }
                phoneModelCards = cards; views.append(cards)
            }
            let symbols = phone ? ["iphone", "iphone.landscape"] : ["ipad", "ipad.landscape"]
            let orientation = VisualChoiceGroup([.init("竖屏", symbol: symbols[0]), .init("横屏", symbol: symbols[1])], label: "方向",
                                                selected: settings.orientation == .portrait ? 0 : 1, layout: .options(columns: 2)) { [weak self] index in
                self?.editDevice { $0.orientation = index == 0 ? .portrait : .landscape }
            }
            orientationCards = orientation; views.append(orientation)
        }
        install(views, in: deviceDetails); refreshArtwork()
    }
    private func rebuildAppearance() {
        var views: [NSView] = []
        let shadow = ValuePicker(["无", "柔和", "明显"], label: "阴影", selected: ShadowStyle.allCases.firstIndex(of: settings.shadow)!) { [weak self] index in
            self?.editDevice { if $0.mode == .transparent { $0.transparentShadow = ShadowStyle.allCases[index] } else { $0.backgroundShadow = ShadowStyle.allCases[index] } }
        }
        shadow.controlSize = .small
        views.append(field("阴影", shadow, width: 172))
        views.append(slider("不透明度", range: 0...100, value: settings.deviceOpacity * 100) { [weak self] v in self?.editDevice { $0.deviceOpacity = v / 100 } })
        if settings.mode == .background {
            views.append(slider("设备缩放", range: 10...150, value: settings.deviceScale * 100) { [weak self] v in self?.editDevice { $0.deviceScale = v / 100 } })
            let center = ActionButton("居中", role: .secondary, size: .compact, symbol: "arrow.up.and.down.and.arrow.left.and.right") { [weak self] in self?.editDevice { $0.deviceX = 0; $0.deviceY = 0 } }
            center.setAccessibilityLabel("设备居中")
            views.append(field("位置", center))
        }
        install(views, in: appearanceDetails, spacing: 6)
    }
    private func rebuildBackground() {
        backgroundSection.isHidden = settings.mode != .background
        backgroundType.selectedIndex = settings.background == .solid ? 0 : settings.background == .gradient ? 1 : 2
        backgroundCards = nil
        var views: [NSView] = []
        if settings.background == .solid || settings.background == .gradient {
            stopBackgroundDrag()
            let c = settings.backgroundColor
            views.append(field("颜色", ColorChoice(label: "背景颜色", color: NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)) { [weak self] value in
                if let rgb = value.usingColorSpace(.sRGB) { self?.edit { $0.backgroundColor = ArtworkColor(rgb.redComponent, rgb.greenComponent, rgb.blueComponent) } }
            }))
        } else {
            let presets: [BackgroundKind] = [.warm, .mist, .sage]
            let backgrounds = VisualChoiceGroup([.init("暖灰"), .init("雾蓝"), .init("灰绿")], label: "背景预设", selected: presets.firstIndex(of: settings.background), layout: .tiles(columns: 3, height: 86)) { [weak self] index in
                self?.edit { $0.background = presets[index]; $0.backgroundScale = 1; $0.backgroundX = 0; $0.backgroundY = 0 }; self?.rebuildBackground()
            }
            backgroundCards = backgrounds; views.append(backgrounds)
            let choose = ActionButton(settings.background == .local ? "更换…" : "选择…", role: .secondary, size: .compact, symbol: "folder") { [weak self] in self?.chooseBackground() }
            choose.setAccessibilityLabel(settings.background == .local ? "更换本地图片" : "选择本地图片")
            let current = settings.background == .local ? settings.localBackgroundPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "尚未选择" : "本地图片"
            views.append(field(current, choose))
            views.append(slider("背景缩放", range: 100...400, value: settings.backgroundScale * 100) { [weak self] value in self?.edit { $0.backgroundScale = value / 100 } })
            let toggle = ToggleControl("拖动背景取景", value: dragBackground) { [weak self] in self?.dragBackground = $0 }; dragToggle = toggle
            let reset = ActionButton("重置", role: .quiet, size: .compact) { [weak self] in
                self?.edit { $0.backgroundX = 0; $0.backgroundY = 0; $0.backgroundScale = 1 }; self?.rebuildBackground()
            }
            reset.setAccessibilityLabel("重置背景取景")
            views.append(FraloStyle.stack([toggle, NSView(), reset], axis: .horizontal, spacing: 8))
        }
        views.append(slider("背景透明度", range: 0...100, value: settings.backgroundOpacity * 100) { [weak self] value in self?.edit { $0.backgroundOpacity = value / 100 } })
        views.append(field("画布比例", ChoiceMenu(CanvasRatio.allCases.map(\.rawValue), label: "画布比例", selected: CanvasRatio.allCases.firstIndex(of: settings.canvas)!) { [weak self] index in self?.edit { $0.canvas = CanvasRatio.allCases[index] } }))
        views.append(field("构图模板", ChoiceMenu(["选择模板…", "暖灰 · 居中", "雾蓝 · 宽幅", "灰绿 · 竖幅"], label: "内置构图模板") { [weak self] index in
            guard index > 0 else { return }
            self?.edit { s in
                s.background = [.warm, .mist, .sage][index - 1]; s.canvas = [.landscape, .wide, .portrait][index - 1]
                s.deviceScale = index == 2 ? 0.68 : 0.74; s.deviceX = 0; s.deviceY = 0; s.backgroundShadow = .soft
                s.backgroundScale = 1; s.backgroundX = 0; s.backgroundY = 0
            }
            self?.stopBackgroundDrag(); self?.rebuildAppearance(); self?.rebuildBackground()
        }))
        install(views, in: backgroundDetails, spacing: 6); refreshArtwork()
    }
    private func rebuildExport() {
        var views: [NSView] = []
        if settings.format == .jpeg {
            views.append(slider("品质", range: 10...100, value: settings.jpegQuality * 100) { [weak self] v in self?.edit { $0.jpegQuality = v / 100 } })
            let c = settings.jpegFill
            let color = ColorChoice(label: "JPEG 透明区域填色", color: NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)) { [weak self] v in
                if let rgb = v.usingColorSpace(.sRGB) { self?.edit { $0.jpegFill = ArtworkColor(rgb.redComponent, rgb.greenComponent, rgb.blueComponent) } }
            }
            views.append(field("透明区域填色", color))
            views.append(FraloStyle.paragraph("复制图片仍使用透明 PNG。"))
        } else {
            pngCompression.selectedIndex = Self.pngPreset(settings)
            views.append(field("体积", pngCompression, width: 172))
        }
        install(views, in: exportDetails, spacing: 6)
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
