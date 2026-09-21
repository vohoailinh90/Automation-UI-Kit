import { expect, test } from "@playwright/test"

test.beforeEach(async ({ page }) => {
  await page.goto("/")
})

/** Token của từng chuỗi dữ liệu, dùng để buộc nhãn legend với đúng chuỗi. */
const series = [
  { name: "Kế hoạch", token: "var(--chart-1)", gradient: "planned" },
  { name: "Thực tế", token: "var(--chart-2)", gradient: "actual" },
] as const

test("legend gắn đúng nhãn với đúng chuỗi dữ liệu", async ({ page }) => {
  const items = page.locator(".recharts-legend-item")
  await expect(items).toHaveCount(2)

  // Kiểm text rời rạc thì đảo `name` của hai <Area> cho nhau vẫn xanh, mà
  // người đọc biểu đồ sẽ hiểu ngược kế hoạch với thực tế. Mỗi nhãn phải gắn
  // với đúng màu của chuỗi nó đại diện.
  for (const [i, { name, token }] of series.entries()) {
    await expect(items.nth(i)).toHaveText(name)
    await expect(items.nth(i).locator("path, line").first()).toHaveAttribute(
      "stroke",
      token,
    )
  }
})

test("màu chart lấy từ token theme, không hardcode", async ({ page }) => {
  // Chuỗi mắt xích: <Area> tô bằng gradient nào → gradient đó dùng token nào
  // → đường kẻ dùng token nào. Đứt mắt xích nào thì hardcode ở đó vẫn lọt.
  const areas = page.locator(".recharts-area-area")
  const curves = page.locator(".recharts-area-curve")
  await expect(areas).toHaveCount(2)
  await expect(curves).toHaveCount(2)

  for (const [i, { token, gradient }] of series.entries()) {
    await expect(areas.nth(i)).toHaveAttribute("fill", `url(#${gradient})`)
    await expect(curves.nth(i)).toHaveAttribute("stroke", token)

    const stops = page.locator(`#${gradient} stop`)
    await expect(stops).toHaveCount(2)
    await expect(stops.nth(0)).toHaveAttribute("stop-color", token)
    await expect(stops.nth(1)).toHaveAttribute("stop-color", token)
  }
})

test("dark mode đổi giá trị của MỌI token chart, và sống qua reload", async ({
  page,
}) => {
  const readTokens = () =>
    page.evaluate(() => {
      const style = getComputedStyle(document.documentElement)
      return {
        chart1: style.getPropertyValue("--chart-1").trim(),
        chart2: style.getPropertyValue("--chart-2").trim(),
      }
    })

  const light = await readTokens()

  await page.getByRole("button", { name: "Toggle theme" }).click()
  await expect(page.locator("html")).toHaveClass(/dark/)

  // Kiểm mỗi --chart-1 thì bỏ định nghĩa dark của --chart-2 vẫn xanh, trong
  // khi một chuỗi dữ liệu hiện lên không còn đổi theo theme.
  const dark = await readTokens()
  expect(dark.chart1).not.toBe(light.chart1)
  expect(dark.chart2).not.toBe(light.chart2)

  // Chỉ xem state React thì bỏ hẳn phần ghi localStorage vẫn xanh, dù theme
  // người dùng chọn mất sạch sau khi tải lại trang.
  await page.reload()
  await expect(page.locator("html")).toHaveClass(/dark/)
  expect(await readTokens()).toEqual(dark)
})
