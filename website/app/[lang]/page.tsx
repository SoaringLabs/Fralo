import { notFound } from "next/navigation"
import { Landing } from "@/components/landing/landing"
import { getRepositoryInfo } from "@/lib/github"
import { getDictionary, hasLocale } from "@/lib/i18n"

export default async function Page({ params }: PageProps<"/[lang]">) {
  const { lang } = await params
  if (!hasLocale(lang)) notFound()
  const repository = await getRepositoryInfo()
  return <Landing locale={lang} dict={getDictionary(lang)} repository={repository} />
}
