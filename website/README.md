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
canvas texture and social preview.

The workbench images are native 2× Mac window captures with the same Field Notes inputs
in the transparent composition. To refresh them, follow the capture steps in
[`docs/assets/README.md`](../docs/assets/README.md) and save a matching pair for each locale as
`public/media/workbench-<locale>-light.png` and `public/media/workbench-<locale>-dark.png`.

## Deployment

On Vercel, set the project's Root Directory to `website`. Optional environment variables:

- `SITE_URL`: canonical origin for metadata. Defaults to the Vercel production domain.
- `GITHUB_TOKEN`: raises the GitHub API rate limit when fetching the star count and release.
- `FRALO_GA_MEASUREMENT_ID`: optional GA4 measurement ID (`G-…`), read at build time. Leave unset to ship without website analytics or a consent prompt. Use a dedicated website property with no advertising destinations or features, and disable enhanced measurement if only page views are needed.

The footer links to the localized **Privacy & settings** page in either configuration. When
analytics is configured, Fralo keeps the Google tag out of the document until the visitor allows
analytics. The decision is stored locally and shared by all language routes on that origin.
Changing it to decline disables the tag and expires its Fralo analytics cookies.
