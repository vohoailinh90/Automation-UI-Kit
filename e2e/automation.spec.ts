import { expect, test, type Page } from "@playwright/test"

test.use({ reducedMotion: "reduce" })

test.beforeEach(async ({ page }) => {
  await page.goto("/automation")
  await expect(page.locator("[data-slot='tracker']").first()).toBeVisible()
})

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

/** Số đầu tiên trong một chuỗi như "1,284", "2 0.2%" hay "17 lỗi". */
function firstNumber(text: string) {
  const match = text.replace(/,/g, "").match(/\d+/)
  if (!match) throw new Error(`không có số trong "${text}"`)
  return Number(match[0])
}

function tracker(page: Page, job: string) {
  return page.getByRole("slider", { name: new RegExp(`^${job}, 30 ngày`) })
}

test("KPI lỗi, chú giải thanh kết quả và bảng lượt chạy cùng kể một chuyện", async ({ page }) => {
  // Ba bề mặt đọc từ một danh sách lượt chạy duy nhất. Test kiểm quan hệ giữa
  // chúng, không kiểm hằng số: ai bịa riêng một con số tổng hợp là lệch ngay.
  const failedKpi = firstNumber(await kpiValue(page, "Lượt lỗi · 7 ngày").innerText())
  const legend = page.locator("[data-slot='category-bar'] li[data-key='failed']")
  expect(firstNumber(await legend.locator(".tabular-nums").innerText())).toBe(failedKpi)

  // Hôm nay Excel → Planner lỗi lúc 08:05: ô cuối của nó đỏ, và bảng lượt chạy
  // gần nhất có đúng dòng đó.
  await expect(tracker(page, "Excel → Planner").locator("[data-status]").last()).toHaveAttribute(
    "data-status",
    "failed",
  )
  const failedRow = page.locator("tbody tr", { hasText: "Excel → Planner" }).filter({ hasText: "08:05" })
  await expect(failedRow).toHaveCount(1)
  await expect(failedRow.locator("[data-slot='status-badge']")).toHaveAttribute("data-tone", "failed")
})

test("tổng lỗi của một ngày trên biểu đồ bằng tổng lỗi các job ngày đó trên tracker", async ({ page }) => {
  // 27/08: đêm token Graph hết hạn. Đọc số lỗi từng job bằng bàn phím trên
  // tracker, rồi so với tooltip của cột biểu đồ ngày đó.
  let fromTrackers = 0
  for (const slider of await page.getByRole("slider").all()) {
    await slider.focus()
    await page.keyboard.press("Home")
    for (let i = 0; i < 7; i += 1) await page.keyboard.press("ArrowRight")
    const text = (await slider.getAttribute("aria-valuetext")) ?? ""
    expect(text, "tiền đề: ô thứ 8 là 27/08").toMatch(/^27\/08/)
    const failed = text.match(/(\d+) lỗi/)
    fromTrackers += failed ? Number(failed[1]) : 0
  }
  expect(fromTrackers, "tiền đề: ngày sự cố thật sự có lỗi").toBeGreaterThan(0)

  // Cột thứ 8 của chuỗi "Thành công" là ngày 27/08 ở khoảng 30 ngày mặc định.
  const bar = page.locator(".recharts-bar").first().locator(".recharts-bar-rectangle").nth(7)
  const box = await bar.boundingBox()
  expect(box).not.toBeNull()
  if (!box) return
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2, { steps: 4 })

  const tooltip = page.locator(".recharts-tooltip-wrapper")
  await expect(tooltip).toContainText("27/08")
  // Một dòng tooltip = nhãn chuỗi + giá trị, nằm chung một khối `justify-between`.
  const failedRow = tooltip
    .locator(".justify-between")
    .filter({ has: page.getByText("Lỗi", { exact: true }) })
  await expect(failedRow).toHaveCount(1)
  expect(firstNumber(await failedRow.innerText())).toBe(fromTrackers)
})

test("chú giải biểu đồ giữ thứ tự chuỗi và buộc đúng màu với cột", async ({ page }) => {
  // Recharts 3 mặc định sắp chú giải theo tên → "Lỗi, Thành công, Cảnh báo".
  const items = page.locator(".recharts-legend-wrapper [class*='gap-1.5']")
  await expect(items).toHaveText(["Thành công", "Cảnh báo", "Lỗi"])

  const series = page.locator(".recharts-bar")
  for (let i = 0; i < 3; i += 1) {
    const swatch = await items.nth(i).locator("div").first().evaluate((el) => getComputedStyle(el).backgroundColor)
    const fill = await series
      .nth(i)
      .locator(".recharts-bar-rectangle path")
      .first()
      .evaluate((el) => getComputedStyle(el).fill)
    expect(fill, `chuỗi ${i}`).toBe(swatch)
  }
})

test("nhóm nút khoảng thời gian đổi số ngày trên biểu đồ, và dùng được bằng bàn phím", async ({ page }) => {
  const group = page.getByRole("radiogroup", { name: "Khoảng thời gian của biểu đồ" })
  const days = page.locator(".recharts-bar").first().locator(".recharts-bar-rectangle")
  await expect(group.getByRole("radio", { name: "30 ngày" })).toHaveAttribute("aria-checked", "true")
  await expect(days).toHaveCount(30)

  await group.getByRole("radio", { name: "7 ngày" }).click()
  await expect(days).toHaveCount(7)

  // Bấm lại nút đang chọn: Radix trả chuỗi rỗng, biểu đồ không được mất dữ liệu.
  await group.getByRole("radio", { name: "7 ngày" }).click()
  await expect(group.getByRole("radio", { name: "7 ngày" })).toHaveAttribute("aria-checked", "true")
  await expect(days).toHaveCount(7)

  // Bàn phím: cả nhóm là một điểm dừng Tab, mũi tên để đi, Space để chọn.
  await group.getByRole("radio", { name: "7 ngày" }).focus()
  await page.keyboard.press("ArrowRight")
  await expect(group.getByRole("radio", { name: "14 ngày" })).toBeFocused()
  await page.keyboard.press("Space")
  await expect(group.getByRole("radio", { name: "14 ngày" })).toHaveAttribute("aria-checked", "true")
  await expect(days).toHaveCount(14)
})

test.describe("tracker", () => {
  test("Tab vào rồi dùng phím mũi tên để đọc từng ngày", async ({ page }) => {
    const slider = tracker(page, "Excel → Planner")
    await slider.focus()
    // Vào dải là đứng ở ngày mới nhất — hôm nay, đang có lỗi.
    await expect(slider).toHaveAttribute("aria-valuetext", /^18\/09 \(hôm nay, tới 09:10\).*1 lỗi/)
    const readout = page.getByTestId("tracker-readout")
    await expect(readout).toContainText("Excel → Planner")
    await expect(readout).toContainText("18/09")

    await page.keyboard.press("ArrowLeft")
    await expect(slider).toHaveAttribute("aria-valuetext", /^17\/09 ·/)
    await expect(readout).toContainText("17/09")

    await page.keyboard.press("Home")
    await expect(slider).toHaveAttribute("aria-valuenow", "0")
    await expect(slider).toHaveAttribute("aria-valuetext", /^20\/08 ·/)

    await page.keyboard.press("PageUp")
    await expect(slider).toHaveAttribute("aria-valuenow", "7")
    await page.keyboard.press("End")
    await expect(slider).toHaveAttribute("aria-valuenow", "29")
    // Không đi quá hai đầu.
    await page.keyboard.press("ArrowRight")
    await expect(slider).toHaveAttribute("aria-valuenow", "29")
  })

  test("rê chuột lên một ô thì readout hiện đúng ô đó; rời dải thì về lời nhắc", async ({ page }) => {
    const slider = tracker(page, "Báo cáo thị trường sáng")
    // Ô thứ 4 (23/08) là chủ nhật — báo cáo sáng chỉ chạy thứ 2–6.
    const sunday = slider.locator("[data-status]").nth(3)
    await expect(sunday).toHaveAttribute("data-status", "idle")
    await sunday.hover()
    const readout = page.getByTestId("tracker-readout")
    await expect(readout).toContainText("Báo cáo thị trường sáng — 23/08 · không chạy")
    await expect(sunday).toHaveAttribute("data-active", "true")

    await page.mouse.move(0, 0)
    await expect(readout).toContainText("Rê chuột lên một dải")
    await expect(slider.locator("[data-active]")).toHaveCount(0)
  })

  test("tên truy cập được đếm đúng số ô theo từng trạng thái", async ({ page }) => {
    // Tên của slider là phần tóm tắt cho screen reader; nó phải khớp với chính
    // các ô đang vẽ, không phải một con số tính riêng.
    for (const slider of await page.getByRole("slider").all()) {
      const name = (await slider.getAttribute("aria-label")) ?? ""
      const labels = { success: "ổn", warning: "có cảnh báo", failed: "có lỗi", idle: "không chạy" }
      for (const [status, word] of Object.entries(labels)) {
        const count = await slider.locator(`[data-status='${status}']`).count()
        if (count === 0) expect(name).not.toContain(word)
        else expect(name).toContain(`${count} ${word}`)
      }
    }
  })
})
