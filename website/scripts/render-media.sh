#!/bin/zsh
# Renders the landing page's demo media with the repository's own CLI.
# Inputs are the fictional Field Notes screens; nothing personal is used.
set -euo pipefail

website=${0:A:h:h}
repo=${website:h}
out=$website/public/media
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

swift build -c release --product fralo --package-path "$repo" --scratch-path "$work/build" >/dev/null
fralo=$work/build/release/fralo

mkdir -p "$work/in/phone" "$work/in/tablet" "$work/in/browser" "$out"
cp "$repo/examples/01-today.png" "$work/in/phone/today.png"
swift "$website/scripts/generate-wide-demo.swift" "$work/in/tablet/today.png" 1376 1032 2 >/dev/null
# A 1440 × 838 page fills the 16:10 Safari window without letterboxing.
swift "$website/scripts/generate-wide-demo.swift" "$work/in/browser/today.png" 1440 838 2 web >/dev/null

render() {
  local name=$1 input=$2 recipe=$3
  print -r -- "$recipe" > "$work/$name.json"
  "$fralo" compose "$work/in/$input" --output "$work/out/$name" --config "$work/$name.json" --overwrite --json >/dev/null
  print -r -- "$work/out/$name/today-fralo.png"
}

for display in phone tablet browser; do
  case $display in
    phone) extra='"display":"phone","phoneModel":"iphone-18-pro-max","orientation":"portrait"' ;;
    tablet) extra='"display":"tablet","orientation":"landscape"' ;;
    browser) extra='"display":"browser","browser":"safari","browserAppearance":"light","windowRatio":"16:10"' ;;
  esac
  png=$(render "$display-clear" $display "{\"schemaVersion\":1,$extra,\"mode\":\"transparent\",\"transparentShadow\":\"soft\"}")
  cp "$png" "$out/$display-clear.png"
done

# Canvas texture alone: the device is fully transparent.
png=$(render texture phone '{"schemaVersion":1,"display":"phone","mode":"background","canvas":"1:1","background":"warm","backgroundShadow":"none","deviceOpacity":0}')
sips -Z 1200 -s format jpeg -s formatOptions 82 "$png" --out "$out/texture-warm.jpg" >/dev/null

cp "$repo/examples/01-today.png" "$out/phone-original.png"
cp "$repo/docs/assets/icon.png" "$out/icon.png"

# Social previews, one per locale: the hero copy beside a before/after split of the phone export above.
for lang in en zh-hans zh-hant ja; do
  node --no-warnings --input-type=module -e '
    const [website, lang, file] = process.argv.slice(1)
    const name = { en: "en", "zh-hans": "zhHans", "zh-hant": "zhHant", ja: "ja" }[lang]
    const tag = { en: "en", "zh-hans": "zh-Hans", "zh-hant": "zh-Hant", ja: "ja" }[lang]
    const d = (await import(`${website}/lib/dictionaries/${lang}.ts`))[name]
    const footer = `${d.hero.meta.split(" · ")[0]} · ${d.url}`
    const copy = { lang: tag, headline: d.hero.title, subtitle: d.meta.title.replace(/^Fralo · /, ""), footer }
    ;(await import("node:fs")).writeFileSync(file, JSON.stringify(copy))
  ' "$website" "$lang" "$work/og-$lang.json"
  swift "$website/scripts/generate-og.swift" "$work/og-$lang.png" "$work/og-$lang.json" "$out" >/dev/null
  sips -s format jpeg -s formatOptions 86 "$work/og-$lang.png" --out "$out/og-$lang.jpg" >/dev/null
done

print "Rendered media into $out"
