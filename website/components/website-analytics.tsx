"use client"

import { useEffect, useRef } from "react"
import { usePathname } from "next/navigation"
import type { PostHog } from "posthog-js/dist/module.slim.no-external"
import { locales, pathFor } from "@/lib/i18n"

const landingPaths = new Set(locales.map(pathFor))

function previouslyDeclinedAnalytics() {
  try {
    // Keep honoring a decline saved by the previous website.
    return window.localStorage.getItem("fralo.analytics.v2") === "declined"
  } catch {
    return false
  }
}

export function WebsiteAnalytics({ token, host }: { token: string; host: string }) {
  const pathname = usePathname()
  const client = useRef<PostHog | null>(null)
  const lastPageview = useRef<string | null>(null)

  useEffect(() => {
    // Use the public path. Next.js internally rewrites / to /en.
    const url = new URL(window.location.href)
    if (!landingPaths.has(url.pathname)) {
      lastPageview.current = null
      return
    }
    if (previouslyDeclinedAnalytics() || lastPageview.current === url.pathname) return

    let cancelled = false
    async function capture() {
      const { default: posthog } = await import("posthog-js/dist/module.slim.no-external")
      if (cancelled || previouslyDeclinedAnalytics() || window.location.pathname !== url.pathname) return

      if (!client.current) {
        posthog.init(token, {
          api_host: host,
          cookieless_mode: "always",
          person_profiles: "never",
          advanced_disable_flags: true,
          autocapture: false,
          rageclick: false,
          disable_session_recording: true,
          capture_pageview: false,
          capture_pageleave: false,
          request_batching: false,
          before_send(event) {
            if (event?.event !== "$pageview" || previouslyDeclinedAnalytics()) return null
            const { properties } = event
            if (!properties) return null
            return {
              ...event,
              properties: {
                token: properties.token,
                distinct_id: properties.distinct_id,
                $session_id: properties.$session_id,
                $cookieless_mode: properties.$cookieless_mode,
                // Required for the cookieless hash; PostHog removes it before storage.
                $raw_user_agent: properties.$raw_user_agent,
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
  }, [pathname, token, host])

  return null
}
