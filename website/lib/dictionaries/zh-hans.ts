import type { Dictionary } from "./en"

export const zhHans: Dictionary = {
  meta: {
    title: "Fralo · 在 Mac 上批量给截图套框",
    description:
      "Fralo 是一款免费开源的 Mac 应用，把一整个文件夹的截图一次性放进手机、平板和浏览器外框，导出透明 PNG 或带背景的成品图。全部在你的 Mac 上完成。",
  },
  skip: "跳到正文",
  url: "fralo.app/zh-hans",
  language: "语言",
  download: "下载",
  hero: {
    title: ["为您的设计套上外壳"],
    lead: "Fralo 能给一整组截图套上同样的手机、平板或浏览器外壳，放到 App Store 页面、发布文章或任何你需要的地方里。",
    cta: "下载 Mac 版",
    meta: "免费开源 · macOS 14 及以上 · Apple 芯片",
    devices: "手机、平板和 Safari 窗口的导出图",
  },
  compare: {
    title: ["瞧瞧带框后的样子"],
    body: "拖动看看它们的不同",
    original: "原图",
    framed: "加框后",
    label: "对比原图和加框后的截图",
  },
  canvases: {
    title: ["自定义画布，尽在你的掌握"],
    body: "你可以把设备放到预设或任意自定义画布上，也可以只导出设备本身，背景透明。",
    group: "画布比例",
    none: "无",
    caption: "画布 {ratio} · 暖色纹理",
    transparent: "透明 PNG · 0 px 边距",
  },
  workbench: {
    alt: "Fralo 工作台：左侧图片列表，中间实时预览，右侧设置",
    notes: [
      ["一批，而不是一张。", "拖入截图或整个文件夹，每一张都用同一套设置。"],
      ["亲手摆位置。", "在预览里直接拖动设备，或按 ⌥ 加方向键一次移动 1 像素。"],
      ["放心导出。", "每次导出到新的文件夹，原图不动；某一张失败，其余照常完成。"],
      ["只在本地。", "无需账号，不上传，不统计。支持 English、简体中文、繁體中文、日本語。"],
    ],
  },
  cli: {
    title: ["一条命令，同样出图"],
    body: "如果想让你的 agent 帮你处理也同样简单，只需一行命令即可。agent 所需的一切，这里都有",
  },
  closing: {
    title: [["外壳、画布、导出，"], ["一个 Mac 应用", "就够了。"]],
  },
  inspector: {
    label: "Fralo 检查器（作用于本页）",
    browser: "浏览器",
    canvas: "画布",
    window: "窗口",
    shadow: "阴影",
    size: "大小",
    canvases: { texture: "纹理", gradient: "渐变", clear: "透明", dark: "深色" },
    appearances: { light: "浅色", dark: "深色" },
    shadows: { none: "无", soft: "浅", strong: "深" },
    export: "导出这个页面",
    exporting: "正在导出…",
    exported: "已导出 1 张图片到 {folder}。",
    tryIt: "用它处理你的截图",
    line: {
      window: "浏览器窗口",
      canvas: "画布",
      shadow: "阴影",
      wide: "px 宽 @2x",
    },
  },
  footer: {
    changelog: "更新记录",
    license: "MIT 许可证",
  },
}
