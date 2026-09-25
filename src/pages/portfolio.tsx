import { Banknote, CalendarDays, PiggyBank, TrendingUp } from "lucide-react"
import * as React from "react"
import { Area, AreaChart, CartesianGrid, Label, Pie, PieChart, XAxis, YAxis } from "recharts"

import { KpiCard, type KpiDelta } from "@/components/dashboard/kpi-card"
import { DataTable, type DataTableColumn } from "@/components/data-table"
import { PriceChange } from "@/components/price-change"
import { Sparkline } from "@/components/sparkline"
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
  ChartTooltip,
  ChartTooltipContent,
  type ChartConfig,
} from "@/components/ui/chart"
import { Label as FieldLabel } from "@/components/ui/label"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import { formatCandleDate } from "@/lib/candles"
import {
  formatPrice,
  isPriceConvention,
  priceConventionLabel,
  priceConventions,
  type PriceConvention,
} from "@/lib/market"
import { formatShortDate } from "@/lib/mock"
import { positions, sectorAllocation, totals, valueHistory, type Position } from "@/lib/portfolio"
import { cn } from "@/lib/utils"

const yen = (value: number) => formatPrice(value, "JPY")
const compactYen = new Intl.NumberFormat("en-US", {
  style: "currency",
  currency: "JPY",
  notation: "compact",
  maximumFractionDigits: 2,
})
const percent = new Intl.NumberFormat("en-US", { style: "percent", maximumFractionDigits: 1 })

/** Số tiền có dấu: `+¥84,200` / `−¥12,000`. Dấu trừ thật (U+2212) cho thẳng hàng. */
function signedYen(value: number) {
  const rounded = Math.round(value)
  if (rounded === 0) return yen(0)
  return `${rounded > 0 ? "+" : "−"}${yen(Math.abs(rounded))}`
}

function signedPct(value: number) {
  const fixed = Math.abs(value).toFixed(2)
  if (Number(fixed) === 0) return `${fixed}%`
  return `${value > 0 ? "+" : "−"}${fixed}%`
}

/** Delta tô theo quy ước giá — lãi/lỗ phải ăn theo `data-price-convention`. */
function marketDelta(value: number, text: string): KpiDelta {
  return { value: text, direction: value > 0 ? "up" : value < 0 ? "down" : "flat", tone: "market" }
}

/** Màu chữ lãi/lỗ theo chiều, như readout ở chart nến. */
function marketText(value: number) {
  return value > 0 ? "text-price-rise" : value < 0 ? "text-price-fall" : "text-muted-foreground"
}

const ranges = [
  { value: "21", label: "1 tháng" },
  { value: "63", label: "3 tháng" },
  { value: "90", label: "90 phiên" },
] as const

type Range = (typeof ranges)[number]["value"]

function isRange(value: string): value is Range {
  return ranges.some((r) => r.value === value)
}

const history = valueHistory.map((p) => ({ ...p, label: formatShortDate(p.time) }))
const trend30 = history.slice(-30).map((p) => p.value)
/**
 * Biến động 30 phiên cho card "Tổng tài sản" — khớp với đường xu hướng vẽ ở đáy
 * card. Không lấy biến động hôm nay: card "Lãi/lỗ hôm nay" ngay cạnh đã nói số
 * đó, hai card cùng một con số là phí một ô.
 */
const change30 = trend30[trend30.length - 1] - trend30[0]
const change30Pct = (change30 / trend30[0]) * 100

const allocation = sectorAllocation()
/** Tiền mặt tô xám trung tính: nó không phải một "ngành" để so màu với các lát khác. */
const allocationColor = (index: number, sector: string) =>
  sector === "Tiền mặt" ? "var(--muted-foreground)" : `var(--chart-${(index % 5) + 1})`
const allocationData = allocation.map((a, i) => ({
  ...a,
  key: `s${i}`,
  token: allocationColor(i, a.sector),
  fill: `var(--color-s${i})`,
}))
const allocationConfig = Object.fromEntries(
  allocationData.map((a) => [a.key, { label: a.sector, color: a.token }]),
) satisfies ChartConfig

const columns: DataTableColumn<Position>[] = [
  { accessorKey: "ticker", header: "Mã", sortFn: "text" },
  {
    id: "name",
    accessorFn: (row) => row.instrument.name,
    header: "Tên",
    sortFn: "text",
    meta: { className: "hidden xl:table-cell" },
    cell: ({ row }) => <span className="text-muted-foreground">{row.original.instrument.name}</span>,
  },
  {
    accessorKey: "shares",
    header: "SL",
    sortFn: "basic",
    meta: { align: "right", className: "hidden xl:table-cell" },
    cell: ({ row }) => <span className="tabular-nums">{row.original.shares.toLocaleString("en-US")}</span>,
  },
  {
    accessorKey: "price",
    header: "Giá",
    sortFn: "basic",
    meta: { align: "right" },
    cell: ({ row }) => <span className="tabular-nums">{yen(row.original.price)}</span>,
  },
  {
    id: "today",
    accessorFn: (row) => row.instrument.changePct,
    header: "Hôm nay",
    sortFn: "basic",
    meta: { align: "right" },
    cell: ({ row }) => <PriceChange value={row.original.instrument.changePct} className="ml-auto" />,
  },
  {
    accessorKey: "pl",
    header: "Lãi/lỗ",
    sortFn: "basic",
    meta: { align: "right", className: "hidden sm:table-cell" },
    cell: ({ row }) => (
      <span className={cn("tabular-nums", marketText(row.original.pl))}>
        {signedYen(row.original.pl)}{" "}
        {/* Dưới xl, % xuống dòng dưới số tiền để cột hẹp lại. */}
        <span className="block text-xs xl:inline">({signedPct(row.original.plPct)})</span>
      </span>
    ),
  },
  {
    accessorKey: "weight",
    header: "Tỉ trọng",
    sortFn: "basic",
    meta: { align: "right", className: "hidden lg:table-cell" },
    cell: ({ row }) => (
      <span className="inline-flex items-center gap-2">
        <span aria-hidden className="h-1.5 w-12 overflow-hidden rounded-full bg-muted">
          <span className="block h-full rounded-full bg-chart-2" style={{ width: `${row.original.weight * 100}%` }} />
        </span>
        <span className="w-12 text-right tabular-nums">{percent.format(row.original.weight)}</span>
      </span>
    ),
  },
  {
    id: "trend",
    header: "90 phiên",
    enableSorting: false,
    meta: { className: "hidden xl:table-cell" },
    cell: ({ row }) => <Sparkline values={row.original.closes} />,
  },
]

export function PortfolioPage() {
  const [convention, setConvention] = React.useState<PriceConvention>("east-asian")
  const [range, setRange] = React.useState<Range>("63")

  const series = history.slice(-Number(range))
  const first = series[0].value
  const last = series[series.length - 1].value
  const rangeChange = last - first
  // Màu vùng theo chiều của **khoảng đang xem**, như Sparkline: xem 1 tháng mà
  // danh mục giảm thì vùng mang màu giảm, dù cả 90 phiên có thể đang tăng.
  const valueConfig = {
    value: { label: "Tổng tài sản", color: rangeChange >= 0 ? "var(--price-rise)" : "var(--price-fall)" },
  } satisfies ChartConfig

  return (
    // Quy ước màu đặt ở gốc trang để badge, sparkline, KPI và vùng chart cùng đọc
    // một nguồn — xem khối `data-price-convention` trong src/index.css.
    <div data-price-convention={convention} className="flex flex-col gap-6">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
        <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-muted-foreground">
          <Badge variant="outline">Dữ liệu mẫu</Badge>
          <span>Tài khoản cổ phiếu Nhật (¥) · không phải lời khuyên đầu tư</span>
        </div>
        <div className="flex flex-col gap-1.5">
          <FieldLabel htmlFor="portfolio-convention" className="text-xs text-muted-foreground">
            Quy ước màu
          </FieldLabel>
          <Select
            value={convention}
            onValueChange={(v) => {
              if (isPriceConvention(v)) setConvention(v)
            }}
          >
            <SelectTrigger id="portfolio-convention" className="w-full sm:w-72" aria-label="Quy ước màu">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {priceConventions.map((c) => (
                <SelectItem key={c} value={c}>
                  {priceConventionLabel[c]}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      </div>

      {/* `*:min-w-0`: con của grid mặc định `min-width: auto`, nên một bảng rộng
          sẽ kéo giãn cả cột grid ra ngoài màn hình điện thoại thay vì tự cuộn
          ngang bên trong card của nó. */}
      <div className="grid gap-4 *:min-w-0 sm:grid-cols-2 xl:grid-cols-4">
        <KpiCard
          label="Tổng tài sản"
          icon={PiggyBank}
          value={yen(totals.value)}
          delta={marketDelta(change30, signedPct(change30Pct))}
          footnote="Cổ phiếu + tiền mặt · 30 phiên"
          trend={trend30}
          trendClassName={change30 >= 0 ? "text-price-rise" : "text-price-fall"}
        />
        <KpiCard
          label="Lãi/lỗ hôm nay"
          icon={CalendarDays}
          value={signedYen(totals.dayChange)}
          delta={marketDelta(totals.dayChange, signedPct(totals.dayChangePct))}
          footnote={`Phiên ${formatCandleDate(history[history.length - 1].time)}`}
        />
        <KpiCard
          label="Lãi/lỗ chưa chốt"
          icon={TrendingUp}
          value={signedYen(totals.pl)}
          delta={marketDelta(totals.pl, signedPct(totals.plPct))}
          footnote={`Trên giá vốn ${yen(totals.costBasis)}`}
        />
        <KpiCard
          label="Tiền mặt"
          icon={Banknote}
          value={yen(totals.cash)}
          footnote={`${percent.format(totals.cash / totals.value)} tổng tài sản`}
        />
      </div>

      <div className="grid gap-4 *:min-w-0 xl:grid-cols-3">
        <Card className="xl:col-span-2">
          <CardHeader className="max-sm:has-[[data-slot=card-action]]:grid-cols-1">
            <CardTitle role="heading" aria-level={2}>
              Tổng tài sản
            </CardTitle>
            <CardDescription>
              <span className={cn("font-medium tabular-nums", marketText(rangeChange))} data-testid="range-change">
                {signedYen(rangeChange)} ({signedPct((rangeChange / first) * 100)})
              </span>{" "}
              trong khoảng đang xem
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
            <ChartContainer config={valueConfig} className="aspect-auto h-72 w-full">
              <AreaChart data={series} margin={{ left: 0, right: 8, top: 8 }}>
                <defs>
                  <linearGradient id="portfolio-value-fill" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="var(--color-value)" stopOpacity={0.3} />
                    <stop offset="95%" stopColor="var(--color-value)" stopOpacity={0.02} />
                  </linearGradient>
                </defs>
                <CartesianGrid vertical={false} />
                <XAxis dataKey="label" tickLine={false} axisLine={false} tickMargin={8} minTickGap={32} />
                <YAxis
                  tickLine={false}
                  axisLine={false}
                  width={56}
                  domain={["auto", "auto"]}
                  tickFormatter={(v: number) => compactYen.format(v)}
                />
                <ChartTooltip
                  cursor={{ stroke: "var(--border)" }}
                  content={
                    <ChartTooltipContent
                      indicator="line"
                      formatter={(value) => (
                        <div className="flex w-full items-center justify-between gap-4">
                          <span className="text-muted-foreground">Tổng tài sản</span>
                          <span className="font-mono font-medium tabular-nums text-foreground">
                            {yen(Number(value))}
                          </span>
                        </div>
                      )}
                    />
                  }
                />
                <Area
                  dataKey="value"
                  type="monotone"
                  stroke="var(--color-value)"
                  strokeWidth={2}
                  fill="url(#portfolio-value-fill)"
                />
              </AreaChart>
            </ChartContainer>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle role="heading" aria-level={2}>
              Phân bổ theo ngành
            </CardTitle>
            <CardDescription>Theo giá trị thị trường, kể cả tiền mặt</CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-4">
            <ChartContainer config={allocationConfig} className="mx-auto aspect-square h-52">
              <PieChart>
                <ChartTooltip content={<ChartTooltipContent nameKey="key" hideLabel />} />
                <Pie
                  data={allocationData}
                  dataKey="value"
                  nameKey="key"
                  innerRadius={58}
                  outerRadius={84}
                  stroke="var(--card)"
                  strokeWidth={2}
                >
                  <Label
                    content={({ viewBox }) => {
                      if (!viewBox || !("cx" in viewBox) || !("cy" in viewBox)) return null
                      return (
                        <text data-slot="donut-center" x={viewBox.cx} y={viewBox.cy} textAnchor="middle" dominantBaseline="middle">
                          <tspan x={viewBox.cx} y={viewBox.cy} className="fill-foreground text-xl font-semibold">
                            {compactYen.format(totals.value)}
                          </tspan>
                          <tspan x={viewBox.cx} y={(viewBox.cy ?? 0) + 22} className="fill-muted-foreground text-xs">
                            {positions.length} mã + tiền mặt
                          </tspan>
                        </text>
                      )
                    }}
                  />
                </Pie>
              </PieChart>
            </ChartContainer>
            <ul aria-label="Tỉ trọng theo ngành" className="grid gap-2 text-sm">
              {allocationData.map((a) => (
                <li key={a.key} className="flex items-center gap-2">
                  <span aria-hidden className="size-2.5 shrink-0 rounded-[3px]" style={{ background: a.token }} />
                  <span className="text-muted-foreground">{a.sector}</span>
                  <span className="ml-auto font-medium tabular-nums">{percent.format(a.value / totals.value)}</span>
                </li>
              ))}
            </ul>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle role="heading" aria-level={2}>
            Danh mục nắm giữ
          </CardTitle>
          <CardDescription>Giá và biến động dùng chung dữ liệu mẫu với trang Watchlist</CardDescription>
        </CardHeader>
        <CardContent>
          <DataTable
            columns={columns}
            data={positions}
            initialSorting={[{ id: "weight", desc: true }]}
            caption="Các mã đang nắm giữ, sắp theo tỉ trọng"
          />
        </CardContent>
      </Card>
    </div>
  )
}
