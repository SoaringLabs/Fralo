import type { Metadata } from "next"
import { defaultLocale, localeInfo, locales, type Locale } from "./i18n"

const siteURL = new URL(process.env.SITE_URL?.trim() || "https://fralo.app")
if (!["http:", "https:"].includes(siteURL.protocol) || siteURL.href !== `${siteURL.origin}/`) {
  throw new Error("SITE_URL must be an HTTP(S) origin without a path, credentials, query or fragment.")
}

export const siteName = "Fralo"
export const siteUrlFor = (path: string) => new URL(path, siteURL).href

export function pageMetadata(
  locale: Locale,
  pathForLocale: (locale: Locale) => string,
  { title, description }: { title: string; description: string },
): Metadata {
  const canonical = siteUrlFor(pathForLocale(locale))
  const languages = Object.fromEntries(
    locales.map((language) => [localeInfo[language].tag, siteUrlFor(pathForLocale(language))]),
  )
  // One preview per locale, rendered by scripts/render-media.sh (generate-og.swift).
  const image = siteUrlFor(`/media/og-${locale}.jpg`)

  return {
    title,
    description,
    alternates: {
      canonical,
      languages: { ...languages, "x-default": siteUrlFor(pathForLocale(defaultLocale)) },
    },
    openGraph: {
      type: "website",
      siteName,
      title,
      description,
      url: canonical,
      locale: localeInfo[locale].openGraph,
      alternateLocale: locales
        .filter((language) => language !== locale)
        .map((language) => localeInfo[language].openGraph),
      images: [{ url: image, width: 2400, height: 1260, alt: siteName }],
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
      images: [{ url: image, alt: siteName }],
    },
  }
}
