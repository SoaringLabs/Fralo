import { pathFor, type Locale } from "./i18n"

export function screenshotGuidePath(locale: Locale) {
  const home = pathFor(locale)
  return `${home === "/" ? "" : home}/app-store-screenshots`
}
