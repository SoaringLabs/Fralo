# 首版候选验证与验收

Fralo 0.1.0 的构建与验收记录。
正式安装包、校验文件与发布说明见 [v0.1.0](https://github.com/SoaringLabs/Fralo/releases/tag/v0.1.0)。

## 2026-10-16 本轮整理结果

- 从首次提交候选导出干净源码，不带设计历史、个人截图或既有构建缓存。
  12 项 Core 测试、10 组 CLI 检查、Release 构建、图标编译、DMG 打包及包核对通过。
- 公开示例三张 GUI / CLI 输出逐文件字节一致；当前剪贴板 PNG 与对应输出字节一致。
- 实际关于窗口显示 0.1.0 (1)、Soaring Labs、Ethan 与 MIT 许可。
- 从最终 DMG 复制出 App，弹出安装卷后独立启动并载入三张公开示例。
  标准用户设置文件与测试前字节一致。
- 带 quarantine 属性的本机副本经系统评估被拒绝，符合尚未公证的状态。
  没有改变系统安全设置；这项模拟不替代真实浏览器下载后的首次启动。

以上为本机验证，维护者体验验收和首次远程 CI 结果仍待确认。

## DMG 安装界面整理

安装卷根目录只保留 Fralo.app 与 Applications 快捷入口。CLI 保留在 App 的
Contents/MacOS，说明、开发者信息与许可证保留在 Contents/Resources。
窗口预设为 660 × 460，左右放置图标；背景画面为 660 × 400，保留 Finder 顶部与底部控件空间。
背景选用 Resources/DMG/background.png，由内置 ImageGen 生成，说明批量截图套框、
本地处理和透明 PNG 导出。Swift / AppKit 将源图转换为 2x TIFF，
打包工具写入图标位置并与画面中的箭头对齐，无需手动摆放。
已在实际 Finder 窗口核对，重新验证包内内容、内置 CLI、严格签名及 SHA-256。
构建时使用的 Python 依赖只存在于开发环境，不随 App 分发。

## 2026-10-17 正式签名与公证

- Developer ID Application 证书已签发并导入本机钥匙串。
- App 与内置 CLI 启用 Hardened Runtime 和安全时间戳，DMG 也使用 Developer ID 签名。
- 新增正式签名入口与 `--require-notarized` 包验证模式。
- Apple 公证返回 Accepted / Ready for distribution，日志没有报告问题。
- 公证凭证已附到最终 DMG，`stapler validate` 验证通过。
- `--require-notarized` 包验证通过，App 与 DMG 均获 Gatekeeper 接受；
  最终校验文件已在附加公证凭证后重新生成。
- 12 项 Core 测试与 10 组 CLI 检查通过；密钥与认证凭据不进入源码。

## 自动化检查

从干净源码目录可运行：

    swift test
    swift build -c release
    python3 scripts/verify_cli.py "$(swift build -c release --show-bin-path)/fralo"
    python3 scripts/check_public_source.py

Core 的 12 项测试覆盖机型与方向、透明边界、边距、分辨率、比例限制、
EXIF 方向、预览规则、配置、命名与去重、覆盖保护、失败继续和取消。

CLI 的 10 组检查使用自动生成的 10 张 PNG，覆盖版本与开发者信息、
机型列表、继承配置、本次覆盖不回写、同名跳过、显式覆盖、
部分失败、参数错误、信号取消、原图与配置不变。
所有输入、设置与输出位于独立临时目录，不读取个人截图或标准配置路径。

公开源码检查验证本机设计历史与产物未进入提交候选、
没有个人绝对路径或明显密钥、没有超大文件，以及 Markdown 本地链接完整。
它不是对 Git 历史或图片内容的完整安全审计。

GitHub Actions 配置已提供；远程结果须在发布后读取确认。
本机执行通过不能替代远程 CI 结果。

## 可公开复现的示例

examples 中的三张图片由 scripts/generate-demo.swift 绘制。
它们是虚构的 Field Notes 界面，不包含个人或真实 App 数据。
README 的界面截图、套框示例和演示使用这些图片。

## GUI 手动验收

1. 打开候选 App，导入 examples 文件夹，确认三张缩略图与对应预览。
2. 切换图片、改变机型和边距；检查放大与适应窗口。
3. 复制当前图片，确认粘贴得到的是带外框的透明成品。
4. 导出全部，再次导出确认默认跳过同名文件；按需显式覆盖。
5. 使用一组更多的图片检查取消后文件保留、结果汇总与打开输出目录。
6. 混入损坏 PNG，检查失败原因、复制禁用和其他图片继续导出。
7. 重启 App，检查设置复用。通过 CLI 指定参数后，检查 App 设置没有被改写。
8. 打开“关于 Fralo”，核对版本、Soaring Labs 与维护者入口。

此前本机已完成 GUI 批处理、取消、损坏输入、剪贴板和 GUI / CLI
逐文件一致性验证。本轮还需以最终候选安装包完成维护者体验验收。

## 安装包与兼容边界

打包后运行：

    .venv/bin/python scripts/verify_package.py
    cd dist
    shasum -a 256 -c SHA256SUMS.txt

打包依赖的隔离安装方式见根目录 README。包检查会只读挂载 DMG，
确认根目录只有 Fralo 和 Applications 两个可见项目、保存的 Finder 布局与背景，
对比整个 App、内置 CLI、App 包内说明和许可证，
核对版本与版权、校验签名、执行卷内 CLI，最后弹出安装卷。
最终 App 图标包含 Assets.car 与 Fralo.icns。

当前运行环境：Apple Silicon、macOS 27.0.1、Xcode 27.0。
编译目标为 macOS 14；旧系统与 Intel 未运行验收。
默认源码构建为 ad-hoc；正式签名和公证的当前进度见上方记录。
本机复制安装包的启动验证不等同于浏览器下载后带 quarantine 的首次启动验收。
真实下载场景需在发布或受控下载测试后补充，见根目录 INSTALL.md。

## 本机记录

首轮日志和验证报告保留在被 Git 忽略的 artifacts/pre-release 中；
正式签名、公证日志及最终包报告保留在 artifacts/signing 中。
原有个人截图与早期验收资料留在本机，不作为开源示例发布。
