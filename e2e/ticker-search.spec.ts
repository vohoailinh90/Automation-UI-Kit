import { expect, test } from "@playwright/test"

test.beforeEach(async ({ page }) => {
  await page.goto("/watchlist")
})

test("Ctrl+K mở bảng tìm mã", async ({ page }) => {
  await expect(page.getByRole("dialog")).toHaveCount(0)
  await page.keyboard.press("Control+k")
  await expect(page.getByRole("dialog")).toBeVisible()
})

test("bảng tìm mã có tên truy cập được", async ({ page }) => {
  await page.getByRole("button", { name: "Tìm mã..." }).click()
  await expect(page.getByRole("dialog", { name: "Tìm mã chứng khoán" })).toBeVisible()
})

test("tìm được bằng TÊN công ty chứ không chỉ bằng mã", async ({ page }) => {
  // Người dùng nhớ "Honda" trước khi nhớ "7267.T" — chỗ này dựa vào prop
  // `keywords`, mà bỏ đi thì mọi thứ khác vẫn chạy nên rất dễ mất âm thầm.
  await page.keyboard.press("Control+k")
  await page.getByPlaceholder("Gõ mã hoặc tên công ty...").fill("Honda")

  const items = page.locator("[cmdk-item]")
  await expect(items).toHaveCount(1)
  await expect(items.first()).toContainText("7267.T")
})

test("tìm bằng mã cũng ra đúng một kết quả", async ({ page }) => {
  await page.keyboard.press("Control+k")
  await page.getByPlaceholder("Gõ mã hoặc tên công ty...").fill("NVDA")
  await expect(page.locator("[cmdk-item]")).toHaveCount(1)
})

test("không khớp gì thì báo rỗng, không phải danh sách trống trơn", async ({ page }) => {
  await page.keyboard.press("Control+k")
  await page.getByPlaceholder("Gõ mã hoặc tên công ty...").fill("khongcomanay")

  await expect(page.locator("[cmdk-item]")).toHaveCount(0)
  await expect(page.getByText("Không tìm thấy mã nào.")).toBeVisible()
})

test("chọn một mã thì đóng bảng và chart đổi sang mã đó", async ({ page }) => {
  await page.keyboard.press("Control+k")
  await page.getByPlaceholder("Gõ mã hoặc tên công ty...").fill("Microsoft")
  await page.keyboard.press("Enter")

  await expect(page.getByRole("dialog")).toHaveCount(0)
  await expect(page.locator("[data-slot='card']").last()).toContainText("MSFT")
})

test("Escape đóng bảng và trả focus về đúng nút đã mở nó", async ({ page }) => {
  const trigger = page.getByRole("button", { name: "Tìm mã..." })
  await trigger.click()
  await expect(page.getByRole("dialog")).toBeVisible()

  await page.keyboard.press("Escape")
  await expect(page.getByRole("dialog")).toHaveCount(0)
  // Mất focus về <body> là người dùng bàn phím phải Tab lại từ đầu trang.
  await expect(trigger).toBeFocused()
})

test("Ctrl+K lần nữa thì đóng lại", async ({ page }) => {
  await page.keyboard.press("Control+k")
  await expect(page.getByRole("dialog")).toBeVisible()
  await page.keyboard.press("Control+k")
  await expect(page.getByRole("dialog")).toHaveCount(0)
})

test("chọn mã nằm ngoài bộ lọc thị trường thì chart vẫn đổi sang đúng mã đó", async ({ page }) => {
  // Lọc "Nhật" rồi tìm NVDA: trước đây `selected` chỉ tìm trong các dòng đã lọc,
  // rơi về dòng đầu, nên dialog đóng lại mà chart vẫn hiện Honda — lỗi im lặng.
  await page.getByLabel("Lọc theo thị trường").click()
  await page.getByRole("option", { name: "Nhật" }).click()
  await expect(page.locator("tbody")).not.toContainText("NVDA")

  await page.keyboard.press("Control+k")
  await page.getByPlaceholder("Gõ mã hoặc tên công ty...").fill("NVDA")
  await page.keyboard.press("Enter")

  await expect(page.locator("[data-slot='card']").last()).toContainText("NVIDIA Corp.")
  // Bảng cũng phải hiện được mã vừa chọn, và đánh dấu nó là đang xem.
  await expect(page.getByLabel("Lọc theo thị trường")).toContainText("Tất cả")
  await expect(page.locator("tbody tr[data-state='selected']")).toContainText("NVDA")
})

test("chọn mã nằm trong bộ lọc thì giữ nguyên bộ lọc", async ({ page }) => {
  // Chỉ nới bộ lọc khi thật sự cần — không phải lần tìm nào cũng xoá lựa chọn
  // của người dùng.
  await page.getByLabel("Lọc theo thị trường").click()
  await page.getByRole("option", { name: "Nhật" }).click()

  await page.keyboard.press("Control+k")
  await page.getByPlaceholder("Gõ mã hoặc tên công ty...").fill("Hitachi")
  await page.keyboard.press("Enter")

  await expect(page.locator("[data-slot='card']").last()).toContainText("Hitachi Ltd.")
  await expect(page.getByLabel("Lọc theo thị trường")).toContainText("Nhật")
  await expect(page.locator("tbody tr")).toHaveCount(5)
})
