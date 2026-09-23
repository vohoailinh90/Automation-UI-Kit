/**
 * Sinh dữ liệu nến OHLC mẫu cho chart giá.
 *
 * Hai ràng buộc làm nên cách viết ở đây:
 *
 * 1. **Tất định.** Seed lấy từ chính mã chứng khoán, không dùng `Math.random()`.
 *    Cùng một mã luôn ra cùng một chuỗi nến, nên test e2e so sánh được và người
 *    xem không thấy chart nhảy mỗi lần re-render.
 * 2. **Không mâu thuẫn với bảng giá.** Chốt **hai** mốc chứ không phải một:
 *    phiên cuối đóng đúng bằng giá ở bảng, *và* phiên trước đó đóng ở mức sao
 *    cho thay đổi trong ngày đúng bằng % ở bảng. Chỉ chốt giá cuối là chưa đủ:
 *    mỗi nến mở đúng ở giá đóng của nến trước, nên thân nến cuối **chính là**
 *    thay đổi trong ngày — chốt thiếu thì bảng ghi +1.42% mà nến cuối lại giảm.
 */

/**
 * `time` là unix timestamp (giây, mốc 00:00 UTC của phiên).
 *
 * Dùng số chứ không dùng chuỗi `YYYY-MM-DD` vì lightweight-charts chuẩn hoá
 * chuỗi ngày thành object `BusinessDay` bên trong. Khi đọc ngược lại từ sự kiện
 * crosshair thì kiểu trả về sẽ không còn giống thứ mình đưa vào, phải đoán —
 * timestamp số thì đưa vào sao, lấy ra vậy.
 */
export type Candle = {
  time: number
  open: number
  high: number
  low: number
  close: number
}

export type VolumeBar = { time: number; value: number }

/**
 * Chuỗi nến neo vào một ngày cố định chứ không phải "hôm nay": dữ liệu mẫu mà
 * trôi theo ngày chạy thì test sẽ đỏ vào một sáng nào đó không vì lý do gì.
 */
const ANCHOR = "2026-09-18"

/** mulberry32 — PRNG 32-bit gọn, đủ tốt cho dữ liệu minh hoạ. */
function mulberry32(seed: number) {
  let state = seed | 0
  return function next() {
    state = (state + 0x6d2b79f5) | 0
    let t = Math.imul(state ^ (state >>> 15), 1 | state)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

function seedOf(text: string) {
  let hash = 0
  for (let i = 0; i < text.length; i += 1) hash = (Math.imul(31, hash) + text.charCodeAt(i)) | 0
  return hash
}

/** Lấy `count` phiên gần nhất tính lùi từ `ANCHOR`, bỏ thứ bảy và chủ nhật. */
function tradingDays(count: number): number[] {
  const days: number[] = []
  const cursor = new Date(`${ANCHOR}T00:00:00Z`)
  while (days.length < count) {
    const weekday = cursor.getUTCDay()
    if (weekday !== 0 && weekday !== 6) days.push(Math.floor(cursor.getTime() / 1000))
    cursor.setUTCDate(cursor.getUTCDate() - 1)
  }
  return days.reverse()
}

/**
 * Định dạng mốc thời gian của nến.
 *
 * Ép `timeZone: "UTC"` vì timestamp được dựng ở 00:00 UTC: để trình duyệt tự
 * quy về giờ địa phương thì máy ở múi giờ âm sẽ lùi mất một ngày.
 */
const candleDateFormat = new Intl.DateTimeFormat("vi-VN", {
  timeZone: "UTC",
  day: "2-digit",
  month: "2-digit",
  year: "numeric",
})

export function formatCandleDate(time: number) {
  return candleDateFormat.format(new Date(time * 1000))
}

export type CandleSeries = { candles: Candle[]; volumes: VolumeBar[] }

/** Những gì bảng giá đang hiện cho một mã — chuỗi nến sinh ra phải khớp với nó. */
export type Quote = {
  /** Dùng làm seed, nên mỗi mã có "tính cách" giá riêng nhưng ổn định. */
  ticker: string
  /** Giá đóng cửa của phiên cuối. */
  price: number
  /** % thay đổi của phiên cuối so với phiên trước. */
  changePct: number
  /** Khối lượng trung bình, dùng để scale dải volume. */
  volume: number
}

export function generateCandles(quote: Quote, count = 90): CandleSeries {
  const rand = mulberry32(seedOf(quote.ticker))
  const days = tradingDays(count)

  // Bước 1: đi bộ ngẫu nhiên lấy chuỗi close thô, xuất phát từ 1. Vẫn rút đủ
  // `count` bước dù bước cuối bị thay ở dưới: giữ nguyên số lần gọi `rand` thì
  // phần sau của chuỗi (bóng nến, volume) không bị xáo theo.
  const walk: number[] = []
  let level = 1
  for (let i = 0; i < count; i += 1) {
    level *= 1 + (rand() - 0.5) * 0.036
    walk.push(level)
  }

  // Bước 2: kéo về thang giá thật, chốt hai mốc — phiên áp chót ở mức mà từ đó
  // đi tới giá cuối đúng bằng `changePct`, và phiên cuối đúng bằng `price`.
  const prevClose = quote.price / (1 + quote.changePct / 100)
  const scale = prevClose / walk[count - 2]
  const closes = walk.map((v, i) => (i === count - 1 ? quote.price : v * scale))

  const candles: Candle[] = []
  const volumes: VolumeBar[] = []

  for (let i = 0; i < count; i += 1) {
    const close = closes[i]
    const open = i === 0 ? close * (1 + (rand() - 0.5) * 0.01) : candles[i - 1].close
    // Bóng nến vẽ ra ngoài thân: giữ bất biến high >= max(open, close) >= min(...) >= low.
    const high = Math.max(open, close) * (1 + rand() * 0.012)
    const low = Math.min(open, close) * (1 - rand() * 0.012)
    candles.push({ time: days[i], open, high, low, close })
    volumes.push({ time: days[i], value: Math.round(quote.volume * (0.45 + rand() * 1.1)) })
  }

  return { candles, volumes }
}

/** Chuỗi close rút gọn cho sparkline — không cần cả OHLC. */
export function closingPrices(series: CandleSeries) {
  return series.candles.map((c) => c.close)
}
