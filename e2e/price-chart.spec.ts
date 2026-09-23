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

/**
 * Đếm điểm ảnh đúng màu `--price-rise` / `--price-fall` trên **trục giá**.
 *
 * Vì sao lại là trục giá: các test "chart vẽ lại" ở trên chỉ biết canvas *có
 * đổi*, nên gán ngược màu nến (màu giảm cho nến tăng) vẫn xanh — canvas vẫn
 * đổi mà. Khung chính thì có đủ nến của cả hai màu nên không phân biệt được.
 * Nhưng nhãn giá cuối trên trục là **một khối màu đặc tô bằng màu của nến cuối**,
 * và trên trục không có gì khác mang hai màu này — đếm là ra đúng chiều.
 *
 * Trục giá là các canvas hẹp (bề rộng dưới 1/4 chart); đó là cách lightweight-
 * charts chia layer. Nếu thư viện đổi cách chia, lượt đếm sẽ ra 0 và test đỏ
 * rõ ràng ở bước tiền đề, chứ không xanh vô nghĩa.
 */
function axisColorCounts(page: Page) {
  return page.locator("[data-testid='price-chart']").evaluate((host) => {
    const rgbOf = (name: string) => {
      const c = document.createElement("canvas")
      c.width = c.height = 1
      const ctx = c.getContext("2d")!
      ctx.fillStyle = getComputedStyle(host).getPropertyValue(name).trim()
      ctx.fillRect(0, 0, 1, 1)
      return Array.from(ctx.getImageData(0, 0, 1, 1).data.slice(0, 3))
    }
    const rise = rgbOf("--price-rise")
    const fall = rgbOf("--price-fall")
    let nRise = 0
    let nFall = 0
    for (const canvas of Array.from(host.querySelectorAll("canvas"))) {
      if (canvas.width >= host.clientWidth / 4 || canvas.height < 100) continue
      const d = canvas.getContext("2d")!.getImageData(0, 0, canvas.width, canvas.height).data
      for (let i = 0; i < d.length; i += 4) {
        if (d[i + 3] !== 255) continue
        if (d[i] === rise[0] && d[i + 1] === rise[1] && d[i + 2] === rise[2]) nRise += 1
        else if (d[i] === fall[0] && d[i + 1] === fall[1] && d[i + 2] === fall[2]) nFall += 1
      }
    }
    return { rise: nRise, fall: nFall }
  })
}

for (const convention of ["Đông Á", "Âu Mỹ"] as const) {
  test(`nến cuối tăng thì nhãn giá cuối màu "tăng", giảm thì màu "giảm" — ${convention}`, async ({
    page,
  }) => {
    if (convention === "Âu Mỹ") {
      await page.getByLabel("Quy ước màu").click()
      await page.getByRole("option", { name: /Âu Mỹ/ }).click()
    }

    const directions = new Set<string>()
    for (const ticker of ["7267.T", "6367.T", "8306.T", "AAPL", "MSFT", "NVDA"]) {
      await page.locator("tbody tr", { hasText: ticker }).click()
      await expect(page.locator("[data-slot='card']").last()).toContainText(ticker)

      // Chiều của nến cuối lấy từ class của readout — nó được tính trên giá trị
      // chính xác. Không parse số hiển thị: Yên làm tròn về số nguyên nên hai
      // giá sát nhau có thể hiện ra giống hệt.
      const closeClass = (await page.locator("[data-field='close'] dd").getAttribute("class")) ?? ""
      const direction = closeClass.includes("text-price-rise") ? "rise" : "fall"
      directions.add(direction)

      await expect
        .poll(() => axisColorCounts(page), { message: `${ticker}: nhãn giá cuối phải màu ${direction}` })
        .toEqual(
          direction === "rise"
            ? { rise: expect.any(Number), fall: 0 }
            : { rise: 0, fall: expect.any(Number) },
        )
      // Tiền đề: thật sự đếm được một khối màu, không phải 0 = 0 cho có.
      const counts = await axisColorCounts(page)
      expect(counts[direction], `${ticker}: phải thấy khối màu của nhãn`).toBeGreaterThan(200)
    }

    // Tiền đề: bộ mã trên phải có cả nến cuối tăng lẫn giảm, không thì chỉ một
    // nhánh được kiểm và gán ngược màu nhánh còn lại sẽ lọt.
    expect([...directions].sort()).toEqual(["fall", "rise"])
  })
}

test("mỗi nến chỉ một màu từ bóng đến thân — không cột điểm ảnh nào lẫn hai màu", async ({
  page,
}) => {
  // Test nhãn giá cuối ở trên bắt được đảo màu *thân* nến, nhưng nhãn chỉ tô
  // theo thân, nên đảo riêng màu *bóng* nến thì vẫn lọt. Bất biến ở đây bắt
  // được: trên chart đúng, mọi cột điểm ảnh chỉ mang một trong hai màu (nến
  // cách nhau bằng khe trống). Bóng khác màu thân thì cột ở tâm mỗi nến sẽ có
  // cả hai.
  //
  // Chỉ phải loại một thứ: đường giá cuối — nét đứt nằm ngang, mang màu nến
  // cuối, cắt qua mọi cột. Nó là hàng có nhiều điểm màu nhất, nên tìm ra được.
  for (const ticker of ["7267.T", "AAPL", "MSFT"]) {
    await page.locator("tbody tr", { hasText: ticker }).click()
    await expect(page.locator("[data-slot='card']").last()).toContainText(ticker)

    const probe = () =>
      page.locator("[data-testid='price-chart']").evaluate((host) => {
        const rgbOf = (name: string) => {
          const c = document.createElement("canvas")
          c.width = c.height = 1
          const ctx = c.getContext("2d")!
          ctx.fillStyle = getComputedStyle(host).getPropertyValue(name).trim()
          ctx.fillRect(0, 0, 1, 1)
          return Array.from(ctx.getImageData(0, 0, 1, 1).data.slice(0, 3))
        }
        const rise = rgbOf("--price-rise")
        const fall = rgbOf("--price-fall")
        const main = Array.from(host.querySelectorAll("canvas")).find(
          (c) => c.width >= host.clientWidth / 2 && c.height > 100,
        )!
        const { width: W, height: H } = main
        const d = main.getContext("2d")!.getImageData(0, 0, W, H).data
        const kind = (x: number, y: number) => {
          const i = (y * W + x) * 4
          if (d[i + 3] !== 255) return 0
          if (d[i] === rise[0] && d[i + 1] === rise[1] && d[i + 2] === rise[2]) return 1
          if (d[i] === fall[0] && d[i + 1] === fall[1] && d[i + 2] === fall[2]) return 2
          return 0
        }
        let lineY = -1
        let lineCount = 0
        let colored = 0
        for (let y = 0; y < H; y += 1) {
          let n = 0
          for (let x = 0; x < W; x += 1) if (kind(x, y)) n += 1
          colored += n
          if (n > lineCount) {
            lineCount = n
            lineY = y
          }
        }
        let mixed = 0
        for (let x = 0; x < W; x += 1) {
          let hasRise = false
          let hasFall = false
          for (let y = 0; y < H; y += 1) {
            if (Math.abs(y - lineY) <= 2) continue
            const k = kind(x, y)
            if (k === 1) hasRise = true
            else if (k === 2) hasFall = true
          }
          if (hasRise && hasFall) mixed += 1
        }
        return { colored, mixed }
      })

    // Tiền đề: chart đã vẽ xong và thật sự có điểm ảnh của hai màu để xét.
    await expect.poll(async () => (await probe()).colored).toBeGreaterThan(1000)
    expect((await probe()).mixed, `${ticker}: cột lẫn hai màu`).toBe(0)
  }
})
