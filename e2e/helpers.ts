import type { Page } from "@playwright/test"

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
    const orig = Storage.prototype.getItem
    const w = window as unknown as { __restoreRead?: () => void }
    Storage.prototype.getItem = function (this: Storage, name: string) {
      if (name === blocked) throw new DOMException("SecurityError")
      return orig.call(this, name)
    }
    w.__restoreRead = () => {
      Storage.prototype.getItem = orig
    }
  }, key)
}

/** Bỏ chặn đọc sau khi trang đã mount xong (mô phỏng storage hồi phục). */
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

export async function readStorage(page: Page, area: "local" | "session", key: string) {
  return page.evaluate(
    ([a, k]) => (a === "local" ? localStorage : sessionStorage).getItem(k),
    [area, key] as const,
  )
}
