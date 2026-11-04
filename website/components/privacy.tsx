"use client"

import { useEffect, useId, useSyncExternalStore } from "react"
import { ShieldCheckIcon } from "lucide-react"
import { Button } from "@/components/ui/button"
import type { Dictionary } from "@/lib/dictionaries/en"

type Choice = "allowed" | "declined"
type Copy = Dictionary["privacy"]

const storageKey = "fralo.analytics.v1"
const changeEvent = "fralo-analytics-choice"
const cookiePrefix = "fralo"
let temporaryChoice: Choice | undefined

function getChoice(): Choice | null {
  if (temporaryChoice) return temporaryChoice
  try {
    const choice = window.localStorage.getItem(storageKey)
    return choice === "allowed" || choice === "declined" ? choice : null
  } catch {
    return null
  }
}

function saveChoice(choice: Choice) {
  try {
    window.localStorage.setItem(storageKey, choice)
    temporaryChoice = undefined
  } catch {
    // The decision still applies to this document when persistent storage is blocked.
    temporaryChoice = choice
  }
  window.dispatchEvent(new Event(changeEvent))
}

function subscribe(onChange: () => void) {
  function onStorage(event: StorageEvent) {
    if (event.key === storageKey || event.key === null) onChange()
  }
  window.addEventListener(changeEvent, onChange)
  window.addEventListener("storage", onStorage)
  window.addEventListener("pageshow", onChange)
  return () => {
    window.removeEventListener(changeEvent, onChange)
    window.removeEventListener("storage", onStorage)
    window.removeEventListener("pageshow", onChange)
  }
}

type AnalyticsWindow = Window & {
  dataLayer?: IArguments[]
}

function clearAnalyticsCookies() {
  for (const entry of document.cookie.split(";")) {
    const name = entry.trim().split("=")[0]
    if (name === `${cookiePrefix}_ga` || name.startsWith(`${cookiePrefix}_ga_`)) {
      // The tag writes these at the root for the current host only.
      document.cookie = `${name}=; Max-Age=0; Path=/`
      document.cookie = `${name}=; Max-Age=0; Path=/; Domain=${location.hostname}`
    }
  }
}

export function WebsiteAnalytics({ id }: { id: string }) {
  useEffect(() => {
    const browser: AnalyticsWindow = window
    const disabled = `ga-disable-${id}`
    const scriptId = "fralo-website-analytics"

    function sync() {
      const allowed = getChoice() === "allowed"
      Reflect.set(browser, disabled, !allowed)
      if (!allowed) {
        clearAnalyticsCookies()
        return
      }

      // Never add the script or queue an event until consent has been granted.
      if (document.getElementById(scriptId)) return
      const queue = (browser.dataLayer ??= [])
      function gtag(command: string, ...parameters: unknown[]): void
      function gtag() {
        // gtag.js expects an Arguments entry, as in Google's installation snippet.
        // eslint-disable-next-line prefer-rest-params
        queue.push(arguments)
      }
      gtag("js", new Date())
      gtag("config", id, {
        cookie_prefix: cookiePrefix,
        cookie_domain: "none",
        cookie_path: "/",
        allow_google_signals: false,
        allow_ad_personalization_signals: false,
      })
      const script = document.createElement("script")
      script.id = scriptId
      script.async = true
      script.src = `https://www.googletagmanager.com/gtag/js?id=${id}`
      document.head.append(script)
    }

    sync()
    return subscribe(sync)
  }, [id])

  return null
}

export function PrivacyControls({ copy, policyHref }: { copy: Copy; policyHref?: string }) {
  // The notice is only for visitors who have not already decided. On the policy
  // page the same controls remain available so a previous decision can be changed.
  const choice = useSyncExternalStore(subscribe, getChoice, () => undefined)
  const heading = useId()
  const Heading = policyHref ? "h2" : "h3"

  if (policyHref && choice !== null) return null

  function choose(value: Choice) {
    if (policyHref) document.getElementById("fralo-hero-title")?.focus({ preventScroll: true })
    saveChoice(value)
  }

  return (
    <section
      aria-labelledby={heading}
      className="privacy-card rounded-2xl border bg-card p-4 text-card-foreground sm:p-5"
    >
      <div className="flex items-start gap-3">
        <span className="grid size-9 shrink-0 place-items-center rounded-[10px] bg-secondary text-foreground">
          <ShieldCheckIcon aria-hidden="true" className="size-[19px]" />
        </span>
        <div className="min-w-0 grow">
          <Heading id={heading} className="text-start text-[15px] font-semibold">{copy.analyticsTitle}</Heading>
          <p className="mt-1 text-sm leading-relaxed text-muted-foreground">
            {copy.analyticsSummary}
            {policyHref && <> <a href={policyHref} className="privacy-link">{copy.link}</a></>}
          </p>
          {!policyHref && (
            <p role="status" className="mt-3 text-sm font-medium">
              {choice === "allowed" ? copy.allowed : copy.notAllowed}
            </p>
          )}
        </div>
      </div>
      <div className="mt-3 flex flex-wrap gap-2">
        <Button type="button" variant="outline" className="privacy-choice" onClick={() => choose("declined")}>
          {copy.decline}
        </Button>
        <Button type="button" variant="outline" className="privacy-choice" onClick={() => choose("allowed")}>
          {copy.allow}
        </Button>
      </div>
    </section>
  )
}
