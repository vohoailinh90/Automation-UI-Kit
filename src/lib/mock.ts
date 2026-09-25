/**
 * Nền chung cho mọi dữ liệu mẫu trong kit.
 *
 * Hai nguyên tắc, áp cho cả nến ở Watchlist lẫn số liệu của các dashboard mẫu:
 *
 * 1. **Tất định.** Seed lấy từ một chuỗi (mã chứng khoán, tên job...), không
 *    dùng `Math.random()`: cùng đầu vào luôn ra cùng số liệu, nên test e2e so
 *    được con số cụ thể và người xem không thấy biểu đồ nhảy mỗi lần render.
 * 2. **Neo vào một ngày cố định**, không phải "hôm nay": dữ liệu mẫu mà trôi theo
 *    ngày chạy thì test sẽ đỏ vào một sáng nào đó không vì lý do gì.
 *
 * Không có gì ở đây là dữ liệu thật — khi copy dashboard sang repo khác, thay
 * lớp `src/lib/*` bằng nguồn dữ liệu của repo đó, đừng copy phần mẫu.
 */

/** Ngày "hôm nay" của mọi dữ liệu mẫu (00:00 UTC). */
export const MOCK_TODAY = "2026-09-18"

/** mulberry32 — PRNG 32-bit gọn, đủ tốt cho dữ liệu minh hoạ. */
export function mulberry32(seed: number) {
  let state = seed | 0
  return function next() {
    state = (state + 0x6d2b79f5) | 0
    let t = Math.imul(state ^ (state >>> 15), 1 | state)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

export function seedOf(text: string) {
  let hash = 0
  for (let i = 0; i < text.length; i += 1) hash = (Math.imul(31, hash) + text.charCodeAt(i)) | 0
  return hash
}

/** PRNG đã seed sẵn theo một chuỗi — cách dùng thường gặp nhất. */
export function randomFor(text: string) {
  return mulberry32(seedOf(text))
}

const DAY_SECONDS = 86_400

/** Unix timestamp (giây) của 00:00 UTC ngày `MOCK_TODAY` lùi `daysAgo` ngày. */
export function mockDay(daysAgo: number) {
  return Math.floor(Date.parse(`${MOCK_TODAY}T00:00:00Z`) / 1000) - daysAgo * DAY_SECONDS
}

/**
 * Định dạng ngày cho dữ liệu mẫu, dạng `dd/mm`.
 *
 * Đọc theo UTC vì mốc được dựng ở 00:00 UTC: để trình duyệt tự quy về giờ địa
 * phương thì máy ở múi giờ âm sẽ lùi mất một ngày. Tự ghép chuỗi thay vì dùng
 * `Intl` với locale `vi-VN`: bản ICU của Node trả `18-09`, của Chromium trả
 * `18/09` — test và người đọc phải thấy cùng một chuỗi.
 */
export function formatShortDate(time: number) {
  const date = new Date(time * 1000)
  const dd = String(date.getUTCDate()).padStart(2, "0")
  const mm = String(date.getUTCMonth() + 1).padStart(2, "0")
  return `${dd}/${mm}`
}
