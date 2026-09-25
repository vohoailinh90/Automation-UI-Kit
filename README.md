# Automation UI Kit

Starter cho **web app nội bộ / công cụ tự động hóa**, gom lại những UI đẹp, miễn phí và mã nguồn mở tốt nhất hiện nay để bạn (hoặc bất kỳ repo nào khác) copy component sang dùng ngay, không phải build từ đầu.

Preview:

| Dashboard | Tasks |
| --- | --- |
| Stat cards + biểu đồ tiến độ | Bảng task với tab lọc theo trạng thái |

| Watchlist | Settings |
| --- | --- |
| Bảng dữ liệu với badge tăng/giảm | Form + toggle cấu hình |

Và ba **dashboard mẫu** (nhóm riêng trong sidebar — xem mục [Dashboard mẫu](#dashboard-mẫu)):

| Automation | Orders | Portfolio |
| --- | --- | --- |
| KPI + tracker trạng thái từng job kiểu status page | Đơn nhiều bước: trễ hạn, đang chờ ai, đúng hạn | Tài sản, phân bổ ngành, bảng nắm giữ |

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

## Dashboard mẫu

Ba trang trong nhóm **"Dashboard mẫu"** là template dựng sẵn cho ba kiểu app nội bộ hay gặp — mở ra xem, thấy hợp thì copy sang repo của bạn:

| Trang | Hợp với | Có gì |
| --- | --- | --- |
| **Automation** (`/automation`) | Job đồng bộ, bot email, script chạy theo lịch | 4 KPI có đường xu hướng · lượt chạy theo ngày (7 / 14 / 30 ngày) · vòng tỉ lệ hoàn tất · **tracker 30 ngày cho từng job** kiểu status page · lỗi thường gặp · lượt chạy gần nhất |
| **Orders** (`/orders`) | Đơn / yêu cầu đi qua nhiều bước và nhiều người giữ | KPI đơn mở / sắp tới hạn / trễ / đúng hạn · phân bố trạng thái · "đang chờ ai" · đơn mới vs đã giao theo tuần · donut theo khách hàng · bảng sắp tới hạn (trễ lên đầu) · thời gian thực hiện so với cam kết |
| **Portfolio** (`/portfolio`) | Dashboard đầu tư, tài chính cá nhân | Tổng tài sản, lãi/lỗ hôm nay và chưa chốt · biểu đồ tài sản (1 tháng / 3 tháng / 90 phiên) tô màu theo chiều · phân bổ theo ngành · bảng nắm giữ dùng chung dữ liệu với Watchlist · đổi quy ước màu |

Cả ba ghép từ các **block tái sử dụng** trong `src/components/dashboard/` — mỗi file tự đứng một mình, chỉ cần `cn()` và token màu:

| Block | Dùng cho | Khác bản gốc ở đâu |
| --- | --- | --- |
| `kpi-card.tsx` | Nhãn, số lớn, badge biến động, vùng xu hướng | Tách **chiều** (mũi tên) khỏi **tốt/xấu** (màu): thời gian chạy giảm là xanh, số lỗi tăng là đỏ; tone `market` tô theo quy ước giá |
| `tracker.tsx` | Dải ô trạng thái theo ngày | Là một `slider` truy cập được: Tab vào, mũi tên / Home / End / PageUp / PageDown để đọc từng ô. Tracker của Tremor chỉ có tooltip khi hover |
| `bar-list.tsx` | "Top N" dạng thanh ngang có nhãn | Danh sách HTML thật, con số là chữ |
| `category-bar.tsx` | Thanh phân đoạn theo tỉ lệ + chú giải có số | Chú giải tự chia cột theo bề rộng **của chính nó** (container query), không theo màn hình |
| `progress-ring.tsx` | Vòng tỉ lệ (hoàn tất, đúng hạn) | Số ở giữa là HTML chứ không phải `<text>` SVG; tắt animation khi người dùng chọn giảm chuyển động |
| `status-badge.tsx` | Trạng thái dạng chấm màu + chữ trung tính | Không phụ thuộc tương phản của chữ màu — vàng cam không bao giờ đạt 4.5:1 khi làm chữ |

Cộng ba primitive mới trong `src/components/ui/`: `chart.tsx` (ChartContainer / Tooltip / Legend của shadcn, bản Recharts 3) và `toggle.tsx` + `toggle-group.tsx` (segmented control chọn khoảng thời gian; Radix dựng sẵn `radiogroup` nên cả nhóm là một điểm dừng Tab).

Dữ liệu cả ba trang là **mẫu, tất định** (`src/lib/mock.ts`: PRNG seed theo chuỗi + ngày neo cố định), và mọi con số trên một trang đều dẫn xuất từ **một** nguồn — một danh sách lượt chạy, một danh sách đơn, một danh mục — nên KPI, biểu đồ, tracker và bảng không bao giờ nói hai chuyện khác nhau. Có sẵn vài sự cố cố ý để dashboard có chuyện để kể: một đêm token Graph hết hạn, hai đơn kẹt mẫu từ nhà cung cấp.

### Màu trạng thái

Token trong `src/index.css` tách **màu chữ** (≥ 4.5:1) khỏi **màu mảng** (≥ 3:1 với nền card, WCAG 1.4.11), cùng cách Primer / Radix Colors làm:

| Token | Dùng làm | Ghi chú |
| --- | --- | --- |
| `--success` | Chữ: badge "Hoàn thành", KPI tốt | Chỉnh từ L 0.6 xuống 0.5 — bản cũ chỉ đạt 3.1:1 trên nền badge |
| `--success-fill` | Mảng: ô tracker, cột biểu đồ, vòng tiến độ | Sáng hơn cho mảng lớn đỡ nặng; 3.7:1 trên card |
| `--warning` | Chỉ làm mảng màu | Vàng cam đủ 4.5:1 làm chữ thì ngả nâu — dùng chấm màu + chữ trung tính |
| `--info` | "Đang xử lý", cả chữ lẫn mảng | 6.1:1 trên card |
| `--destructive` | Chữ + nền | Chỉnh L 0.577 → 0.52: banner lỗi (chữ đỏ trên nền đỏ 10%) từ 4.0:1 lên 5.0:1 |

## Nguồn dashboard đẹp, miễn phí (khảo sát 09/2026)

Khảo sát ngày 25/09/2026, license đọc từ file LICENSE trong repo chứ không từ trang giới thiệu. Kit đã lấy từ hai nguồn đầu; các nguồn còn lại là chỗ nên xem khi cần thêm:

| Nguồn | License | Hợp stack kit? | Nên lấy gì |
| --- | --- | --- | --- |
| [shadcn/ui Blocks & Charts](https://ui.shadcn.com/blocks) | MIT | ✅ Tailwind v4, React 19, Recharts 3 | `chart.tsx` (đã port), block dashboard-01, ~70 mẫu chart |
| [Tremor Raw](https://github.com/tremorlabs/tremor) | Apache-2.0 | ✅ nhưng màu hard-code, phải đổi sang token | Tracker, BarList, CategoryBar, ProgressCircle — kit đã viết lại theo token + a11y. `DonutChart` hỏng với Recharts 3 |
| [Tremor Blocks](https://github.com/tremorlabs/tremor-blocks) | MIT | ⚠️ Tailwind v3 | 325 block (29 KPI card, 10 tracker...) — lấy bố cục làm cảm hứng |
| [Studio Admin](https://github.com/arhamkhnz/next-shadcn-admin-dashboard) | MIT | ✅ Next 16 — bỏ import `next/*` khi port | ~20 trang dashboard đa dạng nhất: finance, CRM, analytics, logistics, kèm theme preset |
| [shadcn-admin](https://github.com/satnaing/shadcn-admin) | MIT | ✅ Vite 8 | App shell, command menu, data-table có filter / thao tác hàng loạt (TanStack v8) |
| [dashboardcn](https://github.com/NoahGdev/dashboardcn) | MIT | ✅ đúng y stack | KPI card, tick bar, segmented meter, heatmap — mới ra 09/2026, nên theo dõi thêm |
| [Evil Charts](https://github.com/legions-developer/evilcharts) | MIT | ✅ cần thêm `motion` | Chart có hiệu ứng, nền tối, hợp màn hình trading |
| [tweakcn](https://github.com/jnsahaj/tweakcn) | Apache-2.0 | ✅ xuất thẳng `@theme inline` oklch | 42 theme preset + editor trực quan (bỏ các preset mang tên thương hiệu) |
| [ReUI](https://github.com/keenthemes/reui) · [Kibo UI](https://github.com/shadcnblocks/kibo) | MIT | ✅ | DataGrid, Gantt, Kanban, contribution graph |
| [Magic UI](https://github.com/magicuidesign/magicui) | MIT | ✅ cần thêm `motion` | NumberTicker, hiệu ứng điểm xuyết |

**Tránh** — license không cho dùng như một kit: bản free của shadcnblocks (MIT + Commons Clause, cấm phân phối lại kể cả dạng đã port), square-ui (license riêng cấm UI kit), bundui (không có file LICENSE, tức là giữ mọi quyền), và repo coss.com ngoài `apps/ui`, `apps/origin` (AGPL-3.0).

## Cấu trúc thư mục

```
src/
  components/
    ui/              # các primitive component kiểu shadcn/ui (copy sang project khác thoải mái)
    dashboard/        # block cho dashboard: kpi-card, tracker, bar-list, category-bar, progress-ring, status-badge
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
    automation.tsx     # dashboard mẫu: job tự động hoá (KPI, tracker từng job, lỗi, lượt chạy)
    orders.tsx         # dashboard mẫu: đơn nhiều bước (trạng thái, đang chờ ai, trễ hạn)
    portfolio.tsx      # dashboard mẫu: danh mục cổ phiếu Nhật (tài sản, phân bổ, nắm giữ)
  hooks/
    use-theme-version.ts # báo cho chart canvas biết lúc nào phải đọc lại màu
  lib/
    utils.ts          # helper `cn()` gộp className, và `createId()` sinh id an toàn
    tasks.ts          # kiểu Task, dữ liệu mẫu, đọc/ghi sessionStorage có validate
    market.ts         # kiểu Instrument, quy ước màu thị trường, format tiền tệ
    candles.ts        # sinh nến OHLC mẫu, tất định theo mã
    mock.ts           # nền của mọi dữ liệu mẫu: PRNG tất định + ngày neo cố định
    automation.ts, orders.ts, portfolio.ts  # dữ liệu mẫu của ba dashboard — đừng copy sang repo khác
    theme-tokens.ts   # đọc token màu CSS ra giá trị sRGB cho canvas
e2e/                   # Playwright test (xem mục "Test end-to-end" bên dưới)
```

Các trang demo đều **tương tác thật** chứ không phải ảnh tĩnh: ô tìm kiếm và tab ở Tasks lọc bảng, nút "Thêm task" mở dialog và thêm dòng mới, Select ở Watchlist lọc theo thị trường, toggle và nút "Lưu thay đổi" ở Settings ghi vào `localStorage`.

Tuy vậy, toàn bộ dữ liệu trong các trang là **dữ liệu mẫu (mock)**, chưa nối backend — không phải dữ liệu thật, không phải lời khuyên đầu tư.

## Hai điều cần biết khi làm UI chứng khoán

Hai thứ này không phải chi tiết nhỏ — làm sai thì UI vẫn chạy, vẫn đẹp, và vẫn sai.

### 1. Đỏ là tăng hay là giảm, tuỳ người xem ở đâu

Âu Mỹ đọc **xanh lá = tăng, đỏ = giảm**. Nhật, Trung Quốc, Hàn Quốc, Đài Loan đọc ngược lại: **đỏ = tăng**. Cùng một badge đỏ, hai nơi hiểu trái nhau hoàn toàn — không phải "hơi khó đọc" mà là đọc sai hẳn chiều.

**Việt Nam đứng về phía Âu Mỹ**, dù ở châu Á: bảng điện HOSE/HNX dùng xanh = tăng, đỏ = giảm, cộng thêm vàng = tham chiếu, tím = trần, xanh lam = sàn (theo hướng dẫn đọc bảng giá của VNDirect, CafeF). Bản trước của README này xếp nhầm Việt Nam vào nhóm đỏ-tăng — port Watchlist sang app chứng khoán Việt với quy ước đó là mọi mã đang tăng hiện màu người Việt đọc là giảm. Nhãn quy ước giờ ghi rõ "Âu Mỹ, VN". Ở nhóm đỏ-tăng, chiều giảm cũng không thống nhất: xanh lá (Rakuten, SBI, Trung Quốc, Đài Loan) hay xanh dương (Hàn Quốc, Daiwa) — kit chọn xanh dương để người mù màu đỏ–lục vẫn tách được hai chiều.

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
| `automation / orders / portfolio.spec.ts` | Ba dashboard mẫu: KPI, biểu đồ, tracker và bảng khớp nhau vì cùng một nguồn; chọn khoảng thời gian bằng chuột lẫn bàn phím; đọc tracker bằng bàn phím; giá danh mục khớp Watchlist; màu lãi/lỗ và vùng biểu đồ theo quy ước + chiều |
| `tracker.spec.ts` | Hợp đồng của `Tracker` với cha khi `blocks` ngắn đi hoặc rỗng lúc đang được đọc: chỉ số cha nghe qua callback luôn là ô slider đang hiện. Chạy trên trang thử `e2e/fixtures/tracker.html` — chỉ dev server phục vụ, không vào bản build |
| `dashboards-a11y.spec.ts` | Quét axe **mọi trang** × 2 theme, cả khổ điện thoại (và Portfolio × 2 quy ước, kể cả lúc hover); tương phản ô tracker và nút đang chọn (axe không đo); không tràn ngang ở 390 / 768 / 1024px; bảng tràn thì Tab tới được vùng cuộn |

Bảng ở Watchlist **bỏ bớt cột theo bề rộng màn hình** (điện thoại chỉ giữ Mã / Giá / %): cuộn ngang được không có nghĩa là dùng được, vì không có gợi ý nào cho thấy còn cột bên phải. Cột tự khai qua `meta.className`, nên bảng không cần biết trước cột nào quan trọng.

Toàn bộ test mới đều được kiểm bằng **mutation test**: đảo lại đúng đoạn code tương ứng rồi xác nhận test chuyển đỏ — 43/43 mutation bị bắt. Lần chạy đầu có **một con lọt lưới**: đổi cách sắp cột Giá về so số thô mà test vẫn xanh, vì lúc đó mọi giá ¥ đều lớn hơn mọi giá $ nên so thô cũng vô tình ra hai khối sạch. Đã thêm một mã Nhật giá ba chữ số để bộ dữ liệu thật sự có ca đan xen, và cho test **tự khẳng định tiền đề của nó** để ai đổi dữ liệu mẫu sẽ thấy test mất hiệu lực thay vì âm thầm.

Đợt dashboard mẫu: **24/24 mutation bị bắt**. Con lọt lưới lúc đầu nằm ở chính test "không tràn ngang": test đo `<html>`, nhưng `<main>` có `overflow-y-auto` nên chiều ngang của nó cũng thành `auto` — `<main>` mới là thứ cuộn ngang, card bị cắt mất nửa bên phải mà test vẫn xanh. Giờ test đo cả `<main>`, ở ba khổ màn hình, và có thêm một test cố ý bơm bảng rộng 1400px để kiểm lớp `*:min-w-0` — thứ dữ liệu mẫu hiện tại không đủ rộng để tự làm lộ.

Hai lần sửa `Tracker` sau review: 5/5 và 9/9 mutation bị bắt. Con lọt lưới ở lần sau: chỉ báo cha `null` mà không xoá chỉ số hover đã lưu — không thấy gì cho tới khi dải dài lại, lúc đó ô cũ tự sáng lên dù chuột chưa hề động. Test giờ có thêm đúng bước đó.

Quét axe mọi trang cũng làm lộ ba lỗi tương phản **có sẵn** ở token/primitive dùng chung — đúng những thứ dashboard mẫu copy đi — nên đã sửa tận gốc: chữ `--success` trên nền badge (3.1:1), tab chưa chọn (4.34:1, theo cách upstream shadcn v4 đã sửa), badge "Trễ hạn" ở dark mode (2.9:1). Primitive `Table` giờ tự nhận Tab khi bảng tràn ngang (axe `scrollable-region-focusable`) — bảng Tasks trên điện thoại trước đây không cuộn được bằng bàn phím.

Hai file `*-storage` là **regression test**: mỗi ca trong đó tương ứng một lỗi có thật đã từng lọt qua review — mất dữ liệu khi storage đọc hỏng rồi hồi phục, switch hiện sai vì `"false"` là chuỗi truthy, task biến mất khi đổi route. Chúng vá `Storage.prototype` để dựng lại tình huống trình duyệt chặn storage; phần đó gom hết trong `e2e/helpers.ts`.

## Dùng lại UI ở repo khác

Vì đây là repo công khai, bạn có thể:

1. Copy nguyên thư mục `src/components/ui/` + `src/lib/utils.ts` sang project React + Tailwind v4 khác.
2. Cài đúng các package Radix tương ứng (xem `package.json`) và `class-variance-authority`, `clsx`, `tailwind-merge`, `lucide-react`.
3. Dán `src/index.css` (phần theme token) vào file CSS gốc của project để có đúng màu sắc/dark mode.
4. Dashboard: copy `src/components/dashboard/*` + `src/components/ui/chart.tsx` (và `toggle.tsx`, `toggle-group.tsx` nếu cần chọn khoảng thời gian, cài `@radix-ui/react-toggle-group`), cùng các token `--success`, `--success-fill`, `--warning`, `--info`, `--destructive`. **Đừng** copy `src/lib/{mock,automation,orders,portfolio}.ts` — đó là dữ liệu mẫu; mỗi trang chỉ gọi vài hàm tổng hợp, thay chúng bằng hàm đọc dữ liệu thật của repo đích. Mang theo `THIRD_PARTY_NOTICES.md` (license của shadcn/ui cho các file đã chép).

### Repo không phải React

Repo khác stack thì port **thiết kế** — token, bố cục, spec component — chứ không ép đổi stack. Mã hex của các token chính, cho những nơi không đọc được CSS variable (Plotly, ttkbootstrap, Excel):

| Token | Light | Dark |
| --- | --- | --- |
| `--background` / `--card` | `#ffffff` / `#ffffff` | `#0a0a0a` / `#171717` |
| `--foreground` | `#0a0a0a` | `#fafafa` |
| `--muted-foreground` | `#737373` | `#a1a1a1` |
| `--border` | `#e5e5e5` | trắng 10% |
| `--success` (chữ) | `#007651` | `#35bf8b` |
| `--success-fill` (mảng) | `#009869` | `#35bf8b` |
| `--warning` (mảng) | `#d76900` | `#fcab00` |
| `--info` | `#0060c1` | `#59a0f9` |
| `--destructive` | `#c9000c` | `#ff6467` |
| `--market-green` / `--market-red` / `--market-blue` | `#007327` / `#c50516` / `#0060c1` | `#44c166` / `#ff6367` / `#59a0f9` |

- **FastAPI / Flask + Jinja (HTML thuần)**: chép token vào CSS gốc — nhớ bốn token mới/đã chỉnh ở mục [Màu trạng thái](#màu-trạng-thái). KPI card, BarList, CategoryBar, StatusBadge chỉ là HTML + CSS; riêng tracker thì giữ `role="slider"` + `aria-valuetext` và vài dòng JS cho phím mũi tên.
- **Streamlit + Plotly**: dùng hex ở bảng trên cho theme và cho Plotly (`increasing_line_color`, `decreasing_line_color`...). App chứng khoán **Việt Nam** dùng quy ước `western`: xanh tăng, đỏ giảm.
- **Tkinter / ttkbootstrap**: dựng theme từ bảng hex; `Meter` và `Floodgauge` của ttkbootstrap là bản tương đương của ProgressRing và thanh tiến độ.

Không cần fork toàn bộ repo — mỗi component là một file độc lập, không phụ thuộc chéo ngoài `cn()` trong `lib/utils.ts`.

Repo cũng có sẵn `components.json` (style `new-york`, alias `@/*`), nên nếu môi trường của bạn vào được `ui.shadcn.com` thì `npx shadcn@latest add <component>` sẽ thêm component mới đúng convention vào `src/components/ui/`.

## License

MIT — dùng, sửa, phân phối lại tự do. Xem [LICENSE](./LICENSE).
