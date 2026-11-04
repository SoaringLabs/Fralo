import * as React from "react"
import { cva, type VariantProps } from "class-variance-authority"
import { cn } from "cn"
import { Slot } from "radix-ui"

// shadcn/ui button, retuned to macOS proportions: press shrinks slightly, focus uses the
// system-blue ring offset from the surface, and hover/press step through semantic fills.
const buttonVariants = cva(
  "inline-flex shrink-0 cursor-pointer items-center justify-center gap-2 font-semibold whitespace-nowrap select-none outline-none transition-[background-color,box-shadow,color,transform] duration-150 ease-out active:scale-[0.97] focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:pointer-events-none disabled:opacity-50 aria-disabled:pointer-events-none aria-disabled:opacity-60 motion-reduce:transition-none motion-reduce:active:scale-100 [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg]:transition-transform [&_svg]:duration-200 [&_svg:not([class*='size-'])]:size-4",
  {
    variants: {
      variant: {
        default:
          "bg-primary text-primary-foreground shadow-[inset_0_1px_0_rgb(255_255_255/20%),0_1px_2px_rgb(6_50_110/28%)] hover:bg-[#0b63c9] active:bg-[#0956af] active:shadow-[inset_0_1px_2px_rgb(0_0_0/18%)]",
        outline:
          "bg-background text-foreground shadow-[inset_0_0_0_1px_var(--border),0_1px_2px_rgb(0_0_0/5%)] hover:bg-accent active:bg-press",
        ghost: "text-foreground hover:bg-hover active:bg-press",
        invert:
          "bg-foreground text-background hover:bg-[color-mix(in_srgb,var(--foreground)_86%,var(--background))] active:bg-[color-mix(in_srgb,var(--foreground)_76%,var(--background))]",
        link: "text-primary underline-offset-4 hover:underline active:scale-100",
      },
      size: {
        sm: "h-8 gap-1.5 rounded-lg px-3 text-[13px] has-[>svg]:px-2.5",
        default: "h-[38px] rounded-[10px] px-4 text-sm has-[>svg]:px-3.5",
        lg: "h-[46px] rounded-xl px-5 text-base [&_svg:not([class*='size-'])]:size-[17px]",
        "icon-sm": "size-8 rounded-lg",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  }
)

function Button({
  className,
  variant = "default",
  size = "default",
  asChild = false,
  ...props
}: React.ComponentProps<"button"> &
  VariantProps<typeof buttonVariants> & {
    asChild?: boolean
  }) {
  const Comp = asChild ? Slot.Root : "button"

  return (
    <Comp
      data-slot="button"
      data-variant={variant}
      data-size={size}
      className={cn(buttonVariants({ variant, size, className }))}
      {...props}
    />
  )
}

export { Button, buttonVariants }
