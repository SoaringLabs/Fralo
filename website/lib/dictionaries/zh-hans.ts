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
    title: ["截图批量套框，", "一次全部导出。"],
    lead: "把 App 截图拖进来，选一次手机、平板或浏览器外框，整批导出透明 PNG 或带背景的成品图。原生 Mac 应用，全程在本地处理，不上传。",
    cta: "下载 Mac 版",
    meta: "免费开源 · macOS 14 及以上 · Apple 芯片",
    devices: "手机、平板和 Safari 窗口的导出图",
  },
  compare: {
    title: ["同样的像素，", "装进了外框。"],
    body: "在手机上左右拖动。线的左边是你截下的原图，1320 × 2868；右边是 Fralo 的导出结果。屏幕按 1:1 放置，所以里面的内容一点都不会动。",
    original: "原图",
    framed: "成品",
    label: "对比原图和成品",
  },
  canvases: {
    title: ["五种画布，", "也可以不要画布。"],
    body: "把设备放到画布上，配纯色、渐变、纹理或你自己的图片；也可以只导出设备本身，背景透明。",
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
    title: ["同样的外框，", "也能用脚本完成。"],
    body: "App 自带命令行工具，读取你在 App 中保存的样式，用同一个渲染引擎处理新截图。",
  },
  closing: {
    title: ["接下来，", "轮到你的截图。"],
    cta: "下载 Fralo {version}",
    ctaNoVersion: "下载 Fralo",
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
