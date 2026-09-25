import { cn } from "@/lib/utils"

export type BarListItem = {
  /** Mặc định lấy `name`; truyền riêng khi hai dòng có thể trùng tên. */
  key?: string
  name: string
  value: number
}

/**
 * Danh sách thanh ngang có nhãn — kiểu BarList của Tremor: tên nằm **trên**
 * thanh, con số ở cột phải. Hợp cho "top N": lỗi hay gặp, đơn đang chờ ai...
 *
 * Là `<ul>` HTML thật, không phải chart: con số là chữ nên đọc được, chọn/copy
 * được, và thanh chỉ là phần nhìn (`aria-hidden`). Độ dài thanh so với **giá trị
 * lớn nhất** trong danh sách, không phải tổng — để dòng đầu luôn đầy.
 */
export function BarList({
  data,
  valueFormatter = (value) => value.toLocaleString("en-US"),
  sortOrder = "descending",
  barClassName = "bg-chart-2/20",
  className,
  "aria-label": ariaLabel,
}: {
  data: BarListItem[]
  valueFormatter?: (value: number) => string
  sortOrder?: "descending" | "ascending" | "none"
  /** Màu thanh, dạng class `bg-*`. Nên để nhạt: chữ nằm đè lên thanh. */
  barClassName?: string
  className?: string
  "aria-label"?: string
}) {
  const rows =
    sortOrder === "none"
      ? data
      : [...data].sort((a, b) => (sortOrder === "descending" ? b.value - a.value : a.value - b.value))
  const max = Math.max(0, ...rows.map((row) => row.value))

  return (
    <ul data-slot="bar-list" aria-label={ariaLabel} className={cn("flex flex-col gap-1.5", className)}>
      {rows.map((row) => {
        // Giá trị > 0 mà quá nhỏ thì vẫn chừa 2% để thấy là "có", khác hẳn 0.
        const width = max > 0 && row.value > 0 ? Math.max((row.value / max) * 100, 2) : 0
        return (
          <li key={row.key ?? row.name} className="flex items-center justify-between gap-4 text-sm">
            <div className="relative flex h-8 min-w-0 flex-1 items-center">
              <div
                aria-hidden
                data-slot="bar-list-bar"
                className={cn("absolute inset-y-0 left-0 rounded-sm", barClassName)}
                style={{ width: `${width}%` }}
              />
              <span className="relative truncate px-2">{row.name}</span>
            </div>
            <span className="shrink-0 font-medium tabular-nums">{valueFormatter(row.value)}</span>
          </li>
        )
      })}
    </ul>
  )
}
