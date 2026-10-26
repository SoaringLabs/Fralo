#if FRALO_DEV
import AppKit
import FraloDesignSystem

@MainActor
enum SoftButtonGallery {
    static func make(state: DesignLabState) -> NSView {
        let feedback = FraloStyle.text("点击按钮体验反馈；候选不修改用户数据。", role: .detail, secondary: true)
        let primary = SoftButton("导出全部", role: .primary, symbol: "square.and.arrow.up") { feedback.stringValue = "柔和主按钮：已触发模拟导出" }
        let add = SoftButton("添加图片", symbol: "plus") { feedback.stringValue = "柔和次按钮：已模拟添加" }
        let reset = SoftButton("重置", role: .quiet) { feedback.stringValue = "柔和轻量按钮：已重置反馈" }
        let remove = SoftButton("移除", role: .destructive) { feedback.stringValue = "柔和危险按钮：已模拟移除" }
        let icon = SoftButton("", role: .quiet, symbol: "sidebar.left", label: "柔和按钮：收起列表") { feedback.stringValue = "柔和图标按钮：已模拟收起" }
        let disabled = SoftButton("不可用", symbol: "plus"); disabled.isEnabled = false
        let busy = SoftButton("导出全部", role: .primary, symbol: "square.and.arrow.up"); busy.isBusy = true
        let demo = SoftButton("模拟处理", symbol: "sparkles")
        demo.onPress = { [weak demo, weak feedback] in
            guard let demo else { return }; demo.isBusy = true; feedback?.stringValue = "处理时保留宽度，并阻止重复触发。"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak demo, weak feedback] in
                demo?.isBusy = false; feedback?.stringValue = "模拟处理完成；按钮恢复可用。"
            }
        }
        let focus = SoftButton("键盘焦点", role: .quiet, symbol: "keyboard") { [weak primary] in
            guard let primary else { return }; primary.window?.makeFirstResponder(primary); primary.needsDisplay = true
        }
        let soft = [primary, add, reset, remove, icon, disabled, busy, demo, focus]
        soft.forEach { $0.preferences = state.preferences }
        let native: [NSView] = [ActionButton("导出全部", role: .primary), ActionButton("添加图片"), ActionButton("重置", role: .quiet), ActionButton("移除", role: .destructive), IconButton("sidebar.left", label: "原生按钮：收起列表")]
        for case let button as ActionButton in native { button.onPress = { feedback.stringValue = "原生对照：已触发模拟操作" } }
        func row(_ label: String, _ controls: [NSView]) -> NSView {
            let caption = FraloStyle.text(label, role: .detail, secondary: true)
            caption.widthAnchor.constraint(equalToConstant: 76).isActive = true
            return FraloStyle.stack([caption] + controls, axis: .horizontal, spacing: 12)
        }
        let contextButton = SoftButton("导出全部 · 3 张", role: .primary, symbol: "square.and.arrow.up") { feedback.stringValue = "面板中的候选主按钮：仅模拟操作" }
        contextButton.preferences = state.preferences
        let context = MaterialSurface(.panel, radius: 16)
        let content = FraloStyle.stack([FraloStyle.text("悬浮面板中的按钮", role: .heading),
            FraloStyle.paragraph("柔和表面搭配系统材质；主操作保留清晰边界。"), contextButton], spacing: 14)
        content.translatesAutoresizingMaskIntoConstraints = false; context.addSubview(content)
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: context.leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: context.trailingAnchor, constant: -18), content.topAnchor.constraint(equalTo: context.topAnchor, constant: 18),
            content.bottomAnchor.constraint(equalTo: context.bottomAnchor, constant: -18)])
        context.preferences = state.preferences
        return FormSection("按钮外观对照 · 柔和定制候选", detail: "真实原生按钮交互，自定义柔和外观。尚未设为稳定默认；用顶部外观和辅助选项比较明暗、对比度及减少动态效果。", views: [
            row("现有原生", native), row("柔和定制", [primary, add, reset, remove, icon]),
            row("状态体验", [disabled, busy, demo, focus]), feedback, LabPages.sample(context, width: 520)
        ])
    }
}
#endif
