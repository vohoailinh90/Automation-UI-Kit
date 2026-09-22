import { expect, test } from "@playwright/test"

import { readStorage, SETTINGS_KEY } from "./helpers"

test.beforeEach(async ({ page }) => {
  await page.goto("/settings")
})

const reminderSwitch = (page: import("@playwright/test").Page) =>
  page.getByRole("switch", { name: "Nhắc milestone sắp tới hạn" })
const syncSwitch = (page: import("@playwright/test").Page) =>
  page.getByRole("switch", { name: "Đồng bộ watchlist với iSPEED" })

test("hai toggle là switch thật, đúng trạng thái mặc định", async ({ page }) => {
  await expect(reminderSwitch(page)).toBeVisible()
  await expect(syncSwitch(page)).toBeVisible()

  await expect(reminderSwitch(page)).toBeChecked()
  await expect(syncSwitch(page)).not.toBeChecked()
})

test("bật switch thì chữ mô tả đổi theo", async ({ page }) => {
  await expect(page.getByText("Chưa kết nối")).toBeVisible()

  await syncSwitch(page).click()

  await expect(syncSwitch(page)).toBeChecked()
  await expect(page.getByText("Đang bật (demo, chưa gọi API thật)")).toBeVisible()
})

test("Lưu thay đổi ghi xuống localStorage và báo đã lưu", async ({ page }) => {
  await page.getByLabel("Họ và tên").fill("Võ Hoài Linh (test)")
  await page.getByRole("button", { name: "Lưu thay đổi" }).click()

  await expect(page.getByText("Đã lưu vào trình duyệt")).toBeVisible()

  const stored = await readStorage(page, "local", SETTINGS_KEY)
  expect(stored).toContain("(test)")
})

test("cấu hình sống sót qua reload — cả sáu trường", async ({ page }) => {
  // Đổi MỌI trường sang giá trị khác mặc định. Nếu chỉ đổi vài trường thì
  // nhánh hợp lệ của `coerceSettings` cho các trường còn lại không bao giờ
  // được chạy tới — hỏng cũng không ai biết vì giá trị trùng mặc định.
  await page.getByLabel("Họ và tên").fill("Tên đã đổi")
  await page.getByLabel("Email").fill("doi@example.com")
  await page.getByLabel("Nơi làm việc").fill("Tokyo, Nhật Bản")
  await page.getByLabel("Ngôn ngữ ưu tiên").click()
  await page.getByRole("option", { name: "日本語" }).click()

  await reminderSwitch(page).click()
  await syncSwitch(page).click()

  await page.getByRole("button", { name: "Lưu thay đổi" }).click()
  await expect(page.getByText("Đã lưu vào trình duyệt")).toBeVisible()

  await page.reload()

  await expect(page.getByLabel("Họ và tên")).toHaveValue("Tên đã đổi")
  await expect(page.getByLabel("Email")).toHaveValue("doi@example.com")
  await expect(page.getByLabel("Nơi làm việc")).toHaveValue("Tokyo, Nhật Bản")
  await expect(page.locator("#language")).toContainText("日本語")
  await expect(reminderSwitch(page)).not.toBeChecked()
  await expect(syncSwitch(page)).toBeChecked()
})

test("bấm hai toggle trong cùng một tick không làm mất thay đổi nào", async ({ page }) => {
  // Cùng một task JS: React chưa kịp re-render giữa hai handler, nên một bản
  // cài đặt đọc từ closure sẽ ghi đè mất thay đổi đầu.
  await page.evaluate(() => {
    const switches = document.querySelectorAll<HTMLElement>('[role="switch"]')
    switches[0].click()
    switches[1].click()
  })

  await expect(reminderSwitch(page)).not.toBeChecked()
  await expect(syncSwitch(page)).toBeChecked()

  const stored = await readStorage(page, "local", SETTINGS_KEY)
  expect(stored).toContain('"milestoneReminder":false')
  expect(stored).toContain('"syncWatchlist":true')
})
