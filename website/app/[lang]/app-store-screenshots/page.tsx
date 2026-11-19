import type { Metadata } from "next"
import Image from "next/image"
import { notFound } from "next/navigation"
import { Button } from "@/components/ui/button"
import { screenshotGuidePath } from "@/lib/guide"
import { getDictionary, hasLocale, localeInfo, locales, pathFor } from "@/lib/i18n"
import { downloadURL } from "@/lib/repository"
import { pageMetadata, publisherData, siteName, siteUrlFor } from "@/lib/seo"
import phoneClear from "@/public/media/phone-clear.png"
import phoneOriginal from "@/public/media/phone-original.png"

const screenshotSpecs = "https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications"

type Props = PageProps<"/[lang]/app-store-screenshots">

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { lang } = await params
  if (!hasLocale(lang)) return {}
  const { guide } = getDictionary(lang)
  return pageMetadata(lang, screenshotGuidePath, {
    title: `${guide.title} · ${siteName}`,
    description: guide.intro,
  })
}

export default async function ScreenshotGuidePage({ params }: Props) {
  const { lang } = await params
  if (!hasLocale(lang)) notFound()
  const dict = getDictionary(lang)
  const { guide } = dict
  const guideData = {
    "@context": "https://schema.org",
    "@type": "Article",
    headline: guide.title,
    description: guide.intro,
    inLanguage: localeInfo[lang].tag,
    mainEntityOfPage: siteUrlFor(screenshotGuidePath(lang)),
    image: siteUrlFor("/media/phone-clear.png"),
    author: publisherData,
    publisher: { "@id": publisherData["@id"] },
  }

  return (
    <div className="document-page min-h-dvh bg-background text-foreground">
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(guideData).replace(/</g, "\\u003c") }} />
      <main className="mx-auto max-w-[720px] px-5 py-9 sm:px-8 sm:py-16">
        <a href={pathFor(lang)} className="document-link text-sm">← {dict.privacy.home}</a>
        <article className="mt-6">
          <h1 className="text-start text-3xl font-bold sm:text-4xl">{guide.title}</h1>
          <p className="mt-3 leading-relaxed text-muted-foreground">{guide.intro}</p>

          <figure className="mt-8 rounded-2xl border bg-accent p-4 sm:p-6">
            <div className="mx-auto grid max-w-[420px] grid-cols-2 items-center justify-items-center gap-5">
              <Image src={phoneOriginal} alt={guide.originalAlt} sizes="(max-width: 480px) 38vw, 190px" className="h-auto w-4/5 rounded-md" />
              <Image src={phoneClear} alt={guide.framedAlt} sizes="(max-width: 480px) 42vw, 200px" className="h-auto w-full" />
            </div>
            <figcaption className="mt-4 text-center text-sm text-muted-foreground">{guide.caption}</figcaption>
          </figure>

          <ol className="mt-8 list-decimal space-y-6 pl-6 marker:font-semibold">
            {guide.steps.map(([title, body]) => (
              <li key={title} className="pl-1">
                <h2 className="text-start text-xl font-semibold">{title}</h2>
                <p className="mt-2 leading-relaxed text-muted-foreground">{body}</p>
              </li>
            ))}
          </ol>

          <section className="mt-8 border-t pt-8">
            <h2 className="text-start text-xl font-semibold">{guide.uploadTitle}</h2>
            <p className="mt-2 leading-relaxed text-muted-foreground">{guide.uploadBody}</p>
            <p className="mt-2"><a className="document-link" href={screenshotSpecs}>{guide.specs}</a></p>
          </section>

          <Button asChild size="lg" className="mt-8">
            <a href={downloadURL}>{dict.hero.cta}</a>
          </Button>
        </article>
        <nav aria-label={dict.language} className="mt-10 flex flex-wrap gap-x-5 gap-y-3 border-t pt-5 text-sm">
          {locales.map((locale) => (
            <a
              key={locale}
              href={screenshotGuidePath(locale)}
              hrefLang={localeInfo[locale].tag}
              lang={localeInfo[locale].tag}
              aria-current={locale === lang ? "page" : undefined}
              className="document-link"
            >
              {localeInfo[locale].name}
            </a>
          ))}
        </nav>
      </main>
    </div>
  )
}
