import { NextResponse, type NextRequest } from "next/server"
import { defaultLocale, hasLocale, localeCookie, matchLocale, pathFor, type Locale } from "./lib/i18n"

function preferredLocale(request: NextRequest): Locale {
  const saved = request.cookies.get(localeCookie)?.value
  if (saved && hasLocale(saved)) return saved

  const ranges = (request.headers.get("accept-language") ?? "")
    .split(",")
    .map((part) => {
      const [range, quality] = part.trim().split(";q=")
      return { range, quality: quality === undefined ? 1 : Number(quality) }
    })
    .filter((entry) => entry.range && entry.quality > 0)
    .sort((a, b) => b.quality - a.quality)

  for (const { range } of ranges) {
    const locale = matchLocale(range)
    if (locale) return locale
  }
  return defaultLocale
}

export function proxy(request: NextRequest) {
  const locale = preferredLocale(request)
  if (locale === defaultLocale) return NextResponse.next()

  const url = request.nextUrl.clone()
  url.pathname = pathFor(locale)
  return NextResponse.redirect(url, 307)
}

export const config = {
  matcher: "/",
}
