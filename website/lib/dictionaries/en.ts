export const en = {
  meta: {
    title: "Fralo · Batch-frame screenshots into device mockups on your Mac",
    description:
      "Fralo is a free, open-source Mac app that puts a whole folder of screenshots into phone, tablet and browser frames, transparent or on a background. Everything stays on your Mac.",
  },
  skip: "Skip to content",
  url: "fralo.app",
  language: "Language",
  download: "Download",
  hero: {
    title: ["Frame your designs"],
    lead: "Fralo adds the same phone, tablet, or browser frame to a whole set of screenshots. Use them on your App Store page, in a release post, or wherever you need them.",
    cta: "Download for Mac",
    meta: "Free and open source · macOS 14+ · Apple silicon",
    devices: "Phone, tablet and Safari window exports",
  },
  compare: {
    title: ["See how it looks framed"],
    body: "Drag to see the difference",
    original: "Original",
    framed: "Framed",
    label: "Compare the original and framed versions",
  },
  canvases: {
    title: ["Make the canvas your own"],
    body: "Place the device on a preset canvas, customize the background, or export just the device on a transparent background.",
    group: "Canvas ratio",
    none: "None",
    caption: "Canvas {ratio} · warm texture",
    transparent: "Transparent PNG · 0 px margin",
  },
  workbench: {
    alt: "The Fralo workbench: batch list, live preview and settings",
    notes: [
      ["A batch, not a file.", "Drag in screenshots or a folder. Every one gets the same setup."],
      ["Placed by hand.", "Drag the device in the preview, or nudge it 1 px with ⌥ and an arrow key."],
      ["Exports you can trust.", "A new folder each time. Originals untouched. One failure never stops the batch."],
      ["Local.", "No account, upload or analytics. English, 简体中文, 繁體中文, 日本語."],
    ],
  },
  cli: {
    title: ["Same look, one command"],
    body: "Want to hand it off to your agent? One line is all it takes. Everything your agent needs is right here.",
  },
  closing: {
    title: [["Frames, canvases, export."], ["One Mac app is all it takes."]],
  },
  inspector: {
    label: "Fralo inspector for this page",
    browser: "Browser",
    canvas: "Canvas",
    window: "Window",
    shadow: "Shadow",
    size: "Size",
    canvases: { texture: "Texture", gradient: "Gradient", clear: "Transparent", dark: "Dark" },
    appearances: { light: "Light", dark: "Dark" },
    shadows: { none: "None", soft: "Soft", strong: "Strong" },
    export: "Export This Page",
    exporting: "Exporting…",
    exported: "Exported 1 image to {folder}.",
    tryIt: "Try it on your screenshots",
    line: {
      window: "browser window",
      canvas: "canvas",
      shadow: "shadow",
      wide: "px wide @2x",
    },
  },
  footer: {
    changelog: "Changelog",
    license: "MIT License",
  },
}

export type Dictionary = typeof en
