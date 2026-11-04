import type { Metadata, Viewport } from "next"
import { notFound } from "next/navigation"
import { getDictionary, hasLocale, localeInfo, locales, pathFor } from "@/lib/i18n"
import { WebsiteAnalytics } from "@/components/privacy"
import { analyticsMeasurementId } from "@/lib/privacy"
import "../globals.css"

const siteURL =
  process.env.SITE_URL ??
  (process.env.VERCEL_PROJECT_PRODUCTION_URL ? `https://${process.env.VERCEL_PROJECT_PRODUCTION_URL}` : "http://localhost:3000")

export function generateStaticParams() {
  return locales.map((lang) => ({ lang }))
}

export async function generateMetadata({ params }: LayoutProps<"/[lang]">): Promise<Metadata> {
  const { lang } = await params
  if (!hasLocale(lang)) return {}
  const { meta } = getDictionary(lang)
  const languages = Object.fromEntries(locales.map((locale) => [localeInfo[locale].tag, pathFor(locale)]))
  return {
    metadataBase: new URL(siteURL),
    title: meta.title,
    description: meta.description,
    alternates: { canonical: pathFor(lang), languages: { ...languages, "x-default": "/" } },
    openGraph: {
      type: "website",
      siteName: "Fralo",
      title: meta.title,
      description: meta.description,
      url: pathFor(lang),
      locale: localeInfo[lang].openGraph,
      images: [{ url: "/media/og.jpg", width: 1200, height: 675, alt: "Fralo" }],
    },
    twitter: { card: "summary_large_image", title: meta.title, description: meta.description, images: ["/media/og.jpg"] },
  }
}

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f3ece6" },
    { media: "(prefers-color-scheme: dark)", color: "#18181a" },
  ],
}

export default async function RootLayout({ children, params }: LayoutProps<"/[lang]">) {
  const { lang } = await params
  if (!hasLocale(lang)) notFound()
  const measurementId = analyticsMeasurementId()
  return (
    <html lang={localeInfo[lang].tag}>
      <body>
        {children}
        {measurementId && <WebsiteAnalytics id={measurementId} />}
      </body>
    </html>
  )
}
