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

- **[shadcn/ui](https://ui.shadcn.com/)** — không phải một component library đóng gói, mà là các component (Button, Card, Table, Dialog, Sheet, Tabs, Select, Switch, Dropdown Menu, Avatar, Badge...) dựng trên [Radix UI](https://www.radix-ui.com/) + [Tailwind CSS](https://tailwindcss.com/) + [class-variance-authority](https://cva.style/), copy thẳng mã nguồn vào repo của bạn nên toàn quyền chỉnh sửa. Các file trong `src/components/ui/*.tsx` được viết theo đúng convention "new-york style" của shadcn.
- **[Tailwind CSS v4](https://tailwindcss.com/)** — theming bằng CSS variables (`src/index.css`), hỗ trợ dark mode qua class `.dark`, không cần file config riêng.
- **[Recharts](https://recharts.org/)** — chart nhẹ, dễ style theo theme, dùng cho biểu đồ tiến độ dự án ở Dashboard. Màu chart lấy từ token `--chart-1`/`--chart-2` nên tự đổi theo light/dark mode.
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
    tasks-provider.tsx  # state task, đặt trên <Routes> nên đổi trang không mất
    stat-card.tsx     # card thống kê dùng ở Dashboard
  pages/
    dashboard.tsx     # stat cards + chart tiến độ (có legend) + milestone sắp tới
    tasks.tsx         # bảng task/milestone, filter theo tab + tìm kiếm + dialog thêm task
    watchlist.tsx      # bảng theo dõi chứng khoán mẫu, lọc theo thị trường (JP / US)
    settings.tsx       # form thông tin cá nhân + toggle cấu hình, lưu vào localStorage
  lib/
    utils.ts          # helper `cn()` gộp className, và `createId()` sinh id an toàn
    tasks.ts          # kiểu Task, dữ liệu mẫu, đọc/ghi sessionStorage có validate
e2e/                   # Playwright test (xem mục "Test end-to-end" bên dưới)
```

Các trang demo đều **tương tác thật** chứ không phải ảnh tĩnh: ô tìm kiếm và tab ở Tasks lọc bảng, nút "Thêm task" mở dialog và thêm dòng mới, Select ở Watchlist lọc theo thị trường, toggle và nút "Lưu thay đổi" ở Settings ghi vào `localStorage`.

Tuy vậy, toàn bộ dữ liệu trong các trang là **dữ liệu mẫu (mock)**, chưa nối backend — không phải dữ liệu thật, không phải lời khuyên đầu tư.

## Bắt đầu

```bash
npm install
npm run dev        # http://localhost:5173
npm run build      # typecheck + build production vào dist/
npm run lint       # oxlint
npm run typecheck  # tsc -b (strict mode)
npm run test:e2e   # Playwright (tự khởi động dev server)
```

Yêu cầu Node.js 20+. TypeScript chạy ở chế độ `strict`, và GitHub Actions (`.github/workflows/ci.yml`) chạy lint + typecheck + build + e2e cho mỗi push/PR.

Lần đầu chạy e2e cần tải browser: `npx playwright install chromium`. Nếu máy/CI của bạn đã có sẵn Chromium và chặn tải, trỏ `PLAYWRIGHT_CHROMIUM_PATH` vào binary đó.

### Test end-to-end

`e2e/` chứa Playwright test chạy trên trình duyệt thật, chia theo mối quan tâm:

| File | Phủ cái gì |
| --- | --- |
| `watchlist / tasks / settings / dashboard / layout.spec.ts` | Luồng chính từng trang |
| `a11y.spec.ts` | Tên truy cập được, thao tác bàn phím, bẫy focus của dialog, vùng `aria-live` |
| `settings-storage.spec.ts` | Tách draft khỏi bản đã lưu, ghi/đọc storage thất bại, dữ liệu sai schema |
| `tasks-storage.spec.ts` | Task sống qua điều hướng, không ghi đè khi đọc hỏng, entry lưu bị hỏng |
| `crypto-fallback.spec.ts` | Thêm task được khi thiếu `crypto.randomUUID` (mở qua `http://<LAN-IP>`) |

Hai file `*-storage` là **regression test**: mỗi ca trong đó tương ứng một lỗi có thật đã từng lọt qua review — mất dữ liệu khi storage đọc hỏng rồi hồi phục, switch hiện sai vì `"false"` là chuỗi truthy, task biến mất khi đổi route. Chúng vá `Storage.prototype` để dựng lại tình huống trình duyệt chặn storage; phần đó gom hết trong `e2e/helpers.ts`.

## Dùng lại UI ở repo khác

Vì đây là repo công khai, bạn có thể:

1. Copy nguyên thư mục `src/components/ui/` + `src/lib/utils.ts` sang project React + Tailwind v4 khác.
2. Cài đúng các package Radix tương ứng (xem `package.json`) và `class-variance-authority`, `clsx`, `tailwind-merge`, `lucide-react`.
3. Dán `src/index.css` (phần theme token) vào file CSS gốc của project để có đúng màu sắc/dark mode.

Không cần fork toàn bộ repo — mỗi component là một file độc lập, không phụ thuộc chéo ngoài `cn()` trong `lib/utils.ts`.

Repo cũng có sẵn `components.json` (style `new-york`, alias `@/*`), nên nếu môi trường của bạn vào được `ui.shadcn.com` thì `npx shadcn@latest add <component>` sẽ thêm component mới đúng convention vào `src/components/ui/`.

## License

MIT — dùng, sửa, phân phối lại tự do. Xem [LICENSE](./LICENSE).
