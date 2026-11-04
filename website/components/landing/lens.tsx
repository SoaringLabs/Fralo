"use client"

import * as React from "react"
import { LiquidGlass, type LiquidGlassHandle } from "liquid-glass-web-react"
import { useMediaQuery } from "./settings"

// Liquid glass that refracts live content in every browser (liquid-glass-web-react): the SVG
// displacement filter is applied to the content under the lens rather than to a backdrop.
// It suits a small, mostly still region: filtering a page-sized surface or chasing scroll
// every frame stutters, so floating chrome uses the frosted .glass recipe instead.

const safariSourceLimit = 2_500_000

function isSafari() {
  const agent = navigator.userAgent
  return /^((?!chrome|chromium|android).)*safari/i.test(agent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)
}

/** Displacement in CSS pixels, converted to the engine's bounding-box-relative strength. */
function strengthFor(pixels: number, width: number, height: number) {
  return pixels / (Math.sqrt(width * width + height * height) / Math.SQRT2)
}

function useSize(element: HTMLElement | null) {
  const [size, setSize] = React.useState<{ width: number; height: number } | null>(null)
  React.useEffect(() => {
    if (!element) return
    const observer = new ResizeObserver(([entry]) => {
      const box = entry.borderBoxSize[0]
      setSize({ width: Math.round(box.inlineSize), height: Math.round(box.blockSize) })
    })
    observer.observe(element)
    return () => observer.disconnect()
  }, [element])
  return size
}

/** A round magnifier riding the original/framed divider. */
export function WipeLens({ split, children }: { split: number; children: React.ReactNode }) {
  const reduceTransparency = useMediaQuery("(prefers-reduced-transparency: reduce)")
  const [box, setBox] = React.useState<HTMLDivElement | null>(null)
  const size = useSize(box)
  const lens = React.useRef<LiquidGlassHandle>(null)
  const [initial] = React.useState(split / 100)
  React.useEffect(() => {
    lens.current?.setPosition(split / 100, 0.5)
  }, [split])

  const refract = size && !reduceTransparency && !(isSafari() && size.width * size.height > safariSourceLimit)
  return (
    <div ref={setBox} className="absolute inset-0">
      {refract ? (
        <LiquidGlass
          ref={lens}
          x={initial}
          y={0.5}
          width={76}
          height={76}
          radius="auto"
          strength={strengthFor(18, size.width, size.height)}
          chromaticAberration={0.4}
          depth={18}
          curvature={0.9}
          glow={0.2}
          edgeHighlight={0.5}
          shadow="0 0 0 0.5px rgb(255 255 255 / 40%), 0 10px 26px rgb(0 0 0 / 28%)"
          style={{ position: "absolute", inset: 0 }}
        >
          <div className="relative" style={{ width: size.width, height: size.height }}>
            {children}
          </div>
        </LiquidGlass>
      ) : (
        children
      )}
    </div>
  )
}
