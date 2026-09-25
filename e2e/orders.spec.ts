import { expect, test, type Page } from "@playwright/test"

test.use({ reducedMotion: "reduce" })

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

function upcomingTable(page: Page) {
  return page.locator("[data-slot='card']", { has: page.getByRole("heading", { name: "Sắp tới hạn" }) })
}

test.beforeEach(async ({ page }) => {
  await page.goto("/orders")
  await expect(page.locator(".recharts-pie")).toBeVisible()
})

test("số đơn trễ ở KPI bằng số dòng 'trễ' trong bảng, và đơn trễ nằm trên cùng", async ({ page }) => {
  const late = Number(await kpiValue(page, "Trễ hạn").innerText())
  // Tiền đề: dữ liệu mẫu có đơn trễ (kịch bản kẹt mẫu), không thì test rỗng.
  expect(late).toBeGreaterThan(0)

  const hints = upcomingTable(page).locator("[data-slot='due-hint']")
  const texts = await hints.allInnerTexts()
  expect(texts.filter((t) => t.startsWith("trễ"))).toHaveLength(late)
  // Trễ nhất lên đầu: mọi dòng trễ đứng trước mọi dòng còn hạn.
  const firstOnTime = texts.findIndex((t) => !t.startsWith("trễ"))
  expect(firstOnTime).toBe(late)
})

test("đơn trễ được nói bằng chữ, không chỉ bằng màu đỏ", async ({ page }) => {
  const hint = upcomingTable(page).locator("[data-slot='due-hint']").first()
  await expect(hint).toHaveText(/^trễ \d+ ngày$/)
  const tone = await hint.evaluate((el) => getComputedStyle(el).color)
  const muted = await upcomingTable(page)
    .locator("[data-slot='due-hint']")
    .last()
    .evaluate((el) => getComputedStyle(el).color)
  // Màu chỉ là phần phụ trợ, nhưng vẫn phải khác dòng còn hạn.
  expect(tone).not.toBe(muted)
})

test("số giữa donut bằng tổng chú giải khách hàng", async ({ page }) => {
  const card = page.locator("[data-slot='card']", { has: page.getByRole("heading", { name: "Theo khách hàng" }) })
  const center = Number((await card.locator("[data-slot='donut-center'] tspan").first().textContent())?.replace(/,/g, ""))
  const counts = await card.locator("ul[aria-label] li .tabular-nums").allInnerTexts()
  expect(counts).toHaveLength(5)
  const sum = counts.reduce((acc, text) => acc + Number(text.split(" ")[0]), 0)
  expect(center).toBe(sum)
})

test("chú giải đọc số và phần trăm tách rời, không dính thành một số", async ({ page }) => {
  // `<span>2<span class="ml-1">4.9%</span></span>`: margin chỉ là khoảng trống
  // lúc vẽ, text thật là "24.9%" — screen reader đọc sai hẳn con số.
  const item = page.locator("[data-slot='category-bar'] li[data-key='draft']")
  await expect(item.locator(".tabular-nums")).toHaveText(/^\d+ \d+(\.\d)?%$/)
})

test("biểu đồ tuần: chú giải đúng thứ tự và mỗi tuần đủ hai cột", async ({ page }) => {
  const card = page.locator("[data-slot='card']", {
    has: page.getByRole("heading", { name: "Đơn mới và đơn đã giao theo tuần" }),
  })
  await expect(card.locator(".recharts-legend-wrapper [class*='gap-1.5']")).toHaveText([
    "Đơn mới",
    "Đã giao kết quả",
  ])
  await expect(card.locator(".recharts-bar").first().locator(".recharts-bar-rectangle")).toHaveCount(12)
  await expect(card.locator(".recharts-bar").nth(1).locator(".recharts-bar-rectangle")).toHaveCount(12)
})

test("trên điện thoại bảng chỉ giữ Đơn + Hạn giao, và không cuộn ngang", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  const table = upcomingTable(page)
  await expect(table.getByRole("columnheader", { name: "Đơn" })).toBeVisible()
  await expect(table.getByRole("columnheader", { name: "Hạn giao" })).toBeVisible()
  await expect(table.getByRole("columnheader", { name: "Trạng thái" })).toBeHidden()
  await expect(table.getByRole("columnheader", { name: "Tiến độ" })).toBeHidden()
  // Gợi ý hạn vẫn hiện — đó là cột người ta mở bảng này để xem.
  await expect(table.locator("[data-slot='due-hint']").first()).toBeVisible()

  const container = table.locator("[data-slot='table-container']")
  expect(await container.evaluate((el) => el.scrollWidth - el.clientWidth)).toBe(0)
})
