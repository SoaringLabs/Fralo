import { cacheLife } from "next/cache"
import { downloadURL, repository, type RepositoryInfo } from "./repository"

async function getJSON(path: string) {
  const headers: HeadersInit = { Accept: "application/vnd.github+json" }
  // Optional; raises the anonymous rate limit during builds.
  if (process.env.GITHUB_TOKEN) headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`
  const response = await fetch(`https://api.github.com/${path}`, { headers })
  if (!response.ok) throw new Error(`GitHub ${path}: ${response.status}`)
  return response.json()
}

async function getLatestReleaseTag() {
  const release = await getJSON(`repos/${repository}/releases/latest`).catch(() => null)
  if (typeof release?.tag_name === "string" && release.tag_name) return release.tag_name

  // The public download link can resolve a release even when the API is unavailable.
  const response = await fetch(downloadURL, { redirect: "manual" })
  const location = response.headers.get("location")
  if (!location) return null
  const target = new URL(location, downloadURL)
  const tagPath = `/${repository}/releases/tag/`
  if (target.origin !== new URL(downloadURL).origin || !target.pathname.startsWith(tagPath)) return null
  return decodeURIComponent(target.pathname.slice(tagPath.length)) || null
}

/** Latest release, refreshed daily. */
export async function getRepositoryInfo(): Promise<RepositoryInfo> {
  "use cache"
  cacheLife("days")

  const tag = await getLatestReleaseTag().catch(() => null)
  return { version: tag ? tag.replace(/^v/, "") : null }
}
