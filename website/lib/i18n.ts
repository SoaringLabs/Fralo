import { en, type Dictionary } from "./dictionaries/en"
import { ja } from "./dictionaries/ja"
import { zhHans } from "./dictionaries/zh-hans"
import { zhHant } from "./dictionaries/zh-hant"

// URL slugs, in the order the language menu lists them. English lives at "/".
export const locales = ["en", "zh-hans", "zh-hant", "ja"] as const
export type Locale = (typeof locales)[number]
export const defaultLocale: Locale = "en"
export const localeCookie = "NEXT_LOCALE"

export const localeInfo: Record<Locale, { tag: string; name: string; openGraph: string }> = {
  en: { tag: "en", name: "English", openGraph: "en_US" },
  "zh-hans": { tag: "zh-Hans", name: "简体中文", openGraph: "zh_CN" },
  "zh-hant": { tag: "zh-Hant", name: "繁體中文", openGraph: "zh_TW" },
  ja: { tag: "ja", name: "日本語", openGraph: "ja_JP" },
}

const dictionaries: Record<Locale, Dictionary> = { en, "zh-hans": zhHans, "zh-hant": zhHant, ja }

export const hasLocale = (value: string): value is Locale => (locales as readonly string[]).includes(value)
export const getDictionary = (locale: Locale) => dictionaries[locale]
export const pathFor = (locale: Locale) => (locale === defaultLocale ? "/" : `/${locale}`)

/** Maps a BCP 47 language range (from Accept-Language or navigator.languages) to a supported locale. */
export function matchLocale(range: string): Locale | null {
  const value = range.trim().toLowerCase()
  if (value.startsWith("zh")) return /hant|-tw|-hk|-mo/.test(value) ? "zh-hant" : "zh-hans"
  if (value.startsWith("ja")) return "ja"
  if (value.startsWith("en")) return "en"
  return null
}

export function format(template: string, values: Record<string, string | number>) {
  return template.replace(/\{(\w+)\}/g, (_, key: string) => String(values[key] ?? ""))
}
