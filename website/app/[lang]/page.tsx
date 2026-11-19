import type { Metadata } from "next"
import { notFound } from "next/navigation"
import { Landing } from "@/components/landing/landing"
import { getRepositoryInfo } from "@/lib/github"
import { defaultLocale, getDictionary, hasLocale, pathFor } from "@/lib/i18n"
import { pageMetadata, publisherData, siteName, siteUrlFor } from "@/lib/seo"

export async function generateMetadata({ params }: PageProps<"/[lang]">): Promise<Metadata> {
  const { lang } = await params
  if (!hasLocale(lang)) return {}
  const google = process.env.FRALO_GOOGLE_SITE_VERIFICATION?.trim()
  return {
    ...pageMetadata(lang, pathFor, getDictionary(lang).meta),
    verification: google ? { google } : undefined,
  }
}

const websiteData = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "WebSite",
      "@id": siteUrlFor("/#website"),
      name: siteName,
      url: siteUrlFor("/"),
      publisher: { "@id": publisherData["@id"] },
    },
    publisherData,
  ],
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
      <Landing locale={lang} dict={getDictionary(lang)} repository={repository} />
    </>
  )
}
