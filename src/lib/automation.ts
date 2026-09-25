/**
 * Dữ liệu mẫu cho dashboard Automation: 30 ngày chạy của vài job tự động hoá.
 *
 * **Dữ liệu mẫu, tất định** (xem `src/lib/mock.ts`) — thay bằng log chạy thật
 * của repo đích khi copy dashboard sang. Hình dạng dữ liệu (`Run`, `DayStat`)
 * mới là thứ đáng giữ.
 *
 * Mọi con số trên trang đều **dẫn xuất từ một danh sách lượt chạy duy nhất**
 * (`runs`), không có bảng tổng hợp nào được bịa riêng. Nhờ vậy ô tracker hôm
 * nay đỏ thì chắc chắn bảng "lượt chạy gần nhất" có dòng lỗi tương ứng, và KPI
 * cộng lại khớp với biểu đồ — hai nguồn số liệu tách rời thì sớm muộn sẽ lệch.
 */

import { formatShortDate, mockDay, randomFor } from "@/lib/mock"

export type RunStatus = "success" | "warning" | "failed"

export type ErrorKind = "graph-token" | "file-locked" | "proxy-timeout" | "schema" | "rate-limit"

export const errorLabel: Record<ErrorKind, string> = {
  "graph-token": "Token Microsoft Graph hết hạn",
  "file-locked": "File Excel đang mở ở máy khác",
  "proxy-timeout": "Timeout qua proxy công ty",
  schema: "Thiếu cột bắt buộc trong file nguồn",
  "rate-limit": "Bị giới hạn tần suất API",
}

export const runStatusLabel: Record<RunStatus, string> = {
  success: "Thành công",
  warning: "Cảnh báo",
  failed: "Lỗi",
}

export type Job = {
  id: string
  name: string
  /** Mô tả lịch chạy cho người đọc. */
  schedule: string
  /** Giờ chạy trong ngày, tính bằng phút từ 00:00. */
  times: number[]
  weekdaysOnly: boolean
  /** Thời gian chạy điển hình, giây. */
  typicalSeconds: number
  /** Xác suất nền mỗi lượt: lỗi lặt vặt và cảnh báo (chạy chậm, bỏ qua dòng). */
  failRate: number
  warnRate: number
}

/** Các mốc `offset`, `offset + step`... còn nằm trong ngày (< 24:00). */
const everyMinutes = (step: number, offset = 0) =>
  Array.from({ length: Math.ceil((1440 - offset) / step) }, (_, i) => offset + i * step)

export const jobs: Job[] = [
  { id: "email-triage", name: "Phân loại email", schedule: "15 phút/lần", times: everyMinutes(15), weekdaysOnly: false, typicalSeconds: 18, failRate: 0.002, warnRate: 0.02 },
  { id: "planner-sync", name: "Excel → Planner", schedule: "Mỗi giờ, phút 05", times: everyMinutes(60, 5), weekdaysOnly: false, typicalSeconds: 42, failRate: 0.004, warnRate: 0.03 },
  { id: "doc-sync", name: "Đồng bộ tài liệu khách hàng", schedule: "06:00 hằng ngày", times: [360], weekdaysOnly: false, typicalSeconds: 312, failRate: 0, warnRate: 0.08 },
  { id: "market-brief", name: "Báo cáo thị trường sáng", schedule: "07:00, thứ 2–6", times: [420], weekdaysOnly: true, typicalSeconds: 95, failRate: 0, warnRate: 0.05 },
  { id: "order-reminder", name: "Nhắc hạn đơn thử nghiệm", schedule: "08:30, thứ 2–6", times: [510], weekdaysOnly: true, typicalSeconds: 7, failRate: 0, warnRate: 0 },
]

export type Run = {
  jobId: string
  /** Số ngày trước `MOCK_TODAY` (0 = hôm nay). */
  daysAgo: number
  /** Phút kể từ 00:00 của ngày đó. */
  minute: number
  status: RunStatus
  seconds: number
  trigger: "schedule" | "manual"
  error?: ErrorKind
}

/** Số ngày lịch sử. */
export const HISTORY_DAYS = 30

/** "Bây giờ" của dữ liệu mẫu: 09:10 ngày `MOCK_TODAY` — hôm nay mới chạy tới đây. */
export const NOW_MINUTE = 9 * 60 + 10

type Incident = {
  jobId: string
  daysAgo: number
  /** Khoảng phút (bao cả hai đầu) mà mọi lượt chạy trong đó đều lỗi. */
  from: number
  to: number
  error: ErrorKind
  /** Chạy lại tay sau sự cố, `minutesAfter` phút sau lượt lỗi cuối. */
  manualRetryAfter?: number
}

/**
 * Sự cố cố ý, để dashboard có chuyện để kể: một đêm token Graph hết hạn kéo đổ
 * hai job cùng lúc, một buổi chiều file Excel bị khoá, một sáng proxy chậm làm
 * báo cáo thị trường phải chạy lại tay — và **hôm nay** Excel → Planner vừa lỗi
 * lúc 08:05, nên ô cuối của nó đỏ và bảng lượt chạy gần nhất có dòng lỗi.
 */
const incidents: Incident[] = [
  { jobId: "email-triage", daysAgo: 22, from: 120, to: 345, error: "graph-token" },
  { jobId: "planner-sync", daysAgo: 22, from: 125, to: 305, error: "graph-token", manualRetryAfter: 25 },
  { jobId: "planner-sync", daysAgo: 9, from: 785, to: 905, error: "file-locked" },
  { jobId: "market-brief", daysAgo: 3, from: 420, to: 420, error: "proxy-timeout", manualRetryAfter: 20 },
  { jobId: "planner-sync", daysAgo: 0, from: 485, to: 485, error: "schema" },
]

function isWeekend(daysAgo: number) {
  const weekday = new Date(mockDay(daysAgo) * 1000).getUTCDay()
  return weekday === 0 || weekday === 6
}

function simulate(): Run[] {
  const out: Run[] = []
  for (const job of jobs) {
    // Mỗi job một seed riêng: thêm hay bớt một job không xáo số liệu job khác.
    const rand = randomFor(`automation:${job.id}`)
    for (let daysAgo = HISTORY_DAYS - 1; daysAgo >= 0; daysAgo -= 1) {
      if (job.weekdaysOnly && isWeekend(daysAgo)) continue
      for (const minute of job.times) {
        if (daysAgo === 0 && minute > NOW_MINUTE) break
        // Rút đủ ba số cho mọi lượt, kể cả lượt bị sự cố ghi đè bên dưới: giữ
        // nguyên số lần gọi `rand` thì thêm một sự cố không xáo phần còn lại.
        const roll = rand()
        const speed = 0.7 + rand() * 0.6
        const pick = rand()
        const incident = incidents.find(
          (i) => i.jobId === job.id && i.daysAgo === daysAgo && minute >= i.from && minute <= i.to,
        )
        let run: Run
        if (incident) {
          run = { jobId: job.id, daysAgo, minute, status: "failed", seconds: Math.round(job.typicalSeconds * 0.4), trigger: "schedule", error: incident.error }
        } else if (roll < job.failRate) {
          const error: ErrorKind = pick < 0.5 ? "proxy-timeout" : "rate-limit"
          run = { jobId: job.id, daysAgo, minute, status: "failed", seconds: Math.round(job.typicalSeconds * speed), trigger: "schedule", error }
        } else if (roll < job.failRate + job.warnRate) {
          // Cảnh báo = chạy xong nhưng chậm bất thường (hoặc phải bỏ qua dòng hỏng).
          run = { jobId: job.id, daysAgo, minute, status: "warning", seconds: Math.round(job.typicalSeconds * (2 + speed)), trigger: "schedule" }
        } else {
          run = { jobId: job.id, daysAgo, minute, status: "success", seconds: Math.round(job.typicalSeconds * speed), trigger: "schedule" }
        }
        out.push(run)
      }
    }
    for (const incident of incidents.filter((i) => i.jobId === job.id && i.manualRetryAfter)) {
      const minute = incident.to + (incident.manualRetryAfter ?? 0)
      if (incident.daysAgo === 0 && minute > NOW_MINUTE) continue
      out.push({ jobId: job.id, daysAgo: incident.daysAgo, minute, status: "success", seconds: job.typicalSeconds, trigger: "manual" })
    }
  }
  // Cũ → mới.
  return out.sort((a, b) => b.daysAgo - a.daysAgo || a.minute - b.minute)
}

/** Toàn bộ lượt chạy, cũ → mới. Mọi tổng hợp bên dưới đều tính từ đây. */
export const runs: Run[] = simulate()

export function jobOf(id: string) {
  return jobs.find((j) => j.id === id)
}

export type DayStat = {
  daysAgo: number
  /** Unix timestamp 00:00 UTC của ngày, cho formatter. */
  day: number
  label: string
  success: number
  warning: number
  failed: number
  total: number
  seconds: number
}

function emptyDay(daysAgo: number): DayStat {
  const day = mockDay(daysAgo)
  return { daysAgo, day, label: formatShortDate(day), success: 0, warning: 0, failed: 0, total: 0, seconds: 0 }
}

/** Gom lượt chạy theo ngày, cũ → mới, đủ `HISTORY_DAYS` ngày kể cả ngày trống. */
export function dailyStats(jobId?: string): DayStat[] {
  const days = Array.from({ length: HISTORY_DAYS }, (_, i) => emptyDay(HISTORY_DAYS - 1 - i))
  for (const run of runs) {
    if (jobId && run.jobId !== jobId) continue
    const stat = days[HISTORY_DAYS - 1 - run.daysAgo]
    stat[run.status] += 1
    stat.total += 1
    stat.seconds += run.seconds
  }
  return days
}

/**
 * Tỉ lệ lượt cảnh báo tối thiểu để cả ngày bị tô là "cảnh báo".
 *
 * Không đặt "có một cảnh báo là vàng": job chạy 15 phút/lần có 96 lượt mỗi
 * ngày, lỡ một hai lượt chậm là chuyện thường — tô vàng cả ngày thì dải tracker
 * lúc nào cũng vàng và màu vàng mất hết nghĩa. Lỗi thì khác: một lượt lỗi là đủ
 * đỏ, vì lỗi nghĩa là có việc **không được làm**.
 */
export const WARNING_SHARE = 0.1

export function dayStatus(stat: DayStat): "success" | "warning" | "failed" | "idle" {
  if (stat.total === 0) return "idle"
  if (stat.failed > 0) return "failed"
  if (stat.warning / stat.total >= WARNING_SHARE) return "warning"
  return "success"
}

/** Bao nhiêu phút trước "bây giờ" (`NOW_MINUTE` của hôm nay). */
function minutesAgo(run: Run) {
  return run.daysAgo * 1440 + (NOW_MINUTE - run.minute)
}

/**
 * Tổng hợp một **cửa sổ trượt** `days` × 24 giờ, lùi `offsetDays` ngày tính từ
 * bây giờ: `window(7)` là 7×24h vừa qua, `window(7, 7)` là 7×24h trước đó.
 *
 * Cố ý không cắt theo ngày lịch: hôm nay mới chạy tới 09:10, nên "7 ngày lịch
 * gần nhất" chỉ có 6 ngày và vài giờ — đem so với 7 ngày đủ của tuần trước thì
 * số lượt chạy lúc nào cũng "giảm" mà chẳng có gì giảm cả.
 */
export function summarizeWindow(days: number, offsetDays = 0) {
  const from = offsetDays * 1440
  const to = (offsetDays + days) * 1440
  const inRange = runs.filter((r) => minutesAgo(r) >= from && minutesAgo(r) < to)
  const total = inRange.length
  const success = inRange.filter((r) => r.status === "success").length
  const warning = inRange.filter((r) => r.status === "warning").length
  const failed = inRange.filter((r) => r.status === "failed").length
  const seconds = inRange.reduce((sum, r) => sum + r.seconds, 0)
  return {
    total,
    success,
    warning,
    failed,
    /** Tỉ lệ lượt **không lỗi** (thành công + cảnh báo đều là chạy xong). */
    completionRate: total > 0 ? (success + warning) / total : 0,
    avgSeconds: total > 0 ? seconds / total : 0,
  }
}

/** Số lỗi theo loại trong `days` ngày gần nhất, nhiều → ít. */
export function errorBreakdown(days = HISTORY_DAYS) {
  const counts = new Map<ErrorKind, number>()
  for (const run of runs) {
    if (run.daysAgo >= days || !run.error) continue
    counts.set(run.error, (counts.get(run.error) ?? 0) + 1)
  }
  return [...counts.entries()]
    .map(([kind, count]) => ({ kind, label: errorLabel[kind], count }))
    .sort((a, b) => b.count - a.count)
}

/** `count` lượt chạy mới nhất, mới → cũ. */
export function latestRuns(count: number) {
  return runs.slice(-count).reverse()
}

/** Lượt chạy mới nhất của một job. */
export function lastRunOf(jobId: string) {
  for (let i = runs.length - 1; i >= 0; i -= 1) if (runs[i].jobId === jobId) return runs[i]
  return undefined
}

export function formatMinute(minute: number) {
  const h = Math.floor(minute / 60)
  const m = minute % 60
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`
}

export function formatDuration(seconds: number) {
  if (seconds < 60) return `${Math.round(seconds)} giây`
  const m = Math.floor(seconds / 60)
  const s = Math.round(seconds % 60)
  return s === 0 ? `${m} phút` : `${m} phút ${s} giây`
}
