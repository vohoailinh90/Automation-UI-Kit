import AxeBuilder from "@axe-core/playwright"
import type { Locator, Page } from "@playwright/test"

export const SETTINGS_KEY = "automation-ui-kit-settings"
export const TASKS_KEY = "automation-ui-kit-tasks"

/**
 * Các helper dưới đây vá `Storage.prototype` để mô phỏng trình duyệt chặn
 * localStorage/sessionStorage (chế độ riêng tư, hết quota, policy của tổ chức).
 * Không có cách nào khác để dựng lại tình huống đó từ bên ngoài, nên phần
 * "chọc vào internal" được gom hết vào một chỗ thay vì rải khắp các spec.
 */

/** Chặn MỌI lệnh ghi storage, áp dụng ngay lập tức cho trang đang mở. */
export async function blockWrites(page: Page) {
  await page.evaluate(() => {
    const w = window as unknown as { __origSetItem?: typeof Storage.prototype.setItem }
    w.__origSetItem ??= Storage.prototype.setItem
    Storage.prototype.setItem = () => {
      throw new DOMException("QuotaExceededError")
    }
  })
}

/** Bỏ chặn ghi, trả `setItem` về nguyên bản. */
export async function restoreWrites(page: Page) {
  await page.evaluate(() => {
    const w = window as unknown as { __origSetItem?: typeof Storage.prototype.setItem }
    if (w.__origSetItem) Storage.prototype.setItem = w.__origSetItem
  })
}

/**
 * Chặn việc ĐỌC đúng một key, cài trước khi code của app chạy.
 * Dùng để dựng lại tình huống "app không đọc được bản đã lưu".
 */
export async function blockReadOf(page: Page, key: string) {
  await page.addInitScript((blocked: string) => {
    // `addInitScript` chạy lại ở MỌI lần navigate, còn `restoreReads` chỉ sửa
    // prototype của document hiện tại — nên nếu không có cờ bền vững thì một
    // lần reload sau khi "hồi phục" sẽ âm thầm bật lại lỗi. `window.name`
    // sống qua các lần điều hướng cùng tab, nên dùng nó làm cờ đó.
    const RESTORED = "storage-read-restored"
    if (window.name === RESTORED) return

    const orig = Storage.prototype.getItem
    const w = window as unknown as { __restoreRead?: () => void }
    Storage.prototype.getItem = function (this: Storage, name: string) {
      if (name === blocked) throw new DOMException("SecurityError")
      return orig.call(this, name)
    }
    w.__restoreRead = () => {
      Storage.prototype.getItem = orig
      window.name = RESTORED
    }
  }, key)
}

/**
 * Bỏ chặn đọc sau khi trang đã mount xong (mô phỏng storage hồi phục).
 * Trạng thái "đã hồi phục" giữ qua cả navigate/reload sau đó.
 */
export async function restoreReads(page: Page) {
  await page.evaluate(() => {
    const w = window as unknown as { __restoreRead?: () => void }
    w.__restoreRead?.()
  })
}

/** Ghi thẳng một giá trị vào storage trước khi app đọc. */
export async function seedStorage(
  page: Page,
  area: "local" | "session",
  key: string,
  value: unknown,
) {
  await page.evaluate(
    ([a, k, v]) => {
      const store = a === "local" ? localStorage : sessionStorage
      store.setItem(k as string, JSON.stringify(v))
    },
    [area, key, value] as const,
  )
}

/**
 * Ghi thẳng một chuỗi thô, KHÔNG qua `JSON.stringify` — cần cái này mới chạm
 * tới được nhánh `JSON.parse` ném lỗi, thứ mà `seedStorage` không bao giờ
 * dựng lại được vì nó luôn sinh ra JSON hợp lệ.
 */
export async function seedRawStorage(
  page: Page,
  area: "local" | "session",
  key: string,
  raw: string,
) {
  await page.evaluate(
    ([a, k, v]) => {
      const store = a === "local" ? localStorage : sessionStorage
      store.setItem(k, v)
    },
    [area, key, raw] as const,
  )
}

export async function readStorage(page: Page, area: "local" | "session", key: string) {
  return page.evaluate(
    ([a, k]) => (a === "local" ? localStorage : sessionStorage).getItem(k),
    [area, key] as const,
  )
}

/**
 * Chạy axe và rút gọn kết quả thành từng dòng "rule: element — lý do", để khi
 * đỏ thì đọc được ngay là element nào, tỉ lệ bao nhiêu.
 */
export async function axeViolations(page: Page) {
  const { violations } = await new AxeBuilder({ page }).analyze()
  return violations.flatMap((v) =>
    v.nodes.map((n) => `${v.id}: ${n.target.join(" ")} — ${n.failureSummary?.split("\n")[1] ?? ""}`),
  )
}

/** Mở trang ở theme chỉ định; `dark` được ghi vào storage trước khi app đọc. */
export async function gotoWithTheme(page: Page, path: string, theme: "light" | "dark") {
  if (theme === "dark") {
    await page.addInitScript(() => localStorage.setItem("automation-ui-kit-theme", "dark"))
  }
  await page.goto(path)
}

/**
 * Tương phản WCAG giữa **màu nền** của `target` và màu thật phía sau `against`
 * — cho mảng màu mang thông tin (ô tracker, nút đang chọn), thứ axe không đo.
 *
 * Màu được rasterize qua canvas nên `oklch()` hay `color-mix()` đều ra sRGB cụ
 * thể; nền phía sau được trộn từ các tổ tiên tới lớp đặc đầu tiên. Màu không
 * hợp lệ thì canvas im lặng giữ màu cũ, nên phát hiện bằng hai mốc và trả
 * `null` — test phải coi `null` là đỏ, không phải "đen, tương phản cao".
 */
export async function backgroundContrast(target: Locator, against: Locator) {
  const other = await against.elementHandle()
  return target.evaluate((el, bgEl) => {
    const canvas = document.createElement("canvas")
    canvas.width = canvas.height = 1
    const ctx = canvas.getContext("2d", { willReadFrequently: true })!
    const rgba = (css: string) => {
      ctx.fillStyle = "#000"
      ctx.fillStyle = css
      const first = ctx.fillStyle
      ctx.fillStyle = "#fff"
      ctx.fillStyle = css
      if (ctx.fillStyle !== first) return null
      ctx.clearRect(0, 0, 1, 1)
      ctx.fillRect(0, 0, 1, 1)
      return Array.from(ctx.getImageData(0, 0, 1, 1).data)
    }
    const over = (top: number[], bottom: number[]) => {
      const a = top[3] / 255
      return [0, 1, 2].map((i) => Math.round(top[i] * a + bottom[i] * (1 - a)))
    }
    // Màu thật của một node: nền của nó trộn lên nền các tổ tiên tới lớp đặc.
    const composite = (node: Element | null) => {
      const layers: number[][] = []
      for (let n = node; n; n = n.parentElement) {
        const c = rgba(getComputedStyle(n).backgroundColor)
        if (!c) return null
        if (c[3] > 0) layers.push(c)
        if (c[3] === 255) break
      }
      let base = [255, 255, 255]
      for (const layer of layers.reverse()) base = over(layer, base)
      return base
    }
    const lum = (c: number[]) => {
      const f = (v: number) => {
        const x = v / 255
        return x <= 0.03928 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4
      }
      return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2])
    }
    const fg = composite(el)
    const bg = composite(bgEl as Element | null)
    if (!fg || !bg) return null
    const [hi, lo] = [lum(fg), lum(bg)].sort((x, y) => y - x)
    return (hi + 0.05) / (lo + 0.05)
  }, other)
}
