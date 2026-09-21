import { expect, test } from "@playwright/test"

const NEW_TASK = "Kiểm tra bản vẽ từ nhà cung cấp"

test.beforeEach(async ({ page }) => {
  await page.goto("/tasks")
})

/** Bảng của tab đang hiển thị — các tab ẩn cũng có <tbody> riêng. */
const visibleRows = (page: import("@playwright/test").Page) =>
  page.locator('[role="tabpanel"]:visible tbody tr')

async function fillNewTask(page: import("@playwright/test").Page, status = "Trễ hạn") {
  const dialog = page.getByRole("dialog")
  await dialog.getByLabel("Tên task").fill(NEW_TASK)
  await dialog.getByLabel("Dự án").fill("Valve Line B")
  await dialog.getByLabel("Phụ trách").fill("Linh")
  await dialog.getByLabel("Hạn").fill("30/09")
  await dialog.getByLabel("Trạng thái").click()
  await page.getByRole("option", { name: status }).click()
}

test("nút Thêm task mở dialog", async ({ page }) => {
  await page.getByRole("button", { name: "Thêm task" }).click()
  await expect(page.getByRole("dialog")).toBeVisible()
})

test("nút gửi bị khoá cho tới khi điền đủ trường bắt buộc", async ({ page }) => {
  await page.getByRole("button", { name: "Thêm task" }).click()
  const submit = page.getByRole("dialog").getByRole("button", { name: "Thêm task" })

  await expect(submit).toBeDisabled()

  await fillNewTask(page)
  await expect(submit).toBeEnabled()
})

test("task mới được thêm lên đầu bảng kèm đúng trạng thái", async ({ page }) => {
  const before = await visibleRows(page).count()

  await page.getByRole("button", { name: "Thêm task" }).click()
  await fillNewTask(page)
  await page.getByRole("dialog").getByRole("button", { name: "Thêm task" }).click()

  await expect(visibleRows(page)).toHaveCount(before + 1)
  await expect(visibleRows(page).first()).toContainText(NEW_TASK)
  await expect(visibleRows(page).first()).toContainText("Trễ hạn")
})

test("task mới xuất hiện đúng tab theo trạng thái", async ({ page }) => {
  await page.getByRole("button", { name: "Thêm task" }).click()
  await fillNewTask(page)
  await page.getByRole("dialog").getByRole("button", { name: "Thêm task" }).click()

  await page.getByRole("tab", { name: "Trễ hạn" }).click()
  await expect(page.locator('[role="tabpanel"]:visible tbody')).toContainText(NEW_TASK)

  await page.getByRole("tab", { name: "Hoàn thành" }).click()
  await expect(page.locator('[role="tabpanel"]:visible tbody')).not.toContainText(NEW_TASK)
})

test("ô tìm kiếm lọc theo cả tên task lẫn dự án", async ({ page }) => {
  await page.getByRole("button", { name: "Thêm task" }).click()
  await fillNewTask(page)
  await page.getByRole("dialog").getByRole("button", { name: "Thêm task" }).click()

  await page.getByLabel("Tìm task hoặc dự án").fill("Valve Line B")

  await expect(visibleRows(page)).toHaveCount(1)
  await expect(visibleRows(page).first()).toContainText(NEW_TASK)
})

test("form trong dialog reset khi mở lại", async ({ page }) => {
  await page.getByRole("button", { name: "Thêm task" }).click()
  await fillNewTask(page)
  await page.keyboard.press("Escape")

  await page.getByRole("button", { name: "Thêm task" }).click()
  await expect(page.getByRole("dialog").getByLabel("Tên task")).toHaveValue("")
})

test("bảng báo rỗng khi tìm không ra gì", async ({ page }) => {
  await page.getByLabel("Tìm task hoặc dự án").fill("không-tồn-tại-xyz")
  await expect(page.locator('[role="tabpanel"]:visible tbody')).toContainText(
    "Không có task nào",
  )
})
