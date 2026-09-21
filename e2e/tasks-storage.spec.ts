import { expect, test } from "@playwright/test"

import {
  blockReadOf,
  blockWrites,
  readStorage,
  restoreReads,
  seedStorage,
  TASKS_KEY,
} from "./helpers"

const SAMPLE_ROW = "Giải thích kỹ thuật"
const WRITE_FAILED = "Không lưu được vào bộ nhớ phiên"
const READ_FAILED = "Không đọc được bộ nhớ phiên"

async function addTask(page: import("@playwright/test").Page, name: string) {
  await page.getByRole("button", { name: "Thêm task" }).click()
  const dialog = page.getByRole("dialog")
  await dialog.getByLabel("Tên task").fill(name)
  await dialog.getByLabel("Dự án").fill("Valve Line Z")
  await dialog.getByRole("button", { name: "Thêm task" }).click()
}

test("task sống sót khi chuyển route rồi quay lại", async ({ page }) => {
  await page.goto("/tasks")
  await addTask(page, "Task phải sống sót")

  await page.getByRole("link", { name: "Watchlist" }).click()
  await expect(page).toHaveURL(/watchlist/)
  await page.getByRole("link", { name: "Tasks" }).click()

  await expect(page.locator("tbody")).toContainText("Task phải sống sót")
})

test("ghi hỏng: task vẫn còn khi đổi route, và có cảnh báo", async ({ page }) => {
  await page.goto("/tasks")
  await blockWrites(page)

  await addTask(page, "Task khi storage hỏng")

  await expect(page.locator("tbody")).toContainText("Task khi storage hỏng")
  await expect(page.getByText(WRITE_FAILED)).toBeVisible()

  // State nằm trên route nên điều hướng không phụ thuộc vào việc ghi được hay không.
  await page.getByRole("link", { name: "Watchlist" }).click()
  await page.getByRole("link", { name: "Tasks" }).click()
  await expect(page.locator("tbody")).toContainText("Task khi storage hỏng")
})

test("đọc hỏng: cảnh báo, và KHÔNG ghi đè task thật khi storage hồi phục", async ({ page }) => {
  await page.goto("/tasks")
  await seedStorage(page, "session", TASKS_KEY, [
    {
      id: "real1",
      task: "TASK THẬT CỦA NGƯỜI DÙNG",
      project: "P",
      owner: "Linh",
      due: "01/01",
      status: "Đang chạy",
    },
  ])

  await blockReadOf(page, TASKS_KEY)
  await page.reload()

  await expect(page.getByText(READ_FAILED)).toBeVisible()

  // Từng là lỗi mất dữ liệu: storage hồi phục rồi lần ghi sau đè sạch task thật.
  await restoreReads(page)
  await addTask(page, "Task mới")

  const stored = await readStorage(page, "session", TASKS_KEY)
  expect(stored).toContain("TASK THẬT CỦA NGƯỜI DÙNG")
})

test.describe("dữ liệu lưu bị hỏng", () => {
  const cases: { label: string; value: unknown; raw?: string }[] = [
    {
      label: "entry thiếu owner và due",
      value: [{ id: "x1", task: "Thiếu field", project: "P", status: "Đang chạy" }],
    },
    {
      label: "entry có owner là object (từng làm React ném lỗi lúc render)",
      value: [
        {
          id: "b1",
          task: "Owner là object",
          project: "P",
          status: "Đang chạy",
          owner: {},
          due: "01/01",
        },
      ],
    },
    { label: "không phải array", value: { not: "an array" } },
  ]

  for (const { label, value } of cases) {
    test(`${label} → quay về dữ liệu mẫu, không vỡ bảng`, async ({ page }) => {
      const errors: string[] = []
      page.on("pageerror", (e) => errors.push(e.message))

      await page.goto("/tasks")
      await seedStorage(page, "session", TASKS_KEY, value)
      await page.reload()

      await expect(page.locator("tbody")).toContainText(SAMPLE_ROW)
      expect(errors).toEqual([])
    })
  }

  test("JSON hỏng → quay về dữ liệu mẫu", async ({ page }) => {
    await page.goto("/tasks")
    await page.evaluate(
      (key) => sessionStorage.setItem(key, "khong-phai-json{{{"),
      TASKS_KEY,
    )
    await page.reload()

    await expect(page.locator("tbody")).toContainText(SAMPLE_ROW)
  })
})
