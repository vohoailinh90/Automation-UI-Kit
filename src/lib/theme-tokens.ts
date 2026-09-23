/**
 * Đọc token màu của theme ra **giá trị màu cụ thể**.
 *
 * Chart ở Dashboard vẽ bằng SVG (Recharts) nên truyền thẳng `var(--chart-1)` là
 * chạy. Chart giá thì vẽ bằng **canvas**, mà canvas không có DOM để resolve
 * `var()` — đưa chuỗi `"var(--chart-1)"` vào là màu hỏng chứ không báo lỗi. Nên
 * ở đây phải tự lấy giá trị đã tính của biến CSS rồi mới đưa cho chart.
 */

let probe: CanvasRenderingContext2D | null | undefined

function getProbe() {
  if (probe === undefined) {
    const canvas = document.createElement("canvas")
    canvas.width = 1
    canvas.height = 1
    probe = canvas.getContext("2d", { willReadFrequently: true })
  }
  return probe
}

/**
 * Chuẩn hoá một màu CSS bất kỳ về `rgb()` / `rgba()`.
 *
 * Token trong `src/index.css` viết bằng `oklch()`. Gán chuỗi đó vào `fillStyle`
 * thì Chromium **nhận**, nhưng đọc lại vẫn trả về nguyên `"oklch(...)"` — nên
 * kiểm tra kiểu "gán rồi đọc lại" không phát hiện được gì, và chuỗi oklch sẽ đi
 * thẳng xuống parser màu riêng của thư viện chart rồi ném
 * `Failed to parse color`.
 *
 * Nên ở đây **tô thật một điểm ảnh rồi đọc byte màu ra**. Trình duyệt tự
 * rasterize, nên vào cú pháp CSS nào cũng ra sRGB cụ thể.
 */
export function normalizeColor(color: string, fallback: string): string {
  if (!color) return fallback
  const ctx = getProbe()
  if (!ctx) return fallback

  // Màu không hợp lệ thì canvas **im lặng giữ nguyên** fillStyle cũ, nên phải so
  // với một mốc đã biết mới phân biệt được "không hợp lệ" và "đúng là màu đó".
  ctx.fillStyle = "#000000"
  ctx.fillStyle = color
  const first = ctx.fillStyle
  ctx.fillStyle = "#ffffff"
  ctx.fillStyle = color
  if (first !== ctx.fillStyle) return fallback

  ctx.clearRect(0, 0, 1, 1)
  ctx.fillRect(0, 0, 1, 1)
  const [r, g, b, a] = ctx.getImageData(0, 0, 1, 1).data
  return a === 255 ? `rgb(${r}, ${g}, ${b})` : `rgba(${r}, ${g}, ${b}, ${(a / 255).toFixed(3)})`
}

/**
 * Giá trị đã tính của một biến CSS, đã chuẩn hoá về dạng màu canvas hiểu.
 *
 * `from` mặc định là `:root`, nhưng truyền vào một element cụ thể thì sẽ lấy
 * được cả các biến bị **ghi đè theo nhánh DOM** — ví dụ `--price-rise` đổi theo
 * `data-price-convention` đặt trên container, chứ không phải trên `<html>`.
 */
export function readColorToken(name: string, fallback: string, from?: Element | null): string {
  const el = from ?? (typeof document === "undefined" ? null : document.documentElement)
  if (!el) return fallback
  const raw = getComputedStyle(el).getPropertyValue(name).trim()
  return normalizeColor(raw, fallback)
}

/**
 * Thêm độ trong suốt vào một màu đã chuẩn hoá.
 *
 * Không nối thêm `"55"` vào chuỗi hex vì canvas chỉ trả hex khi màu **đục**;
 * token nào vốn đã có alpha (ví dụ `--border` ở dark mode là `oklch(1 0 0 / 10%)`)
 * sẽ được trả về dạng `rgba(...)`, nối chuỗi vào là hỏng màu.
 */
export function withAlpha(color: string, alpha: number, fallback: string): string {
  const normalized = normalizeColor(color, "")
  if (!normalized) return fallback

  if (normalized.startsWith("#")) {
    const hex = normalized.slice(1)
    const full =
      hex.length === 3 || hex.length === 4
        ? hex
            .slice(0, 3)
            .split("")
            .map((c) => c + c)
            .join("")
        : hex.slice(0, 6)
    const value = Number.parseInt(full, 16)
    if (Number.isNaN(value)) return fallback
    return `rgba(${(value >> 16) & 255}, ${(value >> 8) & 255}, ${value & 255}, ${alpha})`
  }

  const parts = normalized.match(/-?[\d.]+/g)
  if (!parts || parts.length < 3) return fallback
  // Nhân alpha cũ với alpha mới, để màu vốn đã mờ không bị làm đậm lên.
  const existing = parts.length > 3 ? Number(parts[3]) : 1
  return `rgba(${parts[0]}, ${parts[1]}, ${parts[2]}, ${(existing * alpha).toFixed(3)})`
}
