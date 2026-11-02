# FRALO-25 自动更新流程调查

2026-11-03，针对现有 Sparkle 更新流程完成首轮调查。检查、取消、失败重试、签名拒绝、文件对话框等待、成功导出期间的安装保护及隔离重启均未复现代码缺陷。另观察到测试 App 主界面与更新窗口语言不一致，尚需区分隔离环境与正式行为。按任务要求，先记录结果与验证边界，再决定后续范围；本轮不改变自动下载或安装策略。

## 验证环境

- 源码：`f564030ac0d205f4d853de663ad34098ee954522`，分支 `codex/fralo-25`；macOS 27.0.1，Apple Silicon，Sparkle 2.10.0。
- 正式安装版：`/Applications/Fralo.app`，0.2.0 / build 3，原有进程 PID 14318 保留。
- 隔离 App：独立标识 `app.fralo.fr25validation`、独立设置文件、本机 HTTP 更新源和临时文件签名密钥；未访问正式签名私钥，未修改系统安全设置。
- 起始测试包为本次源码的 Debug 二进制，Bundle 版本 0.2.0 / build 3。目标测试包复用同一二进制，仅将 Bundle 版本设为 0.2.1 / build 4；因此重启验证证明替换、重启和 Bundle 版本回读，不能证明下一真实版本的业务代码或设置页版本文字。
- 目标包启动器固定隔离设置路径，避免 Sparkle 重启未继承环境变量时读取正式配置。测试包、素材、截图、服务日志和不含密钥的环境清单位于 `/tmp/fralo25-validation/`；临时路径不是长期 CI 产物。
- 验证结束后，测试 App、更新助手和本机 HTTP 服务均已退出，临时签名种子已删除；正式 App 的可执行文件及 Info.plist 摘要保持一致。1000 张输出均存在且具有正确 PNG 文件头；此检查不等同于逐张视觉验收。

## 复现与缺口表

| 场景与复现条件 | 预期 | 实际与证据 | 修复判断 |
| --- | --- | --- | --- |
| 菜单手动检查；本机 feed 不含新版本 | 明确提示已是最新版本 | 原生窗口显示当前 0.2.0 为最新；`01-no-update.png` | 未复现缺陷 |
| feed 返回 HTTP 503，再恢复正常 feed，重新检查 | 提示检查失败，恢复后可重试 | 显示获取更新信息错误；重试找到 0.2.1；`02-feed-error.png`、`03-retry-found-update.png` | 未复现缺陷 |
| 限速下载中取消，再次检查 | 取消下载，可重新检查和下载 | 取消后可再次找到更新；`04-downloading.png` 及 HTTP 请求记录 | 未复现缺陷 |
| 更新包下载返回 HTTP 503，再恢复下载 | 下载错误与检查错误可区分，允许重试 | 显示下载错误；恢复后重新下载成功；`05-download-error.png` | 未复现缺陷 |
| 修改更新 ZIP 字节，保留原签名 | 拒绝安装，不替换旧 App | 提示更新未正确签名；`06-signature-error.png` | 未复现缺陷 |
| 下载就绪后打开导出目录对话框，再切至 Sparkle 点击安装 | 关闭文件对话框前不重启 | 对话框保持打开，PID 23261、Bundle build 3 均保持；`09-pending-dialog-install.png` | 未复现缺陷 |
| 取消上述文件对话框 | 解除等待，只执行一次安装和重启 | 自动重启至 PID 24182，实际路径为隔离 App 的 `FraloAppProbe`，Bundle 回读 0.2.1 / build 4；`10-after-relaunch.png` | 未复现缺陷；目标是合成测试版本 |
| 导出 1000 张图片期间安装 | 不取消导出，导出结束后再安装 | 安装后截图显示 191/1000 及导出结束后安装的提示；旧 PID 25004、build 3 保持。最终输出 1000/1000 后自动重启为 PID 26154、build 4；`12-export-update-pending.png` | 未复现缺陷 |
| 设置窗口的更新偏好 | 由设置统一管理，不在工作台重复编辑，重启后保持偏好 | FRALO-22 已合并；现有 8 项设置测试通过，浅色与深色原生窗口实测；关闭自动检查后升级重启，仍为关闭；`07-settings-light.png`、`08-settings-dark.png` | 未复现偏好归属或持久化问题 |
| 隔离测试 App 跟随系统语言 | 核对主界面与更新窗口的语言选择是否一致 | 主界面和设置为英文，语言选择显示 System，Sparkle 更新窗口与错误提示为中文；`03-retry-found-update.png`、`07-settings-light.png` | 待确认；未测试主动选择英文/日文和正式包，不能据此认定正式版缺陷 |
| 公开 Latest、feed、已安装 App 和源码身份 | 版本、构建号、下载地址和资产长度一致 | Latest v0.2.0、feed 0.2.0 / 3，DMG 长度 10,966,193 字节与资产一致，公钥一致；公开 SHA256SUMS 与 GitHub 资产摘要一致 | 未发现元数据缺口；本轮未下载正式 DMG 验签 |

## 自动检查

以下检查在上述源码版本执行通过：

- `swift test --filter UpdateControllerTests`：4 项，覆盖延后安装、只恢复一次、空闲直交 Sparkle、更新中止后的回调清理和 Objective-C delegate 入口。
- `swift test --filter SettingsWindowTests`：8 项，覆盖设置归属、更新偏好、不可用说明等；运行有 AppKit 布局警告，不能据此认定视觉布局全部通过。
- `python3 -B scripts/test_prepare_update.py`：2 项，拒绝发布身份、版本递增、地址、长度和签名字段错误。
- `python3 -B scripts/check_localizations.py`：四语言共 274 个键通过。

## 用户体验依据与边界

依据 [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos) 的标准菜单、键盘和可调整窗口原则，以及 [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) 的可感知状态与熟悉交互原则，沿用原生 AppKit 和 Sparkle 界面。本轮没有新增界面、动效或文案。

已实际检查设置页浅色与深色、检查和下载错误状态、签名错误、文件对话框及导出等待状态，检查入口通过标准菜单执行。最小窗口、日文长文案、完整键盘焦点顺序、VoiceOver 朗读、减少动态效果、降低透明度、增强对比度和旧 macOS 尚未完成本轮验证；英文导出等待提示在实际进度面板可读，但不代表全部英文长文案已通过。未将截图或单元测试视为完整 HIG 或辅助功能认证。

150 张首轮导出也全部完成并重启，但安装点击与导出结束相隔太近，不能据此证明延后安装；因此另用 1000 张批次补齐明确时序证据。用户取消导出、导出失败及跳过结果弹窗期间的实际安装等待，本轮未重测；现有 gate 单元测试不能替代这些端到端场景。

公开更新源只做元数据核对；本机签名升级不替代真实旧版本经 GitHub 下载 Developer ID 签名、公证发行包的生产升级验收。FRALO-1/2 历史记录包含此类测试，但其临时证据目录已不存在，不作为本轮重测通过。

## 后续范围

本轮没有形成已确认的生产代码修复范围。任务保持 In Progress，先提交本表供判断，不将任务标为 Done。下一步可先复核语言不一致是否出现在正式打包及用户主动切换语言后，再按实际结果确定修复；另可考虑把隔离 feed 和升级场景固化为可重复运行的回归工具，并补齐上述实际升级与辅助功能覆盖。本轮临时 harness 不等同于已交付的仓库测试设施。

参考：[现有更新方案](updates.md)、[Sparkle 2.10.0 delegate 接口](https://github.com/sparkle-project/Sparkle/blob/2.10.0/Sparkle/SPUUpdaterDelegate.h)、[Sparkle 程序化接入](https://sparkle-project.org/documentation/programmatic-setup/)、[v0.2.0 发行记录](https://github.com/SoaringLabs/Fralo/releases/tag/v0.2.0)。
