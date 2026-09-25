import * as React from "react"

import { cn } from "@/lib/utils"

/**
 * Vòng tiến độ — kiểu ProgressCircle của Tremor. Hợp cho một tỉ lệ đứng một
 * mình: tỉ lệ thành công, % giao đúng hạn.
 *
 * Nội dung ở giữa (`children`) là HTML thật đặt đè lên SVG, không phải `<text>`
 * trong SVG: vừa đọc được bằng screen reader, vừa ăn theo font/màu của trang.
 * Vì con số đã là chữ, vòng SVG chỉ còn là phần nhìn (`aria-hidden`).
 */
export function ProgressRing({
  value,
  max = 100,
  size = 120,
  strokeWidth = 10,
  indicatorClassName = "text-success-fill",
  className,
  children,
}: {
  value: number
  max?: number
  /** Đường kính, px. */
  size?: number
  strokeWidth?: number
  /** Màu vòng, dạng class `text-*`. */
  indicatorClassName?: string
  className?: string
  children?: React.ReactNode
}) {
  const radius = (size - strokeWidth) / 2
  const circumference = 2 * Math.PI * radius
  // Kẹp về [0, 1]: giá trị vượt max mà vẽ tiếp thì vòng quấn qua điểm đầu và
  // trông như đang ở mức thấp.
  const ratio = max > 0 ? Math.min(1, Math.max(0, value / max)) : 0

  return (
    <div
      data-slot="progress-ring"
      className={cn("relative inline-flex items-center justify-center", className)}
      style={{ width: size, height: size }}
    >
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className="-rotate-90" aria-hidden focusable="false">
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          fill="none"
          strokeWidth={strokeWidth}
          className="stroke-muted"
        />
        <circle
          data-slot="progress-ring-indicator"
          cx={size / 2}
          cy={size / 2}
          r={radius}
          fill="none"
          stroke="currentColor"
          strokeWidth={strokeWidth}
          strokeLinecap={ratio > 0 ? "round" : "butt"}
          strokeDasharray={circumference}
          strokeDashoffset={circumference * (1 - ratio)}
          className={cn("transition-[stroke-dashoffset] duration-500 motion-reduce:transition-none", indicatorClassName)}
        />
      </svg>
      {children && <div className="absolute inset-0 flex flex-col items-center justify-center text-center">{children}</div>}
    </div>
  )
}
