import { pathFor, type Locale } from "./i18n"

export function privacyPath(locale: Locale) {
  return locale === "en" ? "/privacy" : `${pathFor(locale)}/privacy`
}

export function analyticsMeasurementId() {
  const id = process.env.FRALO_GA_MEASUREMENT_ID?.trim()
  return id && /^G-[A-Z0-9]+$/.test(id) ? id : undefined
}
