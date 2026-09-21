import { expect, test } from "@playwright/test"

test.describe("switch", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/settings")
  })

  test("có tên truy cập được qua <label for>, đúng role", async ({ page }) => {
    const sync = page.getByRole("switch", { name: "Đồng bộ watchlist với iSPEED" })
    await expect(sync).toHaveCount(1)
    await expect(sync).toHaveAttribute("role", "switch")
  })

  test("bấm vào label cũng toggle được, không chỉ riêng cái switch", async ({ page }) => {
    const sync = page.getByRole("switch", { name: "Đồng bộ watchlist với iSPEED" })
    await expect(sync).not.toBeChecked()

    await page.locator('label[for="sync-watchlist"]').click()

    await expect(sync).toBeChecked()
  })

  test("focus được bằng bàn phím và toggle bằng Space", async ({ page }) => {
    const sync = page.getByRole("switch", { name: "Đồng bộ watchlist với iSPEED" })

    await sync.focus()
    await expect(sync).toBeFocused()

    await page.keyboard.press("Space")
    await expect(sync).toBeChecked()
  })

  test("có sẵn vùng aria-live trước khi có thông báo nào", async ({ page }) => {
    // Vùng live phải nằm sẵn trong DOM từ đầu thì screen reader mới đọc được
    // khi nội dung xuất hiện: một cho nút Lưu, một cho lỗi ghi storage.
    await expect(page.locator('[aria-live="polite"]')).toHaveCount(2)
  })
})

test.describe("dialog thêm task", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/tasks")
    await page.getByRole("button", { name: "Thêm task" }).click()
  })

  test("có tên và mô tả truy cập được", async ({ page }) => {
    // Chỉ check attribute khớp /.+/ thì một id trỏ trượt vẫn lọt, mà lúc đó
    // dialog thực tế không có tên lẫn mô tả. Hai matcher này resolve tham
    // chiếu ra text thật nên id hỏng là lộ ngay.
    const dialog = page.getByRole("dialog")
    await expect(dialog).toHaveAccessibleName("Thêm task")
    await expect(dialog).toHaveAccessibleDescription(/bộ nhớ trình duyệt của phiên này/)
  })

  test("focus nhảy vào trong dialog khi mở", async ({ page }) => {
    await expect(page.getByRole("dialog").getByLabel("Tên task")).toBeFocused()
  })

  test("Escape đóng dialog và trả focus về đúng nút đã mở nó", async ({ page }) => {
    await page.keyboard.press("Escape")

    await expect(page.getByRole("dialog")).toHaveCount(0)
    // Không trả focus thì người dùng bàn phím phải Tab lại từ đầu trang.
    await expect(page.getByRole("button", { name: "Thêm task" })).toBeFocused()
  })

  test("nút Huỷ cũng trả focus về nút mở", async ({ page }) => {
    await page.getByRole("button", { name: "Huỷ" }).click()

    await expect(page.getByRole("dialog")).toHaveCount(0)
    await expect(page.getByRole("button", { name: "Thêm task" })).toBeFocused()
  })
})
