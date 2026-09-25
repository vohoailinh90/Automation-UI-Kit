import { expect, test, type Locator, type Page } from "@playwright/test"

/**
 * Hợp đồng của `Tracker` với cha khi `blocks` đổi độ dài lúc dải đang được đọc
 * — trang Automation dùng dữ liệu tĩnh nên không tái hiện được, phải dùng trang
 * thử `e2e/fixtures/tracker.html`. Điều cần giữ: chỉ số cha nghe qua callback
 * luôn là ô slider đang hiện, không bao giờ là ô đã biến mất.
 */
test.beforeEach(async ({ page }) => {
  await page.goto("/e2e/fixtures/tracker.html")
  await expect(page.getByRole("slider")).toBeVisible()
})

/** Đổi số ô mà không đụng tới focus hay con trỏ, như dữ liệu mới về. */
async function setCount(page: Page, count: number) {
  await page.evaluate((n) => window.dispatchEvent(new CustomEvent("fixture:count", { detail: n })), count)
}

/** Chỉ số ô đang viền, `-1` nếu không có. */
function activeIndex(slider: Locator) {
  return slider
    .locator("[data-status]")
    .evaluateAll((blocks) => blocks.findIndex((block) => block.hasAttribute("data-active")))
}

test("dải đang focus ngắn đi thì cha nghe đúng ô slider đang báo; dải rỗng thì về null", async ({ page }) => {
  const slider = page.getByRole("slider")
  const cursor = page.getByTestId("cursor")
  await slider.focus()
  await expect(slider).toHaveAttribute("aria-valuenow", "29")
  await expect(cursor).toHaveText("29")

  await setCount(page, 10)
  await expect(slider).toHaveAttribute("aria-valuenow", "9")
  await expect(cursor).toHaveText("9")

  // Dài lại thì vẫn đứng ở ô đang đọc, không nhảy về chỉ số cũ đã kẹp mất.
  await setCount(page, 30)
  await expect(slider).toHaveAttribute("aria-valuenow", "9")
  await expect(cursor).toHaveText("9")

  // Dải rỗng: slider biến mất cùng focus mà Chromium không bắn `blur`.
  await setCount(page, 0)
  await expect(page.getByRole("slider")).toHaveCount(0)
  await expect(cursor).toHaveText("null")

  // Có ô trở lại: không ai đang đọc, nên không ô nào được viền.
  await setCount(page, 10)
  await expect(slider).toHaveAttribute("aria-valuenow", "9")
  expect(await activeIndex(slider)).toBe(-1)
  await expect(cursor).toHaveText("null")
})

test("ô dưới chuột biến mất thì cha không giữ chỉ số slider không còn vẽ", async ({ page }) => {
  const slider = page.getByRole("slider")
  const blocks = slider.locator("[data-status]")
  const hover = page.getByTestId("hover")
  // Chromium tự bắn pointerover cho ô mới nằm dưới con trỏ đứng yên khi layout
  // đổi, nên chuột thật che mất lỗi. Đỗ chuột thật ra ngoài rồi tự phát
  // `pointerover` để kết quả không phụ thuộc chuyện đó.
  await page.mouse.move(1, 1)
  await blocks.nth(25).dispatchEvent("pointerover")
  await expect(hover).toHaveText("25")
  expect(await activeIndex(slider)).toBe(25)

  await setCount(page, 10)
  await expect(hover).toHaveText("null")
  expect(await activeIndex(slider)).toBe(-1)

  // Dài lại khi chuột chưa hề động: ô cũ không được tự sáng lại.
  await setCount(page, 30)
  await expect(blocks).toHaveCount(30)
  expect(await activeIndex(slider)).toBe(-1)
  await expect(hover).toHaveText("null")

  await blocks.nth(5).dispatchEvent("pointerover")
  await expect(hover).toHaveText("5")
  await setCount(page, 0)
  await expect(hover).toHaveText("null")

  // Chuột thật: dù Chromium có trỏ lại ô mới dưới con trỏ hay không, cha và
  // slider phải nói cùng một ô.
  await setCount(page, 10)
  await blocks.nth(9).hover()
  await expect(hover).toHaveText("9")
  await setCount(page, 4)
  await expect
    .poll(async () => {
      const index = await activeIndex(slider)
      return (await hover.innerText()) === (index === -1 ? "null" : String(index))
    })
    .toBe(true)
})
