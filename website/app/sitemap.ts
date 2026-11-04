import type { MetadataRoute } from "next"
import { locales, pathFor } from "@/lib/i18n"
import { privacyPath } from "@/lib/privacy"
import { siteUrlFor } from "@/lib/seo"

export default function sitemap(): MetadataRoute.Sitemap {
  return locales.flatMap((locale) => [
    { url: siteUrlFor(pathFor(locale)) },
    { url: siteUrlFor(privacyPath(locale)) },
  ])
}
