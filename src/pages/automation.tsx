import { Activity, AlertOctagon, CheckCircle2, Timer } from "lucide-react"
import * as React from "react"
import { Bar, BarChart, CartesianGrid, XAxis, YAxis } from "recharts"

import { BarList } from "@/components/dashboard/bar-list"
import { CategoryBar } from "@/components/dashboard/category-bar"
import { KpiCard, type KpiDelta } from "@/components/dashboard/kpi-card"
import { ProgressRing } from "@/components/dashboard/progress-ring"
import { StatusBadge, type StatusTone } from "@/components/dashboard/status-badge"
import { Tracker, type TrackerBlock } from "@/components/dashboard/tracker"
import { Badge } from "@/components/ui/badge"
import {
  Card,
  CardAction,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import {
  ChartContainer,
  ChartLegend,
  ChartLegendContent,
  ChartTooltip,
  ChartTooltipContent,
  type ChartConfig,
} from "@/components/ui/chart"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import {
  HISTORY_DAYS,
  NOW_MINUTE,
  dailyStats,
  dayStatus,
  errorBreakdown,
  formatDuration,
  formatMinute,
  jobOf,
  jobs,
  lastRunOf,
  latestRuns,
  runStatusLabel,
  summarizeWindow,
  type DayStat,
  type RunStatus,
} from "@/lib/automation"
import { MOCK_TODAY, formatShortDate, mockDay } from "@/lib/mock"

const integer = new Intl.NumberFormat("en-US")

const runTone: Record<RunStatus, StatusTone> = {
  success: "success",
  warning: "warning",
  failed: "failed",
}

/**
 * Màu chuỗi lấy từ token **trạng thái** chứ không phải `--chart-*`: xanh/vàng/
 * đỏ ở đây mang nghĩa thành công/cảnh báo/lỗi, và phải trùng màu với ô tracker
 * cùng trang — cùng một ý mà hai màu thì người xem phải học hai lần.
 */
const runsChartConfig = {
  success: { label: "Thành công", color: "var(--success-fill)" },
  warning: { label: "Cảnh báo", color: "var(--warning)" },
  failed: { label: "Lỗi", color: "var(--destructive)" },
} satisfies ChartConfig

const ranges = [
  { value: "7", label: "7 ngày" },
  { value: "14", label: "14 ngày" },
  { value: "30", label: "30 ngày" },
] as const

type Range = (typeof ranges)[number]["value"]

function isRange(value: string): value is Range {
  return ranges.some((r) => r.value === value)
}

/** Chiều + tone cho badge KPI từ hai con số. `higherIsBetter` null = trung tính. */
function deltaOf(current: number, previous: number, text: string, higherIsBetter: boolean | null): KpiDelta {
  const direction = current > previous ? "up" : current < previous ? "down" : "flat"
  const tone =
    higherIsBetter === null ? "neutral" : (direction === "up") === higherIsBetter ? "good" : "bad"
  return { value: text, direction, tone }
}

function signed(value: number, digits = 0) {
  const fixed = Math.abs(value).toFixed(digits)
  if (Number(fixed) === 0) return fixed
  return `${value > 0 ? "+" : "−"}${fixed}`
}

/** Nhãn một ô tracker — thứ screen reader đọc và readout hiện ra. */
function blockLabel(stat: DayStat) {
  const when = stat.daysAgo === 0 ? `${stat.label} (hôm nay, tới ${formatMinute(NOW_MINUTE)})` : stat.label
  if (stat.total === 0) return `${when} · không chạy`
  const parts = [`${integer.format(stat.total)} lượt`]
  if (stat.failed > 0) parts.push(`${stat.failed} lỗi`)
  if (stat.warning > 0) parts.push(`${stat.warning} cảnh báo`)
  if (stat.failed === 0 && stat.warning === 0) parts.push("tất cả thành công")
  return `${when} · ${parts.join(" · ")}`
}

/** Một ô của một job: ô dưới con trỏ, hoặc ô đang đọc bằng phím. */
type Pointer = { jobId: string; index: number }

/**
 * Nối callback của một tracker vào state chung của trang. Không cần phân biệt
 * `null` của dải nào: rời dải cũ luôn tới trước vào dải mới (pointerleave trước
 * pointerenter, blur trước focus), nên một `null` không bao giờ xoá nhầm dải kia.
 */
function follow(set: React.Dispatch<React.SetStateAction<Pointer | null>>, jobId: string) {
  return (index: number | null) => set(index === null ? null : { jobId, index })
}

/** Dải tracker của từng job, dựng một lần lúc import — dữ liệu mẫu là tĩnh. */
const jobRows = jobs.map((job) => {
  const days = dailyStats(job.id)
  const blocks: TrackerBlock[] = days.map((stat) => ({
    key: String(stat.day),
    status: dayStatus(stat),
    label: blockLabel(stat),
  }))
  const total = days.reduce((sum, d) => sum + d.total, 0)
  const failed = days.reduce((sum, d) => sum + d.failed, 0)
  return { job, blocks, completion: total > 0 ? (total - failed) / total : 0, lastRun: lastRunOf(job.id) }
})

const allDays = dailyStats()
const current = summarizeWindow(7)
const previous = summarizeWindow(7, 7)

/**
 * Xu hướng của KPI: 14 cửa sổ 24 giờ liên tiếp, cũ → mới. Dùng cửa sổ trượt chứ
 * không dùng ngày lịch để điểm cuối không tụt xuống chỉ vì hôm nay chưa hết.
 */
const trendWindows = Array.from({ length: 14 }, (_, i) => summarizeWindow(1, 13 - i))

export function AutomationPage() {
  const [range, setRange] = React.useState<Range>("30")
  // Hai trạng thái riêng, như trong `Tracker`: ô dưới con trỏ chuột, và ô đang
  // được đọc bằng phím ở dải đang focus. Readout ưu tiên chuột (thứ người dùng
  // đang nhìn), rời chuột thì quay về chỗ đang đọc bằng phím.
  const [hovered, setHovered] = React.useState<Pointer | null>(null)
  const [reading, setReading] = React.useState<Pointer | null>(null)

  const chartData = allDays.slice(-Number(range))
  const inspected = hovered ?? reading
  const activeRow = inspected ? jobRows.find((row) => row.job.id === inspected.jobId) : undefined
  const activeBlock = activeRow && inspected ? activeRow.blocks[inspected.index] : undefined

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-muted-foreground">
        <Badge variant="outline">Dữ liệu mẫu</Badge>
        <span>
          {jobs.length} job · cập nhật {formatMinute(NOW_MINUTE)} ngày {formatShortDate(mockDay(0))}/
          {MOCK_TODAY.slice(0, 4)}
        </span>
      </div>

      {/* `*:min-w-0`: con của grid mặc định `min-width: auto`, nên một bảng rộng
          sẽ kéo giãn cả cột grid ra ngoài màn hình điện thoại thay vì tự cuộn
          ngang bên trong card của nó. */}
      <div className="grid gap-4 *:min-w-0 sm:grid-cols-2 xl:grid-cols-4">
        <KpiCard
          label="Lượt chạy · 7 ngày"
          icon={Activity}
          value={integer.format(current.total)}
          delta={deltaOf(
            current.total,
            previous.total,
            `${signed(((current.total - previous.total) / previous.total) * 100, 1)}%`,
            null,
          )}
          footnote="So với 7 ngày trước đó"
          trend={trendWindows.map((w) => w.total)}
        />
        <KpiCard
          label="Tỉ lệ hoàn tất"
          icon={CheckCircle2}
          value={`${(current.completionRate * 100).toFixed(2)}%`}
          delta={deltaOf(
            current.completionRate,
            previous.completionRate,
            `${signed((current.completionRate - previous.completionRate) * 100, 2)} điểm`,
            true,
          )}
          footnote="Lượt chạy xong, kể cả có cảnh báo"
          trend={trendWindows.map((w) => w.completionRate)}
          trendClassName="text-success-fill"
        />
        <KpiCard
          label="Thời gian chạy TB"
          icon={Timer}
          value={formatDuration(current.avgSeconds)}
          delta={deltaOf(
            current.avgSeconds,
            previous.avgSeconds,
            `${signed(((current.avgSeconds - previous.avgSeconds) / previous.avgSeconds) * 100, 1)}%`,
            false,
          )}
          footnote="Trung bình mỗi lượt, mọi job"
          trend={trendWindows.map((w) => w.avgSeconds)}
          trendClassName="text-chart-3"
        />
        <KpiCard
          label="Lượt lỗi · 7 ngày"
          icon={AlertOctagon}
          value={integer.format(current.failed)}
          delta={deltaOf(current.failed, previous.failed, signed(current.failed - previous.failed), false)}
          footnote={`${previous.failed} lỗi ở 7 ngày trước đó`}
          trend={trendWindows.map((w) => w.failed)}
          trendClassName="text-destructive"
        />
      </div>

      <div className="grid gap-4 *:min-w-0 xl:grid-cols-3">
        <Card className="xl:col-span-2">
          <CardHeader className="max-sm:has-[[data-slot=card-action]]:grid-cols-1">
            <CardTitle role="heading" aria-level={2}>
              Lượt chạy theo ngày
            </CardTitle>
            <CardDescription>
              Mọi job, theo kết quả · hôm nay tính tới {formatMinute(NOW_MINUTE)}
            </CardDescription>
            {/* Điện thoại: nhóm nút xuống dòng riêng dưới mô tả, không ép tiêu đề
                vào một cột hẹp bên trái. */}
            <CardAction className="max-sm:col-start-1 max-sm:row-span-1 max-sm:row-start-3 max-sm:mt-2 max-sm:justify-self-start">
              <ToggleGroup
                type="single"
                variant="outline"
                size="sm"
                value={range}
                onValueChange={(value) => {
                  // Bấm lại nút đang chọn thì Radix trả chuỗi rỗng — giữ nguyên.
                  if (isRange(value)) setRange(value)
                }}
                aria-label="Khoảng thời gian của biểu đồ"
              >
                {ranges.map((r) => (
                  <ToggleGroupItem key={r.value} value={r.value}>
                    {r.label}
                  </ToggleGroupItem>
                ))}
              </ToggleGroup>
            </CardAction>
          </CardHeader>
          <CardContent className="px-2 sm:px-6">
            <ChartContainer config={runsChartConfig} className="aspect-auto h-64 w-full">
              <BarChart data={chartData} margin={{ left: 0, right: 8, top: 8 }}>
                <CartesianGrid vertical={false} />
                <XAxis dataKey="label" tickLine={false} axisLine={false} tickMargin={8} minTickGap={16} />
                <YAxis tickLine={false} axisLine={false} width={36} allowDecimals={false} />
                <ChartTooltip cursor={{ fill: "var(--muted)" }} content={<ChartTooltipContent />} />
                <ChartLegend itemSorter={null} content={<ChartLegendContent />} />
                <Bar dataKey="success" stackId="runs" fill="var(--color-success)" />
                <Bar dataKey="warning" stackId="runs" fill="var(--color-warning)" />
                <Bar dataKey="failed" stackId="runs" fill="var(--color-failed)" />
              </BarChart>
            </ChartContainer>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle role="heading" aria-level={2}>
              Kết quả 7 ngày
            </CardTitle>
            <CardDescription>{integer.format(current.total)} lượt chạy, mọi job</CardDescription>
          </CardHeader>
          <CardContent className="flex flex-1 flex-col items-center justify-center gap-6">
            <ProgressRing value={current.completionRate * 100} size={148} strokeWidth={12}>
              <span className="text-2xl font-semibold tabular-nums">
                {(current.completionRate * 100).toFixed(1)}%
              </span>
              <span className="text-xs text-muted-foreground">hoàn tất</span>
            </ProgressRing>
            <CategoryBar
              className="w-full"
              aria-label="Lượt chạy 7 ngày theo kết quả"
              segments={[
                { key: "success", label: "Thành công", value: current.success, className: "bg-success-fill" },
                { key: "warning", label: "Cảnh báo", value: current.warning, className: "bg-warning" },
                { key: "failed", label: "Lỗi", value: current.failed, className: "bg-destructive" },
              ]}
            />
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle role="heading" aria-level={2}>
            Tình trạng từng job
          </CardTitle>
          <CardDescription>
            Mỗi ô là một ngày, {HISTORY_DAYS} ngày gần nhất. Đỏ: có lượt lỗi · vàng: từ 10% lượt
            có cảnh báo · xám: không chạy.
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-4">
          {/* Readout dùng chung cho mọi dải — cùng ý tưởng với dòng O/H/L/C
              dưới chart giá: số liệu của ô đang trỏ nằm ở HTML thật. */}
          <p data-testid="tracker-readout" className="min-h-5 text-sm">
            {activeRow && activeBlock ? (
              <>
                <span className="font-medium">{activeRow.job.name}</span>
                <span className="text-muted-foreground"> — {activeBlock.label}</span>
              </>
            ) : (
              <span className="text-muted-foreground">
                Rê chuột lên một dải, hoặc Tab vào rồi dùng phím mũi tên, để xem từng ngày.
              </span>
            )}
          </p>
          <ul className="flex flex-col gap-5">
            {jobRows.map(({ job, blocks, completion, lastRun }) => (
              <li
                key={job.id}
                data-job={job.id}
                className="grid gap-2 md:grid-cols-[minmax(0,13rem)_minmax(0,1fr)_auto] md:items-center md:gap-6"
              >
                <div className="min-w-0">
                  <p className="truncate text-sm font-medium">{job.name}</p>
                  <p className="truncate text-xs text-muted-foreground">{job.schedule}</p>
                </div>
                <Tracker
                  blocks={blocks}
                  label={`${job.name}, ${HISTORY_DAYS} ngày gần nhất`}
                  onCursorChange={follow(setReading, job.id)}
                  onHoverChange={follow(setHovered, job.id)}
                />
                <div className="flex items-center gap-3 md:justify-end">
                  <span className="text-sm tabular-nums">
                    {(completion * 100).toFixed(1)}%
                    <span className="sr-only"> lượt hoàn tất trong {HISTORY_DAYS} ngày</span>
                  </span>
                  {lastRun && (
                    <StatusBadge tone={runTone[lastRun.status]}>
                      <span className="sr-only">Lượt gần nhất: </span>
                      {runStatusLabel[lastRun.status]}
                    </StatusBadge>
                  )}
                </div>
              </li>
            ))}
          </ul>
        </CardContent>
      </Card>

      <div className="grid gap-4 *:min-w-0 xl:grid-cols-5 xl:items-start">
        <Card className="xl:col-span-2">
          <CardHeader>
            <CardTitle role="heading" aria-level={2}>
              Lỗi thường gặp
            </CardTitle>
            <CardDescription>Số lượt lỗi theo nguyên nhân, {HISTORY_DAYS} ngày</CardDescription>
          </CardHeader>
          <CardContent>
            <BarList
              aria-label={`Số lượt lỗi theo nguyên nhân trong ${HISTORY_DAYS} ngày`}
              data={errorBreakdown().map((e) => ({ key: e.kind, name: e.label, value: e.count }))}
              barClassName="bg-destructive/15"
            />
          </CardContent>
        </Card>

        <Card className="xl:col-span-3">
          <CardHeader>
            <CardTitle role="heading" aria-level={2}>
              Lượt chạy gần nhất
            </CardTitle>
            <CardDescription>Mọi job, mới nhất trước</CardDescription>
          </CardHeader>
          <CardContent>
            <Table>
              <caption className="sr-only">Tám lượt chạy gần nhất của mọi job</caption>
              <TableHeader>
                <TableRow>
                  <TableHead>Job</TableHead>
                  <TableHead>Lúc</TableHead>
                  <TableHead className="hidden lg:table-cell">Thời gian chạy</TableHead>
                  <TableHead className="text-right">Kết quả</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {latestRuns(8).map((run) => (
                  <TableRow key={`${run.jobId}-${run.daysAgo}-${run.minute}`}>
                    {/* Tên job được xuống dòng: ở 390px, giữ trên một dòng là bảng tràn ngang. */}
                    <TableCell className="whitespace-normal font-medium">{jobOf(run.jobId)?.name ?? run.jobId}</TableCell>
                    {/* Cách kích hoạt là dòng phụ dưới giờ chạy, không phải cột
                        riêng: card nửa màn hình ở 1280px không chứa nổi năm cột. */}
                    <TableCell className="tabular-nums">
                      {run.daysAgo === 0 ? "" : `${formatShortDate(mockDay(run.daysAgo))} `}
                      {formatMinute(run.minute)}
                      <span className="block text-xs text-muted-foreground">
                        {run.trigger === "manual" ? "Thủ công" : "Theo lịch"}
                      </span>
                    </TableCell>
                    <TableCell className="hidden tabular-nums text-muted-foreground lg:table-cell">
                      {formatDuration(run.seconds)}
                    </TableCell>
                    <TableCell className="text-right">
                      <StatusBadge tone={runTone[run.status]}>{runStatusLabel[run.status]}</StatusBadge>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
