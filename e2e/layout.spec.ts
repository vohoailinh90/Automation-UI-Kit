import { expect, test } from "@playwright/test"

test("ở màn hình hẹp, nav mở ra trong sheet", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 760 })
  await page.goto("/")

  await page.getByRole("button", { name: "Open menu" }).click()

  const sheet = page.getByRole("dialog")
  await expect(sheet).toBeVisible()
  await expect(sheet.getByRole("link", { name: "Watchlist" })).toBeVisible()
})

test("menu có nhóm 'Dashboard mẫu', và tiêu đề trang đi theo route", async ({ page }) => {
  await page.goto("/")
  const nav = page.locator("aside").getByRole("navigation")
  await expect(nav.getByText("Dashboard mẫu", { exact: true })).toBeVisible()

  for (const [label, path] of [
    ["Automation", "/automation"],
    ["Orders", "/orders"],
    ["Portfolio", "/portfolio"],
  ] as const) {
    await nav.getByRole("link", { name: label }).click()
    await expect(page).toHaveURL(path)
    await expect(page.getByRole("heading", { level: 1 })).toHaveText(label)
    // Đúng một mục đang chọn, và là mục vừa bấm.
    await expect(nav.locator("[aria-current='page']")).toHaveCount(1)
    await expect(nav.getByRole("link", { name: label })).toHaveAttribute("aria-current", "page")
  }
})

test("ở màn hình hẹp, dashboard mẫu mở được từ sheet và sheet tự đóng", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 760 })
  await page.goto("/")
  await page.getByRole("button", { name: "Open menu" }).click()

  const sheet = page.getByRole("dialog")
  await sheet.getByRole("link", { name: "Orders" }).click()
  await expect(page).toHaveURL("/orders")
  await expect(sheet).toHaveCount(0)
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Orders")
})
