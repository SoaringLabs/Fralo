<div align="center">

[English](README.md) · **简体中文**

<img src="docs/assets/icon.png" width="128" height="128" alt="Fralo 应用图标">

# Fralo

**在 Mac 上批量给截图套设备外框。一次导入，一次导出。**

[![最新版本](https://img.shields.io/github/v/release/SoaringLabs/Fralo?label=release&color=0a84ff)](https://github.com/SoaringLabs/Fralo/releases/latest)
[![CI](https://github.com/SoaringLabs/Fralo/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/SoaringLabs/Fralo/actions/workflows/ci.yml)
[![平台](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey?logo=apple)](#系统要求)
[![Swift](https://img.shields.io/badge/Swift-5.10-F05138?logo=swift&logoColor=white)](Package.swift)
[![许可：MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

[**下载**](https://github.com/SoaringLabs/Fralo/releases/latest) ·
[更新记录](CHANGELOG.md) ·
[安装说明](INSTALL.md) ·
[贡献指南](CONTRIBUTING.md)

</div>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/workbench-dark.png">
  <img src="docs/assets/workbench-light.png" width="1200" alt="简体中文 Fralo 工作台：三张自生成 Field Notes 示例截图、iPhone 18 Pro Max 外框与暖灰背景">
</picture>

Fralo 是原生 macOS App 和命令行工具，把截图放进手机、平板和浏览器外框。
拖入一批 PNG / JPEG 截图，统一选好设备和样式，检查预览后整批导出：
可以是透明 PNG，也可以是带背景的成品图。

所有处理都在本机完成：无需账号，不上传截图，没有统计。App 与 CLI 基于同一套
Core Graphics 渲染核心。

## 功能

- **为批量而生。** 拖入文件、导入文件夹或从剪贴板粘贴。相同文件自动去重，
  同一批次共享一套设置。
- **手机、平板与浏览器外框。** iPhone 18 Pro / Pro Max 支持横竖屏；另有平板，
  以及 Safari / Chrome 窗口，可选 16:10、16:9、4:3 比例和浅色 / 深色外观。
- **透明或带背景。** 导出带透明通道的设备图，或放在 1:1、4:3、16:9、3:4、9:16 画布上，
  背景可选纯色、渐变、预设纹理或自己的图片。
- **直接构图。** 调整设备大小、位置、阴影和不透明度。在预览中直接拖动设备或平移背景，
  按 ⌥ 加方向键以 1 px 微调。
- **保真输出。** 手机外框按屏幕像素 1:1 定尺寸，原生分辨率截图无需重新采样；
  圆角和灵动岛自动遮罩。
- **PNG 或 JPEG。** 无损 PNG、更小的 PNG 预设，或可调质量与底色的 JPEG。
- **安全导出。** 默认跳过已有文件，覆盖须显式选择；始终保护原图；导出可取消，
  单张失败不影响整批。
- **地道的 Mac App。** 原生侧边栏、工具栏、菜单与快捷键，支持撤销 / 重做、
  英文、简体中文、繁体中文和日语界面，浅色 / 深色外观，
  以及减少动态效果、降低透明度和增强对比度。
- **可脚本化。** 内置 `fralo` CLI，无需打开 App 即可批量渲染。
- **签名更新。** 通过 [Sparkle](https://sparkle-project.org) 应用内更新，更新包经 Ed25519 校验。
  每天检查一次 GitHub，从不静默安装，也可改为仅手动检查。

## 示例

| 暖灰预设 | 渐变 | 灰绿预设 | 透明 PNG |
| :---: | :---: | :---: | :---: |
| <img src="docs/assets/background-1.jpg" width="200" alt="暖灰纹理背景上的手机外框"> | <img src="docs/assets/background-2.jpg" width="200" alt="桃色到蓝色渐变背景上的手机外框"> | <img src="docs/assets/background-3.jpg" width="200" alt="灰绿纹理背景上的手机外框"> | <img src="docs/assets/framed.png" width="140" alt="CLI 导出的透明手机外框"> |

示例均使用 [`examples/`](examples) 中虚构的 *Field Notes* 界面，由
[`scripts/generate-demo.swift`](scripts/generate-demo.swift) 生成，不含个人资料。

## 安装

### 下载

1. 从[最新版本](https://github.com/SoaringLabs/Fralo/releases/latest)下载
   `Fralo-<版本>-arm64.dmg` 和 `SHA256SUMS.txt`。
2. 校验下载文件（可选，推荐）：

   ```bash
   shasum -a 256 -c SHA256SUMS.txt
   ```

3. 打开 DMG，将 **Fralo** 拖入 **Applications**。

正式发行的 DMG 使用 Developer ID 签名并通过 Apple 公证。首次启动、更新与卸载见
[INSTALL.md](INSTALL.md)。

### 更新

Fralo 0.1.1 及以后版本可在应用内升级：选择 **Fralo → 检查更新…**。
正在导出时会等导出结束再安装。0.1.0 没有更新器，请手动安装一次最新 DMG。

### 系统要求

| | |
| --- | --- |
| macOS | macOS 14 Sonoma 或更新（已在 macOS 27 运行验证；更早版本仅为编译目标） |
| 硬件 | Apple 芯片。暂不提供 Intel 版本。 |
| 界面语言 | English、简体中文、繁體中文、日本語 |

## 使用

在 **Fralo → 设置… → 外观 → 语言** 中选择界面语言，立即生效。默认跟随 macOS
首选语言；不支持的语言回退为英文。

1. **添加截图。** 把 PNG / JPEG 拖进窗口，或按 ⌘O 选择文件、⇧⌘O 导入文件夹（仅当前层）、
   ⌘V 粘贴。
2. **选择设备。** 选择手机、平板或浏览器，再选机型和方向。截图方向须与所选方向一致。
3. **选择样式。** 保持透明，或切换到带背景，设置画布、背景、大小、位置和阴影。
4. **检查。** 用 ⌘[ / ⌘] 切换图片，⌘0 适应窗口，⌘1 查看实际像素。
5. **导出。** ⇧⌘E 将整批导出到文件夹，⌘E 导出当前图片，⌘C 以完整分辨率复制当前成品。

<details>
<summary><b>键盘快捷键</b></summary>

| 操作 | 快捷键 |
| --- | --- |
| 添加图片 · 导入文件夹 | ⌘O · ⇧⌘O |
| 粘贴图片 · 复制当前成品 | ⌘V · ⌘C |
| 导出全部 · 导出当前图片 | ⇧⌘E · ⌘E |
| 新批次 | ⌘N |
| 移除所选图片 | ⌫ |
| 撤销 · 重做 | ⌘Z · ⇧⌘Z |
| 上一张 · 下一张 | ⌘[ · ⌘] |
| 适应窗口 · 实际像素 | ⌘0 · ⌘1 |
| 放大 · 缩小 | ⌘+ · ⌘− |
| 以 1 px 微调设备 | ⌥ + 方向键 |
| 侧边栏 · 出图设置 · 成品预览 | ⌃⌘S · ⌥⌘I · ⌥⌘P |
| 设置 | ⌘, |

</details>

## 命令行

`fralo` CLI 随 App 一起安装，无需打开 App 窗口即可渲染透明手机外框：

```bash
/Applications/Fralo.app/Contents/MacOS/fralo --help
```

Fralo 不会修改 `PATH`，如需全局使用请自行链接或复制。

```bash
# 列出可用机型
fralo models

# 处理文件夹中的所有 PNG / JPEG
fralo render ./screenshots --output ./framed

# 指定机型和方向，并输出 JSON 结果
fralo render one.png two.jpg --output ./framed \
  --model iphone-18-pro-max --orientation portrait --json
```

| 选项 | 说明 |
| --- | --- |
| `--output`, `-o <目录>` | 输出目录（必填） |
| `--input`, `-i <路径>` | 追加输入，可重复；文件夹不递归 |
| `--model <ID>` | 机型，例如 `iphone-18-pro-max`，见 `fralo models` |
| `--orientation <方向>` | `portrait` 或 `landscape` |
| `--overwrite` | 覆盖已有输出；始终保护原始输入 |
| `--json` | 结果以 JSON 写到标准输出，进度写到标准错误 |

CLI 支持 iPhone 16、17、18 Pro 与 Pro Max 共六款外框。配置优先级为：
内置默认值 → App 已保存设置 → 本次参数；参数不会写回 App。输出文件命名为 `<原名>-fralo.png`。

<details>
<summary><b>配置与退出码</b></summary>

设置文件位于 `~/Library/Application Support/Fralo/settings.json`。可用
`FRALO_SETTINGS_PATH` 为脚本和测试指定独立配置文件。

| 退出码 | 含义 |
| --- | --- |
| `0` | 完成（可能有跳过的文件） |
| `1` | 存在处理失败的图片 |
| `2` | 参数错误或启动失败 |
| `130` | 按 Ctrl-C 取消，已完成的文件会保留 |

</details>

## 隐私

截图只在你的 Mac 上处理，不会离开本机。唯一的网络请求是向 GitHub 检查更新，
不发送截图，也不发送系统信息。可在 Fralo 菜单关闭自动检查。

## 从源码构建

需要 macOS、Xcode 26.3 或更新版本以及 Python 3.10 或更新版本。打包 App 图标需要
Xcode 27 的 `actool`；核心库和 CLI 不需要。

```bash
git clone https://github.com/SoaringLabs/Fralo.git
cd Fralo

# 测试与构建
swift test --build-system native
swift build --build-system native -c release

# 在 dist/ 中打包 Fralo.app 和 DMG
python3 -m venv .venv
.venv/bin/python -m pip install -r scripts/requirements-dmg.txt
.venv/bin/python scripts/package.py --configuration release --dmg
open dist/Fralo.app
```

本地构建采用 ad-hoc 签名，未经公证。维护者的签名与发布流程见
[docs/signing.md](docs/signing.md) 和 [docs/updates.md](docs/updates.md)。

手动检测依赖和开发工具更新（Python 3.10+，不需要额外安装依赖）：

```bash
python3 -B scripts/check_updates.py
python3 -B scripts/check_updates.py --json
```

脚本只读比较锁定的 Swift 包、DMG 打包工具、GitHub Actions、本机 Swift／Xcode／macOS SDK
及 CI 配置的 Xcode 与上游稳定版，附上游发布信息链接，并明确报告查询失败。
语言模式、包工具要求和最低 macOS 目标仅作背景信息。Apple Swift 与上游 Swift 版本可能不同，
版本差异本身不能证明兼容性或迁移必要性。脚本不修改文件、依赖、安装环境或定时任务。
退出码 `0` 表示所有比较完成（仍可能有新版），`2` 表示有查询失败或需要人工核对的项目。
`--repo` 可指定其他 checkout，`--timeout` 设置单次 HTTP 请求超时（默认 15 秒）。
GitHub 使用公开查询；遇到限流时可设置 `GITHUB_TOKEN` 或 `GH_TOKEN`。
离线验证脚本：`python3 -B scripts/test_check_updates.py`。

<details>
<summary><b>目录结构</b></summary>

| 路径 | 内容 |
| --- | --- |
| [`Sources/FraloCore`](Sources/FraloCore) | App 与 CLI 共用的渲染、设备几何、设置和批量导出 |
| [`Sources/FraloApp`](Sources/FraloApp) | AppKit 工作台、检查器和 Sparkle 更新 |
| [`Sources/FraloDesignSystem`](Sources/FraloDesignSystem) | 共享的原生控件与界面表面 |
| [`Sources/FraloCLI`](Sources/FraloCLI) | `fralo` 命令行工具 |
| [`Tests`](Tests) | Core、App 与设计系统测试 |
| [`scripts`](scripts) | 打包、校验、示例生成和预览启动脚本 |

</details>

## 范围与限制

- 设备外框为原创的参数化绘制，不是 Apple 官方或照片级精确模板，不包含任何 Apple 官方设备素材。
- 截图从不拉伸变形。App 始终在设备屏幕内显示完整截图；CLI 铺满屏幕并允许最多 3% 的裁切，
  比例差异更大的图片会报告失败。
- Fralo 不编辑截图内容、不纠正方向，也不添加文字说明。

## 参与贡献

欢迎提交问题和 Pull Request。请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)，
并在 Issue 中使用生成的示例图，而不是个人截图。CI 会对每个 Pull Request 运行核心测试、
Release 构建、CLI 集成检查和公开源码检查。

## 许可

Fralo 采用 [MIT 许可](LICENSE)，由 [Soaring Labs](https://github.com/SoaringLabs) 开发，
[Ethan (@Peek-A-Booo)](https://github.com/Peek-A-Booo) 维护，详见 [AUTHORS.md](AUTHORS.md)。

应用内更新使用 [Sparkle](https://github.com/sparkle-project/Sparkle)，其许可随 App 一同分发。
iPhone 和 Safari 是 Apple Inc. 的商标，Chrome 是 Google LLC 的商标。
Fralo 与上述公司无关联，也未获其认可。
