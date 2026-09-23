import { ArrowDownRight, ArrowUpRight, Minus } from "lucide-react"

import { changeDirection, formatPercent } from "@/lib/market"
import { cn } from "@/lib/utils"

/**
 * Badge % biến động.
 *
 * Không tự chọn xanh/đỏ mà đi qua `--price-rise` / `--price-fall`, nên đổi quy
 * ước thị trường (xem `src/index.css`) là badge đổi theo, không phải sửa ở đây.
 *
 * Mũi tên `aria-hidden` còn chiều tăng/giảm thì viết thành chữ trong `sr-only`:
 * người dùng screen reader không đọc được màu, mà ở quy ước Đông Á thì màu đỏ
 * lại là *tăng* — suy từ màu ra nghĩa là sai.
 */
export function PriceChange({ value, className }: { value: number; className?: string }) {
  const flat = value === 0
  const rising = value > 0
  const Icon = flat ? Minus : rising ? ArrowUpRight : ArrowDownRight

  return (
    <span
      data-slot="price-change"
      className={cn(
        "inline-flex w-fit items-center gap-1 rounded-md border px-1.5 py-0.5 text-xs font-medium tabular-nums",
        // Không tô nền cho 0%: chữ muted trên nền muted chỉ đạt 4.35:1.
        flat && "border-border text-muted-foreground",
        !flat && rising && "border-price-rise/25 bg-price-rise/10 text-price-rise",
        !flat && !rising && "border-price-fall/25 bg-price-fall/10 text-price-fall",
        className,
      )}
    >
      <Icon className="size-3 shrink-0" aria-hidden />
      <span className="sr-only">{changeDirection(value)} </span>
      {formatPercent(value)}
    </span>
  )
}
