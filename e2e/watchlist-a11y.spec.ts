import AxeBuilder from "@axe-core/playwright"
import { expect, test, type Page } from "@playwright/test"

/**
 * Quét axe trên trang Watchlist ở **mọi tổ hợp** theme × quy ước màu.
 *
 * Lý do phải quét đủ bốn tổ hợp chứ không chỉ mặc định: bản đầu tiên của trang
 * này sạch ở light + Đông Á gần hết, nhưng light + Âu Mỹ có tới 8 vi phạm — chữ
 * xanh lá trên nền badge chỉ đạt 3.4:1. Quy ước nào bị bỏ quên là chỗ đó hỏng.
 *
 * Và phải quét cả lúc **hover**: axe đo đúng trạng thái đang render, nên chỉ khi
 * con trỏ thật sự nằm trên dòng thì nền hover mới được tính. Đỏ cũ (L 0.55) đạt
 * 4.58:1 trên dòng thường nhưng tụt còn 4.41:1 khi hover — quét tĩnh không thấy.
 */

const RISING = "AAPL"
const FALLING = "MSFT"

async function violations(page: Page) {
  const { violations } = await new AxeBuilder({ page }).analyze()
  // Rút gọn để khi đỏ thì đọc được ngay là element nào, tỉ lệ bao nhiêu.
  return violations.flatMap((v) =>
    v.nodes.map((n) => `${v.id}: ${n.target.join(" ")} — ${n.failureSummary?.split("\n")[1] ?? ""}`),
  )
}

const modes = [
  { theme: "light", convention: "Đông Á" },
  { theme: "light", convention: "Âu Mỹ" },
  { theme: "dark", convention: "Đông Á" },
  { theme: "dark", convention: "Âu Mỹ" },
] as const

for (const { theme, convention } of modes) {
  test(`không vi phạm a11y — ${theme} + ${convention}, cả lúc hover dòng tăng lẫn dòng giảm`, async ({
    page,
  }) => {
    if (theme === "dark") {
      await page.addInitScript(() => localStorage.setItem("automation-ui-kit-theme", "dark"))
    }
    await page.goto("/watchlist")
    await expect(page.locator("[data-testid='price-chart'] canvas").first()).toBeVisible()

    // Tiền đề: đúng theme và đúng quy ước, không thì cả test chạy nhầm tổ hợp.
    if (theme === "dark") await expect(page.locator("html")).toHaveClass(/dark/)
    else await expect(page.locator("html")).not.toHaveClass(/dark/)
    if (convention === "Âu Mỹ") {
      await page.getByLabel("Quy ước màu").click()
      await page.getByRole("option", { name: /Âu Mỹ/ }).click()
    }
    await expect(page.getByLabel("Quy ước màu")).toContainText(convention)

    expect(await violations(page), "trạng thái tĩnh").toEqual([])

    for (const ticker of [RISING, FALLING]) {
      const row = page.locator("tbody tr", { hasText: ticker })
      await row.hover()
      // Tiền đề: nền hover thật sự đã áp — nếu không thì lượt quét này vô nghĩa.
      await expect
        .poll(() => row.evaluate((el) => getComputedStyle(el).backgroundColor))
        .not.toBe("rgba(0, 0, 0, 0)")
      expect(await violations(page), `hover ${ticker}`).toEqual([])
    }
  })
}

for (const theme of ["light", "dark"] as const) {
  test(`không vi phạm a11y khi mở bảng tìm mã — ${theme}`, async ({ page }) => {
    if (theme === "dark") {
      await page.addInitScript(() => localStorage.setItem("automation-ui-kit-theme", "dark"))
    }
    await page.goto("/watchlist")
    await page.keyboard.press("Control+k")
    // Item đầu tiên được chọn sẵn, nên lượt quét phủ luôn chữ phụ trên nền accent.
    await expect(page.locator("[cmdk-item][data-selected='true']")).toHaveCount(1)
    expect(await violations(page)).toEqual([])
  })
}

test.describe("chọn dòng bằng bàn phím", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/watchlist")
  })

  test("Tab từ header đi thẳng vào dòng đầu tiên của bảng", async ({ page }) => {
    // Trước đây `onClick` nằm trên <tr> nên Tab đi qua cả bảng mà không dừng
    // ở dòng nào — người dùng bàn phím không có cách nào đổi mã của chart.
    await page.getByRole("button", { name: "Khối lượng" }).focus()
    await page.keyboard.press("Tab")

    const focused = page.locator(":focus")
    await expect(focused).toHaveText("7267.T")
    await expect(focused.locator("xpath=ancestor::tbody")).toHaveCount(1)
  })

  test("Enter trên một dòng đổi chart sang mã đó", async ({ page }) => {
    await page.getByRole("button", { name: "Khối lượng" }).focus()
    await page.keyboard.press("Tab")
    await page.keyboard.press("Tab")
    await expect(page.locator(":focus")).toHaveText("6367.T")

    await page.keyboard.press("Enter")
    await expect(page.locator("[data-slot='card']").last()).toContainText("Daikin Industries")
  })

  test("đúng một dòng mang aria-current, và nó đi theo mã đang xem", async ({ page }) => {
    const current = page.locator("tbody button[aria-current='true']")
    await expect(current).toHaveCount(1)
    await expect(current).toHaveText("7267.T")

    await page.locator("tbody tr", { hasText: "NVDA" }).click()
    await expect(current).toHaveCount(1)
    await expect(current).toHaveText("NVDA")
  })
})
