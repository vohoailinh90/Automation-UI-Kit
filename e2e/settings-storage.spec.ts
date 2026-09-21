import { expect, test } from "@playwright/test"

import {
  blockReadOf,
  blockWrites,
  readStorage,
  restoreReads,
  restoreWrites,
  seedRawStorage,
  seedStorage,
  SETTINGS_KEY,
} from "./helpers"

const BLOCKED = "Không lưu được"
const READ_FAILED = "Không đọc được"

const syncSwitch = (page: import("@playwright/test").Page) =>
  page.getByRole("switch", { name: "Đồng bộ watchlist với iSPEED" })

test.describe("draft của form tách khỏi bản đã lưu", () => {
  test("bật switch không kéo theo form chưa submit", async ({ page }) => {
    await page.goto("/settings")

    await page.getByLabel("Họ và tên").fill("TÊN CHƯA LƯU")
    await syncSwitch(page).click()

    const stored = await readStorage(page, "local", SETTINGS_KEY)
    expect(stored).not.toContain("TÊN CHƯA LƯU")
    expect(stored).toContain('"syncWatchlist":true')

    await page.reload()
    await expect(page.getByLabel("Họ và tên")).not.toHaveValue("TÊN CHƯA LƯU")
  })
})

test.describe("ghi storage thất bại", () => {
  test("không báo đã lưu khi setItem ném lỗi", async ({ page }) => {
    await page.goto("/settings")
    await blockWrites(page)

    await page.getByLabel("Họ và tên").fill("Sẽ thất bại")
    await page.getByRole("button", { name: "Lưu thay đổi" }).click()

    await expect(page.getByText("Đã lưu vào trình duyệt")).toHaveCount(0)
    await expect(page.getByText(BLOCKED)).toBeVisible()
  })

  test("lỗi tự biến mất khi lần ghi sau thành công", async ({ page }) => {
    await page.goto("/settings")
    await expect(page.getByText(BLOCKED)).toHaveCount(0)

    await blockWrites(page)
    await syncSwitch(page).click()
    await expect(page.getByText(BLOCKED)).toBeVisible()

    await restoreWrites(page)
    await page.getByRole("switch", { name: "Nhắc milestone sắp tới hạn" }).click()

    await expect(page.getByText(BLOCKED)).toHaveCount(0)
    const stored = await readStorage(page, "local", SETTINGS_KEY)
    expect(stored).toContain('"milestoneReminder":false')
  })

  test("submit thành công xoá lỗi toggle còn sót", async ({ page }) => {
    await page.goto("/settings")

    await blockWrites(page)
    await syncSwitch(page).click()
    await expect(page.getByText(BLOCKED)).toBeVisible()

    await restoreWrites(page)
    await page.getByLabel("Họ và tên").fill("Tên mới")
    await page.getByRole("button", { name: "Lưu thay đổi" }).click()

    await expect(page.getByText(BLOCKED)).toHaveCount(0)
    await expect(page.getByText("Đã lưu vào trình duyệt")).toBeVisible()
  })

  test("toggle hỏng ngay sau khi submit không hiện hai thông báo trái ngược", async ({
    page,
  }) => {
    await page.goto("/settings")

    await page.getByLabel("Họ và tên").fill("Tên ok")
    await page.getByRole("button", { name: "Lưu thay đổi" }).click()

    const savedNote = page.getByText("Đã lưu vào trình duyệt")
    await expect(savedNote).toBeVisible()

    await blockWrites(page)
    // Tiền đề: vẫn còn trong 2.5s mà xác nhận "đã lưu" hiển thị. Nếu đã trôi
    // qua thì assert cuối sẽ đúng một cách vô nghĩa, nên chốt lại ở đây.
    await expect(savedNote).toBeVisible({ timeout: 500 })

    await syncSwitch(page).click()

    // Lấy mẫu liên tục thay vì assert một lần: assertion của Playwright tự
    // retry, mà thông báo "đã lưu" tự tắt sau 2.5s — chờ đủ lâu thì lần nào
    // cũng "đúng". Bất biến thật là: không được có KHOẢNH KHẮC nào mà cả xác
    // nhận thành công lẫn báo lỗi cùng hiển thị.
    const sawBoth = await page.evaluate(async () => {
      const deadline = Date.now() + 1200
      while (Date.now() < deadline) {
        const text = document.body.innerText
        if (text.includes("Đã lưu vào trình duyệt") && text.includes("Không lưu được")) {
          return true
        }
        await new Promise((resolve) => setTimeout(resolve, 50))
      }
      return false
    })

    expect(sawBoth).toBe(false)
    await expect(page.getByText(BLOCKED)).toBeVisible()
  })
})

test.describe("đọc storage thất bại", () => {
  test("cảnh báo, và KHÔNG ghi đè cấu hình thật khi storage hồi phục", async ({ page }) => {
    await page.goto("/settings")
    await seedStorage(page, "local", SETTINGS_KEY, {
      fullname: "TÊN THẬT ĐÃ LƯU",
      email: "that@example.com",
      location: "Tokyo",
      language: "ja",
      milestoneReminder: false,
      syncWatchlist: true,
    })

    await blockReadOf(page, SETTINGS_KEY)
    await page.reload()

    await expect(page.getByText(READ_FAILED)).toBeVisible()

    // Storage hồi phục rồi người dùng thao tác: lần ghi này từng xoá sạch
    // cấu hình thật và thay bằng giá trị mặc định đang hiển thị.
    await restoreReads(page)
    await syncSwitch(page).click()

    const stored = await readStorage(page, "local", SETTINGS_KEY)
    expect(stored).toContain("TÊN THẬT ĐÃ LƯU")
  })
})

test("JSON hỏng trong storage → về mặc định, không vỡ trang", async ({ page }) => {
  // `seedStorage` luôn `JSON.stringify` nên không bao giờ chạm được nhánh
  // `JSON.parse` ném lỗi của `loadSettings`. Bên Tasks đã có test này, bên
  // Settings thì chưa.
  const errors: string[] = []
  page.on("pageerror", (e) => errors.push(e.message))

  await page.goto("/settings")
  await seedRawStorage(page, "local", SETTINGS_KEY, "khong-phai-json{{{")
  await page.reload()

  await expect(page.getByLabel("Họ và tên")).toHaveValue("Võ Hoài Linh")
  await expect(page.getByRole("switch", { name: "Nhắc milestone sắp tới hạn" })).toBeChecked()
  // Đọc được nhưng là rác thì không phải lỗi đọc — vẫn được phép ghi đè.
  await expect(page.getByText(READ_FAILED)).toHaveCount(0)
  expect(errors).toEqual([])
})

test.describe("dữ liệu đúng JSON nhưng sai schema", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/settings")
    await seedStorage(page, "local", SETTINGS_KEY, {
      fullname: 123,
      syncWatchlist: "false",
      milestoneReminder: "",
      language: "de",
    })
    await page.reload()
  })

  test("chuỗi truthy không làm switch hiện bật", async ({ page }) => {
    await expect(syncSwitch(page)).not.toBeChecked()
  })

  test("giá trị ngoài miền cho phép quay về mặc định", async ({ page }) => {
    await expect(page.locator("#language")).toContainText("Tiếng Việt")
    await expect(page.getByLabel("Họ và tên")).toHaveValue("Võ Hoài Linh")
    await expect(page.getByRole("switch", { name: "Nhắc milestone sắp tới hạn" })).toBeChecked()
  })

  test("lần ghi sau lưu đúng kiểu, không lưu lại rác", async ({ page }) => {
    await syncSwitch(page).click()

    const stored = await readStorage(page, "local", SETTINGS_KEY)
    expect(stored).toContain('"syncWatchlist":true')
    expect(stored).not.toContain('"syncWatchlist":"')
    expect(stored).not.toContain('"fullname":123')
    expect(stored).not.toContain('"language":"de"')
  })
})
