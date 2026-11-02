# 应用内更新与分发

Fralo 使用固定版本的 Sparkle 2.10.0，复用其原生更新界面、下载进度、
取消、错误提示、版本和系统兼容性比较、Ed25519 校验、替换及重启流程。

## 用户流程

- 菜单“Fralo → 检查更新…”手动检查；检查或安装进行中不会再启动一轮。
- 默认每天自动检查，可在“Fralo → 设置… → 更新”中关闭；偏好由 Sparkle 持久保存。
  设置窗口同时显示当前版本和上次检查时间，并提供“立即检查…”。
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
   按下方四语流程完成当前版本的更新说明。发布前先运行
   `python3 -B scripts/release_notes.py check-all`；缺失、过期或未校对的说明会阻止继续。
2. 按 [签名与公证说明](signing.md)完成最终 DMG；附加公证凭证后重新生成 SHA256。
3. 运行完整包校验，再生成更新源。以下以 0.3.0 为示例，替换成实际版本；
   `--previous-build` 为上个公开版本的 build：

       .venv/bin/python scripts/verify_package.py --require-notarized
       python3 scripts/prepare_update.py \
         --archive dist/Fralo-0.3.0-arm64.dmg --previous-build 3

   脚本先检查 `release/v当前版本.json`、四份生成的 Markdown、四语 GitHub 正文
   及校对摘要，随后才读取签名凭据并只读挂载最终 DMG，核对其版本、项目、公钥和更新地址与当前源码一致，
   拒绝未递增的 build、未公证的 DMG 和非 Developer ID 应用。
   使用 Sparkle 官方工具生成最低系统/CPU 要求及包签名，嵌入四种语言的更新说明，
   校验版本、下载地址、文件长度和四语正文，然后用官方 `sign_update` 签名并验证最终
   appcast。输出 `dist/appcast.xml`，不会上传任何文件。旧的单文件 `--notes` 参数已移除。
4. 获得发布授权后，将这个**最终 DMG**、`SHA256SUMS.txt` 和 `appcast.xml`
   以及 `release/v当前版本.{en,zh-Hans,zh-Hant,ja}.md` 一起上传到同一 GitHub Release，
   正文使用生成的 `release/v当前版本.md`（例如 `gh release create` 的 `--notes-file`），
   再将 Release 发布为 Latest。每个版本只创建一个 Release 和一个安装包。
   Feed 固定为 `https://github.com/SoaringLabs/Fralo/releases/latest/download/appcast.xml`，
   包地址固定到具体版本标签。不要让 Latest 指向没有 appcast 的版本。
5. 从真实旧版本验证下载、安装和重启，再确认应用版本；不能只凭 HTTP 200 验收。

DMG、公钥或安装包内容变化后，必须重新签名/公证/生成更新源。
不能先签名更新描述，再对 DMG 附公证凭证或重建。

## 四语更新说明

后续版本必须使用同一份变更清单生成 English、简体中文、繁体中文、日语说明。
`release/v版本.json` 是源文件；`v版本.en.md`、`v版本.zh-Hans.md`、
`v版本.zh-Hant.md`、`v版本.ja.md` 和四语 GitHub 正文 `v版本.md` 均由脚本生成。
CI 在仓库必需的 `core-and-cli` 检查内校验当前 App 版本以及所有新增版本；
已发布的 0.1.0、0.1.1、0.2.0 单语历史保留，
不把后续版本自动列入例外。即使当前 App 尚未升版，新增单语发布文件也会被拒绝。

1. 从已合并变更及实际验收结果确认本版清单，再创建源文件。以下命令中的 0.3.0 为示例：

       python3 -B scripts/release_notes.py new 0.3.0

2. 填写 `release/v0.3.0.json`。`summary` 和每条 `changes[].text` 都必须提供
   `en`、`zh-Hans`、`zh-Hant`、`ja` 四个非空值。每条改动只定义一次稳定的 `id` 和
   `type`；四语由同一批条目生成，避免漏项。`type` 为 `added`、`changed`、`fixed`、
   `breaking` 或 `notes`。仅写用户可见且已有证据的变化，额外说明安装要求或不兼容变更。
   翻译可以辅助生成，四种语言需核对同义、范围、版本号和注意事项；不在用户打开更新窗口时翻译。

3. 生成四语文件和 GitHub 正文，逐份校对。直接修改生成文件会使校验失败，应修改 JSON 再生成：

       python3 -B scripts/release_notes.py render 0.3.0

4. 校对完成后记录内容摘要，再校验：

       python3 -B scripts/release_notes.py mark-reviewed 0.3.0
       python3 -B scripts/release_notes.py check 0.3.0
       python3 -B scripts/release_notes.py check-all

   `mark-reviewed` 是维护者完成校对后的记录操作，不会自动证明译文正确。
   摘要同时绑定源清单、四语 Markdown 和 GitHub 正文。后续更改清单、摘要、任何一种语言，
   或生成模板导致实际输出变化，都会使原校对摘要失效；重新生成、校对并记录后才能发版。
   缺少语言、空文本、TODO 等占位符、缺失或手改的生成文件、未校对或过期摘要都会阻止生成更新源。
   将源 JSON 与五份生成文件一起纳入版本提交。

更新源在同一个版本条目内嵌入四个带 `xml:lang` 的 Markdown `description`，
英文放在第一位作为无匹配语言时的默认内容；不需要额外的说明文件下载请求。
显式应用语言、跟随系统、繁简区分和运行中切换语言的实际选择仍需在正式打包环境验收。
四语内容生成与 Sparkle 窗口按钮语言是两个检查点；本流程不宣称已解决运行时语言同步。

## 验证

    python3 -B scripts/release_notes.py check-all
    python3 -B scripts/test_release_notes.py
    python3 -B scripts/test_prepare_update.py
    swift test
    swift build -c release
    python3 scripts/check_public_source.py

单元测试覆盖导出结束前延后安装、回调仅执行一次、更新中止不再安装，
以及发布包身份、版本递增、更新文件地址/长度/签名字段、四语说明完整性和校对失效的拒绝逻辑。
标准更新窗口与实际安装需另做隔离本地端到端测试。临时测试 App 必须使用独立
bundle identifier、偏好和配置文件，不替换已安装的正式 App，也不改变系统安全设置。

参考：[Sparkle 程序化接入](https://sparkle-project.org/documentation/programmatic-setup/)、
[发布更新](https://sparkle-project.org/documentation/publishing/)。
