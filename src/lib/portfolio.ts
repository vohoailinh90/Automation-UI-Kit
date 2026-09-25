/**
 * Dữ liệu mẫu cho dashboard Portfolio: một tài khoản cổ phiếu Nhật, tính bằng ¥.
 *
 * **Dữ liệu mẫu, không phải danh mục thật, không phải lời khuyên đầu tư.**
 *
 * Dựng **trên chính dữ liệu của Watchlist** (`instruments` + `generateCandles`),
 * không sinh giá riêng: giá hiện tại, % hôm nay và chuỗi 90 phiên của mỗi mã ở
 * đây trùng khớp với bảng giá và chart nến bên Watchlist. Hai trang cùng kit mà
 * nói hai giá khác nhau cho cùng một mã là thứ người xem thấy ngay.
 *
 * Chỉ một đơn vị tiền là cố ý: cộng ¥ với $ cần tỉ giá thật theo từng phiên,
 * mà bịa một tỉ giá tĩnh thì còn tệ hơn là không cộng (xem cột Giá ở Watchlist).
 */

import { closingPrices, generateCandles, type Candle } from "@/lib/candles"
import { instrumentOf, type Instrument } from "@/lib/market"

export type Holding = {
  ticker: string
  shares: number
  /** Giá vốn bình quân mỗi cổ phiếu, ¥. */
  cost: number
  sector: string
}

/** Cổ phiếu Nhật giao dịch theo lô 100, nên số lượng là bội của 100. */
export const holdings: Holding[] = [
  { ticker: "7267.T", shares: 300, cost: 1720, sector: "Ô tô" },
  { ticker: "6367.T", shares: 100, cost: 20450, sector: "Máy móc" },
  { ticker: "8306.T", shares: 500, cost: 1380, sector: "Ngân hàng" },
  { ticker: "6501.T", shares: 200, cost: 3120, sector: "Điện – điện tử" },
  { ticker: "9432.T", shares: 2000, cost: 158, sector: "Viễn thông" },
]

/** Tiền mặt, ¥ — chọn để tổng tài sản tròn 5 triệu cho dễ đọc. */
export const CASH = 625_100

export type Position = Holding & {
  instrument: Instrument
  candles: Candle[]
  closes: number[]
  price: number
  /** Giá đóng cửa phiên trước — suy ngược từ % hôm nay, như `generateCandles`. */
  prevClose: number
  value: number
  costBasis: number
  pl: number
  plPct: number
  dayChange: number
  weight: number
}

function buildPositions(): Position[] {
  const rows = holdings.map((h) => {
    const instrument = instrumentOf(h.ticker)
    if (!instrument || instrument.currency !== "JPY") {
      throw new Error(`Danh mục mẫu chỉ nhận mã Nhật có trong Watchlist: ${h.ticker}`)
    }
    const series = generateCandles(instrument)
    const price = instrument.price
    const prevClose = price / (1 + instrument.changePct / 100)
    const value = h.shares * price
    const costBasis = h.shares * h.cost
    return {
      ...h,
      instrument,
      candles: series.candles,
      closes: closingPrices(series),
      price,
      prevClose,
      value,
      costBasis,
      pl: value - costBasis,
      plPct: ((value - costBasis) / costBasis) * 100,
      dayChange: h.shares * (price - prevClose),
      weight: 0,
    }
  })
  const total = rows.reduce((sum, r) => sum + r.value, 0) + CASH
  return rows.map((r) => ({ ...r, weight: r.value / total }))
}

export const positions: Position[] = buildPositions()

const invested = positions.reduce((sum, p) => sum + p.value, 0)
const costBasis = positions.reduce((sum, p) => sum + p.costBasis, 0)
const dayChange = positions.reduce((sum, p) => sum + p.dayChange, 0)

export const totals = {
  value: invested + CASH,
  invested,
  cash: CASH,
  costBasis,
  pl: invested - costBasis,
  plPct: ((invested - costBasis) / costBasis) * 100,
  dayChange,
  /** % so với tổng tài sản phiên trước (tiền mặt không đổi). */
  dayChangePct: (dayChange / (invested + CASH - dayChange)) * 100,
}

/**
 * Tổng tài sản theo từng phiên, cũ → mới: Σ số lượng × giá đóng cửa + tiền mặt.
 *
 * Giả định số lượng nắm giữ không đổi suốt 90 phiên — đủ cho dữ liệu mẫu. Danh
 * mục thật có mua/bán thì phải cộng theo lịch sử giao dịch, không nhân ngược
 * số lượng hôm nay về quá khứ.
 */
export const valueHistory = positions[0].candles.map((candle, i) => ({
  time: candle.time,
  value: positions.reduce((sum, p) => sum + p.shares * p.closes[i], 0) + CASH,
}))

/** Tỉ trọng theo ngành, kể cả tiền mặt, nhiều → ít. */
export function sectorAllocation() {
  const bySector = new Map<string, number>()
  for (const p of positions) bySector.set(p.sector, (bySector.get(p.sector) ?? 0) + p.value)
  return [
    ...[...bySector.entries()]
      .map(([sector, value]) => ({ sector, value }))
      .sort((a, b) => b.value - a.value),
    { sector: "Tiền mặt", value: CASH },
  ]
}
