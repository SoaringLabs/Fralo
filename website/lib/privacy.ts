import { pathFor, type Locale } from "./i18n"

export function privacyPath(locale: Locale) {
  return locale === "en" ? "/privacy" : `${pathFor(locale)}/privacy`
}

export function websiteAnalyticsConfig() {
  const token = process.env.FRALO_POSTHOG_PROJECT_TOKEN?.trim()
  const host = process.env.FRALO_POSTHOG_HOST?.trim()
  if (!token || !/^phc_[a-zA-Z0-9]+$/.test(token)) return
  if (host !== "https://us.i.posthog.com" && host !== "https://eu.i.posthog.com") return
  return { token, host }
}
