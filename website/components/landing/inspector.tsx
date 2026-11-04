"use client"

import { CheckIcon, ShareIcon } from "lucide-react"
import { cn } from "cn"
import { Button } from "@/components/ui/button"
import { downloadURL } from "@/lib/repository"
import type { Dictionary } from "@/lib/dictionaries/en"
import { Glass } from "./glass"
import { Segmented } from "./segmented"
import { canvases, shadows, type Appearance, type Settings } from "./settings"

export function Inspector({
  dict,
  settings,
  appearance,
  windowWidth,
  onChange,
  exporting,
  onExport,
  toast,
}: {
  dict: Dictionary
  settings: Settings
  appearance: Appearance
  windowWidth: number
  onChange: (patch: Partial<Settings>) => void
  exporting: boolean
  onExport: () => void
  toast: string | null
}) {
  const t = dict.inspector
  return (
    <Glass
      as="aside"
      aria-label={t.label}
      className={cn(
        settings.canvas === "dark" ? "theme-dark" : "theme-light",
        "anim-late order-first grid w-full grid-cols-2 gap-x-3 gap-y-4 rounded-3xl p-4 text-foreground lg:sticky lg:top-6 lg:order-none lg:flex lg:w-auto lg:max-w-[290px] lg:flex-[1_1_260px] lg:flex-col lg:gap-[18px] lg:p-[18px]"
      )}
    >
      <div className="col-span-2 hidden flex-col gap-0.5 lg:flex">
        <strong className="text-sm font-semibold">{dict.url}</strong>
        <span className="text-xs text-muted-foreground">
          1 / 1 · {t.browser} · {t.appearances[appearance]}
        </span>
      </div>

      <fieldset className="col-span-2 m-0 flex flex-col gap-2 border-0 p-0">
        <legend className="mb-2 p-0 text-[13px] font-semibold">{t.canvas}</legend>
        <div role="radiogroup" aria-label={t.canvas} className="grid grid-cols-4 gap-1.5 lg:grid-cols-2">
          {canvases.map((canvas) => {
            const selected = settings.canvas === canvas
            return (
              <button
                key={canvas}
                type="button"
                role="radio"
                aria-checked={selected}
                aria-label={t.canvases[canvas]}
                onClick={() => onChange({ canvas })}
                className={cn(
                  "flex cursor-pointer flex-col items-stretch gap-1.5 rounded-[11px] p-1.5 text-xs font-medium outline-none transition-[background-color,box-shadow] duration-200 focus-visible:ring-2 focus-visible:ring-ring motion-reduce:transition-none",
                  selected ? "bg-segment shadow-[inset_0_0_0_2px_var(--ring)]" : "shadow-[inset_0_0_0_1px_var(--border)] hover:bg-hover"
                )}
              >
                <span className={cn("block h-[34px] rounded-[7px] shadow-[inset_0_0_0_0.5px_rgb(0_0_0/15%)]", `canvas-${canvas}`)} />
                <span className="text-[11px] leading-tight break-words sm:text-xs">{t.canvases[canvas]}</span>
              </button>
            )
          })}
        </div>
      </fieldset>

      <div className="flex flex-col gap-2">
        <span className="text-[13px] font-semibold" id="inspector-window">
          {t.window}
        </span>
        <Segmented
          label={t.window}
          value={appearance}
          onChange={(value) => onChange({ appearance: value })}
          options={(["light", "dark"] as const).map((value) => ({ value, title: t.appearances[value] }))}
        />
      </div>

      <div className="flex flex-col gap-2">
        <span className="text-[13px] font-semibold">{t.shadow}</span>
        <Segmented
          label={t.shadow}
          value={settings.shadow}
          onChange={(value) => onChange({ shadow: value })}
          options={shadows.map((value) => ({ value, title: t.shadows[value] }))}
        />
      </div>

      <div className="hidden flex-col gap-1.5 lg:flex">
        <label htmlFor="inspector-size" className="flex justify-between text-[13px] font-semibold">
          {t.size}
          <span className="font-normal text-muted-foreground tabular-nums">{settings.size}%</span>
        </label>
        <input
          id="inspector-size"
          type="range"
          min={70}
          max={100}
          step={1}
          value={settings.size}
          onChange={(event) => onChange({ size: Number(event.target.value) })}
          className="m-0 w-full cursor-pointer accent-ring"
        />
      </div>

      <div aria-hidden="true" className="hidden h-px bg-border lg:block" />
      <div className="hidden justify-between text-[12.5px] text-muted-foreground tabular-nums lg:flex">
        <span>{windowWidth * 2} × auto px</span>
        <span>PNG</span>
      </div>

      <Button variant="invert" className="hidden h-[42px] w-full rounded-xl lg:inline-flex" onClick={onExport} aria-disabled={exporting}>
        <ShareIcon strokeWidth={2} />
        {exporting ? t.exporting : t.export}
      </Button>

      <div role="status" aria-live="polite" className="hidden lg:block">
        {toast ? (
          <div className="anim-toast flex items-start gap-2.5 rounded-xl bg-segment px-3 py-2.5 text-[12.5px] leading-normal">
            <span aria-hidden="true" className="flex size-[18px] flex-none items-center justify-center rounded-full bg-[#248a3d] text-white">
              <CheckIcon className="size-3" strokeWidth={3} />
            </span>
            <span>
              {toast}{" "}
              <a href={downloadURL} className="font-semibold underline-offset-2 hover:underline">
                {t.tryIt}
              </a>
            </span>
          </div>
        ) : null}
      </div>
    </Glass>
  )
}
