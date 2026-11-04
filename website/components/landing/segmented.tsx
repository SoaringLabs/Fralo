"use client"

import { cn } from "cn"

/** macOS segmented control: one selection pill that slides between equal segments. */
export function Segmented<T extends string>({
  label,
  options,
  value,
  onChange,
  className,
  itemClassName,
}: {
  label: string
  options: readonly { value: T; title: string }[]
  value: T
  onChange: (value: T) => void
  className?: string
  itemClassName?: string
}) {
  const index = Math.max(0, options.findIndex((option) => option.value === value))
  const count = options.length
  return (
    <div
      role="radiogroup"
      aria-label={label}
      className={cn("relative grid rounded-[10px] bg-segment p-0.5", className)}
      style={{ gridTemplateColumns: `repeat(${count}, minmax(0, 1fr))` }}
    >
      <span
        aria-hidden="true"
        className="absolute inset-y-0.5 left-0.5 rounded-[8px] bg-background shadow-[0_1px_2px_rgb(0_0_0/14%),0_0_0_0.5px_rgb(0_0_0/6%)] transition-transform duration-300 ease-[cubic-bezier(0.2,0.9,0.3,1.1)] motion-reduce:transition-none dark:bg-[#636366]"
        style={{ width: `calc((100% - 4px) / ${count})`, transform: `translateX(${index * 100}%)` }}
      />
      {options.map((option) => {
        const selected = option.value === value
        return (
          <button
            key={option.value}
            type="button"
            role="radio"
            aria-checked={selected}
            onClick={() => onChange(option.value)}
            className={cn(
              "relative min-h-7 cursor-pointer rounded-[8px] px-2.5 text-[12.5px] font-medium whitespace-nowrap outline-none transition-colors duration-200 focus-visible:ring-2 focus-visible:ring-ring",
              !selected && "hover:bg-hover",
              itemClassName
            )}
          >
            {option.title}
          </button>
        )
      })}
    </div>
  )
}
