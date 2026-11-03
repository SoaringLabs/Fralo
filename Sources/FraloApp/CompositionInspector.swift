import FraloLocalization
import AppKit
import UniformTypeIdentifiers
import FraloCore
import FraloDesignSystem

/// Native slider that reports the start and end of one drag, so a drag becomes one undo step.
@MainActor
final class CompactSlider: NSSlider {
    var onEditingChanged: ((Bool) -> Void)?
    /// One reference value, marked under the track, that the knob settles on when dragged close.
    var markValue: Double? { didSet { needsDisplay = true } }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        onEditingChanged?(true)
        defer { onEditingChanged?(false) }
        super.mouseDown(with: event)
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let markValue, maxValue > minValue, let cell = cell as? NSSliderCell else { return }
        let bar = cell.barRect(flipped: isFlipped), knob = cell.knobThickness
        let x = bar.minX + knob / 2 + (markValue - minValue) / (maxValue - minValue) * (bar.width - knob)
        NSColor.secondaryLabelColor.setFill()
        NSRect(x: x.rounded() - 0.5, y: isFlipped ? bar.maxY + 2 : bar.minY - 6, width: 1, height: 4).fill()
    }
}

/// Inspector row: label on the leading edge, slider and a tabular percentage on the trailing edge.
@MainActor
final class CompactSliderField: NSStackView {
    let slider: CompactSlider
    let valueLabel = FraloStyle.text("", role: .detail)
    var onEditingChanged: ((Bool) -> Void)? { didSet { slider.onEditingChanged = onEditingChanged } }
    /// VoiceOver reads the reference the number is measured against, e.g. "占画布 74%".
    var accessibilityValuePrefix = "" { didSet { update() } }
    /// Settle on `markValue` within this distance, with a haptic tick on trackpads.
    var snapDistance = 0.0
    private var snapped = false
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
    private func update() {
        valueLabel.stringValue = "\(Int(slider.doubleValue.rounded()))%"
        slider.setAccessibilityValueDescription(accessibilityValuePrefix + valueLabel.stringValue)
    }
    @objc private func changed(_ sender: Any?) {
        if let mark = slider.markValue, snapDistance > 0 {
            let near = abs(slider.doubleValue - mark) <= snapDistance
            if near { slider.doubleValue = mark }
            if near && !snapped { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
            snapped = near
        }
        update(); if slider.isEnabled { onChange(slider.doubleValue) }
    }
}

@MainActor
final class CompositionInspector: NSView {
    private(set) var settings: CompositionSettings
    var onChange: ((CompositionSettings) -> Void)?
    let mode: ValuePicker
    let devicePicker: ValuePicker
    let formatPicker: ValuePicker
    let exportSettings = NSStackView()
    /// Output specifications live with the other export settings in the scrolling form.
    let outputInfo = FraloStyle.text("—", role: .body)
    let sizeEstimate = EstimatedSizeView()
    var outputSize: NSTextField { sizeEstimate.label }
    var onContinuousEditing: ((Bool) -> Void)?
    private let deviceDetails = NSView(), appearanceDetails = NSView(), compositionDetails = NSView(), backgroundDetails = NSView(), exportDetails = NSView()
    /// Layout and backdrop only exist in background mode; their dividers hide with them.
    private let compositionSection = NSStackView(), backgroundSection = NSStackView()
    private let compositionDivider = FraloStyle.divider(), backgroundDivider = FraloStyle.divider()
    private let formatField = NSView()
    private let backgroundType: ValuePicker
    private let pngCompression: ValuePicker
    private let artwork = InspectorArtwork()
    private weak var modelCards: VisualChoiceGroup?
    private weak var phoneModelCards: VisualChoiceGroup?
    private weak var orientationCards: VisualChoiceGroup?
    private weak var backgroundCards: VisualChoiceGroup?
    private var customThumbnail: NSImage?
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
        mode = ValuePicker([L10n.tr("透明"), L10n.tr("带背景")], label: L10n.tr("成品背景"), selected: settings.mode == .transparent ? 0 : 1, purpose: .tabs, size: .large)
        devicePicker = ValuePicker([L10n.tr("手机"), L10n.tr("平板"), L10n.tr("浏览器")], label: L10n.tr("设备类型"), selected: DisplayKind.allCases.firstIndex(of: settings.display)!, purpose: .tabs, size: .large)
        formatPicker = ValuePicker(["PNG", "JPEG"], label: L10n.tr("文件格式"), selected: settings.format == .png ? 0 : 1)
        backgroundType = ValuePicker([L10n.tr("纯色"), L10n.tr("渐变"), L10n.tr("图片")], label: L10n.tr("背景类型"))
        pngCompression = ValuePicker([L10n.tr("原画质"), L10n.tr("适中"), L10n.tr("最小")], label: L10n.tr("压缩"), selected: Self.pngPreset(settings))
        // Value choices use the native regular size (24 pt): easier to hit than small, still a step below the large category tabs.
        super.init(frame: NSRect(x: 0, y: 0, width: 276, height: 500))
        mode.onChange = { [weak self] index in
            self?.edit { $0.mode = index == 0 ? .transparent : .background }
            self?.rebuildDevice(); self?.rebuildAppearance(); self?.rebuildComposition(); self?.rebuildBackground(); self?.rebuildExport()
        }
        devicePicker.onChange = { [weak self] index in
            self?.edit { $0.display = DisplayKind.allCases[index] }; self?.rebuildDevice(); self?.rebuildAppearance()
        }
        formatPicker.onChange = { [weak self] index in
            self?.edit { $0.format = index == 0 ? .png : .jpeg }; self?.rebuildExport()
        }
        backgroundType.onChange = { [weak self] index in
            self?.edit { $0.background = index == 0 ? .solid : index == 1 ? .gradient : .warm }
            self?.rebuildBackground()
        }
        pngCompression.onChange = { [weak self] index in
            self?.edit { $0.pngLossless = index == 0; if index > 0 { $0.pngQuality = Self.pngPresets[index - 1] } }
        }
        // Group titles carry no value summary; output specifications belong to Export.
        let deviceSection = section(L10n.tr("设备"), views: [devicePicker, deviceDetails])
        let appearanceSection = section(L10n.tr("外观"), views: [appearanceDetails])
        configure(compositionSection, views: [header(L10n.tr("构图")), compositionDetails])
        configure(backgroundSection, views: [header(L10n.tr("背景")), backgroundType, backgroundDetails])
        outputInfo.setAccessibilityLabel(L10n.tr("导出尺寸"))
        outputInfo.toolTip = L10n.tr("尺寸单位：像素")
        outputInfo.setAccessibilityHelp(L10n.tr("尺寸单位：像素"))
        outputSize.setAccessibilityLabel(L10n.tr("预计大小"))
        let specifications = FraloStyle.stack([
            field(L10n.tr("导出尺寸"), outputInfo, minimumHeight: 20),
            field(L10n.tr("预计大小"), sizeEstimate, minimumHeight: 20)
        ], spacing: 6, fillWidth: true)
        let summary = FraloStyle.stack([FraloStyle.divider(), specifications], spacing: 12, fillWidth: true)
        configure(exportSettings, views: [header(L10n.tr("导出")), formatField, exportDetails, summary])
        exportSettings.setCustomSpacing(14, after: exportDetails)
        let body = FraloStyle.stack([deviceSection, FraloStyle.divider(), appearanceSection, compositionDivider, compositionSection,
                                     backgroundDivider, backgroundSection, FraloStyle.divider(), exportSettings],
                                    spacing: 16, fillWidth: true)
        body.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 12, right: 0)
        let scroll = ScrollContent.make(body, inset: 0)
        scroll.translatesAutoresizingMaskIntoConstraints = false; addSubview(scroll)
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
                                     scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor)])
        outputInfo.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .regular); outputInfo.alignment = .right
        outputSize.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .regular); outputSize.alignment = .right
        rebuildDevice(); rebuildAppearance(); rebuildComposition(); rebuildBackground(); rebuildExport()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    /// Only the export action stays fixed while settings and output specifications scroll.
    func makeFooter(action: NSView) -> NSView {
        let column = FraloStyle.stack([FraloStyle.divider(), action], spacing: 12, fillWidth: true)
        return column
    }
    func showOutputSize(_ count: Int?, busy: Bool = false) {
        sizeEstimate.show(count, busy: busy)
    }
    func set(_ value: CompositionSettings) {
        // Artwork dragging updates positions only; selection controls keep their identity and focus.
        settings = value; mode.selectedIndex = value.mode == .transparent ? 0 : 1
    }
    func restore(_ value: CompositionSettings) {
        settings = value; mode.selectedIndex = value.mode == .transparent ? 0 : 1
        devicePicker.selectedIndex = DisplayKind.allCases.firstIndex(of: value.display) ?? 0
        formatPicker.selectedIndex = value.format == .png ? 0 : 1
        rebuildDevice(); rebuildAppearance(); rebuildComposition(); rebuildBackground(); rebuildExport()
    }
    func chooseCanvas(_ value: CanvasRatio) { edit { $0.canvas = value }; rebuildComposition() }
    private func refreshArtwork() {
        artwork.load(display: settings.display) { [weak self] result in
            guard let self else { return }
            let frames = result.frames.map { cg in cg.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) } }
            self.modelCards?.setImages(frames)
            // Both phone sizes share one silhouette; the caption carries the size difference.
            self.phoneModelCards?.setImages(CompositionSettings.phoneModels.map { _ in frames.first ?? nil })
            // The fourth tile keeps the custom image's own thumbnail (or its add/missing symbol).
            self.backgroundCards?.setImages(result.backgrounds.map { cg in cg.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) } } + [self.customThumbnail])
        }
    }
    func setEditingEnabled(_ enabled: Bool) {
        editingEnabled = enabled
        func visit(_ view: NSView) { (view as? NSControl)?.isEnabled = enabled; view.subviews.forEach(visit) }
        visit(self); visit(exportSettings); mode.isEnabled = enabled
    }
    private func edit(_ change: (inout CompositionSettings) -> Void) {
        guard editingEnabled else { return }; change(&settings); onChange?(settings)
    }

    // MARK: Layout

    private func header(_ title: String) -> NSView {
        let label = FraloStyle.text(title); label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }
    private func section(_ title: String, views: [NSView]) -> NSStackView {
        let stack = NSStackView(); configure(stack, views: [header(title)] + views); return stack
    }
    /// Supporting notes wrap when a translation needs more than one line.
    private func hint(_ text: String) -> NSTextField {
        let label = FraloStyle.paragraph(text); label.font = FraloStyle.TextRole.caption.font
        label.textColor = .tertiaryLabelColor; return label
    }
    /// Label on the leading edge, a fixed-width control on the trailing edge.
    private func field(_ title: String, _ control: NSView, width: CGFloat? = nil, minimumHeight: CGFloat = 28) -> NSView {
        let label = FraloStyle.text(title, role: .detail, secondary: true); label.font = .systemFont(ofSize: 12.5)
        if let width { control.widthAnchor.constraint(equalToConstant: width).isActive = true }
        let row = FraloStyle.stack([label, NSView(), control], axis: .horizontal, spacing: 8)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: minimumHeight).isActive = true
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
    }

    private static func pngPreset(_ settings: CompositionSettings) -> Int {
        settings.pngLossless ? 0 : settings.pngQuality >= 0.6 ? 1 : 2
    }
    /// Ratios read as shapes, so the menu says what each one is for.
    // Computed so a language change made in Settings is picked up by the rebuilt inspector.
    private static var canvasTitles: [CanvasRatio: String] { [.square: L10n.tr("1:1 方形"), .landscape: L10n.tr("4:3 横向"), .wide: L10n.tr("16:9 宽屏"), .portrait: L10n.tr("3:4 竖向"), .story: L10n.tr("9:16 手机全屏")] }

    // MARK: Groups

    private func rebuildDevice() {
        modelCards = nil; phoneModelCards = nil; orientationCards = nil
        var views: [NSView] = []
        switch settings.display {
        case .browser:
            let cards = VisualChoiceGroup([.init("Safari", symbol: "safari"), .init("Chrome", symbol: "globe")], label: L10n.tr("浏览器外观"), selected: settings.browser == .safari ? 0 : 1, captionsBelow: true) { [weak self] index in self?.edit { $0.browser = index == 0 ? .safari : .chrome } }
            modelCards = cards; views.append(cards)
            views.append(field(L10n.tr("窗口比例"), ChoiceMenu(WindowRatio.allCases.map(\.rawValue), label: L10n.tr("浏览器窗口比例"), selected: WindowRatio.allCases.firstIndex(of: settings.windowRatio)!) { [weak self] index in self?.edit { $0.windowRatio = WindowRatio.allCases[index] } }))
        case .phone, .tablet:
            let phone = settings.display == .phone
            if phone {
                let models = CompositionSettings.phoneModels
                var items: [VisualChoiceItem] = models.map { .init($0.title.replacingOccurrences(of: "iPhone ", with: ""), detail: $0.isMax ? "6.9″" : "6.3″", symbol: "iphone") }
                // Folding form factor: listed so the lineup reads as planned, not selectable yet.
                items.append(.init("Duo", detail: L10n.tr("即将支持"), image: Self.foldingArtwork, available: false))
                let cards = VisualChoiceGroup(items, label: L10n.tr("机型"), selected: models.firstIndex(of: settings.phoneModel)) { [weak self] index in
                    guard models.indices.contains(index) else { return }
                    self?.edit { $0.phoneModel = models[index] }
                }
                phoneModelCards = cards; views.append(cards)
            }
            let symbols = phone ? ["iphone", "iphone.landscape"] : ["ipad", "ipad.landscape"]
            let orientation = VisualChoiceGroup([.init(L10n.tr("竖屏"), symbol: symbols[0]), .init(L10n.tr("横屏"), symbol: symbols[1])], label: L10n.tr("方向"),
                                                selected: settings.orientation == .portrait ? 0 : 1, layout: .options(columns: 2)) { [weak self] index in
                self?.edit { $0.orientation = index == 0 ? .portrait : .landscape }
            }
            orientationCards = orientation; views.append(orientation)
        }
        install(views, in: deviceDetails); refreshArtwork()
    }
    private func rebuildAppearance() {
        var views: [NSView] = []
        if settings.display == .browser {
            let appearance = ValuePicker([L10n.tr("浅色"), L10n.tr("深色")], label: L10n.tr("配色"), selected: settings.browserAppearance == .light ? 0 : 1) { [weak self] index in
                self?.edit { $0.browserAppearance = index == 0 ? .light : .dark }
            }
            appearance.toolTip = L10n.tr("仅改变浏览器外壳，不改变截图或 Fralo 界面外观")
            views.append(field(L10n.tr("配色"), appearance, width: 172))
        }
        let shadow = ValuePicker([L10n.tr("无"), L10n.tr("浅"), L10n.tr("深")], label: L10n.tr("阴影"), selected: ShadowStyle.allCases.firstIndex(of: settings.shadow)!) { [weak self] index in
            self?.edit { if $0.mode == .transparent { $0.transparentShadow = ShadowStyle.allCases[index] } else { $0.backgroundShadow = ShadowStyle.allCases[index] } }
        }
        views.append(field(L10n.tr("阴影"), shadow, width: 172))
        // A see-through device only makes sense over a backdrop; transparent output is always opaque.
        if settings.mode == .background {
            views.append(slider(L10n.tr("不透明度"), range: 0...100, value: settings.deviceOpacity * 100) { [weak self] v in self?.edit { $0.deviceOpacity = v / 100 } })
        }
        install(views, in: appearanceDetails, spacing: 6)
    }
    private func rebuildComposition() {
        let visible = settings.mode == .background
        compositionSection.isHidden = !visible; compositionDivider.isHidden = !visible
        guard visible else { install([], in: compositionDetails); return }
        let ratios = CanvasRatio.allCases
        let canvas = ChoiceMenu(ratios.map { Self.canvasTitles[$0] ?? $0.rawValue }, label: L10n.tr("画布比例"), selected: ratios.firstIndex(of: settings.canvas)!) { [weak self] index in
            self?.edit { $0.canvas = ratios[index] }
        }
        let center = ActionButton(L10n.tr("重新居中"), role: .secondary, size: .compact, symbol: "arrow.up.and.down.and.arrow.left.and.right") { [weak self] in self?.edit { $0.deviceX = 0; $0.deviceY = 0 } }
        center.setAccessibilityLabel(L10n.tr("设备重新居中"))
        // 100% means the device's long side just reaches the canvas edge; past it the device is cropped.
        let overflow = hint(L10n.tr("超出画布的部分会被裁掉")); overflow.isHidden = settings.deviceScale <= 1
        let size = slider(L10n.tr("设备大小"), range: 10...150, value: settings.deviceScale * 100) { [weak self] v in
            overflow.isHidden = v <= 100; self?.edit { $0.deviceScale = v / 100 }
        }
        size.slider.markValue = 100; size.snapDistance = 4; size.accessibilityValuePrefix = L10n.tr("占画布 ")
        size.slider.toolTip = L10n.tr("设备长边占画布的比例，100% 为刚好放满")
        install([field(L10n.tr("画布比例"), canvas), size, overflow, field(L10n.tr("位置"), center), hint(L10n.tr("也可以在预览中直接拖动设备"))], in: compositionDetails, spacing: 6)
    }
    private func rebuildBackground() {
        backgroundSection.isHidden = settings.mode != .background; backgroundDivider.isHidden = backgroundSection.isHidden
        backgroundType.selectedIndex = settings.background == .solid ? 0 : settings.background == .gradient ? 1 : 2
        backgroundCards = nil
        var views: [NSView] = []
        func color(_ title: String, _ value: ArtworkColor, _ apply: @escaping (inout CompositionSettings, ArtworkColor) -> Void) -> NSView {
            field(title, ColorChoice(label: title, color: NSColor(srgbRed: value.red, green: value.green, blue: value.blue, alpha: 1)) { [weak self] picked in
                if let rgb = picked.usingColorSpace(.sRGB) { self?.edit { apply(&$0, ArtworkColor(rgb.redComponent, rgb.greenComponent, rgb.blueComponent)) } }
            })
        }
        if settings.background == .solid {
            views.append(color(L10n.tr("颜色"), settings.backgroundColor) { $0.backgroundColor = $1 })
        } else if settings.background == .gradient {
            views.append(color(L10n.tr("起点颜色"), settings.backgroundColor) { $0.backgroundColor = $1 })
            views.append(color(L10n.tr("终点颜色"), settings.backgroundEndColor) { $0.backgroundEndColor = $1 })
        } else {
            // The custom image is a fourth choice, so it shows as selected and stays one click away after trying a preset.
            let presets: [BackgroundKind] = [.warm, .mist, .sage, .local]
            let path = settings.localBackgroundPath
            customThumbnail = path.flatMap { Self.thumbnail(atPath: $0) }
            let missing = path != nil && customThumbnail == nil
            let custom = VisualChoiceItem(L10n.tr("自定义"), symbol: path == nil ? "plus" : "exclamationmark.triangle", image: customThumbnail)
            let backgrounds = VisualChoiceGroup([.init(L10n.tr("暖灰")), .init(L10n.tr("雾蓝")), .init(L10n.tr("灰绿")), custom], label: L10n.tr("背景图片"), selected: presets.firstIndex(of: settings.background), layout: .tiles(columns: 4, height: 80)) { [weak self] index in
                guard let self else { return }
                if presets[index] == .local && (path == nil || missing) { self.rebuildBackground(); self.chooseBackground(); return }
                self.edit { $0.background = presets[index]; $0.backgroundScale = 1; $0.backgroundX = 0; $0.backgroundY = 0 }; self.rebuildBackground()
            }
            backgrounds.setCardToolTip(path == nil ? L10n.tr("添加自定义图片…") : missing ? L10n.tr("找不到图片，点按重新选择") : URL(fileURLWithPath: path!).lastPathComponent, at: 3)
            backgroundCards = backgrounds; views.append(backgrounds)
            if settings.background == .local, let path {
                let change = ActionButton(L10n.tr("更换…"), role: .secondary, size: .compact, symbol: "folder") { [weak self] in self?.chooseBackground() }
                change.setAccessibilityLabel(L10n.tr("更换自定义图片"))
                let name = FraloStyle.text(missing ? L10n.tr("找不到图片") : URL(fileURLWithPath: path).lastPathComponent, role: .detail, secondary: true)
                name.lineBreakMode = .byTruncatingMiddle; name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                views.append(FraloStyle.stack([name, NSView(), change], axis: .horizontal, spacing: 8))
            }
            views.append(slider(L10n.tr("图片大小"), range: 100...400, value: settings.backgroundScale * 100) { [weak self] value in self?.edit { $0.backgroundScale = value / 100 } })
            let reset = ActionButton(L10n.tr("还原"), role: .quiet, size: .compact) { [weak self] in
                self?.edit { $0.backgroundX = 0; $0.backgroundY = 0; $0.backgroundScale = 1 }; self?.rebuildBackground()
            }
            reset.setAccessibilityLabel(L10n.tr("还原背景位置与大小"))
            views.append(FraloStyle.stack([hint(L10n.tr("在预览中拖动空白处调整背景")), NSView(), reset], axis: .horizontal, spacing: 8))
        }
        views.append(slider(L10n.tr("不透明度"), range: 0...100, value: settings.backgroundOpacity * 100) { [weak self] value in self?.edit { $0.backgroundOpacity = value / 100 } })
        install(views, in: backgroundDetails, spacing: 6); refreshArtwork()
    }
    private func rebuildExport() {
        // Transparent output is always PNG; the stored JPEG choice comes back with a background.
        let format: NSView
        if settings.mode == .transparent {
            let value = FraloStyle.text(L10n.tr("PNG（保留透明）"), role: .detail); value.font = .systemFont(ofSize: 12.5)
            format = field(L10n.tr("格式"), value)
        } else {
            formatPicker.selectedIndex = settings.format == .png ? 0 : 1
            format = field(L10n.tr("格式"), formatPicker, width: 172)
        }
        install([format], in: formatField)
        var views: [NSView] = []
        if settings.outputFormat == .jpeg {
            views.append(slider(L10n.tr("画质"), range: 10...100, value: settings.jpegQuality * 100) { [weak self] v in self?.edit { $0.jpegQuality = v / 100 } })
        } else {
            pngCompression.selectedIndex = Self.pngPreset(settings)
            // Three translated choices need the full inspector width rather than a 172 pt value slot.
            let label = FraloStyle.text(L10n.tr("压缩"), role: .detail, secondary: true); label.font = .systemFont(ofSize: 12.5)
            views.append(FraloStyle.stack([label, pngCompression], spacing: 6, fillWidth: true))
        }
        install(views, in: exportDetails, spacing: 6)
    }
    private static func thumbnail(atPath path: String) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 240,
                                                                          kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
    private func chooseBackground() {
        guard let window else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg]; panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.edit { $0.localBackgroundPath = url.path; $0.background = .local; $0.backgroundScale = 1; $0.backgroundX = 0; $0.backgroundY = 0 }
            self?.rebuildBackground()
        }
    }
}
