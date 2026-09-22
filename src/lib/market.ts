/**
 * Lớp dữ liệu + quy ước thị trường dùng chung cho các UI chứng khoán.
 *
 * Toàn bộ số liệu ở đây là **dữ liệu mẫu sinh tại chỗ**, không gọi API thật và
 * không phải lời khuyên đầu tư. Mục đích là để các component chart/bảng có dữ
 * liệu đúng hình dạng thật mà dựng, và để test có đầu vào tất định.
 */

export type Market = "jp" | "us"

export type Currency = "JPY" | "USD"

export type Instrument = {
  ticker: string
  name: string
  market: Market
  currency: Currency
  /** Giá hiện tại, dạng số để bảng sort được — format lúc render. */
  price: number
  changePct: number
  volume: number
}

export const marketLabel: Record<Market, string> = {
  jp: "Nhật (Rakuten)",
  us: "Mỹ (Rakuten)",
}

const marketCurrency: Record<Market, Currency> = { jp: "JPY", us: "USD" }

/**
 * Quy ước màu tăng/giảm **không phải chuyện thẩm mỹ** mà là quy ước thị trường,
 * và hai quy ước lớn ngược hẳn nhau:
 *
 * - `western` — Mỹ/Âu: xanh lá = tăng, đỏ = giảm.
 * - `east-asian` — Nhật, Việt Nam, Trung Quốc, Hàn, Đài: **đỏ = tăng**, xanh = giảm.
 *
 * Nên một badge đỏ nói "tăng" hay "giảm" là tuỳ người đọc ở đâu. Chọn sai thì
 * người dùng đọc ngược hoàn toàn, chứ không phải chỉ xấu đi.
 *
 * Quy ước này cố ý đặt ở **cấp cả bảng**, không phải theo từng dòng theo sàn
 * niêm yết: một cột badge mà dòng Nhật hiểu theo kiểu này, dòng Mỹ hiểu theo
 * kiểu kia thì còn khó đọc hơn là chọn hẳn một bên. Các nền tảng đa thị trường
 * (Rakuten, IBKR, TradingView) đều cho chọn một quy ước cho cả app.
 */
export type PriceConvention = "western" | "east-asian"

export const priceConventions: readonly PriceConvention[] = ["east-asian", "western"] as const

export const priceConventionLabel: Record<PriceConvention, string> = {
  "east-asian": "Đông Á — đỏ tăng / xanh giảm",
  western: "Âu Mỹ — xanh tăng / đỏ giảm",
}

export function isPriceConvention(value: unknown): value is PriceConvention {
  return value === "western" || value === "east-asian"
}

/**
 * Chiều biến động, dạng chữ.
 *
 * Màu thì đảo theo quy ước, còn chữ thì không — nên chỗ nào cần *ý nghĩa* (nhãn
 * cho screen reader, tooltip) phải lấy ở đây chứ không suy từ màu. Người dùng
 * screen reader không "nghe" được màu đỏ là tăng hay giảm.
 */
export function changeDirection(changePct: number): "tăng" | "giảm" | "không đổi" {
  if (changePct > 0) return "tăng"
  if (changePct < 0) return "giảm"
  return "không đổi"
}

const currencyFormatters: Record<Currency, Intl.NumberFormat> = {
  // Cả hai đều format theo `en-US`, không phải `ja-JP`, là có chủ ý: locale
  // Nhật trả về ký hiệu Yên **fullwidth** `￥` (U+FFE5), nhìn rời hẳn ra giữa
  // văn bản Latin của giao diện. `en-US` cho `¥` (U+00A5) hẹp, khít hơn.
  //
  // Yên không dùng phần lẻ trên bảng giá, còn USD thì luôn 2 chữ số.
  JPY: new Intl.NumberFormat("en-US", { style: "currency", currency: "JPY", maximumFractionDigits: 0 }),
  USD: new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", minimumFractionDigits: 2 }),
}

export function formatPrice(value: number, currency: Currency) {
  return currencyFormatters[currency].format(value)
}

const compactVolume = new Intl.NumberFormat("en-US", { notation: "compact", maximumFractionDigits: 1 })

export function formatVolume(value: number) {
  return compactVolume.format(value)
}

export function formatPercent(value: number) {
  return `${value > 0 ? "+" : ""}${value.toFixed(2)}%`
}

export const instruments: Instrument[] = [
  { ticker: "7267.T", name: "Honda Motor", market: "jp", currency: "JPY", price: 1842, changePct: 1.42, volume: 8_420_000 },
  { ticker: "6367.T", name: "Daikin Industries", market: "jp", currency: "JPY", price: 19120, changePct: -0.83, volume: 1_120_000 },
  { ticker: "8306.T", name: "Mitsubishi UFJ FG", market: "jp", currency: "JPY", price: 1655, changePct: 0.31, volume: 24_800_000 },
  { ticker: "6501.T", name: "Hitachi Ltd.", market: "jp", currency: "JPY", price: 3894, changePct: 2.05, volume: 6_310_000 },
  { ticker: "AAPL", name: "Apple Inc.", market: "us", currency: "USD", price: 232.1, changePct: 0.94, volume: 48_900_000 },
  { ticker: "MSFT", name: "Microsoft Corp.", market: "us", currency: "USD", price: 418.5, changePct: -1.21, volume: 21_400_000 },
  { ticker: "NVDA", name: "NVIDIA Corp.", market: "us", currency: "USD", price: 126.8, changePct: 2.63, volume: 312_000_000 },
  { ticker: "BRK.B", name: "Berkshire Hathaway", market: "us", currency: "USD", price: 461.03, changePct: 0, volume: 3_050_000 },
]

export function instrumentOf(ticker: string) {
  return instruments.find((i) => i.ticker === ticker)
}

export { marketCurrency }
