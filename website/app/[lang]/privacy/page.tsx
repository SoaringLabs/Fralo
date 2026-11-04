import type { Metadata } from "next"
import { notFound } from "next/navigation"
import { PrivacyControls } from "@/components/privacy"
import { getDictionary, hasLocale, localeInfo, locales, pathFor } from "@/lib/i18n"
import { analyticsMeasurementId, privacyPath } from "@/lib/privacy"

export async function generateMetadata({ params }: PageProps<"/[lang]/privacy">): Promise<Metadata> {
  const { lang } = await params
  if (!hasLocale(lang)) return {}
  const { privacy } = getDictionary(lang)
  return {
    title: `${privacy.link} · Fralo`,
    description: privacy.intro,
    alternates: {
      canonical: privacyPath(lang),
      languages: {
        ...Object.fromEntries(locales.map((locale) => [localeInfo[locale].tag, privacyPath(locale)])),
        "x-default": "/privacy",
      },
    },
    openGraph: { title: `${privacy.link} · Fralo`, description: privacy.intro, url: privacyPath(lang) },
  }
}

export default async function PrivacyPage({ params }: PageProps<"/[lang]/privacy">) {
  const { lang } = await params
  if (!hasLocale(lang)) notFound()
  const { privacy } = getDictionary(lang)
  const analyticsEnabled = Boolean(analyticsMeasurementId())

  return (
    <div className="privacy-page min-h-dvh bg-background text-foreground">
      <main className="mx-auto max-w-[720px] px-5 py-9 sm:px-8 sm:py-16">
        <a href={pathFor(lang)} className="privacy-link text-sm">← {privacy.home}</a>
        <h1 className="mt-6 text-start text-3xl font-bold sm:text-4xl">{privacy.link}</h1>
        <p className="mt-3 leading-relaxed text-muted-foreground">{privacy.intro}</p>
        <section aria-labelledby="app-privacy" className="mt-8">
          <h2 id="app-privacy" className="text-start text-xl font-semibold">{privacy.appTitle}</h2>
          <p className="mt-2 leading-relaxed text-muted-foreground">{privacy.appProcessing}</p>
          <p className="mt-2 leading-relaxed text-muted-foreground">{privacy.appUpdates}</p>
        </section>

        <section aria-labelledby="website-privacy" className="mt-8 border-t pt-8">
          <h2 id="website-privacy" className="text-start text-xl font-semibold">{privacy.websiteTitle}</h2>
          <div className="mt-4 space-y-6">
            {analyticsEnabled ? (
              <PrivacyControls copy={privacy} />
            ) : (
              <section aria-labelledby="analytics" className="privacy-card rounded-2xl border bg-card p-4 sm:p-5">
                <h3 id="analytics" className="text-start text-[15px] font-semibold">{privacy.analyticsTitle}</h3>
                <p className="mt-1 text-sm leading-relaxed text-muted-foreground">{privacy.analyticsOff}</p>
              </section>
            )}
            {analyticsEnabled && (
              <section>
                <h3 className="text-start font-semibold">{privacy.analyticsDetailsTitle}</h3>
                <p className="mt-2 leading-relaxed text-muted-foreground">
                  {privacy.analyticsDetails}{" "}
                  <a href="https://policies.google.com/privacy" className="privacy-link">{privacy.googlePolicy}</a>
                </p>
              </section>
            )}
            <section>
              <h3 className="text-start font-semibold">{privacy.storageTitle}</h3>
              <p className="mt-2 leading-relaxed text-muted-foreground">
                {privacy.storageDetails}{analyticsEnabled && ` ${privacy.choiceStorage}`}
              </p>
            </section>
            <section>
              <h3 className="text-start font-semibold">{privacy.downloadsTitle}</h3>
              <p className="mt-2 leading-relaxed text-muted-foreground">{privacy.downloadsDetails}</p>
            </section>
          </div>
        </section>
      </main>
    </div>
  )
}
