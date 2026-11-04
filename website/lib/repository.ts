export const repository = "SoaringLabs/Fralo"
export const repositoryURL = `https://github.com/${repository}`
export const downloadURL = `${repositoryURL}/releases/latest`

export type RepositoryInfo = {
  stars: number | null
  version: string | null
}

export function formatStars(count: number) {
  if (count < 1000) return String(count)
  return `${(Math.round(count / 100) / 10).toString().replace(/\.0$/, "")}k`
}
