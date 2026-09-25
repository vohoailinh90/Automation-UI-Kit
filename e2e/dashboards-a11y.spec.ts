import { expect, test, type Page } from "@playwright/test"

import { axeViolations, backgroundContrast, gotoWithTheme } from "./helpers"

/**
 * Quét axe **mọi trang** ở cả hai theme.
 *
 * Trước đây chỉ Watchlist được quét, và ba trang còn lại có lỗi tương phản thật
 * mà không test nào thấy: badge "Hoàn thành" 3.1:1, tab chưa chọn 4.34:1 (light),
 * badge "Trễ hạn" 2.9:1 (dark). Cả ba nằm ở token/primitive dùng chung — đúng
 * thứ các dashboard mẫu copy đi — nên quét cả trang cũ lẫn trang mới.
 */

test.use({ reducedMotion: "reduce" })

const pages = [
  { path: "/", ready: ".recharts-area-curve" },
  { path: "/tasks", ready: "tbody tr" },
  { path: "/watchlist", ready: "[data-testid='price-chart'] canvas" },
  { path: "/settings", ready: "form" },
  { path: "/automation", ready: "[data-slot='tracker']" },
  { path: "/orders", ready: ".recharts-pie" },
  { path: "/portfolio", ready: ".recharts-area-curve" },
] as const

for (const theme of ["light", "dark"] as const) {
  for (const { path, ready } of pages) {
    test(`không vi phạm a11y — ${path} (${theme})`, async ({ page }) => {
      await gotoWithTheme(page, path, theme)
      await expect(page.locator(ready).first()).toBeVisible()
      // Tiền đề: đúng theme, không thì lượt quét này quét nhầm tổ hợp.
      if (theme === "dark") await expect(page.locator("html")).toHaveClass(/dark/)
      else await expect(page.locator("html")).not.toHaveClass(/dark/)

      expect(await axeViolations(page)).toEqual([])
    })
  }
}

for (const theme of ["light", "dark"] as const) {
  for (const convention of ["Đông Á", "Âu Mỹ"] as const) {
    test(`Portfolio không vi phạm a11y — ${theme} + ${convention}`, async ({ page }) => {
      // Chữ lãi/lỗ và badge KPI mang màu quy ước giá: quy ước nào bị bỏ quên là
      // chỗ đó hỏng (xem watchlist-a11y.spec.ts — Âu Mỹ từng có 8 vi phạm).
      await gotoWithTheme(page, "/portfolio", theme)
      if (convention === "Âu Mỹ") {
        await page.getByLabel("Quy ước màu").click()
        await page.getByRole("option", { name: /Âu Mỹ/ }).click()
      }
      await expect(page.getByLabel("Quy ước màu")).toContainText(convention)
      expect(await axeViolations(page)).toEqual([])

      // Nền hover của dòng bảng kéo tương phản xuống — quét cả lúc đang hover
      // một dòng lãi lẫn một dòng lỗ.
      for (const ticker of ["8306.T", "6367.T"]) {
        const row = page.locator("tbody tr", { hasText: ticker })
        await row.hover()
        await expect
          .poll(() => row.evaluate((el) => getComputedStyle(el).backgroundColor))
          .not.toBe("rgba(0, 0, 0, 0)")
        expect(await axeViolations(page), `hover ${ticker}`).toEqual([])
      }
    })
  }
}

for (const theme of ["light", "dark"] as const) {
  test(`nút khoảng thời gian: lúc hover vẫn đủ tương phản, nút đang chọn tách hẳn khỏi nền — ${theme}`, async ({
    page,
  }) => {
    await gotoWithTheme(page, "/automation", theme)
    const group = page.getByRole("radiogroup", { name: "Khoảng thời gian của biểu đồ" })
    const idle = group.getByRole("radio", { name: "7 ngày" })
    const selected = group.getByRole("radio", { name: "30 ngày" })
    await expect(selected).toHaveAttribute("aria-checked", "true")

    // Upstream shadcn đổi chữ sang muted-foreground lúc hover → 4.34:1 trên nền muted.
    await idle.hover()
    await expect
      .poll(() => idle.evaluate((el) => getComputedStyle(el).backgroundColor))
      .not.toBe("rgba(0, 0, 0, 0)")
    expect(await axeViolations(page)).toEqual([])

    // Nút đang chọn là chỉ báo trạng thái: cần ≥ 3:1 với nền card (WCAG 1.4.11).
    // Nền `accent` của upstream chỉ lệch nền trắng ~1.1:1.
    const card = page.locator("[data-slot='card']", { has: group })
    const ratio = await backgroundContrast(selected, card)
    expect(ratio, "phải đo được màu").not.toBeNull()
    expect(ratio!).toBeGreaterThanOrEqual(3)
  })
}

for (const theme of ["light", "dark"] as const) {
  test(`ô tracker có lỗi / cảnh báo / thành công đủ tương phản với nền card — ${theme}`, async ({
    page,
  }) => {
    await gotoWithTheme(page, "/automation", theme)
    const card = page.locator("[data-slot='card']", { has: page.locator("[data-slot='tracker']") })

    for (const status of ["success", "warning", "failed"] as const) {
      const block = card.locator(`[data-slot='tracker'] [data-status='${status}']`).first()
      // Tiền đề: dữ liệu mẫu thật sự có ô ở trạng thái này, không thì test rỗng.
      await expect(block, `phải có ít nhất một ô ${status}`).toHaveCount(1)
      const ratio = await backgroundContrast(block, card)
      expect(ratio, `phải đo được màu ô ${status}`).not.toBeNull()
      expect(ratio!, `ô ${status}`).toBeGreaterThanOrEqual(3)
    }
  })
}

/**
 * Độ tràn ngang của trang. Đo cả `<main>` chứ không chỉ `<html>`: `<main>` có
 * `overflow-y-auto`, nên chiều ngang của nó cũng thành `auto` — nội dung rộng
 * làm **`<main>`** cuộn ngang, còn `<html>` vẫn vừa khít. Chỉ đo `<html>` thì
 * test xanh ngay cả khi card bị cắt mất nửa bên phải (đã xảy ra, và test cũ
 * không thấy).
 */
function pageOverflow(page: Page) {
  return page.evaluate(() => {
    const main = document.querySelector("main")
    const doc = document.documentElement
    return Math.max(doc.scrollWidth - doc.clientWidth, main ? main.scrollWidth - main.clientWidth : 0)
  })
}

const widths = [390, 768, 1024] as const

test("không trang nào tràn ngang, từ điện thoại tới tablet có sidebar", async ({ page }) => {
  for (const width of widths) {
    await page.setViewportSize({ width, height: 844 })
    for (const { path, ready } of pages) {
      await page.goto(path)
      await expect(page.locator(ready).first()).toBeAttached()
      expect(await pageOverflow(page), `${path} @ ${width}px`).toBe(0)
    }
  }
})

test("bảng của dashboard mẫu vừa khung ở mọi khổ — cột tự ẩn thay vì bắt cuộn ngang", async ({ page }) => {
  // Cuộn ngang được không có nghĩa là dùng được: không có gợi ý nào cho thấy
  // còn cột bên phải. Khổ 768–1024 khó nhất vì sidebar hiện ra ăn mất 256px.
  for (const width of [390, 640, 768, 1024, 1280]) {
    await page.setViewportSize({ width, height: 844 })
    for (const path of ["/automation", "/orders", "/portfolio"]) {
      await page.goto(path)
      const tables = page.locator("[data-slot='table-container']")
      await expect(tables.first()).toBeVisible()
      for (const table of await tables.all()) {
        expect(await table.evaluate((el) => el.scrollWidth - el.clientWidth), `${path} @ ${width}px`).toBe(0)
      }
    }
  }
})

test("nội dung rộng bất thường chỉ cuộn trong bảng, không đẩy cả trang tràn ngang", async ({ page }) => {
  // Con của grid mặc định `min-width: auto`: không có `*:min-w-0` thì một bảng
  // rộng kéo giãn cả cột grid ra ngoài màn hình. Bảng mẫu hiện vừa khung nên
  // phải cố ý làm nó rộng ra mới kiểm được lớp bảo vệ này.
  await page.setViewportSize({ width: 390, height: 844 })
  for (const path of ["/automation", "/orders"]) {
    await page.goto(path)
    const table = page.locator("[data-slot='table-container']").first()
    await table.locator("table").evaluate((el) => {
      el.style.minWidth = "1400px"
    })
    // Tiền đề: bảng thật sự rộng hơn khung.
    await expect.poll(() => table.evaluate((el) => el.scrollWidth - el.clientWidth)).toBeGreaterThan(0)
    expect(await pageOverflow(page), path).toBe(0)
  }
})

test("không vi phạm a11y trên điện thoại — mọi trang", async ({ page }) => {
  // Ở 390px bảng nào cũng dễ tràn ngang, và vùng cuộn không Tab tới được là lỗi
  // axe thật (scrollable-region-focusable) — quét desktop không bao giờ thấy.
  await page.setViewportSize({ width: 390, height: 844 })
  for (const { path, ready } of pages) {
    await page.goto(path)
    await expect(page.locator(ready).first()).toBeAttached()
    expect(await axeViolations(page), path).toEqual([])
  }
})

test("bảng tràn ngang thì Tab tới được vùng cuộn; bảng vừa khung thì không thêm điểm dừng Tab", async ({
  page,
}) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await page.goto("/tasks")
  const container = page.locator("[data-slot='table-container']").first()
  // Tiền đề: bảng Tasks năm cột thật sự tràn ở 390px.
  expect(await container.evaluate((el) => el.scrollWidth > el.clientWidth)).toBe(true)
  await expect(container).toHaveAttribute("tabindex", "0")

  // Tab tới được thì phải cuộn được bằng phím, không thì điểm dừng đó vô dụng.
  await container.focus()
  await page.keyboard.press("ArrowRight")
  await expect.poll(() => container.evaluate((el) => el.scrollLeft)).toBeGreaterThan(0)

  // Nới cửa sổ ra cho bảng vừa khung: điểm dừng Tab phải tự biến mất, không
  // chỉ đúng ở lần render đầu.
  await page.setViewportSize({ width: 1280, height: 800 })
  await expect.poll(() => container.evaluate((el) => el.scrollWidth > el.clientWidth)).toBe(false)
  await expect(container).not.toHaveAttribute("tabindex")
})
