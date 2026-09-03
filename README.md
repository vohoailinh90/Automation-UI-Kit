# Automation UI Kit

Starter cho **web app nội bộ / công cụ tự động hóa**, gom lại những UI đẹp, miễn phí và mã nguồn mở tốt nhất hiện nay để bạn (hoặc bất kỳ repo nào khác) copy component sang dùng ngay, không phải build từ đầu.

Preview:

| Dashboard | Tasks |
| --- | --- |
| Stat cards + biểu đồ tiến độ | Bảng task với tab lọc theo trạng thái |

| Watchlist | Settings |
| --- | --- |
| Bảng dữ liệu với badge tăng/giảm | Form + toggle cấu hình |

## Vì sao chọn stack này

Đây là các thư viện UI miễn phí, MIT license, đang được cộng đồng React dùng nhiều nhất năm 2026, chọn theo tiêu chí: **đẹp sẵn, copy-paste được, không khoá vendor**:

- **[shadcn/ui](https://ui.shadcn.com/)** — không phải một component library đóng gói, mà là các component (Button, Card, Table, Dialog, Sheet, Tabs, Select, Dropdown Menu, Avatar, Badge...) dựng trên [Radix UI](https://www.radix-ui.com/) + [Tailwind CSS](https://tailwindcss.com/) + [class-variance-authority](https://cva.style/), copy thẳng mã nguồn vào repo của bạn nên toàn quyền chỉnh sửa. Các file trong `src/components/ui/*.tsx` được viết theo đúng convention "new-york style" của shadcn.
- **[Tailwind CSS v4](https://tailwindcss.com/)** — theming bằng CSS variables (`src/index.css`), hỗ trợ dark mode qua class `.dark`, không cần file config riêng.
- **[Recharts](https://recharts.org/)** — chart nhẹ, dễ style theo theme, dùng cho biểu đồ tiến độ dự án ở Dashboard.
- **[lucide-react](https://lucide.dev/)** — icon set miễn phí, cùng hệ với shadcn.
- **React Router** — routing phía client, tách layout (sidebar + topbar) khỏi từng trang.

> Ghi chú: `npx shadcn@latest add ...` cần gọi tới `ui.shadcn.com`. Nếu môi trường của bạn chặn domain đó (proxy công ty, sandbox CI...), các component trong `src/components/ui/` ở đây đã được viết sẵn thủ công theo đúng API/behaviour của shadcn nên bạn không cần chạy CLI — cứ copy thư mục `src/components/ui` sang project khác là dùng được.

## Cấu trúc thư mục

```
src/
  components/
    ui/              # các primitive component kiểu shadcn/ui (copy sang project khác thoải mái)
    layout/           # AppLayout, sidebar nav, danh sách menu
    theme-provider.tsx, theme-toggle.tsx
    stat-card.tsx     # card thống kê dùng ở Dashboard
  pages/
    dashboard.tsx     # stat cards + chart tiến độ + milestone sắp tới
    tasks.tsx         # bảng task/milestone, filter theo tab + tìm kiếm
    watchlist.tsx      # bảng theo dõi chứng khoán mẫu (JP + US)
    settings.tsx       # form thông tin cá nhân + cấu hình
  lib/utils.ts         # helper `cn()` gộp className (clsx + tailwind-merge)
```

Toàn bộ dữ liệu trong các trang là **dữ liệu mẫu (mock)** để minh hoạ UI — không phải dữ liệu thật, không phải lời khuyên đầu tư.

## Bắt đầu

```bash
npm install
npm run dev      # http://localhost:5173
npm run build    # build production vào dist/
npm run lint      # oxlint
```

Yêu cầu Node.js 20+.

## Dùng lại UI ở repo khác

Vì đây là repo công khai, bạn có thể:

1. Copy nguyên thư mục `src/components/ui/` + `src/lib/utils.ts` sang project React + Tailwind v4 khác.
2. Cài đúng các package Radix tương ứng (xem `package.json`) và `class-variance-authority`, `clsx`, `tailwind-merge`, `lucide-react`.
3. Dán `src/index.css` (phần theme token) vào file CSS gốc của project để có đúng màu sắc/dark mode.

Không cần fork toàn bộ repo — mỗi component là một file độc lập, không phụ thuộc chéo ngoài `cn()` trong `lib/utils.ts`.

## License

MIT — dùng, sửa, phân phối lại tự do. Xem [LICENSE](./LICENSE).
