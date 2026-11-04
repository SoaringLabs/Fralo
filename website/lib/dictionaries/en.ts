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
    title: ["Batch-frame screenshots into device mockups."],
    lead: "Drop in a folder of App screenshots, pick a phone, tablet or browser frame once, and export every image, transparent or on a background. A native Mac app. Nothing is uploaded.",
    cta: "Download for Mac",
    meta: "Free and open source · macOS 14+ · Apple silicon",
    devices: "Phone, tablet and Safari window exports",
  },
  compare: {
    title: ["Same pixels.", "Now in a frame."],
    body: "Drag across the phone. Left of the line is the screenshot as you took it, 1320 × 2868. Right of it is Fralo's export. The screen is placed 1:1, so nothing inside it moves.",
    original: "Original",
    framed: "Framed",
    label: "Compare original and framed",
  },
  canvases: {
    title: ["Five canvases.", "Or none at all."],
    body: "Put the device on a canvas with a color, gradient, texture or your own image. Or export it alone with a transparent background.",
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
    title: ["The same frame,", "from a script."],
    body: "The bundled CLI reads the look you saved in the App and renders new screenshots with the same engine.",
  },
  closing: {
    title: ["Frame yours next."],
    cta: "Download Fralo {version}",
    ctaNoVersion: "Download Fralo",
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
