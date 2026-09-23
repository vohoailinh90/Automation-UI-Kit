import * as React from "react"

/**
 * Đếm số lần theme đổi, để component vẽ bằng canvas biết lúc nào phải **đọc lại
 * màu**.
 *
 * Chỗ này cố ý nghe `class` của `<html>` bằng MutationObserver chứ không dùng
 * `useTheme()` cho gọn. Lý do: `ThemeProvider` gắn class `.dark` trong một
 * `useEffect`, mà effect của component con luôn chạy **trước** effect của cha.
 * Nếu phụ thuộc vào `theme`, effect đọc màu sẽ chạy lúc class chưa kịp đổi và
 * lấy nguyên bộ màu của theme cũ — chart sẽ trễ đúng một nhịp toggle.
 */
export function useThemeVersion() {
  const [version, setVersion] = React.useState(0)

  React.useEffect(() => {
    const observer = new MutationObserver(() => setVersion((v) => v + 1))
    observer.observe(document.documentElement, { attributes: true, attributeFilter: ["class"] })
    return () => observer.disconnect()
  }, [])

  return version
}
