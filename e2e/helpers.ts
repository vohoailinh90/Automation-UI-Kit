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
