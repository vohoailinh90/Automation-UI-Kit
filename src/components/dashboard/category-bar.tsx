import { cn } from "@/lib/utils"

export type CategorySegment = {
  key: string
  label: string
  value: number
  /** Màu đoạn và ô màu ở chú giải, dạng class `bg-*`. */
  className: string
}

// Một chữ số lẻ: 2 lượt lỗi trên 858 làm tròn thành "0%" là nói sai — có lỗi mà.
const percent = new Intl.NumberFormat("en-US", { style: "percent", maximumFractionDigits: 1 })

/**
 * Thanh phân đoạn theo tỉ lệ + chú giải có số — kiểu CategoryBar của Tremor.
 * Hợp cho "phân bố": đơn theo trạng thái, lượt chạy theo kết quả...
 *
 * Thanh là `aria-hidden`; mọi thông tin nằm ở chú giải bằng chữ (nhãn, số, %),
 * nên không có chỗ nào **chỉ** nói bằng màu (WCAG 1.4.1). Đoạn bằng 0 không vẽ
 * lên thanh nhưng vẫn giữ trong chú giải — "0 đơn trễ" cũng là thông tin.
 */
export function CategoryBar({
  segments,
  valueFormatter = (value) => value.toLocaleString("en-US"),
  className,
  "aria-label": ariaLabel,
}: {
  segments: CategorySegment[]
  valueFormatter?: (value: number) => string
  className?: string
  "aria-label"?: string
}) {
  const total = segments.reduce((sum, s) => sum + s.value, 0)

  return (
    // `@container`: chú giải chia cột theo bề rộng của **chính component**, không
    // theo màn hình — cùng một CategoryBar nằm trong card hẹp hay card rộng đều
    // không bị cắt chữ.
    <div data-slot="category-bar" className={cn("@container flex flex-col gap-3", className)}>
      <div aria-hidden className="flex h-2.5 w-full gap-0.5 overflow-hidden rounded-full bg-muted">
        {segments
          .filter((s) => s.value > 0)
          .map((s) => (
            // `flex-grow` theo giá trị thay vì `width: %` để phần hở giữa các
            // đoạn không làm tổng vượt 100% và đẩy đoạn cuối ra ngoài.
            <div key={s.key} data-key={s.key} className={cn("min-w-1", s.className)} style={{ flex: `${s.value} 1 0%` }} />
          ))}
      </div>
      <ul aria-label={ariaLabel} className="grid grid-cols-1 gap-x-6 gap-y-2 text-sm @sm:grid-cols-2 @xl:grid-cols-3">
        {segments.map((s) => (
          <li key={s.key} data-key={s.key} className="flex min-w-0 items-center gap-2">
            <span aria-hidden className={cn("size-2.5 shrink-0 rounded-[3px]", s.className)} />
            <span className="truncate text-muted-foreground">{s.label}</span>
            <span className="ml-auto font-medium tabular-nums">
              {valueFormatter(s.value)}{" "}
              {/* Dấu cách thật, không phải margin: margin chỉ là khoảng trống lúc
                  vẽ, screen reader vẫn đọc "2" và "0.2%" liền nhau thành "20.2%". */}
              <span className="text-xs font-normal text-muted-foreground">
                {total > 0 ? percent.format(s.value / total) : "–"}
              </span>
            </span>
          </li>
        ))}
      </ul>
    </div>
  )
}
