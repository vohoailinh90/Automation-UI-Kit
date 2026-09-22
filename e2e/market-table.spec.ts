import { expect, test } from "@playwright/test"

/** Mã của từng dòng, theo đúng thứ tự đang hiển thị. */
async function tickers(page: import("@playwright/test").Page) {
  return page.locator("tbody tr td:first-child").allInnerTexts()
}

test.beforeEach(async ({ page }) => {
  await page.goto("/watchlist")
})

test("cột sắp xếp được là nút bấm thật, có aria-sort", async ({ page }) => {
  const header = page.getByRole("columnheader", { name: "Giá" })
  // Chưa bấm thì cột vẫn phải báo là sắp xếp được, không phải im lặng.
  await expect(header).toHaveAttribute("aria-sort", "none")

  await page.getByRole("button", { name: "Giá" }).click()
  await expect(header).toHaveAttribute("aria-sort", /ascending|descending/)
})

test("cột không sắp xếp được thì không có nút và không có aria-sort", async ({ page }) => {
  const header = page.getByRole("columnheader", { name: "90 phiên" })
  await expect(header).not.toHaveAttribute("aria-sort", /.*/)
  await expect(header.getByRole("button")).toHaveCount(0)
})

test("sắp theo tên đổi thứ tự dòng, và đổi tiếp khi bấm lần nữa", async ({ page }) => {
  const original = await tickers(page)

  await page.getByRole("button", { name: "Tên" }).click()
  const once = await tickers(page)
  expect(once).not.toEqual(original)

  await page.getByRole("button", { name: "Tên" }).click()
  const twice = await tickers(page)
  expect(twice).not.toEqual(once)
  // Đảo chiều thật sự, chứ không phải xáo lại lung tung.
  expect(twice).toEqual([...once].reverse())
})

test("sắp theo % thay đổi cho đúng thứ tự số, không phải thứ tự chữ", async ({ page }) => {
  await page.getByRole("button", { name: "% Thay đổi" }).click()
  await expect(page.getByRole("columnheader", { name: "% Thay đổi" })).toHaveAttribute(
    "aria-sort",
    /ascending|descending/,
  )

  const percents = await page.locator("tbody tr [data-slot='price-change']").allInnerTexts()
  const numbers = percents.map((t) => Number(t.replace(/[^\d.+-]/g, "")))
  const sorted = [...numbers].sort((a, b) => a - b)
  // Chấp nhận cả hai chiều, miễn là đơn điệu theo *giá trị số*.
  expect(numbers.every((n, i) => n === sorted[i]) || numbers.every((n, i) => n === sorted[sorted.length - 1 - i])).toBe(true)
})

test("sắp theo giá KHÔNG trộn lẫn hai đơn vị tiền", async ({ page }) => {
  await page.getByRole("button", { name: "Giá" }).click()

  const prices = await page.locator("tbody tr td:nth-child(5)").allInnerTexts()
  const symbols = prices.map((p) => (p.trim().startsWith("¥") ? "JPY" : "USD"))

  // ¥1,842 ≈ $12 nhưng về số thì lớn hơn $461: nếu so thẳng, hai đơn vị sẽ đan
  // xen nhau. Mỗi đơn vị phải nằm gọn thành một khối liền.
  const blocks = symbols.filter((s, i) => i === 0 || s !== symbols[i - 1])
  expect(blocks).toHaveLength(2)

  // Và trong từng khối thì phải thật sự có thứ tự theo giá trị.
  const values = prices.map((p) => Number(p.replace(/[^\d.]/g, "")))
  for (let i = 1; i < values.length; i += 1) {
    if (symbols[i] === symbols[i - 1]) {
      expect(Math.sign(values[i] - values[i - 1])).toBe(Math.sign(values[1] - values[0]) || 0)
    }
  }
})

test("bấm một dòng thì chart đổi sang mã đó", async ({ page }) => {
  await page.locator("tbody tr", { hasText: "NVDA" }).click()

  const chartCard = page.locator("[data-slot='card']").last()
  await expect(chartCard).toContainText("NVDA")
  await expect(chartCard).toContainText("NVIDIA Corp.")
  // Mã Mỹ nên readout phải là USD, không phải ¥ của mã mặc định.
  await expect(page.locator("[data-field='close'] dd")).toContainText("$")
})

test("dòng đang xem được đánh dấu là đang chọn", async ({ page }) => {
  const row = page.locator("tbody tr", { hasText: "MSFT" })
  await expect(row).toHaveAttribute("aria-selected", "false")
  await row.click()
  await expect(row).toHaveAttribute("aria-selected", "true")
  // Và chỉ đúng một dòng được chọn.
  await expect(page.locator("tbody tr[aria-selected='true']")).toHaveCount(1)
})
