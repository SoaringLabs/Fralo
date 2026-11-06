# 安装 Fralo

Fralo 提供 Apple 芯片（arm64）安装包，支持 macOS 14 或更新版本。
实际运行验证环境为 Apple 芯片 / macOS 27；更早的 macOS 仅为编译目标，尚未完成运行验收。
暂不提供 Intel 版本。

## 从 DMG 安装

1. 从 [GitHub Releases](https://github.com/SoaringLabs/Fralo/releases/latest) 下载
   Fralo-<版本>-arm64.dmg 和 SHA256SUMS.txt。
2. 将两个文件放在同一目录，在终端进入该目录，运行：
   shasum -a 256 -c SHA256SUMS.txt
3. 打开 DMG，将 Fralo.app 拖入 Applications。
4. 从 Applications 打开 Fralo，然后弹出安装卷。

安装窗口只显示 Fralo 和 Applications 两个图标，中间箭头指示拖拽方向。
CLI 位于 App 的 Contents/MacOS，许可证、开发者信息和本说明位于 Contents/Resources。

正式发行的 DMG 使用 Developer ID 签名，并在完成 Apple 公证后发布。
首次打开时，macOS 仍可能显示来自互联网的下载确认提示。
如果提示无法验证开发者或检查恶意软件，请先核对来源、版本和校验值，
并向维护者反馈；不要关闭系统安全保护。

自行从源码构建默认采用 ad-hoc 签名，不带 Apple 公证；这与正式发行包的信任状态不同。

Apple 说明：https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac

## 从终端安装 / Install from terminal

在 Apple 芯片 Mac 的终端粘贴下面这一行。脚本完整下载后才会运行。
Paste this line into Terminal on an Apple silicon Mac. The script runs after the download succeeds.

```sh
curl -fsSL https://fralo.app/install.sh | sh
```

安装成功后，当前终端可直接使用 / After a successful installation, run directly:

```sh
fralo --version
fralo --help
```

首次安装默认下载最新稳定版。脚本校验 SHA-256、发布者签名和 Gatekeeper，再把正式 DMG 中的
App 复制到 `~/Applications/Fralo.app`。它还会在 `/usr/local/bin/fralo` 安装命令入口；写入该目录
可能要求管理员密码，只有命令入口操作会提权。`/usr/local/bin` 必须已在 PATH 中，否则脚本会
在安装前报错并说明处理方式，不会声称命令已就绪。脚本不会修改 shell 配置或自动打开 App。

已有 `~/Applications/Fralo.app` 时，会先验证它，再为该版本补装命令，不替换或升级 App；
更新仍使用应用内更新器。需要固定版本时，使用 `sh -s -- --version 0.3.1`，现有 App
版本不匹配则拒绝安装。已有其他来源的同名命令也会报错，不覆盖。

The first installation downloads the latest stable release, verifies its checksum,
publisher signature and Gatekeeper assessment, and copies the app to
`~/Applications/Fralo.app`. It also installs `/usr/local/bin/fralo`; writing this
command may request an administrator password. Only the launcher operation elevates.
The directory must already be on PATH; otherwise installation stops with guidance.
The script never edits shell profiles or launches the GUI.

An existing official app at `~/Applications/Fralo.app` is verified and reused to
add the command. Re-running the script does not upgrade or replace it; use the
in-app updater. To pin a version, use `sh -s -- --version 0.3.1`. A different
installed version or an unrelated existing `fralo` command stops installation.

无需管理员权限的安装方式 / Install into a user-owned command directory:

```sh
mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"
curl -fsSL https://fralo.app/install.sh | sh -s -- --bin-dir "$HOME/.local/bin"
fralo --version
```

如需让新终端也能找到自定义目录，请自行将上面的 PATH 设置加入对应的 shell 配置。
For future terminals, add that PATH setting to your shell profile yourself.

命令入口调用 App 内的 CLI，保留配套资源；同路径更新 App 后，CLI 随之更新。
App 被移动或删除后，命令会提示重新安装。成功时标准输出仍只有包内 CLI 的绝对路径，
以便既有自动化继续使用；安装进度和命令就绪信息写入标准错误。
The launcher executes the bundled CLI with its matching resources. Updating the app
at the same path updates the CLI too. Moving or deleting the app produces a repair
message. Success stdout remains the single absolute bundled CLI path for existing
automation; progress and readiness messages go to stderr.

Agent 在 Bash 或 Zsh 自动化里可先启用 `set -o pipefail`，让入口下载失败时整条命令返回错误。
For automation in Bash or Zsh, enable `set -o pipefail` so the command reports an error
if the initial download fails.

已有 Fralo 的用户可以继续使用其内置 CLI 和更新器。终端安装和拖拽安装可以位于不同目录，
请使用你希望调用的那份 App 的 CLI 路径。
If you already have Fralo, you can keep using its bundled CLI and in-app updater.
Terminal and drag-and-drop installs can live in different folders; use the CLI
path for the copy you intend to run.

## 第一次使用

拖入 PNG / JPEG → 选择设备、机型和方向 → 选择透明或带背景 → 检查预览 → 导出全部。
透明成品为 PNG；带背景的成品可选 PNG 或 JPEG。截图方向须与所选方向一致。
所有处理在本机完成，无需登录，也不上传图片。

## 更新

0.1.1 及以后版本内置更新器。选择菜单“Fralo → 检查更新…”，阅读版本说明后
选择下载、安装并重启。0.1.0 没有更新器，需要手动安装一次新版 DMG。

默认每天自动检测，可关闭“自动检查更新（每天）”；不会自动下载安装。
更新不会中断正在进行的导出。请先导出需要保留的成品，当前批次不跨重启恢复。
更新失败时保留当前版本，可重新检查；也可从 GitHub Releases 手动安装。

## CLI

通过脚本安装后可直接运行 `fralo --help`，也可使用脚本输出的 CLI 路径。
仅通过 DMG 拖拽安装不会创建终端命令入口，请运行
`"/Applications/Fralo.app/Contents/MacOS/fralo" --help`。
CLI 会从 App 包读取配套资源；请保留完整 App，不要单独复制或软链接 CLI。
设置文件位于 ~/Library/Application Support/Fralo/。

## 卸载

如果通过脚本装过命令入口，先移除它 / Remove a script-installed launcher first:

```sh
curl -fsSL https://fralo.app/install.sh | sh -s -- --uninstall-cli
```

自定义目录需同时传入 `--bin-dir "$HOME/.local/bin"`。该操作只删除与本安装器生成内容一致的
入口，保留 App 和设置；默认目录可能需要管理员密码。
For a custom directory, also pass `--bin-dir "$HOME/.local/bin"`. This removes only
this installer's matching launcher, preserving the app and settings. The default
directory may require an administrator password.

退出 Fralo，再将 Applications（终端安装时为 `~/Applications`）中的 Fralo.app 移到废纸篓。
设置保存在 ~/Library/Application Support/Fralo/，是否保留由你决定。

## 源码构建

需要 Xcode 26.3 或更新版本与 Python 3.10 或更新版本；打包 App 图标需要 Xcode 27 的 actool。
在源码根目录运行：

    swift test --build-system native
    python3 -m venv .venv
    .venv/bin/python -m pip install -r scripts/requirements-dmg.txt
    .venv/bin/python scripts/package.py --configuration release --dmg

构建后的 App、CLI、DMG 和 SHA256SUMS.txt 位于 dist。
DMG 布局依赖仅用于构建，不会打入 App，也不需要使用者安装 Python。
完整使用说明见源码中的 README.md；维护者制作正式发行包的流程见 docs/signing.md。
