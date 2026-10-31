# Fralo project rules

## 调试进程交接

- 每次完成需求改动并启动新版调试程序时，先构建成功，再结束同一 Git 仓库全部 worktree 中同一种预览的所有旧进程，确认退出后启动新版；无响应时升级为强制终止。验收时同类预览只保留当前新版。
- Workbench Preview 和 Design Lab 分别最多保留一个新版实例；通过各自的 `scripts/run-*.sh` 启动，它们自动按完整可执行路径清理旧进程。`--build-only` 只构建，不清理进程。
- 使用其他启动方式或临时调试程序时，也执行上述交接，逐个核对完整可执行路径、所属仓库和 PID；清理范围覆盖本仓库全部 worktree，保留正式安装版及其他仓库的进程。交付前核对旧进程已退出、同类预览仅一个、新进程版本和窗口正常。

## Apple HIG

- 所有后续改动都检查其用户体验影响；涉及界面、交互、状态反馈或辅助功能时，尽量以 [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/) 为默认依据。
- 实现前按改动范围阅读相关 Apple 官方章节，并结合既有设计系统及用户已确认的决定；用户明确要求优先，偏离 HIG 时简述理由。
- 优先使用原生 AppKit 控件、系统语义颜色与材质、标准菜单/快捷键、焦点行为和撤销机制；让侧栏、工作区和检查器有可辨认的层级。
- 验证改动所影响的浅色/深色、常用/最小窗口、键盘与焦点、空/加载/错误/禁用状态；适用时检查减少动态效果、降低透明度及增强对比度。
- 涉及拖动、缩放或坐标变换时，验证实际绘制结果的四方向及对角移动，并核对拖动中、松手后和导出结果的一致性；仅检查数值或水平移动不足以证明正确。
- 交付时记录采用的 HIG 依据、实际验证结果及未验证项；截图和自动测试不等同于完整 VoiceOver 或 HIG 合规认证。

## Review references

- [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)
- [Layout](https://developer.apple.com/design/human-interface-guidelines/layout), [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars), [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
