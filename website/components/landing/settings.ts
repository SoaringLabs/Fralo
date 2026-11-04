"use client"

import * as React from "react"

export const canvases = ["texture", "gradient", "clear", "dark"] as const
export const shadows = ["none", "soft", "strong"] as const
export type Canvas = (typeof canvases)[number]
export type Shadow = (typeof shadows)[number]
export type Appearance = "light" | "dark"

export type Settings = {
  canvas: Canvas
  /** null follows the visitor's system appearance until they pick one. */
  appearance: Appearance | null
  shadow: Shadow
  size: number
}

const defaults: Settings = { canvas: "gradient", appearance: null, shadow: "soft", size: 100 }
const storageKey = "fralo-landing-settings"

function restore(): Settings {
  try {
    const saved = JSON.parse(sessionStorage.getItem(storageKey) ?? "null")
    if (!saved || typeof saved !== "object") return defaults
    return {
      canvas: canvases.includes(saved.canvas) ? saved.canvas : defaults.canvas,
      appearance: saved.appearance === "light" || saved.appearance === "dark" ? saved.appearance : null,
      shadow: shadows.includes(saved.shadow) ? saved.shadow : defaults.shadow,
      size: typeof saved.size === "number" && saved.size >= 70 && saved.size <= 100 ? saved.size : defaults.size,
    }
  } catch {
    return defaults
  }
}

/** Inspector settings; kept for the tab session so switching language keeps the look. */
export function useSettings() {
  const [settings, setSettings] = React.useState<Settings>(defaults)
  const restored = React.useRef(false)

  React.useEffect(() => {
    // Read after hydration: the server always renders the defaults.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setSettings(restore())
    restored.current = true
  }, [])

  React.useEffect(() => {
    if (!restored.current) return
    try {
      sessionStorage.setItem(storageKey, JSON.stringify(settings))
    } catch {}
  }, [settings])

  const update = React.useCallback((patch: Partial<Settings>) => setSettings((current) => ({ ...current, ...patch })), [])
  return [settings, update] as const
}

function subscribe(query: string) {
  return (onChange: () => void) => {
    const media = window.matchMedia(query)
    media.addEventListener("change", onChange)
    return () => media.removeEventListener("change", onChange)
  }
}

export function useMediaQuery(query: string) {
  return React.useSyncExternalStore(
    React.useMemo(() => subscribe(query), [query]),
    () => window.matchMedia(query).matches,
    () => false
  )
}
