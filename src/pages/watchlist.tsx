import * as React from "react"

import { DataTable, type DataTableColumn } from "@/components/data-table"
import { PriceChange } from "@/components/price-change"
import { Sparkline } from "@/components/sparkline"
import { TickerSearch } from "@/components/ticker-search"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Label } from "@/components/ui/label"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { closingPrices, generateCandles, type CandleSeries } from "@/lib/candles"
import {
  formatPrice,
  formatVolume,
  instrumentOf,
  instruments,
  isPriceConvention,
  marketLabel,
  priceConventionLabel,
  priceConventions,
  type Instrument,
  type Market,
  type PriceConvention,
} from "@/lib/market"

/**
 * Chart giá tải trễ.
 *
 * `lightweight-charts` là dependency nặng nhất trong repo và chỉ đúng trang này
 * dùng. Import tĩnh thì cả người chỉ mở Dashboard cũng phải tải nó. Tách ra đây
 * giữ bundle khởi động mỏng, đổi lại một khung chờ đúng bằng chiều cao chart nên
 * không giật layout.
 */
const PriceChart = React.lazy(() =>
  import("@/components/price-chart").then((m) => ({ default: m.PriceChart })),
)

/** Khung chờ cao đúng bằng chart thật (readout + h-64) để không đẩy layout. */
function ChartSkeleton() {
  return (
    <div className="flex flex-col gap-3" aria-hidden>
      <div className="h-4 w-64 animate-pulse rounded bg-muted" />
      <div className="h-64 w-full animate-pulse rounded bg-muted" />
    </div>
  )
}

/**
 * Nến sinh sẵn một lần cho cả module.
 *
 * `generateCandles` là hàm thuần và tất định, nên không có lý do gì chạy lại
 * mỗi lần render — 8 mã × 90 phiên tính một lần lúc import là xong.
 */
const seriesByTicker = new Map<string, CandleSeries>(
  instruments.map((i) => [i.ticker, generateCandles(i)]),
)

function seriesOf(ticker: string) {
  return seriesByTicker.get(ticker)
}

const columns: DataTableColumn<Instrument>[] = [
  { accessorKey: "ticker", header: "Mã", sortFn: "text" },
  {
    accessorKey: "name",
    header: "Tên",
    sortFn: "text",
    // Trên điện thoại chỉ giữ Mã / Giá / % — ba cột người ta thật sự liếc vào.
    // Bảy cột trên màn 390px thì cuộn ngang mãi mới thấy hết, mà không có gợi ý
    // nào là còn cột bên phải.
    meta: { className: "hidden lg:table-cell" },
    cell: ({ row }) => <span className="text-muted-foreground">{row.original.name}</span>,
  },
  {
    accessorKey: "market",
    header: "Thị trường",
    sortFn: "text",
    meta: { className: "hidden lg:table-cell" },
    cell: ({ row }) => (
      <span className="text-muted-foreground">{marketLabel[row.original.market]}</span>
    ),
  },
  {
    id: "trend",
    header: "90 phiên",
    enableSorting: false,
    meta: { className: "hidden md:table-cell" },
    cell: ({ row }) => {
      const series = seriesOf(row.original.ticker)
      return series ? <Sparkline values={closingPrices(series)} /> : null
    },
  },
  {
    accessorKey: "price",
    header: "Giá",
    /**
     * So giá thô giữa hai sàn là **so sai**: ¥1,842 xấp xỉ $12, nhưng sắp theo
     * số thì nó đứng trên $461.03. Bảng sẽ khẳng định một điều không đúng, mà
     * người xem lại hay dựa đúng vào cột này.
     *
     * Quy đổi thì cần tỉ giá thật — repo này không có, và bịa một tỉ giá tĩnh
     * còn tệ hơn là không sắp. Nên nhóm theo đơn vị tiền trước rồi mới so trong
     * từng nhóm: lọc về một thị trường (trường hợp thường gặp) thì y hệt sắp
     * theo giá bình thường, còn khi trộn thì không nói điều gì sai.
     */
    sortFn: (a, b) => {
      const x = a.original
      const y = b.original
      if (x.currency !== y.currency) return x.currency < y.currency ? -1 : 1
      return x.price - y.price
    },
    meta: { align: "right" },
    cell: ({ row }) => (
      <span className="tabular-nums">
        {formatPrice(row.original.price, row.original.currency)}
      </span>
    ),
  },
  {
    accessorKey: "changePct",
    header: "% Thay đổi",
    sortFn: "basic",
    meta: { align: "right" },
    cell: ({ row }) => <PriceChange value={row.original.changePct} className="ml-auto" />,
  },
  {
    accessorKey: "volume",
    header: "Khối lượng",
    sortFn: "basic",
    meta: { align: "right", className: "hidden md:table-cell" },
    cell: ({ row }) => (
      <span className="tabular-nums text-muted-foreground">
        {formatVolume(row.original.volume)}
      </span>
    ),
  },
]

export function WatchlistPage() {
  const [market, setMarket] = React.useState<Market | "all">("all")
  const [convention, setConvention] = React.useState<PriceConvention>("east-asian")
  const [picked, setPicked] = React.useState(instruments[0].ticker)

  const rows = market === "all" ? instruments : instruments.filter((i) => i.market === market)

  // Chọn mã theo kiểu dẫn xuất chứ không đồng bộ bằng effect: lọc thị trường mà
  // mã đang xem bị lọc mất thì tự rơi về mã đầu danh sách, không cần setState.
  const selected = rows.find((i) => i.ticker === picked) ?? rows[0]

  /**
   * Tìm mã là thao tác **toàn cục**: ô ⌘K liệt kê mọi mã, bất kể đang lọc gì.
   * Nếu chỉ `setPicked` thì chọn NVDA lúc đang lọc "Nhật" sẽ bị dòng trên nuốt
   * mất — `selected` chỉ tìm trong các dòng đã lọc, rơi về dòng đầu, và dialog
   * đóng lại trong khi chart vẫn hiện Honda. Nên mã nằm ngoài bộ lọc thì đưa bộ
   * lọc về "Tất cả" để mã vừa chọn hiện ra cả ở bảng lẫn ở chart.
   *
   * Không làm theo hướng ngược lại (chỉ cho tìm trong các dòng đã lọc): gõ
   * "NVDA" mà nhận "Không tìm thấy mã nào" là nói sai — mã đó có tồn tại.
   */
  function pickFromSearch(ticker: string) {
    setPicked(ticker)
    if (market !== "all" && instrumentOf(ticker)?.market !== market) setMarket("all")
  }
  const series = selected ? seriesOf(selected.ticker) : undefined
  const mixedCurrencies = new Set(rows.map((i) => i.currency)).size > 1

  return (
    // Quy ước màu đặt ở đây để badge, sparkline và chart canvas cùng đọc một
    // nguồn — xem khối `data-price-convention` trong src/index.css.
    <div data-price-convention={convention} className="flex flex-col gap-4">
      <Card>
        <CardHeader className="gap-4">
          <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <CardTitle>Watchlist chứng khoán</CardTitle>
              <CardDescription>
                Dữ liệu mẫu minh họa — không phải giá thực tế, không phải lời khuyên đầu tư
              </CardDescription>
            </div>
            <TickerSearch instruments={instruments} onSelect={pickFromSearch} />
          </div>

          <div className="flex flex-col gap-3 sm:flex-row sm:items-end">
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="market-filter" className="text-xs text-muted-foreground">
                Thị trường
              </Label>
              <Select value={market} onValueChange={(v) => setMarket(v as Market | "all")}>
                <SelectTrigger id="market-filter" className="w-40" aria-label="Lọc theo thị trường">
                  <SelectValue placeholder="Thị trường" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">Tất cả</SelectItem>
                  <SelectItem value="jp">Nhật</SelectItem>
                  <SelectItem value="us">Mỹ</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div className="flex flex-col gap-1.5">
              <Label htmlFor="price-convention" className="text-xs text-muted-foreground">
                Quy ước màu
              </Label>
              <Select
                value={convention}
                onValueChange={(v) => {
                  if (isPriceConvention(v)) setConvention(v)
                }}
              >
                <SelectTrigger id="price-convention" className="w-72" aria-label="Quy ước màu">
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
        </CardHeader>

        <CardContent>
          <DataTable
            columns={columns}
            data={rows}
            caption="Danh sách mã theo dõi, bấm vào một dòng để xem chart của mã đó"
            emptyMessage="Không có mã nào trong thị trường này."
            onRowClick={(row) => setPicked(row.ticker)}
            isRowActive={(row) => row.ticker === selected?.ticker}
          />
          {mixedCurrencies && (
            <p className="mt-3 text-xs text-muted-foreground">
              Đang trộn nhiều đơn vị tiền, nên cột Giá sắp theo nhóm ¥ / $ rồi mới so trong
              từng nhóm — hai đơn vị không so trực tiếp được nếu không có tỉ giá.
            </p>
          )}
        </CardContent>
      </Card>

      {selected && series && (
        <Card>
          <CardHeader>
            <CardTitle className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
              <span>{selected.ticker}</span>
              <span className="text-sm font-normal text-muted-foreground">{selected.name}</span>
              <span className="ml-auto tabular-nums">
                {formatPrice(selected.price, selected.currency)}
              </span>
              <PriceChange value={selected.changePct} />
            </CardTitle>
            <CardDescription>Giá và khối lượng 90 phiên gần nhất (dữ liệu mẫu)</CardDescription>
          </CardHeader>
          <CardContent>
            <React.Suspense fallback={<ChartSkeleton />}>
              <PriceChart
                candles={series.candles}
                volumes={series.volumes}
                currency={selected.currency}
                convention={convention}
              />
            </React.Suspense>
          </CardContent>
        </Card>
      )}
    </div>
  )
}
