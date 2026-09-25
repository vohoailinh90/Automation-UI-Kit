import { ArrowDownRight, ArrowUpRight, Minus, type LucideIcon } from "lucide-react"
import * as React from "react"

import { Card, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card"
import { cn } from "@/lib/utils"

export type KpiDelta = {
  /** Đã format sẵn, ví dụ `"+8.2%"`, `"−6 giây"`. */
  value: string
  /** Chiều của con số — quyết định **mũi tên** và chữ đọc cho screen reader. */
  direction: "up" | "down" | "flat"
  /**
   * Tốt hay xấu — quyết định **màu**, và cố ý tách khỏi `direction`: thời gian
   * chạy giảm là tốt, số lỗi tăng là xấu. Gộp hai thứ làm một là lỗi kinh điển
   * của dashboard (mọi mũi tên xuống đều đỏ, kể cả khi đó là tin tốt).
   *
   * `market` = tô theo quy ước giá (`--price-rise` / `--price-fall`), dùng cho
   * lãi/lỗ để ăn theo `data-price-convention` như badge ở Watchlist.
   */
  tone: "good" | "bad" | "neutral" | "market"
}

const directionIcon = { up: ArrowUpRight, down: ArrowDownRight, flat: Minus } as const
const directionWord = { up: "tăng", down: "giảm", flat: "không đổi" } as const

/**
 * Màu badge theo tone. Chữ màu nằm trên nền 10% của chính màu đó — ca khó nhất
 * về tương phản; các token trong `src/index.css` đã được chỉnh để ca này đạt
 * ≥ 4.5:1 ở cả hai theme (xem chú thích ở `--success` / `--destructive`).
 */
function toneClass(delta: KpiDelta) {
  if (delta.direction === "flat" || delta.tone === "neutral") return "border-border text-muted-foreground"
  if (delta.tone === "good") return "border-success/25 bg-success/10 text-success"
  if (delta.tone === "bad") return "border-destructive/25 bg-destructive/10 text-destructive"
  return delta.direction === "up"
    ? "border-price-rise/25 bg-price-rise/10 text-price-rise"
    : "border-price-fall/25 bg-price-fall/10 text-price-fall"
}

/**
 * Badge biến động của KPI. Mũi tên chỉ để nhìn; chiều được viết thành chữ trong
 * `sr-only` vì screen reader không đọc được màu hay hình mũi tên.
 */
export function KpiDeltaBadge({ delta, className }: { delta: KpiDelta; className?: string }) {
  const Icon = directionIcon[delta.direction]
  return (
    <span
      data-slot="kpi-delta"
      data-tone={delta.tone}
      data-direction={delta.direction}
      className={cn(
        "inline-flex w-fit items-center gap-1 rounded-md border px-1.5 py-0.5 text-xs font-medium tabular-nums",
        toneClass(delta),
        className,
      )}
    >
      <Icon className="size-3 shrink-0" aria-hidden />
      <span className="sr-only">{directionWord[delta.direction]} </span>
      {delta.value}
    </span>
  )
}

/**
 * Vùng xu hướng thu nhỏ ở đáy card, SVG thuần (không kéo Recharts vào cho một
 * hình 40px). Tô bằng `currentColor`, nên màu do class của cha quyết định.
 *
 * `aria-hidden`: con số và badge phía trên đã nói đủ; đọc thêm một đường cong
 * không cho screen reader thêm thông tin gì.
 */
function TrendArea({ values, className }: { values: number[]; className?: string }) {
  const gradientId = `kpi-trend-${React.useId().replace(/[^a-zA-Z0-9_-]/g, "")}`
  if (values.length < 2) return null

  const width = 100
  const height = 32
  const min = Math.min(...values)
  const max = Math.max(...values)
  // Chuỗi phẳng thì range = 0; chia cho 0 ra NaN và mất luôn đường.
  const range = max - min || 1
  const step = width / (values.length - 1)
  // Chừa 2px trên đỉnh để nét 1.5px không bị cắt mất nửa.
  const y = (v: number) => 2 + (height - 2) * (1 - (v - min) / range)
  const line = values.map((v, i) => `${(i * step).toFixed(2)},${y(v).toFixed(2)}`).join(" ")

  return (
    <svg
      data-slot="kpi-trend"
      viewBox={`0 0 ${width} ${height}`}
      preserveAspectRatio="none"
      className={cn("h-10 w-full overflow-visible", className)}
      aria-hidden
      focusable="false"
    >
      <defs>
        <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="currentColor" stopOpacity={0.22} />
          <stop offset="100%" stopColor="currentColor" stopOpacity={0} />
        </linearGradient>
      </defs>
      <polygon points={`0,${height} ${line} ${width},${height}`} fill={`url(#${gradientId})`} />
      <polyline
        points={line}
        fill="none"
        stroke="currentColor"
        strokeWidth={1.5}
        strokeLinecap="round"
        strokeLinejoin="round"
        vectorEffect="non-scaling-stroke"
      />
    </svg>
  )
}

/**
 * Card KPI kiểu "section cards" của shadcn dashboard-01 + KPI card của Tremor:
 * nhãn, con số lớn, badge biến động ở góc, vùng xu hướng và dòng chú thích.
 *
 * Khác `StatCard` (card icon gọn cho trang tổng quan) ở chỗ tách **chiều** khỏi
 * **tốt/xấu** và có chỗ cho chuỗi xu hướng.
 */
export function KpiCard({
  label,
  value,
  delta,
  footnote,
  trend,
  trendClassName = "text-chart-2",
  icon: Icon,
  className,
}: {
  label: string
  /** Đã format sẵn — card không tự đoán đơn vị hay số chữ số thập phân. */
  value: string
  delta?: KpiDelta
  footnote?: React.ReactNode
  /** Chuỗi giá trị theo thời gian, cũ → mới. */
  trend?: number[]
  /** Màu vùng xu hướng, dạng class `text-*`. */
  trendClassName?: string
  icon?: LucideIcon
  className?: string
}) {
  return (
    <Card data-slot="kpi-card" className={cn("gap-3 overflow-hidden pb-0", !trend && "pb-6", className)}>
      <CardHeader className="gap-2">
        <CardDescription className="flex items-center gap-1.5">
          {Icon && <Icon className="size-3.5 shrink-0" aria-hidden />}
          {label}
        </CardDescription>
        {/* Badge nằm ngay sau con số (kiểu Tremor) chứ không ở góc phải như
            dashboard-01: card hẹp mà badge chiếm góc thì nhãn phải xuống dòng. */}
        <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
          <CardTitle className="text-2xl font-semibold tabular-nums tracking-tight">{value}</CardTitle>
          {delta && <KpiDeltaBadge delta={delta} />}
        </div>
      </CardHeader>
      {footnote && <CardFooter className="text-xs text-muted-foreground">{footnote}</CardFooter>}
      {trend && <TrendArea values={trend} className={cn("-mt-1", trendClassName)} />}
    </Card>
  )
}
