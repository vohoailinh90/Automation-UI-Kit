import { expect, test, type Locator, type Page } from "@playwright/test"

/**
 * Quy ước màu tăng/giảm là thứ dễ "sửa cho đúng" theo hướng sai nhất trong repo
 * này: ai quen thị trường Mỹ nhìn badge đỏ ở dòng tăng sẽ tưởng là bug.
 *
 * Nên các test ở đây không kiểm "có màu gì", mà kiểm **quan hệ giữa hai quy
 * ước**: đúng cái đỏ mà Đông Á dùng cho tăng phải là đúng cái đỏ mà Âu Mỹ dùng
 * cho giảm. Gán nhầm chiều là quan hệ đó gãy ngay.
 */

const RISING = "7267.T" // +1.42%
const FALLING = "6367.T" // -0.83%
const FLAT = "BRK.B" // 0.00%

function badge(page: Page, ticker: string): Locator {
  return page.locator("tbody tr", { hasText: ticker }).locator("[data-slot='price-change']")
}

const colorOf = (el: Locator) => el.evaluate((node) => getComputedStyle(node).color)

async function useConvention(page: Page, name: RegExp) {
  await page.getByLabel("Quy ước màu").click()
  await page.getByRole("option", { name }).click()
}

test.beforeEach(async ({ page }) => {
  await page.goto("/watchlist")
})

test("mặc định là quy ước Đông Á", async ({ page }) => {
  await expect(page.getByLabel("Quy ước màu")).toContainText("Đông Á")
})

test("đổi quy ước thì đảo màu tăng/giảm, và đúng là đảo chứ không phải đổi bảng màu khác", async ({
  page,
}) => {
  const eastRise = await colorOf(badge(page, RISING))
  const eastFall = await colorOf(badge(page, FALLING))
  expect(eastRise).not.toBe(eastFall)

  await useConvention(page, /Âu Mỹ/)
  const westRise = await colorOf(badge(page, RISING))
  const westFall = await colorOf(badge(page, FALLING))
  expect(westRise).not.toBe(westFall)

  // Điểm mấu chốt: màu của "tăng" phải thật sự đổi khi đổi quy ước...
  expect(westRise).not.toBe(eastRise)
  // ...và ĐỎ phải là cùng một màu đỏ, chỉ đổi vai: Đông Á dùng cho tăng, Âu Mỹ
  // dùng cho giảm. Nếu ai gán nhầm chiều thì đẳng thức này gãy.
  expect(westFall).toBe(eastRise)
})

test("mã không đổi giá thì trung tính ở cả hai quy ước", async ({ page }) => {
  const eastFlat = await colorOf(badge(page, FLAT))
  const eastRise = await colorOf(badge(page, RISING))
  expect(eastFlat).not.toBe(eastRise)

  await useConvention(page, /Âu Mỹ/)
  // 0% không có chiều, nên không được ăn theo quy ước.
  expect(await colorOf(badge(page, FLAT))).toBe(eastFlat)
})

test("chữ mô tả chiều KHÔNG đảo theo quy ước, chỉ màu mới đảo", async ({ page }) => {
  // Người dùng screen reader không nghe được màu. Nếu nghĩa được suy từ màu thì
  // ở quy ước Đông Á họ sẽ nghe "giảm" cho một mã đang tăng.
  await expect(badge(page, RISING)).toContainText("tăng")
  await expect(badge(page, FALLING)).toContainText("giảm")

  await useConvention(page, /Âu Mỹ/)
  await expect(badge(page, RISING)).toContainText("tăng")
  await expect(badge(page, FALLING)).toContainText("giảm")
})

test("sparkline vẽ theo xu hướng 90 phiên, không phải theo % của hôm nay", async ({ page }) => {
  // 7267.T hôm nay tăng, nhưng cả chuỗi 90 phiên thì đi xuống. Hai cột nói hai
  // khoảng thời gian khác nhau — làm sparkline ăn theo % ngày là mất thông tin.
  const spark = page.locator("tbody tr", { hasText: RISING }).locator("[data-slot='sparkline']")
  const fallColor = await colorOf(badge(page, FALLING))

  expect(await colorOf(spark)).toBe(fallColor)
  expect(await colorOf(spark)).not.toBe(await colorOf(badge(page, RISING)))
})

test("sparkline là trang trí, không nhân đôi nội dung cho screen reader", async ({ page }) => {
  const sparks = page.locator("[data-slot='sparkline']")
  await expect(sparks).toHaveCount(9)
  for (const spark of await sparks.all()) {
    await expect(spark).toHaveAttribute("aria-hidden", "true")
  }
})
