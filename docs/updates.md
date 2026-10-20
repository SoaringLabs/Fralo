# 应用内更新与分发

Fralo 使用固定版本的 Sparkle 2.10.0，复用其原生中文更新界面、下载进度、
取消、错误提示、版本和系统兼容性比较、Ed25519 校验、替换及重启流程。

## 用户流程

- 菜单“Fralo → 检查更新…”手动检查；检查或安装进行中不会再启动一轮。
- 默认每天自动检查，可通过同一菜单的勾选项关闭；偏好由 Sparkle 持久保存。
- 无更新时手动检查会明确提示；网络失败保留当前版本，可再次手动检查。
- 有更新时显示版本说明，用户选择跳过、稍后或下载安装。
- 下载完成后，用户点击安装并重启。正在导出时，导出面板显示等待提示，
  到导出结束（包括用户主动取消）再安装。更新本身不会取消导出。
  已打开的文件选择或结果弹窗也会延后重启，待用户关闭后继续。
  当更新已在等待全部成功的导出结束时，不再弹出一份会挡住重启的完成窗口。
  跳过、取消或失败的结果仍会显示，确认结果后再继续安装。
- 未导出的当前批次与普通退出一致，不跨重启恢复；请先导出需要保留的成品。
- 自动检测只提供提示，不静默下载或安装。检查只连接 GitHub，不上传截图，
  不启用 Sparkle 系统信息统计。CLI 不包含更新器。

首次带更新器的版本仍需手动下载安装；公开的 0.1.0 无法自行获得更新器。
0.1.1（build 2）是首个带更新器的正式版本，更新源随 GitHub Release 发布。
0.1.0 用户需先手动安装 0.1.1，后续版本可在应用内升级。更新源不可用时会显示
检查失败；这不能当成“已经是最新版”。隔离测试使用本地更新源，发布验收另用真实更新源。

## 打包

`swift build` 解析锁定的 Sparkle 依赖；`scripts/package.py` 将框架及更新助手
嵌入 App，保留符号链接，并从内到外签名。App 使用包内 Frameworks 的运行时路径。
Fralo 没有启用沙盒，因此移除 Sparkle 不需要的 XPC 服务。
App 的 `Contents/Resources/Sparkle-LICENSE` 保留 Sparkle 及其依赖的完整许可声明。

源代码直接运行的 `FraloApp` 不支持安装更新，会提示使用完整的 `Fralo.app`。
源码构建默认 ad-hoc 签名；正式更新必须是 Developer ID 签名且完成公证的 DMG。

## 签名密钥

公钥定义在 `Sources/FraloCore/FraloInfo.swift`，打包时写入 `SUPublicEDKey`。
对应私钥保存在 macOS 钥匙串，Sparkle account 为 `app.fralo.desktop`。
私钥不进入源码、日志或安装包。发布机可用以下命令核对公钥，不会导出私钥：

    .build/artifacts/sparkle/Sparkle/bin/generate_keys --account app.fralo.desktop -p

维护者应妥善备份钥匙串中的签名密钥；换机器或丢失密钥时，先按
[Sparkle 官方说明](https://sparkle-project.org/documentation/)处理密钥迁移，
不要直接替换公钥破坏已安装版本的信任链。

## 准备正式更新（不自动发布）

1. 在 `FraloInfo.swift` 同时更新 `version` 和递增的数字 `build`。
   首次含更新器的正式版本可使用 `0.1.1` / `2`；不复用公开 0.1.0 的 build 1。
2. 按 [签名与公证说明](signing.md)完成最终 DMG；附加公证凭证后重新生成 SHA256。
3. 运行完整包校验，再生成更新源。`--previous-build` 为上个公开版本的 build：

       .venv/bin/python scripts/verify_package.py --require-notarized
       python3 scripts/prepare_update.py \
         --archive dist/Fralo-0.1.1-arm64.dmg \
         --notes release/v0.1.1.md --previous-build 1

   脚本只读挂载最终 DMG，核对其版本、项目、公钥和更新地址与当前源码一致，
   拒绝未递增的 build、未公证的 DMG 和非 Developer ID 应用。
   使用 Sparkle 官方工具生成含版本说明、最低系统/CPU 要求及包签名的 appcast，
   再校验签名、下载地址和文件长度，输出 `dist/appcast.xml`。不会上传任何文件。
4. 获得发布授权后，将这个**最终 DMG**、`SHA256SUMS.txt` 和 `appcast.xml`
   一起上传到同一 GitHub Release，再将 Release 发布为 Latest。
   Feed 固定为 `https://github.com/SoaringLabs/Fralo/releases/latest/download/appcast.xml`，
   包地址固定到具体版本标签。不要让 Latest 指向没有 appcast 的版本。
5. 从真实旧版本验证下载、安装和重启，再确认应用版本；不能只凭 HTTP 200 验收。

DMG、公钥或安装包内容变化后，必须重新签名/公证/生成更新源。
不能先签名更新描述，再对 DMG 附公证凭证或重建。

## 验证

    swift test
    python3 scripts/test_prepare_update.py
    swift build -c release
    python3 scripts/check_public_source.py

单元测试覆盖导出结束前延后安装、回调仅执行一次、更新中止不再安装，
以及发布包身份、版本递增、更新文件地址/长度/签名字段的拒绝逻辑。
标准更新窗口与实际安装需另做隔离本地端到端测试。临时测试 App 必须使用独立
bundle identifier、偏好和配置文件，不替换已安装的正式 App，也不改变系统安全设置。

参考：[Sparkle 程序化接入](https://sparkle-project.org/documentation/programmatic-setup/)、
[发布更新](https://sparkle-project.org/documentation/publishing/)。
