import type { Viewport } from "next"
import { notFound } from "next/navigation"
import { hasLocale, localeInfo, locales } from "@/lib/i18n"
import { WebsiteAnalytics } from "@/components/website-analytics"
import { websiteAnalyticsConfig } from "@/lib/privacy"
import "../globals.css"

export function generateStaticParams() {
  return locales.map((lang) => ({ lang }))
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
  const analytics = websiteAnalyticsConfig()
  return (
    <html lang={localeInfo[lang].tag}>
      <body>
        {children}
        {analytics && <WebsiteAnalytics {...analytics} />}
      </body>
    </html>
  )
}
