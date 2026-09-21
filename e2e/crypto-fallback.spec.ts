import { expect, test } from "@playwright/test"

/**
 * `crypto.randomUUID()` chỉ tồn tại trong secure context (https hoặc
 * localhost). App nội bộ hay được mở qua `http://<LAN-IP>` từ máy khác, lúc đó
 * nó là `undefined` — và trước khi có `createId()` thì bấm "Thêm task" làm
 * trắng cả trang. Không dựng được LAN origin thật trong test, nhưng gỡ đúng
 * API đó ra khỏi trang thì tái hiện được chính xác điều kiện gây lỗi.
 */

const NEW_TASK = "Task không có randomUUID"

/**
 * Các API này nằm trên `Crypto.prototype`, không phải own property của
 * `crypto`, nên phải xoá trên prototype — xoá trên instance là no-op và test
 * sẽ xanh một cách vô nghĩa. Mọi test dưới đây đều assert lại tiền đề sau khi
 * gỡ, chính vì lý do đó.
 */
async function removeCryptoApis(page: import("@playwright/test").Page, names: string[]) {
  await page.addInitScript((toRemove: string[]) => {
    for (const name of toRemove) Reflect.deleteProperty(Crypto.prototype, name)
  }, names)
}

async function addTask(page: import("@playwright/test").Page) {
  await page.getByRole("button", { name: "Thêm task" }).click()
  const dialog = page.getByRole("dialog")
  await dialog.getByLabel("Tên task").fill(NEW_TASK)
  await dialog.getByLabel("Dự án").fill("Valve Line Y")
  await dialog.getByRole("button", { name: "Thêm task" }).click()
}

test("thêm task được khi thiếu crypto.randomUUID", async ({ page }) => {
  const errors: string[] = []
  page.on("pageerror", (e) => errors.push(e.message))

  await removeCryptoApis(page, ["randomUUID"])
  await page.goto("/tasks")

  expect(await page.evaluate(() => typeof crypto.randomUUID)).toBe("undefined")
  expect(await page.evaluate(() => typeof crypto.getRandomValues)).toBe("function")

  await addTask(page)

  await expect(page.locator("tbody")).toContainText(NEW_TASK)
  expect(errors).toEqual([])
})

test("thêm task được khi thiếu cả randomUUID lẫn getRandomValues", async ({ page }) => {
  const errors: string[] = []
  page.on("pageerror", (e) => errors.push(e.message))

  await removeCryptoApis(page, ["randomUUID", "getRandomValues"])
  await page.goto("/tasks")

  expect(await page.evaluate(() => typeof crypto.randomUUID)).toBe("undefined")
  expect(await page.evaluate(() => typeof crypto.getRandomValues)).toBe("undefined")

  await addTask(page)

  await expect(page.locator("tbody")).toContainText(NEW_TASK)
  expect(errors).toEqual([])
})

test("id sinh ra là duy nhất giữa các task", async ({ page }) => {
  await removeCryptoApis(page, ["randomUUID"])
  await page.goto("/tasks")
  expect(await page.evaluate(() => typeof crypto.randomUUID)).toBe("undefined")

  for (const name of ["Task A", "Task B", "Task C"]) {
    await page.getByRole("button", { name: "Thêm task" }).click()
    const dialog = page.getByRole("dialog")
    await dialog.getByLabel("Tên task").fill(name)
    await dialog.getByLabel("Dự án").fill("P")
    await dialog.getByRole("button", { name: "Thêm task" }).click()
    await expect(page.locator("tbody")).toContainText(name)
  }

  const ids = await page.evaluate(() => {
    const raw = sessionStorage.getItem("automation-ui-kit-tasks")
    return (JSON.parse(raw ?? "[]") as { id: string }[]).map((t) => t.id)
  })

  expect(ids.length).toBeGreaterThanOrEqual(3)
  expect(new Set(ids).size).toBe(ids.length)
})
