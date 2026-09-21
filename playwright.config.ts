import { defineConfig, devices } from "@playwright/test"

const PORT = 5173
const BASE_URL = `http://localhost:${PORT}`

/**
 * Một số môi trường (CI nội bộ, sandbox) đã cài sẵn Chromium và chặn việc tải
 * browser. Đặt `PLAYWRIGHT_CHROMIUM_PATH` trỏ vào binary đó để dùng lại.
 * Bỏ trống thì Playwright dùng browser do chính nó quản lý như bình thường.
 */
const executablePath = process.env.PLAYWRIGHT_CHROMIUM_PATH

export default defineConfig({
  testDir: "./e2e",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [["github"], ["list"]] : [["list"]],
  use: {
    baseURL: BASE_URL,
    trace: "on-first-retry",
  },
  projects: [
    {
      name: "chromium",
      use: {
        ...devices["Desktop Chrome"],
        ...(executablePath ? { launchOptions: { executablePath } } : {}),
      },
    },
  ],
  webServer: {
    command: `npm run dev -- --port ${PORT}`,
    url: BASE_URL,
    reuseExistingServer: !process.env.CI,
    stdout: "ignore",
    stderr: "pipe",
  },
})
