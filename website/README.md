# Fralo website

The landing page for [Fralo](../README.md): a Next.js site whose own page is presented as a
Fralo export. Visitors change the canvas, window appearance, shadow and size from an inspector
that mirrors the App's.

## Develop

```bash
pnpm install
pnpm dev
```

Before sending a change:

```bash
pnpm lint
pnpm typecheck
pnpm build
```

Node 24 and the pnpm version in `package.json` are expected.

## Structure

| Path | Purpose |
| --- | --- |
| `app/[lang]/` | One statically generated page per locale |
| `proxy.ts` | Serves English at `/`; sends other visitors to `/zh-hans`, `/zh-hant` or `/ja` from their saved choice or `Accept-Language` |
| `lib/dictionaries/` | English, Simplified Chinese, Traditional Chinese and Japanese copy |
| `lib/github.ts` | Latest release, cached for a day |
| `components/landing/` | The framed page, inspector and sections |
| `components/landing/lens.tsx` | The comparison magnifier, which refracts the screenshot under it with [liquid-glass-web-react](https://github.com/PallavAg/liquid-glass-web-react). Floating chrome (dock, inspector, menus) uses frosted glass from `glass.tsx` |
| `components/ui/` | shadcn/ui Button and Select, themed with macOS semantic colors |
| `public/media/` | Images generated from this repository |

## Media

`pnpm media` builds the repository's `fralo` CLI and renders the phone, tablet and Safari
exports at full resolution from the fictional Field Notes screens. It also generates the
canvas texture and one social preview per locale (`og-<locale>.jpg`, drawn by
`scripts/generate-og.swift` from the hero copy in `lib/dictionaries/`).

The workbench images are native 2× Mac window captures with the same Field Notes inputs
in the transparent composition. To refresh them, follow the capture steps in
[`docs/assets/README.md`](../docs/assets/README.md) and save a matching pair for each locale as
`public/media/workbench-<locale>-light.png` and `public/media/workbench-<locale>-dark.png`.

## Deployment

On Vercel, set the project's Root Directory to `website`. Optional environment variables:

- `SITE_URL`: public origin for canonical links, sharing cards and the sitemap. Defaults to
  `https://fralo.app`. Set it only to override the public origin, without any path or query;
  use the same public origin in production and previews.
- `GITHUB_TOKEN`: raises the GitHub API rate limit when fetching the star count and release.
- `FRALO_POSTHOG_PROJECT_TOKEN`: PostHog's public project token (`phc_…`), read at build time.
- `FRALO_POSTHOG_HOST`: the project's ingestion endpoint, either `https://us.i.posthog.com`
  or `https://eu.i.posthog.com`.

Set both variables for production and enable cookieless tracking and IP discard in the PostHog
project settings. With analytics configured, the four landing pages send page views and the
referring site by default. Visitors who previously declined remain excluded. PostHog estimates
daily visitors without storing analytics cookies or browser identifiers. Session replay,
interaction autocapture, and person profiles are disabled. The footer links to the localized
**Privacy & settings** page, which describes analytics when configured.

After deploying, check that the public origin serves `/robots.txt` and `/sitemap.xml`, and
that the sitemap URLs return `200` without a language cookie or `Accept-Language` header.
The sitemap lists the four homepages and four privacy pages; their HTML links each language
to its equivalents. Confirm that production has no `noindex` and that Vercel preview URLs
return `X-Robots-Tag: noindex`. Submit the production sitemap in Google Search Console once
the domain is verified there.
