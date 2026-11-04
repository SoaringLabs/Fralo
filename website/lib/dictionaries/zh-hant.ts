import type { Dictionary } from "./en"

export const zhHant: Dictionary = {
  meta: {
    title: "Fralo · 在 Mac 上批次為截圖套框",
    description:
      "Fralo 是一款免費開源的 Mac App，把一整個資料夾的截圖一次放進手機、平板和瀏覽器外框，輸出透明 PNG 或含背景的成品圖。全部在你的 Mac 上完成。",
  },
  skip: "跳到內容",
  url: "fralo.app/zh-hant",
  language: "語言",
  download: "下載",
  hero: {
    title: ["為您的設計加上外框"],
    lead: "Fralo 能替整組截圖套上同一款手機、平板或瀏覽器外框，用在 App Store 產品頁面、版本公告，或任何需要配圖的地方。",
    cta: "下載 Mac 版",
    meta: "免費開源 · macOS 14 以上 · Apple 晶片",
    devices: "手機、平板和 Safari 視窗的輸出圖",
  },
  compare: {
    title: ["看看加框後的樣子"],
    body: "拖曳看看有什麼不同",
    original: "原圖",
    framed: "加框後",
    label: "比較原圖與加框後的截圖",
  },
  canvases: {
    title: ["自訂畫布，由你決定"],
    body: "你可以把裝置放到預設畫布上，自訂背景，也可以只輸出裝置，保留透明背景。",
    group: "畫布比例",
    none: "無",
    caption: "畫布 {ratio} · 暖色紋理",
    transparent: "透明 PNG · 0 px 邊距",
  },
  workbench: {
    alt: "Fralo 工作臺：左側圖片列表，中間即時預覽，右側設定",
    notes: [
      ["一批，而不是一張。", "拖入截圖或整個資料夾，每一張都套用同一組設定。"],
      ["親手調整位置。", "在預覽中直接拖曳裝置，或按 ⌥ 加方向鍵一次移動 1 像素。"],
      ["安心輸出。", "每次輸出到新的資料夾，原圖不變；某一張失敗，其餘照常完成。"],
      ["只在本機。", "無需帳號，不上傳，不統計。支援 English、简体中文、繁體中文、日本語。"],
    ],
  },
  cli: {
    title: ["一行指令，同樣出圖"],
    body: "想交給你的 AI agent 處理？一行指令就夠了。它需要的資訊，這裡都有",
  },
  closing: {
    title: [["外框、畫布、輸出，"], ["一個 Mac App", "就夠了。"]],
  },
  inspector: {
    label: "Fralo 檢查器（作用於本頁）",
    browser: "瀏覽器",
    canvas: "畫布",
    window: "視窗",
    shadow: "陰影",
    size: "大小",
    canvases: { texture: "紋理", gradient: "漸層", clear: "透明", dark: "深色" },
    appearances: { light: "淺色", dark: "深色" },
    shadows: { none: "無", soft: "淺", strong: "深" },
    export: "輸出這個頁面",
    exporting: "正在輸出…",
    exported: "已輸出 1 張圖片到 {folder}。",
    tryIt: "用它處理你的截圖",
    line: {
      window: "瀏覽器視窗",
      canvas: "畫布",
      shadow: "陰影",
      wide: "px 寬 @2x",
    },
  },
  footer: {
    changelog: "更新記錄",
    license: "MIT 授權",
  },
}
