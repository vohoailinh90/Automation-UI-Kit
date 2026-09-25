import { expect, test, type Page } from "@playwright/test"

import { axeViolations as violations } from "./helpers"

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

/**
 * Đo tương phản của chỉ báo focus/đang chọn — thứ axe **không** đo được.
 *
 * axe chỉ kiểm chữ; vòng focus và vạch "đang chọn" là chỉ báo phi văn bản, cần
 * ≥ 3:1 với màu kề bên (WCAG 1.4.11). Nên ở đây tự làm: tách các lớp
 * `box-shadow` (vòng focus của Tailwind là box-shadow), rasterize từng màu ra
 * sRGB, trộn nền của các tổ tiên để biết màu thật phía sau, rồi tính tỉ lệ WCAG.
 *
 * Trả về tương phản của vòng so với nền xung quanh và so với dải offset (nếu
 * có), hoặc của vạch `inset` so với nền của chính element.
 */
function indicatorContrast(page: Page, selector: string) {
  return page.locator(selector).first().evaluate((el) => {
    const canvas = document.createElement("canvas")
    canvas.width = canvas.height = 1
    const ctx = canvas.getContext("2d", { willReadFrequently: true })!
    // Màu không hợp lệ thì canvas **im lặng giữ fillStyle cũ** — tức là đọc ra
    // màu đen đặc, mà đen trên nền sáng đạt ~19–21:1. Parser `box-shadow` bóc
    // nhầm (ví dụ trình duyệt đổi thứ tự khi serialize) sẽ làm test xanh vô
    // nghĩa: đã thử, test ⌘K ở light mode xanh với parser hỏng. Nên phát hiện
    // bằng hai mốc và coi như trong suốt — khi đó bước tiền đề "phải có vòng /
    // vạch" sẽ đỏ.
    const rgba = (css: string) => {
      ctx.fillStyle = "#000"
      ctx.fillStyle = css
      const first = ctx.fillStyle
      ctx.fillStyle = "#fff"
      ctx.fillStyle = css
      if (ctx.fillStyle !== first) return [0, 0, 0, 0]
      ctx.clearRect(0, 0, 1, 1)
      ctx.fillRect(0, 0, 1, 1)
      return Array.from(ctx.getImageData(0, 0, 1, 1).data)
    }
    const lum = (c: number[]) => {
      const f = (v: number) => {
        const x = v / 255
        return x <= 0.03928 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4
      }
      return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2])
    }
    const contrast = (a: number[], b: number[]) => {
      const [hi, lo] = [lum(a), lum(b)].sort((x, y) => y - x)
      return (hi + 0.05) / (lo + 0.05)
    }
    const over = (top: number[], bottom: number[]) => {
      const a = top[3] / 255
      return [0, 1, 2].map((i) => Math.round(top[i] * a + bottom[i] * (1 - a)))
    }
    // Màu thật phía sau một node: trộn nền các tổ tiên từ dưới lên tới lớp đặc.
    const backdrop = (node: Element | null) => {
      const layers: number[][] = []
      for (let n = node; n; n = n.parentElement) {
        const c = rgba(getComputedStyle(n).backgroundColor)
        if (c[3] > 0) layers.push(c)
        if (c[3] === 255) break
      }
      let base = [255, 255, 255]
      for (const layer of layers.reverse()) base = over(layer, base)
      return base
    }
    // Tách các lớp box-shadow, không cắt vào dấu phẩy nằm trong ngoặc màu.
    const raw = getComputedStyle(el).boxShadow
    const parts: string[] = []
    let depth = 0
    let current = ""
    for (const ch of raw) {
      if (ch === "(") depth += 1
      if (ch === ")") depth -= 1
      if (ch === "," && depth === 0) {
        parts.push(current.trim())
        current = ""
      } else current += ch
    }
    if (current.trim()) parts.push(current.trim())
    const shadows = parts
      .map((part) => {
        const m = part.match(/^(.*?\))\s+(.*)$/)
        const lengths = (m?.[2].match(/-?[\d.]+px/g) ?? []).map(parseFloat)
        return { color: rgba(m?.[1] ?? "transparent"), spread: lengths[3] ?? 0, inset: /inset/.test(part) }
      })
      .filter((sh) => sh.color[3] > 0)

    const outer = shadows.filter((sh) => !sh.inset).sort((a, b) => b.spread - a.spread)
    const inset = shadows.find((sh) => sh.inset)
    const around = backdrop(el.parentElement)
    return {
      shadows: shadows.length,
      ringVsSurround: outer[0] ? contrast(over(outer[0].color, around), around) : null,
      ringVsOffset: outer[1] ? contrast(over(outer[0].color, around), over(outer[1].color, around)) : null,
      insetVsOwnBg: inset ? contrast(over(inset.color, backdrop(el)), backdrop(el)) : null,
    }
  })
}

for (const theme of ["light", "dark"] as const) {
  test.describe(`chỉ báo focus / đang chọn đủ tương phản — ${theme}`, () => {
    test.beforeEach(async ({ page }) => {
      if (theme === "dark") {
        await page.addInitScript(() => localStorage.setItem("automation-ui-kit-theme", "dark"))
      }
      await page.goto("/watchlist")
    })

    test("vòng focus của nút sắp xếp", async ({ page }) => {
      // Đi bằng Tab để `:focus-visible` chắc chắn áp — focus bằng script thì
      // trình duyệt có thể không coi là focus từ bàn phím.
      await page.getByRole("button", { name: "Thị trường" }).focus()
      await page.keyboard.press("Tab")
      await expect(page.getByRole("button", { name: "Giá" })).toBeFocused()

      const m = await indicatorContrast(page, ":focus")
      // Tiền đề: thật sự có vòng để đo, không thì so null với số là vô nghĩa.
      expect(m.ringVsSurround, "phải có vòng focus").not.toBeNull()
      expect(m.ringVsSurround!).toBeGreaterThanOrEqual(3)
      expect(m.ringVsOffset!).toBeGreaterThanOrEqual(3)
    })

    test("vòng focus của nút ở ô đầu mỗi dòng — cả trên dòng đang chọn", async ({ page }) => {
      // Dòng đầu (7267.T) là dòng đang chọn: nền /50 là ca tệ nhất cho vòng.
      await page.getByRole("button", { name: "Khối lượng" }).focus()
      await page.keyboard.press("Tab")
      await expect(page.locator(":focus")).toHaveText("7267.T")
      await expect(page.locator("tbody tr").first()).toHaveAttribute("data-state", "selected")

      const m = await indicatorContrast(page, ":focus")
      expect(m.ringVsSurround, "phải có vòng focus").not.toBeNull()
      expect(m.ringVsSurround!).toBeGreaterThanOrEqual(3)
      expect(m.ringVsOffset!).toBeGreaterThanOrEqual(3)
    })

    test("item đang chọn trong ⌘K có vạch chỉ báo, không chỉ đổi nền", async ({ page }) => {
      await page.keyboard.press("Control+k")
      const active = "[cmdk-item][data-selected='true']"
      await expect(page.locator(active)).toHaveCount(1)
      await page.keyboard.press("ArrowDown")
      await expect(page.locator(active)).toHaveCount(1)

      const m = await indicatorContrast(page, active)
      expect(m.insetVsOwnBg, "phải có vạch chỉ báo").not.toBeNull()
      expect(m.insetVsOwnBg!).toBeGreaterThanOrEqual(3)
    })
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
