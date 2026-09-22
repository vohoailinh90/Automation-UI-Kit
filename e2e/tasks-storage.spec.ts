import { expect, test } from "@playwright/test"

import {
  blockReadOf,
  blockWrites,
  readStorage,
  restoreReads,
  restoreWrites,
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

test("task sống sót qua reload, tức là đã ghi và đọc lại được", async ({ page }) => {
  // Điều hướng thôi thì chưa chứng minh gì: TasksProvider nằm trên <Routes>
  // nên không hề unmount, `persistTasks` có hỏng hẳn test vẫn xanh. Reload
  // mới thật sự đi qua serialize ra sessionStorage rồi `loadTasks` + nhánh
  // hợp lệ của `isTask` lúc đọc lại.
  await page.goto("/tasks")
  await addTask(page, "Task qua reload")

  await page.reload()

  await expect(page.locator("tbody")).toContainText("Task qua reload")
  await expect(page.getByText(READ_FAILED)).toHaveCount(0)
  await expect(page.getByText(WRITE_FAILED)).toHaveCount(0)
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

test("ghi hồi phục: cảnh báo biến mất và task được lưu lại", async ({ page }) => {
  // Dừng ở lúc hỏng thì một cờ `writeFailed` kẹt vĩnh viễn vẫn xanh, trong khi
  // người dùng cứ thấy cảnh báo cũ dù storage đã hoạt động lại.
  await page.goto("/tasks")
  await blockWrites(page)
  await addTask(page, "Task lúc hỏng")
  await expect(page.getByText(WRITE_FAILED)).toBeVisible()

  await restoreWrites(page)
  await addTask(page, "Task lúc đã hồi phục")

  await expect(page.getByText(WRITE_FAILED)).toHaveCount(0)

  const stored = await readStorage(page, "session", TASKS_KEY)
  expect(stored).toContain("Task lúc đã hồi phục")
  expect(stored).toContain("Task lúc hỏng")
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

  const before = await readStorage(page, "session", TASKS_KEY)

  await blockReadOf(page, TASKS_KEY)
  await page.reload()

  await expect(page.getByText(READ_FAILED)).toBeVisible()

  // Từng là lỗi mất dữ liệu: storage hồi phục rồi lần ghi sau đè sạch task thật.
  await restoreReads(page)
  await addTask(page, "Task mới")

  // Hợp đồng là KHÔNG ghi gì cả, nên so nguyên văn. Chỉ assert "task thật vẫn
  // còn" thì một implementation ghi thêm task mới vào cạnh nó vẫn lọt, dù nó
  // đã ghi trong lúc đáng lẽ phải nhịn.
  const after = await readStorage(page, "session", TASKS_KEY)
  expect(after).toBe(before)
})

test.describe("dữ liệu lưu bị hỏng", () => {
  /**
   * `isTask` nối các điều kiện bằng `&&` nên nó short-circuit: một entry thiếu
   * cùng lúc `owner` và `due` sẽ dừng ngay ở `owner`, và việc `due` có bị từ
   * chối hay không thì không quan sát được. Nên mỗi case chỉ làm hỏng ĐÚNG MỘT
   * trường trên một entry vốn hợp lệ, để mỗi lần từ chối đều nhìn thấy được.
   */
  const validEntry = {
    id: "v1",
    task: "Entry hợp lệ",
    project: "Valve Line V",
    owner: "Linh",
    due: "01/01",
    status: "Đang chạy",
  }

  /** Task thật của người dùng, phải sống sót bên cạnh entry hỏng. */
  const KEPT_TASK = "Task thật phải được giữ"
  const keptEntry = { ...validEntry, id: "kept-1", task: KEPT_TASK }

  const withoutField = (field: string) => {
    const copy: Record<string, unknown> = { ...validEntry }
    delete copy[field]
    return copy
  }

  const brokenEntries: { label: string; entry: unknown }[] = [
    { label: "id sai kiểu", entry: { ...validEntry, id: 123 } },
    { label: "task sai kiểu", entry: { ...validEntry, task: {} } },
    { label: "project thiếu", entry: withoutField("project") },
    { label: "owner là object", entry: { ...validEntry, owner: {} } },
    { label: "due thiếu", entry: withoutField("due") },
    { label: "status ngoài danh sách", entry: { ...validEntry, status: "Không rõ" } },
    // `typeof null === "object"` nên không có guard `t !== null` thì `isTask`
    // ném ngay lúc đọc `t.id`, lỗi lọt ra ngoài `filter` và rơi vào catch —
    // task thật bị giấu mất mà không ai biết.
    { label: "entry là null", entry: null },
  ]

  for (const { label, entry } of brokenEntries) {
    test(`${label} → entry bị loại, quay về dữ liệu mẫu`, async ({ page }) => {
      const errors: string[] = []
      page.on("pageerror", (e) => errors.push(e.message))

      await page.goto("/tasks")
      // Seed kèm một entry HỢP LỆ: nếu chỉ seed mỗi entry hỏng thì một
      // implementation loại nguyên mảng khi có phần tử sai sẽ pass y hệt
      // `parsed.filter(isTask)` — mà hai thứ đó khác hẳn nhau khi storage của
      // người dùng lẫn lộn task thật với entry hỏng.
      await seedStorage(page, "session", TASKS_KEY, [keptEntry, entry])
      await page.reload()

      const rows = page.locator("tbody tr")
      await expect(rows).toHaveCount(1) // loại cả mảng ⇒ 7 dòng mẫu; nhận cả hai ⇒ 2
      await expect(rows.first()).toContainText(KEPT_TASK)
      await expect(page.locator("tbody")).not.toContainText(SAMPLE_ROW)
      expect(errors).toEqual([])
    })
  }

  test("không phải array → quay về dữ liệu mẫu", async ({ page }) => {
    const errors: string[] = []
    page.on("pageerror", (e) => errors.push(e.message))

    await page.goto("/tasks")
    await seedStorage(page, "session", TASKS_KEY, { not: "an array" })
    await page.reload()

    await expect(page.locator("tbody")).toContainText(SAMPLE_ROW)
    expect(errors).toEqual([])
  })

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
