import type { MetadataRoute } from "next"
import { locales, pathFor } from "@/lib/i18n"
import { screenshotGuidePath } from "@/lib/guide"
import { privacyPath } from "@/lib/privacy"
import { siteUrlFor } from "@/lib/seo"

export default function sitemap(): MetadataRoute.Sitemap {
  return locales.flatMap((locale) => [
    { url: siteUrlFor(pathFor(locale)) },
    { url: siteUrlFor(screenshotGuidePath(locale)) },
    { url: siteUrlFor(privacyPath(locale)) },
  ])
}
