import { expect, test, type Page } from "@playwright/test"

/** Ảnh của canvas chính, dùng để biết chart có vẽ lại hay không. */
function canvasSnapshot(page: Page) {
  return page
    .locator("[data-testid='price-chart'] canvas")
    .first()
    .evaluate((c) => (c as HTMLCanvasElement).toDataURL())
}

const closeValue = (page: Page) => page.locator("[data-field='close'] dd").innerText()

/**
 * Khung của canvas, sau khi đã cuộn chart vào tầm nhìn.
 *
 * `mouse.move` dùng toạ độ **viewport**, còn `boundingBox()` trả toạ độ theo
 * trang. Viewport mặc định chỉ cao 720px nên chart nằm dưới màn: không cuộn thì
 * con trỏ rơi ra ngoài cửa sổ và chart không hề nhận được sự kiện nào — test sẽ
 * đỏ vì lý do chẳng liên quan gì tới chart.
 */
async function chartBox(page: Page) {
  const canvas = page.locator("[data-testid='price-chart'] canvas").first()
  await canvas.scrollIntoViewIfNeeded()
  const box = await canvas.boundingBox()
  expect(box).not.toBeNull()
  return box!
}

test.beforeEach(async ({ page }) => {
  await page.goto("/watchlist")
  await expect(page.locator("[data-testid='price-chart'] canvas").first()).toBeVisible()
})

test("chart vẽ ra canvas có kích thước thật, không phải khung rỗng", async ({ page }) => {
  const box = await chartBox(page)
  expect(box.width).toBeGreaterThan(200)
  expect(box.height).toBeGreaterThan(100)
})

test("giá đóng cửa trên chart khớp đúng giá trong bảng", async ({ page }) => {
  // Chart và bảng mà nói hai con số khác nhau cho cùng một mã thì người xem
  // không biết tin cái nào — dữ liệu mẫu cũng phải nhất quán.
  const tablePrice = await page
    .locator("tbody tr", { hasText: "7267.T" })
    .locator("td")
    .nth(4)
    .innerText()

  expect(await closeValue(page)).toBe(tablePrice.trim())
})

test("rê chuột lên chart thì readout đổi sang phiên đang trỏ", async ({ page }) => {
  const atRest = await closeValue(page)
  const box = await chartBox(page)

  await page.mouse.move(box.x + box.width * 0.25, box.y + box.height * 0.5)
  await expect(page.locator("[data-field='close'] dd")).not.toHaveText(atRest)

  // Rời chuột ra thì quay về phiên gần nhất, chứ không kẹt ở giá trị cũ.
  await page.mouse.move(box.x + box.width / 2, box.y - 120)
  await expect(page.locator("[data-field='close'] dd")).toHaveText(atRest)
})

test("đổi mã thì readout quay về phiên cuối của mã mới, không giữ giá trị đang hover", async ({
  page,
}) => {
  const box = await chartBox(page)
  await page.mouse.move(box.x + box.width * 0.3, box.y + box.height * 0.5)
  const hovered = await closeValue(page)

  await page.locator("tbody tr", { hasText: "AAPL" }).click()

  const tablePrice = await page
    .locator("tbody tr", { hasText: "AAPL" })
    .locator("td")
    .nth(4)
    .innerText()
  await expect(page.locator("[data-field='close'] dd")).toHaveText(tablePrice.trim())
  expect(await closeValue(page)).not.toBe(hovered)
})

test("đổi theme thì chart đọc lại màu và vẽ lại", async ({ page }) => {
  // Canvas không resolve được `var(--token)`, nên màu phải đọc ra rồi áp lại.
  // Hỏng cái này thì chart giữ nguyên bộ màu của theme cũ mà không báo lỗi gì.
  const before = await canvasSnapshot(page)
  await page.getByLabel("Toggle theme").click()
  await expect(page.locator("html")).toHaveClass(/dark/)
  await expect.poll(() => canvasSnapshot(page)).not.toBe(before)
})

test("đổi quy ước màu thì chart vẽ lại theo", async ({ page }) => {
  const before = await canvasSnapshot(page)
  await page.getByLabel("Quy ước màu").click()
  await page.getByRole("option", { name: /Âu Mỹ/ }).click()
  await expect.poll(() => canvasSnapshot(page)).not.toBe(before)
})

test("đổi theme và quy ước không làm thư viện chart ném lỗi màu", async ({ page }) => {
  // Token viết bằng `oklch()`. Chromium nhận oklch trong `fillStyle` nhưng đọc
  // lại vẫn trả nguyên chuỗi, nên nếu không rasterize ra sRGB thì chuỗi oklch
  // rơi xuống parser riêng của thư viện và ném "Failed to parse color".
  const errors: string[] = []
  page.on("pageerror", (e) => errors.push(e.message))

  await page.getByLabel("Quy ước màu").click()
  await page.getByRole("option", { name: /Âu Mỹ/ }).click()
  await page.getByLabel("Toggle theme").click()
  await expect(page.locator("html")).toHaveClass(/dark/)
  await page.locator("tbody tr", { hasText: "NVDA" }).click()
  await expect(page.locator("[data-field='close'] dd")).toContainText("$")

  expect(errors).toEqual([])
})

test("readout có nhãn truy cập được và đủ các trường OHLC", async ({ page }) => {
  const readout = page.getByLabel("Số liệu phiên đang xem")
  await expect(readout).toBeVisible()
  for (const field of ["date", "open", "high", "low", "close", "volume"]) {
    await expect(readout.locator(`[data-field='${field}']`)).toHaveCount(1)
  }
})

test("giá cao nhất không thấp hơn giá đóng cửa của cùng phiên", async ({ page }) => {
  // Bất biến của nến: bóng trên luôn bao thân. Dữ liệu sinh sai chỗ này thì
  // chart vẽ ra hình vô lý mà vẫn không lỗi.
  const num = async (field: string) =>
    Number((await page.locator(`[data-field='${field}'] dd`).innerText()).replace(/[^\d.]/g, ""))

  const [high, low, open, close] = await Promise.all([
    num("high"),
    num("low"),
    num("open"),
    num("close"),
  ])
  expect(high).toBeGreaterThanOrEqual(Math.max(open, close))
  expect(low).toBeLessThanOrEqual(Math.min(open, close))
})
