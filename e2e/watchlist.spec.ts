import { expect, test } from "@playwright/test"

test.beforeEach(async ({ page }) => {
  await page.goto("/watchlist")
})

test("hiện đủ 8 mã khi chưa lọc", async ({ page }) => {
  await expect(page.locator("tbody tr")).toHaveCount(8)
})

test('lọc "Nhật" chỉ còn mã Nhật', async ({ page }) => {
  await page.getByLabel("Lọc theo thị trường").click()
  await page.getByRole("option", { name: "Nhật" }).click()

  await expect(page.locator("tbody tr")).toHaveCount(4)
  await expect(page.locator("tbody")).toContainText("7267.T")
  await expect(page.locator("tbody")).not.toContainText("AAPL")
})

test('lọc "Mỹ" chỉ còn mã Mỹ', async ({ page }) => {
  await page.getByLabel("Lọc theo thị trường").click()
  await page.getByRole("option", { name: "Mỹ" }).click()

  await expect(page.locator("tbody tr")).toHaveCount(4)
  await expect(page.locator("tbody")).toContainText("AAPL")
  await expect(page.locator("tbody")).not.toContainText("7267.T")
})

test("lọc về một thị trường thì bỏ luôn ghi chú về đơn vị tiền", async ({ page }) => {
  const note = page.getByText("Đang trộn nhiều đơn vị tiền")
  // Ghi chú chỉ có nghĩa khi đang thật sự trộn ¥ và $.
  await expect(note).toBeVisible()

  await page.getByLabel("Lọc theo thị trường").click()
  await page.getByRole("option", { name: "Nhật" }).click()
  await expect(note).toBeHidden()
})
