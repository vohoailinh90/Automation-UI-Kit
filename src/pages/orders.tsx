import { AlarmClock, CalendarClock, ClipboardList, Target } from "lucide-react"
import { Bar, BarChart, CartesianGrid, Label, Pie, PieChart, XAxis, YAxis } from "recharts"

import { BarList } from "@/components/dashboard/bar-list"
import { CategoryBar } from "@/components/dashboard/category-bar"
import { KpiCard, type KpiDelta } from "@/components/dashboard/kpi-card"
import { StatusBadge, type StatusTone } from "@/components/dashboard/status-badge"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
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
import {
  customerMix,
  dueDateLabel,
  holderLabel,
  holderLoad,
  leadTimeByGroup,
  openHolders,
  orderStatusLabel,
  snapshot,
  statusBreakdown,
  statusOn,
  stepsDone,
  upcomingOrders,
  weeklyThroughput,
  type Holder,
  type OrderStatus,
  type TestOrder,
} from "@/lib/orders"
import { cn } from "@/lib/utils"

const integer = new Intl.NumberFormat("en-US")

const statusTone: Record<OrderStatus, StatusTone> = {
  draft: "neutral",
  requested: "info",
  "in-progress": "info",
  delivered: "success",
  closed: "neutral",
}

/** Màu từng trạng thái trên thanh phân bố — đi từ nhạt (mới tạo) tới đậm (xong). */
const statusSegmentClass: Record<OrderStatus, string> = {
  draft: "bg-muted-foreground/40",
  requested: "bg-info/60",
  "in-progress": "bg-info",
  delivered: "bg-success-fill",
  closed: "bg-foreground/70",
}

const holderShort: Record<Holder, string> = {
  requester: "Người yêu cầu",
  "role-a": "Role A",
  "role-b": "Role B",
}

/**
 * Màu theo **nghĩa**, cùng bảng màu với badge trạng thái trên trang: đơn mới là
 * việc đang vào (xanh dương `info`), đơn đã giao là việc đã xong (xanh lá). Cả
 * hai đạt ≥ 3:1 với nền card ở hai theme — khác `--chart-1` (tối quá ở dark
 * mode) hay `--chart-4`/`--chart-5` (nhạt quá ở light mode).
 */
const throughputConfig = {
  created: { label: "Đơn mới", color: "var(--info)" },
  delivered: { label: "Đã giao kết quả", color: "var(--success-fill)" },
} satisfies ChartConfig

const leadConfig = {
  median: { label: "Thực tế (trung vị)", color: "var(--chart-2)" },
  planned: { label: "Cam kết", color: "var(--muted-foreground)" },
} satisfies ChartConfig

/** Key của config phải là định danh CSS hợp lệ (`--color-<key>`), không để dấu cách. */
const customerKeys = ["a", "b", "c", "d", "e"] as const

const today = snapshot(0)
const lastWeek = snapshot(-7)
/** Ảnh chụp cuối mỗi tuần trong 12 tuần, cũ → mới — làm xu hướng cho KPI. */
const weeklySnapshots = Array.from({ length: 12 }, (_, i) => snapshot(-7 * (11 - i)))

const throughput = weeklyThroughput(12)
const pipeline = statusBreakdown(30)
const holders = holderLoad()
const leadTimes = leadTimeByGroup(90)
const upcoming = upcomingOrders(6)

const mix = customerMix(90)
const mixTotal = mix.reduce((sum, m) => sum + m.count, 0)
const customerConfig = Object.fromEntries(
  mix.map((m, i) => [customerKeys[i], { label: m.customer, color: `var(--chart-${i + 1})` }]),
) satisfies ChartConfig
const customerData = mix.map((m, i) => ({
  ...m,
  key: customerKeys[i],
  /** Màu gốc, cho chú giải nằm **ngoài** ChartContainer (nơi `--color-*` không tồn tại). */
  token: `var(--chart-${i + 1})`,
  fill: `var(--color-${customerKeys[i]})`,
}))

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

/** "còn 4 ngày" / "hạn hôm nay" / "trễ 3 ngày" — đơn trễ viết rõ bằng chữ, không chỉ tô đỏ. */
function dueHint(order: TestOrder) {
  if (order.due === 0) return "hạn hôm nay"
  return order.due > 0 ? `còn ${order.due} ngày` : `trễ ${-order.due} ngày`
}

/**
 * Tiến độ bốn bước 15–18 dạng bốn vạch. Vạch chỉ để nhìn; số bước viết thành
 * chữ trong `sr-only`.
 */
function StepBar({ done }: { done: number }) {
  return (
    <span className="inline-flex items-center gap-2">
      <span aria-hidden className="flex gap-0.5">
        {[0, 1, 2, 3].map((i) => (
          <span key={i} className={cn("h-1.5 w-4 rounded-full", i < done ? "bg-info" : "bg-muted")} />
        ))}
      </span>
      <span className="text-xs tabular-nums text-muted-foreground">
        {done}/4<span className="sr-only"> bước</span>
      </span>
    </span>
  )
}

export function OrdersPage() {
  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-muted-foreground">
        <Badge variant="outline">Dữ liệu mẫu</Badge>
        <span>Đơn thử nghiệm mẫu · luồng yêu cầu → nhận mẫu / giờ công → giao kết quả → đóng</span>
      </div>

      {/* `*:min-w-0`: con của grid mặc định `min-width: auto`, nên một bảng rộng
          sẽ kéo giãn cả cột grid ra ngoài màn hình điện thoại thay vì tự cuộn
          ngang bên trong card của nó. */}
      <div className="grid gap-4 *:min-w-0 sm:grid-cols-2 xl:grid-cols-4">
        <KpiCard
          label="Đơn đang mở"
          icon={ClipboardList}
          value={integer.format(today.open)}
          delta={deltaOf(today.open, lastWeek.open, signed(today.open - lastWeek.open), null)}
          footnote="Chưa giao kết quả · so với 7 ngày trước"
          trend={weeklySnapshots.map((s) => s.open)}
        />
        <KpiCard
          label="Hạn giao 7 ngày tới"
          icon={CalendarClock}
          value={integer.format(today.dueSoon)}
          delta={deltaOf(today.dueSoon, lastWeek.dueSoon, signed(today.dueSoon - lastWeek.dueSoon), null)}
          footnote="Đơn mở có hạn từ hôm nay tới 7 ngày"
          trend={weeklySnapshots.map((s) => s.dueSoon)}
          trendClassName="text-chart-3"
        />
        <KpiCard
          label="Trễ hạn"
          icon={AlarmClock}
          value={integer.format(today.late)}
          delta={deltaOf(today.late, lastWeek.late, signed(today.late - lastWeek.late), false)}
          footnote="Đơn mở đã quá hạn giao"
          trend={weeklySnapshots.map((s) => s.late)}
          trendClassName="text-destructive"
        />
        <KpiCard
          label="Đúng hạn · 30 ngày"
          icon={Target}
          value={`${(today.onTimeRate * 100).toFixed(1)}%`}
          delta={deltaOf(
            today.onTimeRate,
            lastWeek.onTimeRate,
            `${signed((today.onTimeRate - lastWeek.onTimeRate) * 100, 1)} điểm`,
            true,
          )}
          footnote={`${today.delivered30} đơn đã giao trong 30 ngày`}
          trend={weeklySnapshots.map((s) => s.onTimeRate)}
          trendClassName="text-success-fill"
        />
      </div>

      <div className="grid gap-4 *:min-w-0 xl:grid-cols-3">
        <Card className="xl:col-span-2">
          <CardHeader>
            <CardTitle role="heading" aria-level={2}>
              Đơn 30 ngày theo trạng thái
            </CardTitle>
            <CardDescription>Đơn tạo trong 30 ngày gần nhất, trạng thái tính tới hôm nay</CardDescription>
          </CardHeader>
          <CardContent>
            <CategoryBar
              aria-label="Số đơn tạo trong 30 ngày theo trạng thái"
              segments={pipeline.map((p) => ({
                key: p.status,
                label: orderStatusLabel[p.status],
                value: p.count,
                className: statusSegmentClass[p.status],
              }))}
            />
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle role="heading" aria-level={2}>
              Đang chờ ai
            </CardTitle>
            <CardDescription>Số bước đang mở theo người giữ</CardDescription>
          </CardHeader>
          <CardContent>
            <BarList
              aria-label="Số bước đang mở theo người giữ"
              data={(Object.keys(holders) as Holder[]).map((h) => ({ key: h, name: holderLabel[h], value: holders[h] }))}
              barClassName="bg-info/15"
            />
          </CardContent>
        </Card>
      </div>

      <div className="grid gap-4 *:min-w-0 xl:grid-cols-3">
        <Card className="xl:col-span-2">
          <CardHeader>
            <CardTitle role="heading" aria-level={2}>
              Đơn mới và đơn đã giao theo tuần
            </CardTitle>
            <CardDescription>12 tuần gần nhất · nhãn là ngày đầu tuần</CardDescription>
          </CardHeader>
          <CardContent className="px-2 sm:px-6">
            <ChartContainer config={throughputConfig} className="aspect-auto h-72 w-full">
              <BarChart data={throughput} margin={{ left: 0, right: 8, top: 8 }}>
                <CartesianGrid vertical={false} />
                <XAxis dataKey="label" tickLine={false} axisLine={false} tickMargin={8} minTickGap={12} />
                <YAxis tickLine={false} axisLine={false} width={32} allowDecimals={false} />
                <ChartTooltip cursor={{ fill: "var(--muted)" }} content={<ChartTooltipContent />} />
                <ChartLegend itemSorter={null} content={<ChartLegendContent />} />
                <Bar dataKey="created" fill="var(--color-created)" radius={[3, 3, 0, 0]} />
                <Bar dataKey="delivered" fill="var(--color-delivered)" radius={[3, 3, 0, 0]} />
              </BarChart>
            </ChartContainer>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle role="heading" aria-level={2}>
              Theo khách hàng
            </CardTitle>
            <CardDescription>Đơn tạo trong 90 ngày</CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-4">
            <ChartContainer config={customerConfig} className="mx-auto aspect-square h-52">
              <PieChart>
                <ChartTooltip content={<ChartTooltipContent nameKey="key" hideLabel />} />
                <Pie
                  data={customerData}
                  dataKey="count"
                  nameKey="key"
                  innerRadius={58}
                  outerRadius={84}
                  // Viền màu nền giữa các lát: hai lát kề nhau có màu gần nhau
                  // vẫn tách được bằng khe hở, không chỉ bằng màu.
                  stroke="var(--card)"
                  strokeWidth={2}
                >
                  <Label
                    content={({ viewBox }) => {
                      if (!viewBox || !("cx" in viewBox) || !("cy" in viewBox)) return null
                      return (
                        <text data-slot="donut-center" x={viewBox.cx} y={viewBox.cy} textAnchor="middle" dominantBaseline="middle">
                          <tspan x={viewBox.cx} y={viewBox.cy} className="fill-foreground text-2xl font-semibold">
                            {integer.format(mixTotal)}
                          </tspan>
                          <tspan x={viewBox.cx} y={(viewBox.cy ?? 0) + 22} className="fill-muted-foreground text-xs">
                            đơn
                          </tspan>
                        </text>
                      )
                    }}
                  />
                </Pie>
              </PieChart>
            </ChartContainer>
            {/* Chú giải có số: donut không được là nơi duy nhất nói tỉ lệ bằng màu. */}
            <ul aria-label="Số đơn theo khách hàng trong 90 ngày" className="grid gap-2 text-sm">
              {customerData.map((m) => (
                <li key={m.key} className="flex items-center gap-2">
                  <span aria-hidden className="size-2.5 shrink-0 rounded-[3px]" style={{ background: m.token }} />
                  <span className="text-muted-foreground">{m.customer}</span>
                  <span className="ml-auto font-medium tabular-nums">
                    {m.count}{" "}
                    <span className="text-xs font-normal text-muted-foreground">
                      {Math.round((m.count / mixTotal) * 100)}%
                    </span>
                  </span>
                </li>
              ))}
            </ul>
          </CardContent>
        </Card>
      </div>

      <div className="grid gap-4 *:min-w-0 xl:grid-cols-3">
        <Card className="xl:col-span-2">
          <CardHeader>
            <CardTitle role="heading" aria-level={2}>
              Sắp tới hạn
            </CardTitle>
            <CardDescription>Đơn còn mở, trễ nhất lên đầu</CardDescription>
          </CardHeader>
          <CardContent>
            <Table>
              <caption className="sr-only">Sáu đơn còn mở có hạn giao gần nhất</caption>
              <TableHeader>
                <TableRow>
                  <TableHead>Đơn</TableHead>
                  <TableHead>Hạn giao</TableHead>
                  <TableHead className="hidden lg:table-cell">Tiến độ</TableHead>
                  <TableHead className="hidden 2xl:table-cell">Đang chờ</TableHead>
                  {/* Điện thoại chỉ giữ Đơn + Hạn giao — hai thứ người ta mở bảng
                      này để xem. Cột ẩn tự khai bằng class, như bảng Watchlist. */}
                  <TableHead className="hidden text-right sm:table-cell">Trạng thái</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {upcoming.map((order) => {
                  const status = statusOn(order) ?? "draft"
                  return (
                    <TableRow key={order.number} data-order={order.number}>
                      {/* Số đơn + khách + nhóm gộp một ô hai dòng: bảy cột riêng
                          thì card nửa màn hình đã phải cuộn ngang. */}
                      <TableCell>
                        <span className="block font-medium tabular-nums">{order.number}</span>
                        <span className="block text-xs text-muted-foreground">
                          {order.customer} · {order.productGroup}
                        </span>
                      </TableCell>
                      <TableCell className="tabular-nums">
                        {dueDateLabel(order)}
                        <span
                          data-slot="due-hint"
                          className={cn(
                            "block text-xs",
                            order.due < 0 ? "font-medium text-destructive" : "text-muted-foreground",
                          )}
                        >
                          {dueHint(order)}
                        </span>
                      </TableCell>
                      <TableCell className="hidden lg:table-cell">
                        <StepBar done={stepsDone(order)} />
                      </TableCell>
                      <TableCell className="hidden text-muted-foreground 2xl:table-cell">
                        {openHolders(order).map((h) => holderShort[h]).join(", ")}
                      </TableCell>
                      <TableCell className="hidden text-right sm:table-cell">
                        <StatusBadge tone={statusTone[status]}>{orderStatusLabel[status]}</StatusBadge>
                      </TableCell>
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle role="heading" aria-level={2}>
              Thời gian thực hiện
            </CardTitle>
            <CardDescription>Ngày, từ lúc gửi yêu cầu tới lúc giao · đơn giao trong 90 ngày</CardDescription>
          </CardHeader>
          <CardContent className="px-2 sm:px-6">
            <ChartContainer config={leadConfig} className="aspect-auto h-56 w-full">
              <BarChart data={leadTimes} layout="vertical" margin={{ left: 0, right: 16 }}>
                <CartesianGrid horizontal={false} />
                <XAxis type="number" tickLine={false} axisLine={false} allowDecimals={false} />
                <YAxis dataKey="group" type="category" tickLine={false} axisLine={false} width={96} />
                <ChartTooltip cursor={{ fill: "var(--muted)" }} content={<ChartTooltipContent />} />
                <ChartLegend itemSorter={null} content={<ChartLegendContent />} />
                <Bar dataKey="median" fill="var(--color-median)" radius={3} />
                <Bar dataKey="planned" fill="var(--color-planned)" radius={3} />
              </BarChart>
            </ChartContainer>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
