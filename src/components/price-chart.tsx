import {
  CandlestickSeries,
  ColorType,
  CrosshairMode,
  HistogramSeries,
  createChart,
  type IChartApi,
  type ISeriesApi,
  type UTCTimestamp,
} from "lightweight-charts"
import * as React from "react"

import { useThemeVersion } from "@/hooks/use-theme-version"
import { formatCandleDate, type Candle, type VolumeBar } from "@/lib/candles"
import { formatPrice, formatVolume, type Currency, type PriceConvention } from "@/lib/market"
import { readColorToken, withAlpha } from "@/lib/theme-tokens"
import { cn } from "@/lib/utils"

/** Màu dự phòng khi chưa đọc được token (SSR, hoặc CSS chưa kịp áp). */
const FALLBACK = {
  rise: "#16a34a",
  fall: "#dc2626",
  text: "#71717a",
  grid: "#e4e4e7",
} as const

/**
 * Chiều của một nến — **ba** trạng thái, không phải hai.
 *
 * Lightweight Charts tự gộp "đứng giá" (mở = đóng) vào nhánh tăng, và viết
 * `close >= open` cũng vậy. Nhưng `--price-rise` mang nghĩa *tăng* ở cả hai quy
 * ước, nên tô nến 0% bằng màu đó là nói sai — ngay cạnh badge "không đổi".
 */
function trendOf(c: Candle): "rise" | "fall" | "flat" {
  if (c.close > c.open) return "rise"
  if (c.close < c.open) return "fall"
  return "flat"
}

const readoutTone = {
  rise: "text-price-rise",
  fall: "text-price-fall",
  flat: "text-muted-foreground",
} as const

type PriceChartProps = {
  candles: Candle[]
  volumes: VolumeBar[]
  currency: Currency
  /**
   * Chỉ dùng để biết **lúc nào phải đọc lại màu**: quy ước đổi thì `--price-rise`
   * đổi giá trị, mà tên biến thì không đổi nên không tự phát hiện được.
   */
  convention: PriceConvention
  className?: string
}

/**
 * Chart nến + khối lượng, dựng trên TradingView Lightweight Charts.
 *
 * Hai điểm khác hẳn chart Recharts ở Dashboard:
 *
 * 1. **Vẽ bằng canvas, không phải SVG.** Canvas không có DOM để resolve `var()`,
 *    nên không truyền được `var(--price-rise)` vào — phải đọc giá trị đã tính ra
 *    rồi mới đưa cho chart, và đọc lại mỗi lần đổi theme hoặc đổi quy ước màu.
 * 2. **Không assert được nội dung canvas.** Nên phần số liệu của nến đang trỏ
 *    được render ra HTML thật ở dưới: vừa là thứ người dùng cần (bảng O/H/L/C
 *    như mọi app chứng khoán), vừa là bề mặt để test kiểm chứng được.
 */
export function PriceChart({ candles, volumes, currency, convention, className }: PriceChartProps) {
  const containerRef = React.useRef<HTMLDivElement>(null)
  const chartRef = React.useRef<IChartApi | null>(null)
  const candleSeriesRef = React.useRef<ISeriesApi<"Candlestick"> | null>(null)
  const volumeSeriesRef = React.useRef<ISeriesApi<"Histogram"> | null>(null)
  const byTimeRef = React.useRef(new Map<number, Candle>())
  const candlesRef = React.useRef(candles)
  // Mảng nến mà chart đã `fitContent` gần nhất. Dữ liệu nến giờ được đặt lại mỗi
  // lần đổi theme (màu nến đứng giá lấy từ token), nhưng chỉ fit khi đổi *mã*,
  // để đổi theme không làm mất vùng người dùng đang zoom.
  const fittedRef = React.useRef<Candle[] | null>(null)

  // Giữ luôn mảng nến đang trỏ cùng với nến được hover: khi đổi mã, `candles` là
  // mảng khác nên readout tự quay về nến cuối, không cần effect reset state.
  const [hover, setHover] = React.useState<{ source: Candle[]; candle: Candle } | null>(null)
  const hovered = hover && hover.source === candles ? hover.candle : null
  const readout = hovered ?? candles[candles.length - 1]

  const themeVersion = useThemeVersion()

  React.useEffect(() => {
    const el = containerRef.current
    if (!el) return

    const chart = createChart(el, {
      autoSize: true,
      layout: {
        background: { type: ColorType.Solid, color: "transparent" },
        fontSize: 12,
      },
      grid: { vertLines: { visible: false } },
      rightPriceScale: { borderVisible: false, scaleMargins: { top: 0.08, bottom: 0.26 } },
      timeScale: { borderVisible: false, fixLeftEdge: true, fixRightEdge: true },
      crosshair: { mode: CrosshairMode.Magnet },
    })

    const candleSeries = chart.addSeries(CandlestickSeries, { borderVisible: false })
    // `priceScaleId: ""` = thang đo chồng lên, để volume nằm dưới đáy chart giá
    // thay vì chiếm một khung riêng.
    const volumeSeries = chart.addSeries(HistogramSeries, {
      priceFormat: { type: "volume" },
      priceScaleId: "",
    })
    volumeSeries.priceScale().applyOptions({ scaleMargins: { top: 0.8, bottom: 0 } })

    chart.subscribeCrosshairMove((param) => {
      const time = param.time
      if (typeof time !== "number") {
        setHover(null)
        return
      }
      const candle = byTimeRef.current.get(time)
      setHover(candle ? { source: candlesRef.current, candle } : null)
    })

    chartRef.current = chart
    candleSeriesRef.current = candleSeries
    volumeSeriesRef.current = volumeSeries

    return () => {
      chart.remove()
      chartRef.current = null
      candleSeriesRef.current = null
      volumeSeriesRef.current = null
      // Chart mới (StrictMode dựng lại, hoặc remount) chưa được fit lần nào.
      fittedRef.current = null
    }
  }, [])

  // Bảng tra nến theo thời gian, cho crosshair.
  React.useEffect(() => {
    byTimeRef.current = new Map(candles.map((c) => [c.time, c]))
    candlesRef.current = candles
  }, [candles])

  // Màu: đọc token từ chính container (nên ăn theo `data-price-convention` bên
  // dưới), chạy lại khi đổi theme hoặc đổi quy ước.
  React.useEffect(() => {
    const el = containerRef.current
    const chart = chartRef.current
    if (!el || !chart) return

    const rise = readColorToken("--price-rise", FALLBACK.rise, el)
    const fall = readColorToken("--price-fall", FALLBACK.fall, el)
    const text = readColorToken("--muted-foreground", FALLBACK.text, el)
    const grid = readColorToken("--border", FALLBACK.grid, el)

    chart.applyOptions({
      layout: { textColor: text },
      grid: { horzLines: { color: grid } },
      crosshair: {
        horzLine: { color: text, labelBackgroundColor: text },
        vertLine: { color: text, labelBackgroundColor: text },
      },
    })

    candleSeriesRef.current?.applyOptions({
      upColor: rise,
      downColor: fall,
      wickUpColor: rise,
      wickDownColor: fall,
    })

    // Nến đứng giá mang màu trung tính riêng (thư viện tự xếp nó vào nhánh
    // tăng). Màu đó lấy từ token nên phải đặt lại dữ liệu mỗi lần đổi theme.
    candleSeriesRef.current?.setData(
      candles.map((c) => {
        const bar = { ...c, time: c.time as UTCTimestamp }
        return trendOf(c) === "flat"
          ? { ...bar, color: text, borderColor: text, wickColor: text }
          : bar
      }),
    )
    if (fittedRef.current !== candles) {
      chart.timeScale().fitContent()
      fittedRef.current = candles
    }

    // Cột volume mờ hơn thân nến để không tranh chỗ với đường giá.
    const soft = {
      rise: withAlpha(rise, 0.35, FALLBACK.rise),
      fall: withAlpha(fall, 0.35, FALLBACK.fall),
      flat: withAlpha(text, 0.35, FALLBACK.text),
    }
    volumeSeriesRef.current?.setData(
      volumes.map((v, i) => ({
        time: v.time as UTCTimestamp,
        value: v.value,
        color: candles[i] ? soft[trendOf(candles[i])] : soft.flat,
      })),
    )
  }, [candles, volumes, themeVersion, convention])

  const volumeOf = readout ? volumes.find((v) => v.time === readout.time)?.value : undefined

  return (
    <div className={cn("flex flex-col gap-3", className)}>
      {readout && (
        <dl
          className="flex flex-wrap items-baseline gap-x-4 gap-y-1 text-xs"
          aria-label="Số liệu phiên đang xem"
          data-testid="ohlc-readout"
        >
          <div data-field="date" className="text-muted-foreground">
            <dt className="sr-only">Phiên</dt>
            <dd className="font-medium">{formatCandleDate(readout.time)}</dd>
          </div>
          {(
            [
              ["open", "Mở", readout.open],
              ["high", "Cao", readout.high],
              ["low", "Thấp", readout.low],
              ["close", "Đóng", readout.close],
            ] as const
          ).map(([field, label, value]) => (
            <div key={field} data-field={field} className="flex items-baseline gap-1">
              <dt className="text-muted-foreground">{label}</dt>
              <dd
                className={cn("font-medium tabular-nums", readoutTone[trendOf(readout)])}
              >
                {formatPrice(value, currency)}
              </dd>
            </div>
          ))}
          {volumeOf !== undefined && (
            <div data-field="volume" className="flex items-baseline gap-1">
              <dt className="text-muted-foreground">KL</dt>
              <dd className="font-medium tabular-nums">{formatVolume(volumeOf)}</dd>
            </div>
          )}
        </dl>
      )}
      <div
        ref={containerRef}
        data-price-convention={convention}
        data-testid="price-chart"
        className="h-64 w-full"
      />
    </div>
  )
}
