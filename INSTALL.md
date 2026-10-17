# 安装 Fralo 0.1.0

首版提供 Apple Silicon（arm64）安装包。开发与实际运行验证环境为 macOS 27.0.1、Xcode 27.0。
编译目标为 macOS 14；旧版 macOS 和 Intel 尚未完成运行验收。

## 从 DMG 安装

1. 从项目发布页获取 Fralo-0.1.0-arm64.dmg 和 SHA256SUMS.txt；发布前使用维护者提供的本地候选包。
2. 将两个文件放在同一目录，在终端进入该目录，运行：
   shasum -a 256 -c SHA256SUMS.txt
3. 打开 DMG，将 Fralo.app 拖入 Applications。
4. 从 Applications 打开 Fralo，然后弹出安装卷。

安装窗口只显示 Fralo 和 Applications 两个图标，中间箭头指示拖拽方向。
CLI 位于 App 的 Contents/MacOS，许可证、开发者信息和本说明位于 Contents/Resources。

维护者的正式发行 DMG 使用 Developer ID 签名，并在完成 Apple 公证后发布。
首次打开时，macOS 仍可能显示来自互联网的下载确认提示。
如果提示无法验证开发者或检查恶意软件，请先核对来源、版本和校验值，
并向维护者反馈；不要关闭系统安全保护。

自行从源码构建默认采用 ad-hoc 签名，不带 Apple 公证；这与正式发行包的信任状态不同。

Apple 说明：https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac

## 第一次使用

拖入 PNG / JPEG → 选择对应机型和横竖屏 → 检查预览 → 导出全部。
所有处理在本机完成。输出是包含设备外框的透明 PNG，默认透明边距为 0。
截图方向须与设置一致；差异过大的截图比例会报告失败。
没有自带个人截图，也无需登录或上传图片。

## CLI

安装 App 后，在终端运行：
"/Applications/Fralo.app/Contents/MacOS/fralo" --help

也可以将 App 包内的 fralo 单独复制到自己的 PATH，项目不会自动改动 PATH。
设置文件位于 ~/Library/Application Support/Fralo/settings.json。
卸载时退出 App，再移除 Applications 中的 Fralo.app；是否保留设置由你决定。

## 源码构建

需要完整 Xcode 27 工具链（图标编译依赖 actool）与 Python 3.10 或更新版本。
在源码根目录运行：

    swift test
    python3 -m venv .venv
    .venv/bin/python -m pip install -r scripts/requirements-dmg.txt
    .venv/bin/python scripts/package.py --configuration release --dmg

构建后的 App、CLI、DMG 和 SHA256SUMS.txt 位于 dist。
DMG 布局依赖仅用于构建，不会打入 App，也不需要使用者安装 Python。
仅构建渲染核心和 CLI 可使用 SwiftPM：swift build -c release。
完整使用说明见源码中的 README.md。
维护者制作正式发行包的流程见源码中的 docs/signing.md。
