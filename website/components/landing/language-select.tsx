"use client"

import { GlobeIcon } from "lucide-react"
import { useRouter } from "next/navigation"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { hasLocale, localeCookie, localeInfo, locales, pathFor, type Locale } from "@/lib/i18n"

export function LanguageSelect({ locale, label, container }: { locale: Locale; label: string; container: HTMLElement | null }) {
  const router = useRouter()
  return (
    <Select
      value={locale}
      onValueChange={(value) => {
        if (!hasLocale(value) || value === locale) return
        // Remembered for "/", so a chosen language wins over Accept-Language next time.
        document.cookie = `${localeCookie}=${value}; path=/; max-age=31536000; samesite=lax`
        router.push(pathFor(value))
      }}
    >
      <SelectTrigger aria-label={label}>
        <GlobeIcon className="size-[15px] opacity-70" strokeWidth={1.8} />
        <SelectValue />
      </SelectTrigger>
      <SelectContent container={container}>
        {locales.map((value) => (
          <SelectItem key={value} value={value} lang={localeInfo[value].tag}>
            {localeInfo[value].name}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  )
}
