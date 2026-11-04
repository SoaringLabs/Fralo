"use client"

import * as React from "react"
import Image from "next/image"
import { ChevronsLeftRightIcon } from "lucide-react"
import { cn } from "cn"
import { Button } from "@/components/ui/button"
import { downloadURL, repositoryURL, type RepositoryInfo } from "@/lib/repository"
import { format, type Locale } from "@/lib/i18n"
import type { Dictionary } from "@/lib/dictionaries/en"
import browserClear from "@/public/media/browser-clear.png"
import phoneClear from "@/public/media/phone-clear.png"
import phoneOriginal from "@/public/media/phone-original.png"
import tabletClear from "@/public/media/tablet-clear.png"
import workbenchEnDark from "@/public/media/workbench-en-dark.png"
import workbenchEnLight from "@/public/media/workbench-en-light.png"
import workbenchZhHansDark from "@/public/media/workbench-zh-hans-dark.png"
import workbenchZhHansLight from "@/public/media/workbench-zh-hans-light.png"
import { DownloadGlyph, GitHubStar } from "./github-star"
import { WipeLens } from "./lens"
import { Segmented } from "./segmented"
import type { Appearance } from "./settings"

const section = "border-t border-border px-[clamp(20px,5vw,72px)] py-24"

/** Headline phrases; CJK lines break only between them, never before trailing punctuation. */
function Phrases({ phrases }: { phrases: string[] }) {
  return phrases.map((phrase) => (
    <span key={phrase} className="phrase">
      {phrase}
    </span>
  ))
}

function TwoLineHeading({ lines, className }: { lines: string[]; className?: string }) {
  return (
    <h2 className={cn("heading m-0 text-[clamp(28px,3.2vw,44px)] font-bold", className)}>
      {lines.map((line, index) => (
        <React.Fragment key={line}>
          {index > 0 ? <br /> : null}
          {line}
        </React.Fragment>
      ))}
    </h2>
  )
}

export function Hero({ dict, stars }: { dict: Dictionary; stars: number | null }) {
  return (
    <section className="flex flex-wrap items-center gap-10 px-[clamp(20px,5vw,72px)] pt-[clamp(32px,5vw,72px)] pb-14">
      <div className="flex max-w-[500px] flex-[1_1_340px] flex-col gap-[22px]">
        <h1 className="display m-0 text-[clamp(38px,4.6vw,62px)] font-bold">
          <Phrases phrases={dict.hero.title} />
        </h1>
        <p className="m-0 text-lg leading-relaxed text-muted-foreground">{dict.hero.lead}</p>
        <div id="hero-actions" className="flex flex-wrap items-center gap-2.5">
          <Button asChild size="lg" className="group">
            <a href={downloadURL}>
              <DownloadGlyph />
              {dict.hero.cta}
            </a>
          </Button>
          <GitHubStar stars={stars} variant="large" />
        </div>
        <p className="m-0 text-[13px] text-muted-foreground">{dict.hero.meta}</p>
      </div>
      <div role="img" aria-label={dict.hero.devices} className="device-fan relative aspect-[5/4] min-w-0 flex-[999_1_440px]">
        <div className="device device-browser absolute top-[4%] right-0 w-[78%]" style={{ animationDelay: "0.55s" }}>
          <Image src={browserClear} alt="" preload sizes="(min-width: 1200px) 560px, 70vw" className="h-auto w-full drop-shadow-[0_20px_30px_rgb(0_0_0/18%)]" style={{ "--float": "8s" } as React.CSSProperties} />
        </div>
        <div className="device device-tablet absolute bottom-[7%] left-[3%] w-[58%]" style={{ animationDelay: "0.7s" }}>
          <Image src={tabletClear} alt="" preload sizes="(min-width: 1200px) 420px, 55vw" className="h-auto w-full drop-shadow-[0_24px_34px_rgb(0_0_0/22%)]" style={{ "--float": "7s", "--float-delay": "-2s" } as React.CSSProperties} />
        </div>
        <div className="device device-phone absolute bottom-0 left-[56%] w-[22%]" style={{ animationDelay: "0.85s" }}>
          <Image src={phoneClear} alt="" preload sizes="(min-width: 1200px) 160px, 22vw" className="h-auto w-full drop-shadow-[0_28px_36px_rgb(0_0_0/28%)]" style={{ "--float": "6s", "--float-delay": "-4s" } as React.CSSProperties} />
        </div>
      </div>
    </section>
  )
}

// Measured from a solid-colour export: the 1320 × 2868 screen sits at (146, 132) inside the
// 1612 × 3132 transparent phone export, so both layers line up pixel for pixel.
const screen = { left: 146 / 1612, top: 132 / 3132, width: 1320 / 1612, height: 2868 / 3132 }

export function Compare({ dict }: { dict: Dictionary }) {
  const [split, setSplit] = React.useState(52)
  return (
    <section className={cn(section, "reveal flex flex-wrap items-center gap-x-16 gap-y-10")}>
      <div className="flex max-w-[420px] flex-[1_1_300px] flex-col gap-3.5">
        <TwoLineHeading lines={dict.compare.title} />
        <p className="m-0 text-[17px] leading-relaxed text-muted-foreground">{dict.compare.body}</p>
        <p className="m-0 font-mono text-xs text-muted-foreground">01-today.png → 01-today-fralo.png · 1612 × 3132</p>
      </div>
      <div className="flex min-w-0 flex-[999_1_300px] justify-center pt-8">
        <div className="group/wipe relative aspect-[1612/3132] w-full max-w-[300px]">
          <WipeLens split={split}>
            <Image
              src={phoneOriginal}
              alt=""
              sizes="300px"
              className="absolute shadow-[0_0_0_1px_var(--border)]"
              style={{ left: `${screen.left * 100}%`, top: `${screen.top * 100}%`, width: `${screen.width * 100}%`, height: `${screen.height * 100}%` }}
            />
            <Image src={phoneClear} alt="" sizes="300px" className="absolute inset-0 size-full" style={{ clipPath: `inset(0 0 0 ${split}%)` }} />
            <span aria-hidden="true" className="absolute inset-y-0 -ml-px w-0.5 bg-ring" style={{ left: `${split}%` }} />
          </WipeLens>
          <span
            aria-hidden="true"
            className="pointer-events-none absolute top-1/2 -mt-[38px] -ml-[38px] flex size-[76px] items-center justify-center rounded-full text-white drop-shadow-[0_1px_2px_rgb(0_0_0/45%)] group-has-[input:focus-visible]/wipe:ring-2 group-has-[input:focus-visible]/wipe:ring-ring group-has-[input:focus-visible]/wipe:ring-offset-2"
            style={{ left: `${split}%` }}
          >
            <ChevronsLeftRightIcon className="size-5" strokeWidth={2.4} />
          </span>
          <span aria-hidden="true" className="absolute -top-[30px] left-0 text-xs text-muted-foreground">
            {dict.compare.original}
          </span>
          <span aria-hidden="true" className="absolute -top-[30px] right-0 text-xs text-muted-foreground">
            {dict.compare.framed}
          </span>
          <input
            type="range"
            min={0}
            max={100}
            value={split}
            onChange={(event) => setSplit(Number(event.target.value))}
            aria-label={dict.compare.label}
            className="absolute inset-0 m-0 size-full cursor-ew-resize opacity-0"
          />
        </div>
      </div>
    </section>
  )
}

const ratios = [
  { label: null, value: 0 },
  { label: "1:1", value: 1 },
  { label: "4:3", value: 4 / 3 },
  { label: "16:9", value: 16 / 9 },
  { label: "3:4", value: 3 / 4 },
  { label: "9:16", value: 9 / 16 },
] as const
const stageRatio = 16 / 10

export function Canvases({ dict, reduceMotion }: { dict: Dictionary; reduceMotion: boolean }) {
  const [index, setIndex] = React.useState(2)
  const [auto, setAuto] = React.useState(true)
  const [visible, setVisible] = React.useState(false)
  const stage = React.useRef<HTMLDivElement>(null)

  React.useEffect(() => {
    const element = stage.current
    if (!element) return
    const observer = new IntersectionObserver(([entry]) => setVisible(entry.isIntersecting), { threshold: 0.4 })
    observer.observe(element)
    return () => observer.disconnect()
  }, [])

  // Cycle through the ratios only while the diagram is on screen and untouched.
  React.useEffect(() => {
    if (!auto || !visible || reduceMotion) return
    const timer = window.setInterval(() => setIndex((current) => (current + 1) % ratios.length), 2600)
    return () => window.clearInterval(timer)
  }, [auto, visible, reduceMotion])

  const ratio = ratios[index]
  let width = 62
  let height = 96
  if (ratio.value) {
    if (ratio.value >= stageRatio) {
      width = 88
      height = (88 * stageRatio) / ratio.value
    } else {
      height = 88
      width = (88 * ratio.value) / stageRatio
    }
  }
  const caption = ratio.label ? format(dict.canvases.caption, { ratio: ratio.label }) : dict.canvases.transparent

  return (
    <section className={cn(section, "reveal flex flex-wrap items-center gap-x-14 gap-y-10")}>
      <div className="flex max-w-[420px] flex-[1_1_300px] flex-col gap-4">
        <TwoLineHeading lines={dict.canvases.title} />
        <p className="m-0 text-[17px] leading-relaxed text-muted-foreground">{dict.canvases.body}</p>
        <Segmented
          label={dict.canvases.group}
          className="self-start"
          itemClassName="min-h-[30px] px-[11px] text-[13px]"
          value={String(index)}
          onChange={(next) => {
            setIndex(Number(next))
            setAuto(false)
          }}
          options={ratios.map((option, optionIndex) => ({ value: String(optionIndex), title: option.label ?? dict.canvases.none }))}
        />
      </div>
      <div ref={stage} className="relative mx-auto mb-7 aspect-[16/10] w-full max-w-[620px] min-w-0 flex-[999_1_420px]">
        <div
          aria-hidden="true"
          className={cn("morph absolute top-1/2 left-1/2 -translate-1/2 rounded-md shadow-[0_0_0_1px_var(--border),0_18px_40px_rgb(0_0_0/12%)]", ratio.value ? "canvas-texture bg-cover!" : "canvas-clear")}
          style={{ width: `${width}%`, height: `${height}%` }}
        />
        <Image src={phoneClear} alt="" sizes="200px" className="morph absolute top-1/2 left-1/2 w-auto -translate-1/2" style={{ height: `${ratio.value ? height * 0.76 : 80}%` }} />
        <span role="status" className="absolute right-0 -bottom-7 text-xs text-muted-foreground">
          {caption}
        </span>
      </div>
    </section>
  )
}

export function Workbench({ dict, locale, appearance }: { dict: Dictionary; locale: Locale; appearance: Appearance }) {
  // Only Simplified Chinese has its own captures so far; other locales show the English UI.
  const [light, dark] = locale === "zh-hans" ? [workbenchZhHansLight, workbenchZhHansDark] : [workbenchEnLight, workbenchEnDark]
  return (
    <section className={cn(section, "reveal")}>
      <div className="relative">
        <Image src={light} alt={dict.workbench.alt} sizes="(min-width: 1240px) 1100px, 92vw" className="h-auto w-full transition-opacity duration-600" style={{ opacity: appearance === "dark" ? 0 : 1 }} />
        <Image src={dark} alt="" sizes="(min-width: 1240px) 1100px, 92vw" className="absolute inset-0 size-full transition-opacity duration-600" style={{ opacity: appearance === "dark" ? 1 : 0 }} />
      </div>
      <div className="mt-9 grid grid-cols-[repeat(auto-fit,minmax(230px,1fr))] gap-x-10 gap-y-6">
        {dict.workbench.notes.map(([title, body]) => (
          <p key={title} className="m-0 text-base leading-relaxed">
            <strong className="font-semibold">{title}</strong> <span className="text-muted-foreground">{body}</span>
          </p>
        ))}
      </div>
    </section>
  )
}

export function Cli({ dict }: { dict: Dictionary }) {
  return (
    <section className={cn(section, "reveal flex flex-wrap items-center gap-x-14 gap-y-6")}>
      <div className="flex flex-[1_1_260px] flex-col gap-3">
        <TwoLineHeading lines={dict.cli.title} className="text-[clamp(26px,2.8vw,38px)]" />
        <p className="m-0 text-base leading-relaxed text-muted-foreground">{dict.cli.body}</p>
      </div>
      <pre lang="en" className="m-0 min-w-0 flex-[999_1_460px] overflow-x-auto rounded-xl bg-bar p-[22px] font-mono text-[13.5px] leading-[1.85]">
        <span className="text-muted-foreground">$ </span>
        <span className="typed">fralo compose ./screenshots --output ./framed --app-settings --json</span>
        {"\n"}
        <span className="typed-after text-muted-foreground">{'  "status": "completed",\n  "succeeded": 12,\n  "failed": 0'}</span>
      </pre>
    </section>
  )
}

export function Closing({ dict, repository }: { dict: Dictionary; repository: RepositoryInfo }) {
  return (
    <section className="flex flex-wrap items-end justify-between gap-x-10 gap-y-6 border-t border-border px-[clamp(20px,5vw,72px)] pt-24 pb-24">
      <h2 className="display m-0 text-[clamp(36px,4.6vw,64px)] font-bold">
        <Phrases phrases={dict.closing.title} />
      </h2>
      <div className="flex flex-wrap items-center gap-2.5">
        <Button asChild size="lg" className="group">
          <a href={downloadURL}>
            <DownloadGlyph />
            {repository.version ? format(dict.closing.cta, { version: repository.version }) : dict.closing.ctaNoVersion}
          </a>
        </Button>
        <GitHubStar stars={repository.stars} variant="large" />
      </div>
    </section>
  )
}

export function Footer({ dict }: { dict: Dictionary }) {
  return (
    <footer className="flex flex-wrap gap-x-6 gap-y-2 border-t border-border px-[clamp(20px,5vw,72px)] pt-6 pb-24 text-[13px] text-muted-foreground">
      <span className="mr-auto">SoaringLabs · {dict.footer.license}</span>
      <a href={`${repositoryURL}/blob/main/CHANGELOG.md`} className="hover:text-foreground">
        {dict.footer.changelog}
      </a>
      <a href={repositoryURL} className="hover:text-foreground">
        GitHub
      </a>
    </footer>
  )
}
