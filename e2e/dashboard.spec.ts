import { expect, test } from "@playwright/test"

test.beforeEach(async ({ page }) => {
  await page.goto("/")
})

test("chart có legend phân biệt kế hoạch với thực tế", async ({ page }) => {
  const legend = page.locator(".recharts-legend-item-text")
  await expect(legend.filter({ hasText: "Kế hoạch" })).toBeVisible()
  await expect(legend.filter({ hasText: "Thực tế" })).toBeVisible()
})

test("màu chart lấy từ token theme, không hardcode", async ({ page }) => {
  // Kiểm cả hai đường: chỉ kiểm đường đầu thì hardcode lại đường còn lại
  // vẫn lọt, dù tiêu đề nói "màu chart".
  const curves = page.locator(".recharts-area-curve")
  await expect(curves).toHaveCount(2)
  await expect(curves.nth(0)).toHaveAttribute("stroke", "var(--chart-1)")
  await expect(curves.nth(1)).toHaveAttribute("stroke", "var(--chart-2)")
})

test("bật dark mode thì token đổi giá trị", async ({ page }) => {
  const chartColor = () =>
    page.evaluate(() =>
      getComputedStyle(document.documentElement).getPropertyValue("--chart-1").trim(),
    )

  const light = await chartColor()

  await page.getByRole("button", { name: "Toggle theme" }).click()
  await expect(page.locator("html")).toHaveClass(/dark/)

  const dark = await chartColor()
  expect(dark).not.toBe(light)
})
