#if FRALO_DEV
import AppKit
import FraloDesignSystem

@MainActor
enum LabPages {
    static func sample(_ view: NSView, width: CGFloat = 520) -> NSView {
        let wrapper = NSView(); view.translatesAutoresizingMaskIntoConstraints = false; wrapper.addSubview(view)
        let preferred = view.widthAnchor.constraint(equalToConstant: width); preferred.priority = .defaultHigh
        NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor), view.topAnchor.constraint(equalTo: wrapper.topAnchor),
                                     view.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor), view.widthAnchor.constraint(lessThanOrEqualTo: wrapper.widthAnchor), preferred])
        return wrapper
    }
    static func document(title: String, detail: String, sections: [NSView]) -> NSView {
        let heading = FraloStyle.stack([FraloStyle.text(title, role: .title), FraloStyle.paragraph(detail)], spacing: 8)
        let column = FraloStyle.stack([heading] + sections, spacing: 28)
        for view in column.arrangedSubviews { view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
        let scroll = NSScrollView(); ScrollContent.install(column, in: scroll, inset: 24)
        return scroll
    }

    static func foundations(state: DesignLabState) -> NSView {
        let typeRows = FraloStyle.TextRole.allCases.map { role in
            FraloStyle.stack([FraloStyle.text("\(role.rawValue) · \(Int(role.font.pointSize)) pt", secondary: true),
                              FraloStyle.text("Fralo 截图展示 · A little outside.", role: role)], axis: .horizontal, spacing: 24)
        }
        let surfaceRows: [NSView] = [
            InfoRow("workspace", value: "标准材质 · 桌面透色 · 不属于输出"),
            InfoRow("panel", value: "悬浮设置 · 比工作区扎实 · 随系统变化"),
            InfoRow("artwork", value: "真实输出矩形 · 不透桌面 · 透明处棋盘格"),
            InfoRow("label / secondaryLabel / disabled", value: "系统语义颜色，禁止页面各自猜灰度")
        ]
        return document(title: "稳定基础", detail: "这些角色来自 FraloDesignSystem，供实验室和正式界面共同使用。它们是 Fralo 的产品规格，不是 Apple 官方固定尺寸。", sections: [
            FormSection("文字层级", views: typeRows),
            FormSection("表面与颜色语义", views: surfaceRows),
            FormSection("空间与尺寸", views: [
                InfoRow("间距阶梯", value: "4 / 8 / 12 / 16 / 24 / 32 pt"),
                InfoRow("图标按钮命中区", value: "28 × 28 pt · 图标来自 SF Symbols"),
                InfoRow("参数选择器", value: "30 pt 起 · 单选语义，不冒充导航"),
                InfoRow("缩略图", value: "48 × 60 pt 等比容纳，76 pt 行高")
            ]),
            FormSection("反馈与动效", detail: "系统开启减少动态效果时直接切换。上方模拟选项只能加强系统设置。", views: [
                InfoRow("选择 / 结构 / 预览", value: "180 / 220 / 160 ms，减少动态效果时为 0"),
                InfoRow("按下与悬停", value: "优先原生控件反馈，避免整行缩放"),
                InfoRow("稳定与实验", value: "稳定角色在共享模块，候选只在实验室")
            ])
        ])
    }

    static func components(state: DesignLabState) -> NSView {
        let feedback = FraloStyle.text("操作反馈会显示在这里", role: .detail, secondary: true)
        let primary = ActionButton("主操作", role: .primary) { feedback.stringValue = "已触发主操作" }
        let secondary = ActionButton("次要操作") { feedback.stringValue = "已触发次要操作" }
        let quiet = ActionButton("轻量操作", role: .quiet) { feedback.stringValue = "已触发轻量操作" }
        let destructive = ActionButton("移除", role: .destructive) { feedback.stringValue = "已模拟移除；不修改用户数据" }
        let disabled = ActionButton("不可用"); disabled.isEnabled = false
        let busy = ActionButton("导出样例"); busy.isBusy = true
        let icon = IconButton("arrow.counterclockwise", label: "重置样例") { feedback.stringValue = "已重置样例" }
        let export = ExportAction(count: 3)
        export.onExportAll = { feedback.stringValue = "主按钮仍然作用于全部 3 张" }
        export.onExportCurrent = { feedback.stringValue = "下拉只作用于当前图，主按钮范围不变" }
        let picker = ValuePicker(["透明套壳", "背景成图"], label: "出图模式") { feedback.stringValue = "模式变更：\($0)" }
        picker.preferences = state.preferences
        let orientation = ValuePicker(["竖屏", "横屏"], label: "输出方向"); orientation.preferences = state.preferences
        let disabledPicker = ValuePicker(["无", "柔和", "明显"], label: "不可用阴影"); disabledPicker.isEnabled = false
        let popup = ChoiceMenu(["Safari", "Chrome"], label: "浏览器样式") { feedback.stringValue = "浏览器样式变更：\($0)" }
        let color = ColorChoice(label: "填底颜色", color: .white) { _ in feedback.stringValue = "已选择样例颜色" }
        let number = ValueField(label: "JPEG 质量", value: 90, range: 1...100) { feedback.stringValue = "已提交有效数值：\($0)" }
        let slider = SliderRow("设备缩放", range: 20...100, value: 74) { feedback.stringValue = "设备缩放：\(Int($0))%" }
        let opacity = SliderRow("设备透明度", range: 0...100, value: 100)
        let unavailable = SliderRow("不可用设置", range: 0...100, value: 40); unavailable.isEnabled = false
        let navigation = InspectorTabs([("设备", FraloStyle.text("设备页内容")), ("背景", FraloStyle.text("背景页内容")), ("导出", FraloStyle.text("导出页内容"))])
        navigation.heightAnchor.constraint(equalToConstant: 88).isActive = true
        navigation.onSelection = { feedback.stringValue = "内容导航切换到第 \($0 + 1) 页" }
        let list = BatchList(entries: state.samples.entries(longNames: true))
        list.heightAnchor.constraint(equalToConstant: 245).isActive = true
        list.onSelection = { feedback.stringValue = "原图列表选中第 \($0 + 1) 张" }
        let swatches = SwatchPicker(["暖灰", "雾蓝", "灰绿"].enumerated().map { index, title -> (String, NSImage?) in
            let image = state.samples.backgrounds.indices.contains(index) ? state.samples.backgrounds[index] : nil
            return (title, image)
        })
        swatches.onSelection = { feedback.stringValue = "背景样例：\($0 + 1)" }
        let states: [StateView] = [
            StateView(.empty, title: "尚无图片", detail: "空态和导入入口") { feedback.stringValue = "已触发样例导入" },
            StateView(.loading, title: "生成预览", detail: "加载反馈不会替代整个窗口"),
            StateView(.failure, title: "无法读取样例", detail: "错误保留原因与重试入口") { feedback.stringValue = "已模拟重试" },
            StateView(.progress, title: "已完成 2 / 5", detail: "取消保留已完成结果") { feedback.stringValue = "已模拟取消；不运行真实导出" }
        ]
        let statesRow = FraloStyle.stack(states, axis: .horizontal, spacing: 16); statesRow.distribution = .fillEqually
        statesRow.heightAnchor.constraint(equalToConstant: 200).isActive = true
        let sections: [NSView] = [
            SoftButtonGallery.make(state: state),
            FormSection("按钮与反馈", detail: "可直接点击，并用 Tab / Shift-Tab 检查焦点；这是共享组件的真实行为。", views: [FraloStyle.stack([primary, secondary, quiet, destructive, icon], axis: .horizontal), FraloStyle.stack([disabled, busy, export], axis: .horizontal), feedback]),
            FormSection("参数选择与内容导航", views: [sample(picker, width: 320), sample(orientation, width: 240), sample(disabledPicker, width: 300), sample(navigation)]),
            FormSection("表单、颜色与数值", views: [sample(FormRow("窗口样式", content: popup)), sample(FormRow("透明填底", content: color)), sample(FormRow("质量数值", content: number)), sample(slider), sample(opacity), sample(unavailable), sample(InfoRow("实际尺寸", value: "2400 × 1800 px"))]),
            FormSection("背景缩略图", views: [swatches, ToggleControl("布尔选项", value: true) { feedback.stringValue = "布尔选项：\($0)" }]),
            FormSection("原图列表与长文件名", views: [list]),
            FormSection("空态、加载、失败与进度", views: [statesRow])
        ]
        return document(title: "真实组件展厅", detail: "稳定组件直接来自共享模块。悬浮面板、收起栏、画布和查看工具条在 Scenarios 中以完整组合验证。", sections: sections)
    }
}

@MainActor
final class MaterialExperiment: NSView {
    let workspace = MaterialSurface(.workspace, radius: 12)
    let panel = MaterialSurface(.panel, radius: 18)
    let canvas = CanvasSurface()
    let status = FraloStyle.text("", role: .detail, secondary: true)
    let opacity = SliderRow("材质层不透明度", range: 0...100, value: 100)
    let tint = SliderRow("背景遮罩浓度", range: 0...100, value: 0)
    let tintOverlay = NSView()
    private let state: DesignLabState
    init(state: DesignLabState) {
        self.state = state; super.init(frame: .zero)
        workspace.preferences = state.preferences; panel.preferences = state.preferences
        tintOverlay.wantsLayer = true
        tintOverlay.translatesAutoresizingMaskIntoConstraints = false
        workspace.addSubview(tintOverlay)
        NSLayoutConstraint.activate([
            tintOverlay.leadingAnchor.constraint(equalTo: workspace.leadingAnchor), tintOverlay.trailingAnchor.constraint(equalTo: workspace.trailingAnchor),
            tintOverlay.topAnchor.constraint(equalTo: workspace.topAnchor), tintOverlay.bottomAnchor.constraint(equalTo: workspace.bottomAnchor)
        ])
        canvas.image = state.samples.backgrounds.first
        let materials: [(String, NSVisualEffectView.Material)] = [("窗口背后背景", .underWindowBackground), ("页面背后背景", .underPageBackground), ("侧栏材质", .sidebar)]
        workspace.material = materials[state.materialIndex].1
        workspace.effect.blendingMode = state.blendingIndex == 0 ? .behindWindow : .withinWindow
        let choice = ChoiceMenu(materials.map(\.0), label: "实验候选材质", selected: state.materialIndex) { [weak self] index in
            self?.state.materialIndex = index; self?.workspace.material = materials[index].1; self?.updateStatus()
        }
        let blend = ValuePicker(["窗口背后", "当前窗口内"], label: "实验混合方式", selected: state.blendingIndex) { [weak self] index in
            self?.state.blendingIndex = index; self?.workspace.effect.blendingMode = index == 0 ? .behindWindow : .withinWindow; self?.updateStatus()
        }
        blend.preferences = state.preferences
        opacity.onChange = { [weak self] value in self?.state.materialOpacity = value; self?.refreshTranslucency() }
        tint.onChange = { [weak self] value in self?.state.materialTint = value; self?.refreshTranslucency() }
        let presets = FraloStyle.stack([
            ActionButton("更通透", size: .compact) { [weak self] in self?.setTranslucency(opacity: 65, tint: 0) },
            ActionButton("更柔实", size: .compact) { [weak self] in self?.setTranslucency(opacity: 100, tint: 35) },
            ActionButton("实色参考", size: .compact) { [weak self] in self?.setTranslucency(opacity: 100, tint: 100) }
        ], axis: .horizontal, spacing: 8)
        let reset = ActionButton("恢复原生效果") { [weak self] in self?.setTranslucency(opacity: 100, tint: 0) }
        let controls = FraloStyle.stack([FraloStyle.text("实验候选", role: .heading), choice, blend,
            FraloStyle.text("背景通透感", role: .heading), presets, opacity, tint, reset,
            FraloStyle.paragraph("材质层 100% 是完整原生效果，仍然透色；降低数值会淡化模糊层。遮罩越浓，背景越实。数值不是系统模糊强度。"),
            FraloStyle.paragraph("仅作用于左侧样例周围的工作区；图片和菜单保持清晰。切换窗口焦点可比较原生状态。降低透明度开启时暂停调节。")], spacing: 14)
        for view in [opacity, tint, blend] { view.widthAnchor.constraint(equalTo: controls.widthAnchor).isActive = true }
        let header = FraloStyle.stack([FraloStyle.text("原生材质实验", role: .title), FraloStyle.paragraph("标准材质、真实窗口合成与不透桌面的成品。不是用固定渐变假装系统玻璃。")], spacing: 8)
        for view in [header, workspace, status] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        for view in [canvas, panel] { view.translatesAutoresizingMaskIntoConstraints = false; workspace.addSubview(view) }
        let scroll = ScrollContent.make(controls)
        scroll.translatesAutoresizingMaskIntoConstraints = false; panel.addSubview(scroll)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 24), header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24), header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            workspace.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 20), workspace.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24), workspace.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24), workspace.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -12),
            status.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24), status.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24), status.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            panel.topAnchor.constraint(equalTo: workspace.topAnchor, constant: 24), panel.bottomAnchor.constraint(equalTo: workspace.bottomAnchor, constant: -24), panel.trailingAnchor.constraint(equalTo: workspace.trailingAnchor, constant: -24), panel.widthAnchor.constraint(equalToConstant: 310),
            canvas.topAnchor.constraint(equalTo: workspace.topAnchor, constant: 24), canvas.bottomAnchor.constraint(equalTo: workspace.bottomAnchor, constant: -24), canvas.leadingAnchor.constraint(equalTo: workspace.leadingAnchor, constant: 24), canvas.trailingAnchor.constraint(equalTo: panel.leadingAnchor, constant: -16),
            scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor), scroll.topAnchor.constraint(equalTo: panel.topAnchor), scroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor)
        ])
        refreshTranslucency()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshTranslucency() }
    func setTranslucency(opacity: Double, tint: Double) {
        guard opacity.isFinite, tint.isFinite else { return }
        state.materialOpacity = min(100, max(0, opacity)); state.materialTint = min(100, max(0, tint))
        refreshTranslucency()
    }
    private func refreshTranslucency() {
        let fallback = workspace.isUsingOpaqueFallback
        opacity.value = state.materialOpacity; tint.value = state.materialTint
        opacity.isEnabled = !fallback; tint.isEnabled = !fallback
        workspace.effect.alphaValue = fallback ? 1 : state.materialOpacity / 100
        tintOverlay.isHidden = fallback
        effectiveAppearance.performAsCurrentDrawingAppearance {
            tintOverlay.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(state.materialTint / 100).cgColor
        }
        updateStatus()
    }
    private func updateStatus() {
        status.stringValue = "仅实验 · 材质层 \(Int(state.materialOpacity))% · 遮罩 \(Int(state.materialTint))% · \(workspace.isUsingOpaqueFallback ? "降低透明度：调节暂停" : "原生材质随窗口焦点变化") · 不影响成品或正式默认值"
    }
}

@MainActor
final class MotionExperiment: NSView {
    let picker = ValuePicker(["竖屏", "横屏"], label: "动效方向选择")
    let workbench: ScenarioWorkbench
    init(state: DesignLabState) {
        let motionState = DesignLabState(samples: state.samples)
        motionState.preferences = state.preferences
        workbench = ScenarioWorkbench(state: motionState)
        super.init(frame: .zero)
        picker.preferences = state.preferences
        let replay = ActionButton("重播选择过渡") { [weak picker] in guard let picker else { return }; picker.choose(1 - picker.selectedIndex) }
        let collapse = ActionButton("展开 / 收起图片列表") { [weak workbench] in workbench?.toggleSidebar() }
        let preview = ActionButton("切换成品预览") { [weak workbench] in workbench?.togglePreview() }
        let status = FraloStyle.text("实际过渡：选择 \(Int(FraloMotion.duration(.selection, preferences: state.preferences) * 1000)) ms · 结构 \(Int(FraloMotion.duration(.structure, preferences: state.preferences) * 1000)) ms", role: .detail, secondary: true)
        let heading = FraloStyle.stack([FraloStyle.text("交互与动效实验", role: .title),
            FraloStyle.paragraph("结构变化不能修改成品构图；原生控件保留自己的反馈。开启上方减少动态效果后重播，过渡应直接完成。"),
            FraloStyle.stack([picker, replay, collapse, preview], axis: .horizontal, spacing: 12), status], spacing: 10)
        for view in [heading, workbench] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24), heading.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24), heading.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            workbench.leadingAnchor.constraint(equalTo: leadingAnchor), workbench.trailingAnchor.constraint(equalTo: trailingAnchor), workbench.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 12), workbench.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}
#endif
