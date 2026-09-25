import { expect, test, type Locator, type Page } from "@playwright/test"

test.use({ reducedMotion: "reduce" })

/** "¥1,842" / "2,000" / "+¥137,500" → số. */
function amount(text: string) {
  const sign = /^[−-]/.test(text.trim()) ? -1 : 1
  return sign * Number(text.replace(/[^\d.]/g, ""))
}

/**
 * Con số của KPI có **đúng** nhãn `label`. Không dùng `hasText` trên cả card:
 * nó so chuỗi con không phân biệt hoa thường, nên "Tiền mặt" khớp luôn dòng
 * chú thích "Cổ phiếu + tiền mặt" của card khác.
 */
function kpiValue(page: Page, label: string) {
  return page
    .locator("[data-slot='kpi-card']")
    .filter({ has: page.locator("[data-slot='card-description']").getByText(label, { exact: true }) })
    .locator("[data-slot='card-title']")
}

/** Bảng đầu tiên trên trang → { mã: { tên cột: chữ trong ô } }. */
function readTable(page: Page) {
  return page.locator("table").first().evaluate((table) => {
    const headers = [...table.querySelectorAll("thead th")].map((th) => th.textContent?.trim() ?? "")
    const rows: Record<string, Record<string, string>> = {}
    for (const tr of table.querySelectorAll("tbody tr")) {
      const cells = [...tr.querySelectorAll("td")].map((td) => td.textContent?.trim() ?? "")
      rows[cells[0]] = Object.fromEntries(headers.map((h, i) => [h, cells[i]]))
    }
    return rows
  })
}

const colorOf = (el: Locator) => el.evaluate((node) => getComputedStyle(node).color)

function plCell(page: Page, ticker: string) {
  // Cột Lãi/lỗ là ô có dấu ¥ kèm %, nằm trong dòng của mã.
  return page.locator("tbody tr", { hasText: ticker }).locator("td span.tabular-nums", { hasText: "%)" })
}

async function useConvention(page: Page, name: RegExp) {
  await page.getByLabel("Quy ước màu").click()
  await page.getByRole("option", { name }).click()
}

test("giá trong danh mục khớp từng mã với bảng Watchlist", async ({ page }) => {
  // Hai trang cùng kit mà nói hai giá khác nhau cho cùng một mã là thứ người
  // xem thấy ngay — danh mục phải đọc cùng dữ liệu mẫu, không sinh giá riêng.
  await page.goto("/watchlist")
  const watchlist = await readTable(page)
  await page.goto("/portfolio")
  const holdings = await readTable(page)

  const tickers = Object.keys(holdings)
  expect(tickers.length, "tiền đề: danh mục có mã").toBeGreaterThan(0)
  for (const ticker of tickers) {
    expect(watchlist[ticker], `${ticker} phải có trong Watchlist`).toBeDefined()
    expect(holdings[ticker]["Giá"], ticker).toBe(watchlist[ticker]["Giá"])
  }
})

test("tổng tài sản bằng Σ số lượng × giá cộng tiền mặt", async ({ page }) => {
  await page.goto("/portfolio")
  const holdings = await readTable(page)
  const invested = Object.values(holdings).reduce((sum, row) => sum + amount(row["SL"]) * amount(row["Giá"]), 0)
  const cash = amount(await kpiValue(page, "Tiền mặt").innerText())
  const total = amount(await kpiValue(page, "Tổng tài sản").innerText())
  expect(invested + cash).toBe(total)
})

test("lãi/lỗ đổi màu theo quy ước, và đúng là đảo vai chứ không phải bảng màu khác", async ({ page }) => {
  await page.goto("/portfolio")
  const rising = plCell(page, "8306.T")
  const falling = plCell(page, "6367.T")
  // Tiền đề: đúng một mã lãi, một mã lỗ.
  await expect(rising).toHaveText(/^\+/)
  await expect(falling).toHaveText(/^−/)

  const eastRise = await colorOf(rising)
  const eastFall = await colorOf(falling)
  expect(eastRise).not.toBe(eastFall)

  await useConvention(page, /Âu Mỹ/)
  const westRise = await colorOf(rising)
  const westFall = await colorOf(falling)
  expect(westRise).not.toBe(eastRise)
  // Cùng một màu đỏ, chỉ đổi vai: Đông Á dùng cho lãi, Âu Mỹ dùng cho lỗ.
  expect(westFall).toBe(eastRise)

  // Badge KPI lãi/lỗ đi cùng quy ước với bảng.
  const badge = page.locator("[data-slot='kpi-card']", { hasText: "Lãi/lỗ chưa chốt" }).locator("[data-slot='kpi-delta']")
  await expect(badge).toHaveAttribute("data-direction", "up")
  expect(await colorOf(badge)).toBe(westRise)
})

test("vùng biểu đồ mang màu theo chiều của khoảng đang xem", async ({ page }) => {
  await page.goto("/portfolio")
  const group = page.getByRole("radiogroup", { name: "Khoảng thời gian của biểu đồ" })
  const change = page.getByTestId("range-change")
  const curve = page.locator(".recharts-area-curve")
  const stroke = () => curve.evaluate((el) => getComputedStyle(el).stroke)

  // 3 tháng: danh mục tăng; 1 tháng: giảm (dữ liệu mẫu tất định).
  await group.getByRole("radio", { name: "3 tháng" }).click()
  await expect(change, "tiền đề: 3 tháng là tăng").toHaveText(/^\+/)
  const up = await stroke()
  expect(up).toBe(await colorOf(change))

  await group.getByRole("radio", { name: "1 tháng" }).click()
  await expect(change, "tiền đề: 1 tháng là giảm").toHaveText(/^−/)
  await expect.poll(stroke).not.toBe(up)
  expect(await stroke()).toBe(await colorOf(change))
})

test("bảng nắm giữ mặc định sắp theo tỉ trọng giảm dần", async ({ page }) => {
  await page.goto("/portfolio")
  await expect(page.getByRole("columnheader", { name: "Tỉ trọng" })).toHaveAttribute("aria-sort", "descending")
  const weights = Object.values(await readTable(page)).map((row) => amount(row["Tỉ trọng"]))
  expect(weights).toEqual([...weights].sort((a, b) => b - a))
})
