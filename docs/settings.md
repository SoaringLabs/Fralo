# Settings window

Fralo → 设置…（⌘,）打开应用级设置窗口；侧栏“更多”菜单中的“设置…”打开同一个窗口。
重复打开会复用已有窗口，并回到上次查看的分类和窗口位置。

## 偏好归属

| 偏好 | 编辑位置 | 保存 | 生效 |
| --- | --- | --- | --- |
| 界面外观（跟随系统 / 浅色 / 深色） | 设置 → 外观 | `UserDefaults` 的 `workbenchAppearance` | 立即应用到 Fralo 的所有窗口，重启后保持 |
| 界面语言（跟随系统 / English / 简体中文 / 繁體中文 / 日本語） | 设置 → 外观 → 语言 | App 域的 `AppleLanguages`，与“系统设置 → 通用 → 语言与地区 → App”为 Fralo 写入的是同一个值 | 立即切换 Fralo 自有界面，重启后保持 |
| 每天自动检查更新 | 设置 → 更新 | Sparkle 自己的偏好（`SUEnableAutomaticChecks`） | 立即生效，重启后保持；默认开启 |

设置窗口只管理应用偏好。设备、背景、导出等出图参数只在工作台右侧的出图设置中编辑，
不会出现在设置窗口；精简/高级模式（FRALO-26）同样只改变出图设置的呈现方式。
同一偏好只有一个编辑入口：原“显示 → 外观”子菜单和“自动检查更新（每天）”菜单项已移除。
“检查更新…”是一次性操作，不是偏好，仍保留在 Fralo 菜单中，设置窗口的“立即检查…”与之等价。

窗口的大小、位置和最后查看的分类属于界面状态，分别保存在 `NSWindow Frame FraloSettingsWindow`
和 `settingsPane` 中，不属于上表的偏好。

## 搜索

侧栏顶部的搜索框（⌘F）按分类名、分组名、设置项名称和选项名（如“深色”“日本語”）检索，
同时匹配当前界面语言和英文名称，不区分大小写和全角/半角。输入时侧栏只列出匹配的分类，
右侧高亮匹配的设置行；只匹配分类名时不高亮具体行。没有匹配时侧栏显示“无结果”。
Return 或 ↓ 进入结果列表，Esc 清空搜索；从结果外选择分类会清空搜索。
结果数量变化通过 VoiceOver 播报，高亮行带“与搜索匹配”的辅助功能描述。切换界面语言后搜索词保留并按新语言重新匹配。

## 状态

- 选择界面语言后立即切换：工作台窗口用新语言重建并接管当前批次、选中项和设置窗口，菜单栏随之重建，
  设置窗口保持在原分类。撤销记录不跨语言切换保留。正在导出或主窗口有对话框时不切换，
  设置窗口说明原因并恢复原来的选项。
- 即时切换只覆盖 Fralo 自己的界面。系统提供的文字（如“服务”菜单、文本右键菜单、打开/存储面板）
  和 Sparkle 更新窗口在进程启动时确定语言，下次启动 Fralo 后才跟随新语言。
- 语言名称始终用各自语言显示（由系统 `Locale` 提供），便于在任何界面语言下找到自己的语言。

- 直接运行构建目录中的可执行文件，或更新服务启动失败时，“更新”分类第一行说明原因，
  自动检查开关和“立即检查…”禁用，上次检查显示“从未检查”。
- 上次检查时间来自 Sparkle，按当前界面语言显示相对日期；窗口重新成为主窗口时刷新。

## 设计依据

结构参照 macOS 系统设置：原生源列表侧栏、圆角分组行、行内说明文字，控件使用 `NSSwitch`
和标准按钮，颜色来自系统语义色或随外观变化的低对比度填充。参考 Apple HIG
[Settings](https://developer.apple.com/design/human-interface-guidelines/settings)、
[Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)、
[Layout](https://developer.apple.com/design/human-interface-guidelines/layout) 与
[Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)。
增强对比度时分组恢复描边、分隔线加深。外观缩略图作为单选组提供给辅助功能，获得焦点后可用方向键切换。
切换分类不使用动画。

## 预览

Debug Workbench Preview 可直接打开设置窗口用于检查，不修改用户的外观选择：

```sh
scripts/run-workbench-preview.sh --preview-settings=updates --preview-updates=available --preview-appearance=dark --preview-language=ja
```

`--preview-settings` 取 `appearance` 或 `updates`。加 `--preview-settings-minimum` 以最小窗口（640×400）打开。加 `--preview-settings-search=深色` 在搜索框输入内容；加 `--preview-switch-language=en` 在启动后通过设置中的语言菜单切换语言，用于检查即时切换（会写入预览程序自己的语言偏好）。不加 `--preview-updates=available` 时显示更新不可用状态；
加上后使用不联网的模拟更新服务。
