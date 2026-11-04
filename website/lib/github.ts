import { cacheLife } from "next/cache"
import { repository, type RepositoryInfo } from "./repository"

async function getJSON(path: string) {
  const headers: HeadersInit = { Accept: "application/vnd.github+json" }
  // Optional; raises the anonymous rate limit during builds.
  if (process.env.GITHUB_TOKEN) headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`
  const response = await fetch(`https://api.github.com/${path}`, { headers })
  if (!response.ok) throw new Error(`GitHub ${path}: ${response.status}`)
  return response.json()
}

/** Star count and latest release, refreshed daily. Missing values hide their UI instead of failing the page. */
export async function getRepositoryInfo(): Promise<RepositoryInfo> {
  "use cache"
  cacheLife("days")

  const [repo, release] = await Promise.allSettled([
    getJSON(`repos/${repository}`),
    getJSON(`repos/${repository}/releases/latest`),
  ])
  const stars = repo.status === "fulfilled" && typeof repo.value.stargazers_count === "number" ? repo.value.stargazers_count : null
  const tag = release.status === "fulfilled" && typeof release.value.tag_name === "string" ? release.value.tag_name : null
  return { stars, version: tag ? tag.replace(/^v/, "") : null }
}
