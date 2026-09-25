/**
 * Trang thử riêng cho `Tracker`, chỉ dev server phục vụ — `vite build` chỉ build
 * `index.html`, nên trang này không lọt vào bản dựng.
 *
 * Dữ liệu trang Automation là tĩnh, không tái hiện được chuyện `blocks` đổi độ
 * dài lúc dải đang được đọc. Ở đây test đổi số ô bằng sự kiện `fixture:count`
 * trên `window`: không đụng tới focus hay con trỏ chuột như bấm một nút thật.
 * Hai giá trị cha nghe được từ callback hiện ra ở `data-testid="cursor"` và
 * `"hover"` để test so với thứ slider đang hiện.
 */
import * as React from "react"
import { createRoot } from "react-dom/client"

import { Tracker, type TrackerBlock } from "@/components/dashboard/tracker"
import "@/index.css"

const statuses = ["success", "warning", "failed", "idle"] as const

function blocksOf(count: number): TrackerBlock[] {
  return Array.from({ length: count }, (_, i) => ({
    key: String(i),
    status: statuses[i % statuses.length],
    label: `Ô ${i}`,
  }))
}

export function Fixture() {
  const [count, setCount] = React.useState(30)
  const [cursor, setCursor] = React.useState<number | null>(null)
  const [hover, setHover] = React.useState<number | null>(null)

  React.useEffect(() => {
    const onCount = (event: Event) => setCount((event as CustomEvent<number>).detail)
    window.addEventListener("fixture:count", onCount)
    return () => window.removeEventListener("fixture:count", onCount)
  }, [])

  return (
    <main style={{ padding: 32, width: 600 }}>
      {/* Mảng mới mỗi lần render, như một trang thật `map` ngay trong JSX. */}
      <Tracker blocks={blocksOf(count)} label="Dải thử" onCursorChange={setCursor} onHoverChange={setHover} />
      <p>
        cursor <output data-testid="cursor">{String(cursor)}</output> · hover{" "}
        <output data-testid="hover">{String(hover)}</output>
      </p>
    </main>
  )
}

createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <Fixture />
  </React.StrictMode>,
)
