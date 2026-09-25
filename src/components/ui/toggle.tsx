import * as TogglePrimitive from "@radix-ui/react-toggle"
import { cva, type VariantProps } from "class-variance-authority"
import * as React from "react"

import { cn } from "@/lib/utils"

/**
 * Theo API của shadcn/ui (new-york-v4), khác upstream ở ba chỗ, đều vì a11y:
 *
 * - Vòng focus đặc có offset như `Button`, thay cho `ring-ring/50` — bản mờ chỉ
 *   đạt ~1.5:1, gần như không thấy đang focus ở đâu.
 * - Hover đổi nền sang `muted` nhưng **giữ chữ đậm**: upstream đổi luôn chữ sang
 *   `muted-foreground`, mà chữ đó trên nền `muted` chỉ đạt 4.34:1.
 * - Trạng thái bật dùng `primary` đặc thay cho `accent`: nền `accent` chỉ lệch
 *   nền trắng ~1.1:1, nên nhìn không ra nút nào đang được chọn (WCAG 1.4.11 cần
 *   ≥ 3:1 cho chỉ báo trạng thái). Hover lên nút đang bật phải khai riêng
 *   (`data-[state=on]:hover:`): `hover:bg-muted` và `data-[state=on]:bg-primary`
 *   cùng độ ưu tiên CSS, lỡ hover thắng là chữ trắng nằm trên nền xám nhạt.
 */
const toggleVariants = cva(
  "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm font-medium transition-colors outline-none hover:bg-muted focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:pointer-events-none disabled:opacity-50 data-[state=on]:bg-primary data-[state=on]:text-primary-foreground data-[state=on]:hover:bg-primary/90 [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4",
  {
    variants: {
      variant: {
        default: "bg-transparent",
        outline: "border border-input bg-transparent shadow-xs",
      },
      size: {
        default: "h-9 min-w-9 px-2",
        sm: "h-8 min-w-8 px-1.5",
        lg: "h-10 min-w-10 px-2.5",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  },
)

function Toggle({
  className,
  variant,
  size,
  ...props
}: React.ComponentProps<typeof TogglePrimitive.Root> & VariantProps<typeof toggleVariants>) {
  return (
    <TogglePrimitive.Root
      data-slot="toggle"
      className={cn(toggleVariants({ variant, size, className }))}
      {...props}
    />
  )
}

export { Toggle, toggleVariants }
