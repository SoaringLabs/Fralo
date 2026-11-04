"use client"

import * as React from "react"
import { cn } from "cn"

// Frosted glass panel: blur and saturation, a specular rim and a highlight that follows the
// pointer. Real refraction is reserved for the small magnifier in lens.tsx.

type GlassProps<T extends React.ElementType> = {
  as?: T
} & Omit<React.ComponentPropsWithoutRef<T>, "as">

export function Glass<T extends React.ElementType = "div">({ as, className, onPointerMove, ...props }: GlassProps<T>) {
  const Tag = (as ?? "div") as React.ElementType
  return (
    <Tag
      className={cn("glass", className)}
      onPointerMove={(event: React.PointerEvent<HTMLElement>) => {
        const rect = event.currentTarget.getBoundingClientRect()
        event.currentTarget.style.setProperty("--pointer-x", `${event.clientX - rect.left}px`)
        event.currentTarget.style.setProperty("--pointer-y", `${event.clientY - rect.top}px`)
        onPointerMove?.(event)
      }}
      {...props}
    />
  )
}
