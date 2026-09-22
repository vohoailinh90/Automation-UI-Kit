import { cn } from "@/lib/utils"

/**
 * Đường xu hướng thu nhỏ vẽ bằng SVG thuần — không kéo thêm thư viện chart cho
 * một hình 64×20.
 *
 * `aria-hidden` là cố ý: sparkline luôn đứng cạnh cột % đã nói đúng con số, nên
 * để screen reader đọc thêm một lần nữa chỉ làm bảng dài ra mà không thêm thông
 * tin. Dùng nó một mình ở chỗ khác thì phải bọc nhãn riêng.
 */
export function Sparkline({
  values,
  width = 64,
  height = 20,
  className,
}: {
  values: number[]
  width?: number
  height?: number
  className?: string
}) {
  if (values.length < 2) return null

  const min = Math.min(...values)
  const max = Math.max(...values)
  // Chuỗi phẳng hoàn toàn thì range = 0; chia cho 0 sẽ ra NaN và mất luôn đường.
  const range = max - min || 1
  const stepX = width / (values.length - 1)

  const points = values
    .map((v, i) => {
      const x = i * stepX
      // SVG có trục y hướng xuống, nên giá cao phải ra y nhỏ.
      const y = height - ((v - min) / range) * height
      return `${x.toFixed(2)},${y.toFixed(2)}`
    })
    .join(" ")

  const rising = values[values.length - 1] >= values[0]

  return (
    <svg
      data-slot="sparkline"
      viewBox={`0 0 ${width} ${height}`}
      width={width}
      height={height}
      className={cn("overflow-visible", rising ? "text-price-rise" : "text-price-fall", className)}
      aria-hidden
      focusable="false"
    >
      <polyline
        points={points}
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
