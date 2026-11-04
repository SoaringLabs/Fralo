import type { Metadata } from "next"
import { notFound } from "next/navigation"
import { Landing } from "@/components/landing/landing"
import { getRepositoryInfo } from "@/lib/github"
import { websiteAnalyticsConfig } from "@/lib/privacy"
import { defaultLocale, getDictionary, hasLocale, pathFor } from "@/lib/i18n"
import { pageMetadata, siteName, siteUrlFor } from "@/lib/seo"

export async function generateMetadata({ params }: PageProps<"/[lang]">): Promise<Metadata> {
  const { lang } = await params
  return hasLocale(lang) ? pageMetadata(lang, pathFor, getDictionary(lang).meta) : {}
}

const websiteData = {
  "@context": "https://schema.org",
  "@type": "WebSite",
  name: siteName,
  url: siteUrlFor("/"),
}

export default async function Page({ params }: PageProps<"/[lang]">) {
  const { lang } = await params
  if (!hasLocale(lang)) notFound()
  const repository = await getRepositoryInfo()
  return (
    <>
      {lang === defaultLocale && (
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(websiteData).replace(/</g, "\\u003c") }}
        />
      )}
      <Landing locale={lang} dict={getDictionary(lang)} repository={repository} analyticsEnabled={Boolean(websiteAnalyticsConfig())} />
    </>
  )
}
