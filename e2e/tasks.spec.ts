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
  const dialog = page.getByRole("dialog")
  const submit = dialog.getByRole("button", { name: "Thêm task" })

  await expect(submit).toBeDisabled()

  // Chỉ điền hai trường bắt buộc, cố tình bỏ trống "Phụ trách" và "Hạn".
  // Nếu dùng helper điền hết thì lỡ hai trường đó thành bắt buộc, test vẫn xanh.
  await dialog.getByLabel("Tên task").fill(NEW_TASK)
  await expect(submit).toBeDisabled()

  await dialog.getByLabel("Dự án").fill("Valve Line B")
  await expect(submit).toBeEnabled()
})

test("trường tuỳ chọn bỏ trống thì nhận giá trị mặc định", async ({ page }) => {
  await page.getByRole("button", { name: "Thêm task" }).click()
  const dialog = page.getByRole("dialog")
  await dialog.getByLabel("Tên task").fill(NEW_TASK)
  await dialog.getByLabel("Dự án").fill("Valve Line B")
  await dialog.getByRole("button", { name: "Thêm task" }).click()

  const row = visibleRows(page).first()
  await expect(row).toContainText("Chưa gán")
  await expect(row).toContainText("—")
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

test("mỗi tab chỉ chứa task đúng trạng thái của nó", async ({ page }) => {
  // Kiểm "có X, không có Y" thì một predicate quá rộng vẫn lọt: đổi filter
  // tab Đang chạy thành `t.status !== "Hoàn thành"` vẫn chứa task đang chạy
  // và vẫn không chứa task hoàn thành. Nên phải chốt số dòng, và MỌI dòng
  // hiện ra đều phải mang đúng trạng thái của tab.
  const byStatus = [
    { tab: "Tất cả", count: 7, statuses: null },
    { tab: "Đang chạy", count: 2, statuses: ["Đang chạy"] },
    { tab: "Trễ hạn", count: 1, statuses: ["Trễ hạn"] },
    { tab: "Hoàn thành", count: 1, statuses: ["Hoàn thành"] },
  ]

  for (const { tab, count, statuses } of byStatus) {
    await page.getByRole("tab", { name: tab }).click()
    const rows = page.locator('[role="tabpanel"]:visible tbody tr')
    await expect(rows).toHaveCount(count)

    if (!statuses) continue
    const badges = await rows.locator("[data-slot=badge]").allInnerTexts()
    expect([...new Set(badges)].sort()).toEqual(statuses)
  }
})

test("ô tìm kiếm lọc theo cả tên task lẫn dự án", async ({ page }) => {
  await page.getByRole("button", { name: "Thêm task" }).click()
  await fillNewTask(page)
  await page.getByRole("dialog").getByRole("button", { name: "Thêm task" }).click()

  const search = page.getByLabel("Tìm task hoặc dự án")

  // Tìm theo tên dự án
  await search.fill("Valve Line B")
  await expect(visibleRows(page)).toHaveCount(1)
  await expect(visibleRows(page).first()).toContainText(NEW_TASK)

  // Và theo tên task — thiếu vế này thì bỏ hẳn match `t.task` vẫn xanh,
  // dù tiêu đề test hứa cả hai.
  await search.fill("bản vẽ từ nhà cung cấp")
  await expect(visibleRows(page)).toHaveCount(1)
  await expect(visibleRows(page).first()).toContainText(NEW_TASK)
})

test("form trong dialog reset khi mở lại", async ({ page }) => {
  await page.getByRole("button", { name: "Thêm task" }).click()
  await fillNewTask(page)
  await page.keyboard.press("Escape")

  await page.getByRole("button", { name: "Thêm task" }).click()

  // Kiểm MỌI trường, kể cả Select trạng thái: chỉ kiểm "Tên task" thì một
  // trường sót lại giá trị cũ vẫn lọt, dù tiêu đề nói cả form.
  const dialog = page.getByRole("dialog")
  await expect(dialog.getByLabel("Tên task")).toHaveValue("")
  await expect(dialog.getByLabel("Dự án")).toHaveValue("")
  await expect(dialog.getByLabel("Phụ trách")).toHaveValue("")
  await expect(dialog.getByLabel("Hạn")).toHaveValue("")
  await expect(dialog.locator("#task-status")).toContainText("Chưa bắt đầu")
})

test("bảng báo rỗng khi tìm không ra gì", async ({ page }) => {
  await page.getByLabel("Tìm task hoặc dự án").fill("không-tồn-tại-xyz")
  await expect(page.locator('[role="tabpanel"]:visible tbody')).toContainText(
    "Không có task nào",
  )
})
