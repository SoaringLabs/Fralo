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

安装 App 后，在终端运行：
"/Applications/Fralo.app/Contents/MacOS/fralo" --help

也可以将 App 包内的 fralo 单独复制到自己的 PATH，项目不会自动改动 PATH。
设置文件位于 ~/Library/Application Support/Fralo/。

## 卸载

退出 Fralo，再将 Applications 中的 Fralo.app 移到废纸篓。
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
