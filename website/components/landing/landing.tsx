"use client"

import * as React from "react"
import Image from "next/image"
import { ChevronLeftIcon, ChevronRightIcon, LockIcon, PanelLeftIcon, PlusIcon, ShareIcon } from "lucide-react"
import { cn } from "cn"
import { PrivacyControls } from "@/components/privacy"
import { privacyPath } from "@/lib/privacy"
import { Button } from "@/components/ui/button"
import { downloadURL, type RepositoryInfo } from "@/lib/repository"
import { format, type Locale } from "@/lib/i18n"
import type { Dictionary } from "@/lib/dictionaries/en"
import icon from "@/public/media/icon.png"
import { DownloadGlyph, GitHubStar } from "./github-star"
import { Glass } from "./glass"
import { Inspector } from "./inspector"
import { LanguageSelect } from "./language-select"
import { Canvases, Cli, Closing, Compare, Footer, Hero, TerminalInstall, Workbench } from "./sections"
import { canvases, useMediaQuery, useSettings } from "./settings"

const windowShadows = {
  none: "none",
  soft: "0 30px 60px rgb(0 0 0 / 18%), 0 8px 20px rgb(0 0 0 / 10%)",
  strong: "0 60px 120px rgb(0 0 0 / 42%), 0 18px 36px rgb(0 0 0 / 24%)",
}

const exportFolder = "fralo-20261104-101500"

export function Landing({ locale, dict, repository, analyticsEnabled }: {
  locale: Locale
  dict: Dictionary
  repository: RepositoryInfo
  analyticsEnabled: boolean
}) {
  const [settings, update] = useSettings()
  const systemDark = useMediaQuery("(prefers-color-scheme: dark)")
  const reduceMotion = useMediaQuery("(prefers-reduced-motion: reduce)")
  const appearance = settings.appearance ?? (systemDark ? "dark" : "light")
  const windowWidth = Math.round(1240 * (settings.size / 100))
  const outerInk = settings.canvas === "dark" ? "#d8d8dc" : "#2a2622"
  const [windowElement, setWindowElement] = React.useState<HTMLDivElement | null>(null)

  // The dimension line and export size report the window as rendered, not just its maximum.
  const [renderedWidth, setRenderedWidth] = React.useState(windowWidth)
  React.useEffect(() => {
    if (!windowElement) return
    const observer = new ResizeObserver(([entry]) => setRenderedWidth(Math.round(entry.borderBoxSize[0].inlineSize)))
    observer.observe(windowElement)
    return () => observer.disconnect()
  }, [windowElement])

  // The dock takes over once the hero's own buttons have scrolled away.
  const [dockShown, setDockShown] = React.useState(false)
  React.useEffect(() => {
    const actions = document.getElementById("hero-actions")
    if (!actions) return
    const observer = new IntersectionObserver(([entry]) => setDockShown(!entry.isIntersecting && entry.boundingClientRect.top < 0))
    observer.observe(actions)
    return () => observer.disconnect()
  }, [])

  // "Export This Page": a Safari-style progress bar, a shutter flash, then a confirmation.
  const [progress, setProgress] = React.useState<number | null>(null)
  const [flash, setFlash] = React.useState(false)
  const [toast, setToast] = React.useState(false)
  const timers = React.useRef<number[]>([])
  React.useEffect(() => () => timers.current.forEach((timer) => window.clearTimeout(timer)), [])
  const exportPage = React.useCallback(() => {
    if (progress !== null) return
    setToast(false)
    const duration = reduceMotion ? 0 : 900
    const started = performance.now()
    const step = () => {
      const value = duration ? Math.min(100, ((performance.now() - started) / duration) * 100) : 100
      setProgress(value)
      if (value < 100) {
        requestAnimationFrame(step)
        return
      }
      setFlash(!reduceMotion)
      setToast(true)
      timers.current.push(
        window.setTimeout(() => {
          setFlash(false)
          setProgress(null)
        }, 750),
        window.setTimeout(() => setToast(false), 6000)
      )
    }
    requestAnimationFrame(step)
  }, [progress, reduceMotion])

  const exportLine = [
    dict.url,
    `${dict.inspector.line.window} ${dict.inspector.appearances[appearance]}`,
    `${dict.inspector.line.canvas} ${dict.inspector.canvases[settings.canvas]}`,
    `${dict.inspector.line.shadow} ${dict.inspector.shadows[settings.shadow]}`,
    `${renderedWidth * 2} ${dict.inspector.line.wide}`,
  ].join(" · ")

  return (
    <div className="relative min-h-dvh overflow-clip px-3 pt-6 pb-8 sm:px-[clamp(12px,3.5vw,56px)] sm:pt-[clamp(18px,3.5vw,56px)] sm:pb-[clamp(48px,6vw,96px)]">
      <a
        href="#content"
        className="sr-only z-50 rounded-lg bg-background px-3 py-2 text-sm font-semibold text-foreground focus:not-sr-only focus:absolute focus:top-3 focus:left-3"
      >
        {dict.skip}
      </a>

      {canvases.map((canvas) => (
        <div
          key={canvas}
          aria-hidden="true"
          className={cn("canvas-layer absolute inset-0", `canvas-${canvas}`)}
          style={{ opacity: settings.canvas === canvas ? 1 : 0 }}
        />
      ))}
      <div aria-hidden="true" className="pointer-events-none absolute inset-x-1.5 inset-y-2 sm:inset-3.5">
        {(["top-0 left-0 border-t border-l origin-top-left", "top-0 right-0 border-t border-r origin-top-right", "bottom-0 left-0 border-b border-l origin-bottom-left", "right-0 bottom-0 border-r border-b origin-bottom-right"] as const).map((position) => (
          <span key={position} className={cn("anim-mark absolute size-4 sm:size-6", position)} style={{ borderColor: outerInk }} />
        ))}
      </div>

      <div className="relative z-[1] mx-auto flex max-w-[1560px] flex-wrap items-start gap-7">
        <div className="flex min-w-0 flex-[999_1_640px] flex-col items-center">
          {/* The ruler is 28px tall (16px line + 12px gap); the inspector drops by the same amount so it lines up with the window. */}
          <div
            aria-hidden="true"
            className="anim-late mb-3 flex w-full items-center gap-2.5 font-mono text-[11px] leading-4 transition-[max-width] duration-500 motion-reduce:transition-none"
            style={{ maxWidth: windowWidth, color: outerInk }}
          >
            <span className="h-[9px] w-px" style={{ background: outerInk }} />
            <span className="h-px flex-1 opacity-55" style={{ background: outerInk }} />
            <span className="tabular-nums">{renderedWidth} pt</span>
            <span className="h-px flex-1 opacity-55" style={{ background: outerInk }} />
            <span className="h-[9px] w-px" style={{ background: outerInk }} />
          </div>

          <div
            ref={setWindowElement}
            className={cn(
              appearance === "dark" ? "theme-dark" : "theme-light",
              "anim-settle relative w-full overflow-clip rounded-[14px] bg-background text-foreground outline outline-border transition-[box-shadow,background-color,color,max-width] duration-500 motion-reduce:transition-none"
            )}
            style={{ maxWidth: windowWidth, boxShadow: windowShadows[settings.shadow] }}
          >
            {flash ? <div aria-hidden="true" className="anim-flash pointer-events-none absolute inset-0 z-20 bg-white" /> : null}

            <div className="flex h-[52px] items-center gap-3 border-b border-border bg-bar px-3.5 text-muted-foreground">
              <span aria-hidden="true" className="flex flex-none gap-2">
                {["#ff5f57", "#febc2e", "#28c840"].map((color) => (
                  <span key={color} className="size-3 rounded-full shadow-[inset_0_0_0_0.5px_rgb(0_0_0/12%)]" style={{ background: color }} />
                ))}
              </span>
              <PanelLeftIcon aria-hidden="true" className="ml-1.5 hidden size-[18px] flex-none sm:block" strokeWidth={1.6} />
              <ChevronLeftIcon aria-hidden="true" className="hidden size-4 flex-none sm:block" strokeWidth={1.8} />
              <ChevronRightIcon aria-hidden="true" className="hidden size-4 flex-none opacity-45 sm:block" strokeWidth={1.8} />
              <div className="relative mx-auto flex h-[34px] max-w-[560px] min-w-0 flex-1 items-center justify-center gap-1.5 overflow-hidden rounded-[9px] bg-field text-[13px] text-foreground">
                <LockIcon aria-hidden="true" className="size-[11px] text-muted-foreground" strokeWidth={2.4} />
                <span className="truncate">{dict.url}</span>
                <span
                  aria-hidden="true"
                  className="absolute bottom-0 left-0 h-0.5 bg-ring transition-opacity duration-300"
                  style={{ width: `${progress ?? 0}%`, opacity: progress === null ? 0 : 1 }}
                />
              </div>
              <ShareIcon aria-hidden="true" className="hidden size-[17px] flex-none sm:block" strokeWidth={1.7} />
              <PlusIcon aria-hidden="true" className="hidden size-[17px] flex-none sm:block" strokeWidth={1.7} />
            </div>

            <main id="content">
              <nav aria-label="Fralo" className="flex flex-wrap items-center gap-x-3 gap-y-2.5 px-[clamp(20px,5vw,72px)] pt-[18px]">
                <span className="mr-auto flex items-center gap-2.5 text-[15px] font-semibold">
                  <Image src={icon} alt="" width={36} height={36} />
                  Fralo
                </span>
                <LanguageSelect locale={locale} label={dict.language} container={windowElement} />
              </nav>

              {analyticsEnabled && (
                <div className="mx-[clamp(20px,5vw,72px)] mt-4 empty:hidden">
                  <PrivacyControls copy={dict.privacy} policyHref={privacyPath(locale)} />
                </div>
              )}
              <Hero dict={dict} />
              <Compare dict={dict} />
              <Canvases dict={dict} reduceMotion={reduceMotion} />
              <Workbench dict={dict} locale={locale} appearance={appearance} />
              <TerminalInstall dict={dict} />
              <Cli dict={dict} />
              <Closing dict={dict} repository={repository} />
              <Footer dict={dict} privacyHref={privacyPath(locale)} />
            </main>
            <div className="pointer-events-none sticky bottom-0 z-10 flex h-0 items-start justify-center">
              <Glass data-shown={dockShown} aria-hidden={!dockShown} inert={!dockShown} className="dock pointer-events-auto flex items-center gap-1.5 rounded-full py-1.5 pr-1.5 pl-2.5 text-foreground">
                <Image src={icon} alt="" width={24} height={24} />
                <span className="pr-1.5 pl-0.5 text-[13px] font-semibold">
                  Fralo{repository.version ? <span className="font-normal text-muted-foreground"> {repository.version}</span> : null}
                </span>
                <span aria-hidden="true" className="h-[18px] w-px bg-border" />
                <GitHubStar variant="dock" />
                <Button asChild size="sm" className="group rounded-full has-[>svg]:pe-[11px]">
                  <a href={downloadURL}>
                    <DownloadGlyph />
                    {dict.download}
                  </a>
                </Button>
              </Glass>
            </div>
          </div>

          <p className="anim-late mt-[18px] mb-0 w-full font-mono text-xs" style={{ maxWidth: windowWidth, color: outerInk }}>
            {exportLine}
          </p>
        </div>

        <Inspector
          dict={dict}
          settings={settings}
          appearance={appearance}
          windowWidth={renderedWidth}
          onChange={update}
          exporting={progress !== null && progress < 100}
          onExport={exportPage}
          toast={toast ? format(dict.inspector.exported, { folder: exportFolder }) : null}
        />
      </div>
    </div>
  )
}
