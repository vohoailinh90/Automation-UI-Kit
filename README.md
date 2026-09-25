# Automation UI Kit

Starter cho **web app nội bộ / công cụ tự động hóa**, gom lại những UI đẹp, miễn phí và mã nguồn mở tốt nhất hiện nay để bạn (hoặc bất kỳ repo nào khác) copy component sang dùng ngay, không phải build từ đầu.

> **Làm app iPhone?** Xem [`ios/`](ios/README.md): bộ giao diện SwiftUI (iOS 17+, Liquid Glass trên iOS 26+) kèm khảo sát giao diện iOS đẹp nhất 2026, dựng cho các app của `app-idea-lab`.

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

Và ba thư viện nữa dành riêng cho **UI chứng khoán**, đều miễn phí và mã nguồn mở:

- **[TradingView Lightweight Charts](https://github.com/tradingview/lightweight-charts)** (Apache-2.0) — chart nến + khối lượng, chính thư viện TradingView mở mã. Chỉ ~50 kB gzip mà đủ crosshair, time scale, nhiều price scale. Logo TradingView trên chart được **giữ nguyên** làm ghi công cho họ.
- **[TanStack Table v9](https://github.com/TanStack/table)** (MIT) — bảng headless: lo phần sắp xếp/lọc, còn markup thì vẫn là component `Table` của shadcn trong repo này. v9 bắt khai báo rõ từng feature nên bảng chỉ sắp xếp sẽ không kéo theo mã của phân trang hay gom nhóm.
- **[cmdk](https://github.com/pacocoursey/cmdk)** (MIT) — bảng lệnh ⌘K, dùng làm ô tìm mã chứng khoán. Chính là thư viện chạy dưới component Command của shadcn.

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
    data-table.tsx    # bảng sắp xếp được (TanStack Table v9) dựng trên <Table> của shadcn
    price-chart.tsx   # chart nến + khối lượng (Lightweight Charts), kèm readout O/H/L/C
    price-change.tsx  # badge % biến động, ăn theo quy ước màu thị trường
    sparkline.tsx     # đường xu hướng thu nhỏ, SVG thuần
    ticker-search.tsx # tìm mã kiểu ⌘K
  pages/
    dashboard.tsx     # stat cards + chart tiến độ (có legend) + milestone sắp tới
    tasks.tsx         # bảng task/milestone, filter theo tab + tìm kiếm + dialog thêm task
    watchlist.tsx      # watchlist chứng khoán: bảng sắp xếp + chart nến + tìm mã ⌘K
    settings.tsx       # form thông tin cá nhân + toggle cấu hình, lưu vào localStorage
  hooks/
    use-theme-version.ts # báo cho chart canvas biết lúc nào phải đọc lại màu
  lib/
    utils.ts          # helper `cn()` gộp className, và `createId()` sinh id an toàn
    tasks.ts          # kiểu Task, dữ liệu mẫu, đọc/ghi sessionStorage có validate
    market.ts         # kiểu Instrument, quy ước màu thị trường, format tiền tệ
    candles.ts        # sinh nến OHLC mẫu, tất định theo mã
    theme-tokens.ts   # đọc token màu CSS ra giá trị sRGB cho canvas
e2e/                   # Playwright test (xem mục "Test end-to-end" bên dưới)
```

Các trang demo đều **tương tác thật** chứ không phải ảnh tĩnh: ô tìm kiếm và tab ở Tasks lọc bảng, nút "Thêm task" mở dialog và thêm dòng mới, Select ở Watchlist lọc theo thị trường, toggle và nút "Lưu thay đổi" ở Settings ghi vào `localStorage`.

Tuy vậy, toàn bộ dữ liệu trong các trang là **dữ liệu mẫu (mock)**, chưa nối backend — không phải dữ liệu thật, không phải lời khuyên đầu tư.

## Hai điều cần biết khi làm UI chứng khoán

Hai thứ này không phải chi tiết nhỏ — làm sai thì UI vẫn chạy, vẫn đẹp, và vẫn sai.

### 1. Đỏ là tăng hay là giảm, tuỳ người xem ở đâu

Âu Mỹ đọc **xanh lá = tăng, đỏ = giảm**. Nhật, Việt Nam, Trung Quốc, Hàn Quốc, Đài Loan đọc ngược lại: **đỏ = tăng, xanh dương = giảm**. Cùng một badge đỏ, hai nơi hiểu trái nhau hoàn toàn — không phải "hơi khó đọc" mà là đọc sai hẳn chiều.

Nên trong repo này **không component nào tự chọn xanh hay đỏ**. Tất cả đi qua hai biến `--price-rise` / `--price-fall`, và chỉ một khối trong `src/index.css` quyết định hai biến đó là màu gì, theo thuộc tính `data-price-convention`:

```tsx
<div data-price-convention="east-asian">  {/* hoặc "western" */}
  <PriceChange value={1.42} />            {/* badge tự ăn theo */}
</div>
```

Chart canvas cũng đọc đúng hai biến đó, nên đổi quy ước là cả bảng lẫn chart đổi cùng lúc. Trang Watchlist để nó ở state của trang; muốn áp cho cả app thì nâng lên một provider hoặc gắn thẳng thuộc tính lên `<html>`.

Quy ước cố ý đặt ở **cấp cả bảng chứ không theo từng mã**: một cột badge mà dòng Nhật hiểu kiểu này, dòng Mỹ hiểu kiểu kia thì còn khó đọc hơn là chọn hẳn một bên.

Chiều tăng/giảm còn được viết thành **chữ** trong `sr-only`, vì người dùng screen reader không "nghe" được màu — mà ở quy ước Đông Á thì suy nghĩa từ màu sẽ ra ngược.

Ba màu thị trường vừa tô nến vừa làm **màu chữ** của badge, nên ở light mode độ sáng của chúng bị chặn bởi yêu cầu tương phản chữ (≥ 4.5:1), chứ không phải bởi đồ hoạ. Xanh lá là màu khó nhất: bản sáng hơn một chút chỉ đạt 3.4:1. Ca tệ nhất là badge trên dòng đang **hover hoặc đang chọn** — nền xám nhạt kéo tương phản xuống, và axe chỉ thấy được khi con trỏ thật sự nằm trên dòng, nên `e2e/watchlist-a11y.spec.ts` quét cả lúc hover.

### 2. Chart canvas không đọc được `var(--token)`

Chart ở Dashboard vẽ bằng SVG (Recharts) nên truyền thẳng `var(--chart-1)` là chạy. Chart giá vẽ bằng **canvas**, mà canvas không có DOM để resolve `var()`.

Tệ hơn: token trong repo này viết bằng `oklch()`, và Chromium **nhận** `oklch()` trong `fillStyle` rồi đọc lại vẫn trả về nguyên chuỗi — nên kiểu kiểm tra "gán rồi đọc lại xem có đổi không" không phát hiện được gì, và chuỗi oklch sẽ rơi xuống parser màu riêng của thư viện chart rồi ném `Failed to parse color`.

`src/lib/theme-tokens.ts` xử lý bằng cách **tô thật một điểm ảnh rồi đọc byte màu ra**, nên vào cú pháp CSS nào cũng ra sRGB cụ thể. Và vì canvas không tự biết theme đã đổi, `useThemeVersion()` nghe `class` của `<html>` qua MutationObserver — cố ý không dùng `useTheme()`, vì effect của component con luôn chạy *trước* effect của cha nên sẽ đọc trúng bộ màu của theme cũ.

Cũng vì canvas không assert được, số liệu nến đang trỏ được render ra **HTML thật** ở dưới chart: vừa là thứ người dùng cần (bảng O/H/L/C như mọi app chứng khoán), vừa là bề mặt để test kiểm chứng được.


## Bắt đầu

```bash
npm install
npm run dev        # http://localhost:5173
npm run build      # typecheck + build production vào dist/
npm run lint       # oxlint
npm run typecheck  # tsc -b (strict mode)
npm run test:e2e   # Playwright (tự khởi động dev server)
```

Yêu cầu Node.js 20+. TypeScript chạy ở chế độ `strict`, và GitHub Actions (`.github/workflows/ci.yml`) chạy lint + typecheck + build + e2e cho mỗi PR và mỗi push lên `main`.

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
| `price-convention.spec.ts` | Quy ước màu tăng/giảm, và chữ mô tả chiều không đảo theo màu |
| `market-table.spec.ts` | Sắp xếp, `aria-sort`, và giá không so lẫn giữa hai đơn vị tiền |
| `price-chart.spec.ts` | Chart đọc lại màu khi đổi theme/quy ước, nến tăng/giảm đúng màu, readout khớp bảng giá |
| `ticker-search.spec.ts` | ⌘K, tìm theo tên công ty, trả focus về nút khi đóng, chọn mã ngoài bộ lọc |
| `watchlist-a11y.spec.ts` | Quét axe ở cả 4 tổ hợp theme × quy ước, kể cả lúc hover; tương phản vòng focus (axe không đo); chọn dòng bằng bàn phím |

Bảng ở Watchlist **bỏ bớt cột theo bề rộng màn hình** (điện thoại chỉ giữ Mã / Giá / %): cuộn ngang được không có nghĩa là dùng được, vì không có gợi ý nào cho thấy còn cột bên phải. Cột tự khai qua `meta.className`, nên bảng không cần biết trước cột nào quan trọng.

Toàn bộ test mới đều được kiểm bằng **mutation test**: đảo lại đúng đoạn code tương ứng rồi xác nhận test chuyển đỏ — 43/43 mutation bị bắt. Lần chạy đầu có **một con lọt lưới**: đổi cách sắp cột Giá về so số thô mà test vẫn xanh, vì lúc đó mọi giá ¥ đều lớn hơn mọi giá $ nên so thô cũng vô tình ra hai khối sạch. Đã thêm một mã Nhật giá ba chữ số để bộ dữ liệu thật sự có ca đan xen, và cho test **tự khẳng định tiền đề của nó** để ai đổi dữ liệu mẫu sẽ thấy test mất hiệu lực thay vì âm thầm.

Hai file `*-storage` là **regression test**: mỗi ca trong đó tương ứng một lỗi có thật đã từng lọt qua review — mất dữ liệu khi storage đọc hỏng rồi hồi phục, switch hiện sai vì `"false"` là chuỗi truthy, task biến mất khi đổi route. Chúng vá `Storage.prototype` để dựng lại tình huống trình duyệt chặn storage; phần đó gom hết trong `e2e/helpers.ts`.

## Dùng lại UI ở repo khác

Vì đây là repo công khai, bạn có thể:

1. Copy nguyên thư mục `src/components/ui/` + `src/lib/utils.ts` sang project React + Tailwind v4 khác.
2. Cài đúng các package Radix tương ứng (xem `package.json`) và `class-variance-authority`, `clsx`, `tailwind-merge`, `lucide-react`.
3. Dán `src/index.css` (phần theme token) vào file CSS gốc của project để có đúng màu sắc/dark mode.

Không cần fork toàn bộ repo — mỗi component là một file độc lập, không phụ thuộc chéo ngoài `cn()` trong `lib/utils.ts`.

Repo cũng có sẵn `components.json` (style `new-york`, alias `@/*`), nên nếu môi trường của bạn vào được `ui.shadcn.com` thì `npx shadcn@latest add <component>` sẽ thêm component mới đúng convention vào `src/components/ui/`.

App iOS thì chép `ios/IdeaLabKit/` — hướng dẫn ở [ios/README.md](ios/README.md#3-dùng-trong-app-idea-lab).

## License

MIT — dùng, sửa, phân phối lại tự do. Xem [LICENSE](./LICENSE).
