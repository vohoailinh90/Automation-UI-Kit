import { expect, test } from "@playwright/test"

test("ở màn hình hẹp, nav mở ra trong sheet", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 760 })
  await page.goto("/")

  await page.getByRole("button", { name: "Open menu" }).click()

  const sheet = page.getByRole("dialog")
  await expect(sheet).toBeVisible()
  await expect(sheet.getByRole("link", { name: "Watchlist" })).toBeVisible()
})
