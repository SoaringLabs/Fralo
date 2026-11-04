"use client"

import { useEffect, useId, useRef, useSyncExternalStore } from "react"
import { usePathname } from "next/navigation"
import type { PostHog } from "posthog-js/dist/module.slim.no-external"
import { locales, pathFor } from "@/lib/i18n"
import { ShieldCheckIcon } from "lucide-react"
import { Button } from "@/components/ui/button"
import type { Dictionary } from "@/lib/dictionaries/en"

type Choice = "allowed" | "declined"
type Copy = Dictionary["privacy"]

// A previous choice for Google Analytics cannot grant consent for PostHog.
const storageKey = "fralo.analytics.v2"
const changeEvent = "fralo-analytics-choice"
const landingPaths = new Set(locales.map(pathFor))
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

export function WebsiteAnalytics({ token, host }: { token: string; host: string }) {
  const pathname = usePathname()
  const choice = useSyncExternalStore(subscribe, getChoice, () => undefined)
  const client = useRef<PostHog | null>(null)
  const lastPageview = useRef<string | null>(null)

  useEffect(() => {
    if (choice !== "allowed") {
      client.current?.opt_out_capturing()
      lastPageview.current = null
      return
    }

    // Use the public path. Next.js internally rewrites / to /en.
    const url = new URL(window.location.href)
    if (!landingPaths.has(url.pathname)) lastPageview.current = null

    let cancelled = false
    async function capture() {
      const { default: posthog } = await import("posthog-js/dist/module.slim.no-external")
      if (cancelled || getChoice() !== "allowed" || window.location.pathname !== url.pathname) return

      if (!client.current) {
        posthog.init(token, {
          api_host: host,
          persistence: "localStorage",
          opt_out_capturing_persistence_type: "localStorage",
          opt_out_persistence_by_default: true,
          person_profiles: "never",
          advanced_disable_flags: true,
          autocapture: false,
          rageclick: false,
          disable_session_recording: true,
          capture_pageview: false,
          capture_pageleave: false,
          request_batching: false,
          before_send(event) {
            if (event?.event !== "$pageview" || getChoice() !== "allowed") return null
            const { properties } = event
            if (!properties) return null
            return {
              ...event,
              properties: {
                token: properties.token,
                distinct_id: properties.distinct_id,
                $session_id: properties.$session_id,
                $current_url: properties.$current_url,
                $host: properties.$host,
                $pathname: properties.$pathname,
                $referrer: properties.$referrer,
                $referring_domain: properties.$referring_domain,
                $process_person_profile: false,
                $geoip_disable: true,
              },
            }
          },
        })
        client.current = posthog
      }

      if (posthog.has_opted_out_capturing()) posthog.opt_in_capturing({ captureEventName: false })
      if (!landingPaths.has(url.pathname) || lastPageview.current === url.pathname) return

      const referrer = document.referrer ? new URL(document.referrer) : null
      const externalReferrer = referrer && referrer.origin !== url.origin ? referrer : null
      lastPageview.current = url.pathname
      posthog.capture("$pageview", {
        $current_url: url.origin + url.pathname,
        $host: url.host,
        $pathname: url.pathname,
        $referrer: externalReferrer?.origin ?? "$direct",
        $referring_domain: externalReferrer?.hostname ?? "$direct",
      })
    }
    // Analytics must not interfere with the page when the SDK or network is unavailable.
    void capture().catch(() => {})
    return () => { cancelled = true }
  }, [choice, pathname, token, host])

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
