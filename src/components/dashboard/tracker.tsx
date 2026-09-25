import * as React from "react"

import { cn } from "@/lib/utils"

export type TrackerStatus = "success" | "warning" | "failed" | "idle"

export type TrackerBlock = {
  key: string
  status: TrackerStatus
  /** Mô tả đầy đủ của ô, ví dụ `"17/09 · 24 lượt · 1 lỗi"` — hiện ở readout. */
  label: string
}

/**
 * Màu từng trạng thái. Ô tracker là **mảng màu mang thông tin** nên cần ≥ 3:1 so
 * với nền card (WCAG 1.4.11) — `--success`, `--warning`, `--destructive` đều
 * đạt ở cả hai theme. `idle` (không có lượt chạy) cố ý nhạt: nó nói "không có
 * dữ liệu", không phải một trạng thái cần phân biệt với ba cái còn lại.
 */
const trackerStatusClass: Record<TrackerStatus, string> = {
  success: "bg-success-fill",
  warning: "bg-warning",
  failed: "bg-destructive",
  idle: "bg-muted-foreground/20",
}

const trackerStatusLabel: Record<TrackerStatus, string> = {
  success: "ổn",
  warning: "có cảnh báo",
  failed: "có lỗi",
  idle: "không chạy",
}

/** "28 ổn, 1 có cảnh báo, 1 có lỗi" — chỉ liệt kê trạng thái có mặt. */
function summarizeTracker(blocks: TrackerBlock[]) {
  const order: TrackerStatus[] = ["success", "warning", "failed", "idle"]
  return order
    .map((status) => [status, blocks.filter((b) => b.status === status).length] as const)
    .filter(([, count]) => count > 0)
    .map(([status, count]) => `${count} ${trackerStatusLabel[status]}`)
    .join(", ")
}

/**
 * Dải ô trạng thái theo thời gian (kiểu status page / Tremor Tracker), mỗi ô là
 * một mốc — một ngày, một lượt chạy.
 *
 * Tremor chỉ có tooltip khi hover, tức người dùng bàn phím không xem được từng
 * ô. Ở đây cả dải là **một** điểm dừng Tab với `role="slider"`: mũi tên trái/
 * phải đi từng ô, Home/End về đầu/cuối, PageUp/PageDown nhảy 7 ô. Screen reader
 * đọc `aria-valuetext` (mô tả ô đang trỏ) mỗi lần đổi, không cần vùng live.
 *
 * Ô đang trỏ do **cha** giữ (`activeIndex`) để nhiều tracker dùng chung một
 * readout — xem trang Automation. Chưa trỏ ô nào thì slider báo ô mới nhất.
 */
export function Tracker({
  blocks,
  label,
  activeIndex,
  onActiveIndexChange,
  className,
}: {
  blocks: TrackerBlock[]
  /** Tên của cả dải, ví dụ `"Excel → Planner, 30 ngày gần nhất"`. */
  label: string
  activeIndex: number | null
  onActiveIndexChange: (index: number | null) => void
  className?: string
}) {
  const rootRef = React.useRef<HTMLDivElement>(null)
  const last = blocks.length - 1
  const current = activeIndex ?? last

  function move(to: number) {
    onActiveIndexChange(Math.min(last, Math.max(0, to)))
  }

  function handleKeyDown(event: React.KeyboardEvent<HTMLDivElement>) {
    const keys: Record<string, number> = {
      ArrowLeft: current - 1,
      ArrowDown: current - 1,
      ArrowRight: current + 1,
      ArrowUp: current + 1,
      PageDown: current - 7,
      PageUp: current + 7,
      Home: 0,
      End: last,
    }
    if (!(event.key in keys)) return
    event.preventDefault()
    move(keys[event.key])
  }

  if (blocks.length === 0) return null

  return (
    <div
      ref={rootRef}
      role="slider"
      tabIndex={0}
      aria-label={`${label}: ${summarizeTracker(blocks)}`}
      aria-valuemin={0}
      aria-valuemax={last}
      aria-valuenow={current}
      aria-valuetext={blocks[current].label}
      aria-orientation="horizontal"
      data-slot="tracker"
      onKeyDown={handleKeyDown}
      onFocus={() => onActiveIndexChange(current)}
      onBlur={() => onActiveIndexChange(null)}
      // Rời chuột chỉ xoá ô đang trỏ khi dải **không** giữ focus: người đang đọc
      // bằng phím mũi tên mà chuột lỡ lướt qua rồi đi ra thì không được bị đẩy
      // về ô mới nhất giữa chừng. Focus rời đi (`onBlur`) mới là lúc xoá.
      onPointerLeave={() => {
        if (document.activeElement !== rootRef.current) onActiveIndexChange(null)
      }}
      className={cn(
        "flex h-8 w-full items-stretch gap-px rounded-sm outline-none",
        "focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-card",
        className,
      )}
    >
      {blocks.map((block, index) => (
        <div
          key={block.key}
          data-status={block.status}
          data-active={index === activeIndex || undefined}
          onPointerEnter={() => onActiveIndexChange(index)}
          className={cn(
            "min-w-0 flex-1 first:rounded-l-sm last:rounded-r-sm",
            trackerStatusClass[block.status],
            // Ô đang trỏ: viền đặc màu chữ, đủ tương phản trên mọi màu ô. Chỉ
            // hạ độ đậm các ô khác thì ô idle vốn đã nhạt sẽ gần như biến mất.
            "data-[active]:relative data-[active]:z-10 data-[active]:outline-2 data-[active]:outline-offset-1 data-[active]:outline-foreground",
          )}
        />
      ))}
    </div>
  )
}
