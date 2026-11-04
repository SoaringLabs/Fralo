import { StarIcon } from "lucide-react"
import { Button } from "@/components/ui/button"
import { repositoryURL } from "@/lib/repository"

export function GitHubMark({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className={className} fill="currentColor">
      <path d="M12 .5C5.65.5.5 5.65.5 12c0 5.08 3.29 9.39 7.86 10.91.58.11.79-.25.79-.56v-2c-3.2.7-3.87-1.36-3.87-1.36-.52-1.33-1.28-1.69-1.28-1.69-1.04-.71.08-.7.08-.7 1.15.08 1.76 1.18 1.76 1.18 1.03 1.76 2.69 1.25 3.35.96.1-.75.4-1.25.73-1.54-2.55-.29-5.24-1.28-5.24-5.68 0-1.26.45-2.28 1.18-3.09-.12-.29-.51-1.46.11-3.04 0 0 .97-.31 3.17 1.18a11 11 0 0 1 5.77 0c2.2-1.49 3.17-1.18 3.17-1.18.63 1.58.23 2.75.11 3.04.74.81 1.18 1.83 1.18 3.09 0 4.41-2.69 5.38-5.25 5.67.41.36.78 1.06.78 2.14v3.17c0 .31.21.68.8.56A11.5 11.5 0 0 0 23.5 12C23.5 5.65 18.35.5 12 .5Z" />
    </svg>
  )
}

export function DownloadGlyph() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" className="group-hover:translate-y-0.5">
      <path d="M12 4v11M7 10.5l5 5 5-5" />
      <path d="M5 20h14" />
    </svg>
  )
}

const starIcon = "size-3 transition-[fill,color,transform] group-hover:rotate-[-12deg] group-hover:scale-110 group-hover:fill-[#f5b400] group-hover:text-[#e0a100]"

const starLabel = "Star SoaringLabs/Fralo on GitHub"

/** The project's GitHub call to action. Always English, like GitHub's own UI. */
export function GitHubStar({ variant }: { variant: "large" | "dock" }) {
  if (variant === "dock") {
    return (
      <Button asChild variant="ghost" size="sm" className="group rounded-full">
        <a href={repositoryURL} aria-label={starLabel}>
          <GitHubMark className="size-[15px]" />
          <StarIcon className={starIcon} strokeWidth={2.2} />
          <span>Star</span>
        </a>
      </Button>
    )
  }
  return (
    <Button asChild variant="outline" size="lg" className="group">
      <a href={repositoryURL} aria-label={starLabel}>
        <GitHubMark className="size-[17px]" />
        Star on GitHub
      </a>
    </Button>
  )
}
