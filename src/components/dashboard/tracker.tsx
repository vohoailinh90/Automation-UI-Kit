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
 * Hai trạng thái **tách rời**: vị trí đọc bằng phím (`cursor`) chỉ phím mới đổi
 * được, còn ô dưới con trỏ chuột (`hover`) chỉ là xem tạm. Gộp làm một thì chuột
 * lướt qua — trên dải này hay dải khác — là người dùng bàn phím mất chỗ đang
 * đọc, và `aria-valuetext` nhảy về ô mới nhất trong khi readout nói ô khác.
 * Chưa đọc ô nào thì slider báo ô mới nhất.
 *
 * Cha nghe hai callback để nhiều tracker dùng chung một readout — xem trang
 * Automation: có ô dưới con trỏ thì readout theo chuột, không thì theo dải đang
 * được đọc bằng phím.
 */
export function Tracker({
  blocks,
  label,
  onCursorChange,
  onHoverChange,
  className,
}: {
  blocks: TrackerBlock[]
  /** Tên của cả dải, ví dụ `"Excel → Planner, 30 ngày gần nhất"`. */
  label: string
  /** Ô đang đọc bằng bàn phím; `null` khi dải mất focus. */
  onCursorChange?: (index: number | null) => void
  /** Ô dưới con trỏ chuột; `null` khi chuột rời dải. */
  onHoverChange?: (index: number | null) => void
  className?: string
}) {
  const [cursor, setCursor] = React.useState<number | null>(null)
  const [hover, setHover] = React.useState<number | null>(null)
  const last = blocks.length - 1
  const clamp = (index: number) => Math.min(last, Math.max(0, index))
  // Kẹp khi đọc chứ không tin chỉ số đã lưu: `blocks` có thể ngắn đi giữa hai
  // lần render (đổi khoảng thời gian, dữ liệu mới).
  const position = cursor === null ? last : clamp(cursor)
  const shown = hover !== null && hover <= last ? hover : cursor === null ? null : position

  function moveCursor(next: number | null) {
    setCursor(next)
    onCursorChange?.(next)
  }

  function hoverAt(next: number | null) {
    setHover(next)
    onHoverChange?.(next)
  }

  function handleKeyDown(event: React.KeyboardEvent<HTMLDivElement>) {
    const keys: Record<string, number> = {
      ArrowLeft: position - 1,
      ArrowDown: position - 1,
      ArrowRight: position + 1,
      ArrowUp: position + 1,
      PageDown: position - 7,
      PageUp: position + 7,
      Home: 0,
      End: last,
    }
    if (!(event.key in keys)) return
    event.preventDefault()
    moveCursor(clamp(keys[event.key]))
  }

  if (blocks.length === 0) return null

  return (
    <div
      role="slider"
      tabIndex={0}
      aria-label={`${label}: ${summarizeTracker(blocks)}`}
      aria-valuemin={0}
      aria-valuemax={last}
      aria-valuenow={position}
      aria-valuetext={blocks[position].label}
      aria-orientation="horizontal"
      data-slot="tracker"
      onKeyDown={handleKeyDown}
      onFocus={() => moveCursor(position)}
      onBlur={() => moveCursor(null)}
      onPointerLeave={() => hoverAt(null)}
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
          data-active={index === shown || undefined}
          onPointerEnter={() => hoverAt(index)}
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
