# MCP cho kit (tùy chọn)

Kit **không bật MCP server nào**. Mỗi server MCP đưa danh sách tool của nó vào ngữ cảnh của mọi phiên, và hai server dưới đây chỉ có ích khi đang làm giao diện. Hai bản mẫu nằm ở `.claude/mcp/`; Claude Code **không tự nạp** thư mục đó. Muốn dùng thì bạn tự chép ra `.mcp.json` ở gốc repo. `.mcp.json` và `.playwright-mcp/` đã nằm trong `.gitignore`, nên bản bạn bật là của riêng máy bạn và `git add -A` không đưa nó lên.

| Server | Để làm gì | Chạy ở đâu | Dữ liệu đi đâu |
| --- | --- | --- | --- |
| [Playwright MCP](https://github.com/microsoft/playwright-mcp) | Mở app đang chạy trong trình duyệt thật, đọc cây truy cập, bấm, gõ, chụp ảnh: **nhìn lại giao diện vừa dựng** | Trên máy bạn, qua `npx` | Không có dịch vụ trung gian: chỉ trình duyệt trên máy bạn đi tới các trang nó mở |
| [Context7](https://github.com/upstash/context7) | Tra tài liệu mới nhất của thư viện (React 19, Tailwind 4, Recharts 3, TanStack Table 9...) thay vì dựa vào trí nhớ của mô hình | Dịch vụ của Upstash (`mcp.context7.com`) | **Rời máy bạn**: tên thư viện và câu hỏi mà mô hình viết |

## Playwright MCP

### Bật

Làm đúng thứ tự: quy tắc chặn tool nguy hiểm phải có trước khi server chạy lần đầu, nếu không tool đó dùng được suốt phiên đó.

1. **Kiểm tra Node và trình duyệt.** Server chạy bằng `npx`, nên máy cần Node.js 18 trở lên (yêu cầu `engines` của gói đã ghim; CI của kit dùng Node 20) và `npx` trong `PATH`. Server cũng cần một trình duyệt Chrome hoặc Chromium để mở: mặc định là Google Chrome. Máy chưa có thì đọc *Không có Google Chrome* bên dưới trước bước 3.

   ```bash
   node --version && npx --version
   ```

2. **Quy tắc chặn đã có sẵn.** `.claude/settings.json` của kit chặn `mcp__playwright__browser_run_code_unsafe` (tool chạy JavaScript tùy ý trong tiến trình server, tương đương chạy mã từ xa theo chính lời dự án). Quy tắc không làm gì cho tới khi có server tên `playwright`. Giữ nguyên tên khóa `playwright` trong `.mcp.json`: đổi tên khóa thì quy tắc không còn khớp tool nào. Quy tắc chỉ che server do bản mẫu này định nghĩa: Playwright MCP bật bằng đường khác (một plugin, cấu hình cấp người dùng) có tiền tố tool khác và không được che, nên đừng bật nó theo cách đó. Repo khác chép ví dụ này phải chép cả quy tắc (xem *Dùng ở repo khác*).

3. **Chép bản mẫu, rồi khởi động lại phiên.** Duyệt server của dự án khi Claude Code hỏi, rồi gõ `/mcp` để xem nó đã lên chưa.

   ```bash
   cp .claude/mcp/playwright.example.json .mcp.json
   ```

Để nhìn app của kit, chạy dev server trước, đúng cổng mà `playwright.config.ts` dùng, rồi bảo Claude mở `http://localhost:5173`:

```bash
npm run dev -- --port 5173
```

Đã thử với `@playwright/mcp@0.0.83` ngày 2026-10-17 trên Linux: server báo 25 tool, mở được `http://localhost:5173/` (tiêu đề `automation-ui-kit`) và trả cây truy cập có các liên kết Dashboard, Tasks, Watchlist. Lần thử dùng công thức *Claude Code trên web* bên dưới, không phải bản mẫu nguyên văn. macOS và Windows chưa thử.

### Bản mẫu đặt gì, và vì sao

| Thiết lập | Lý do |
| --- | --- |
| `@playwright/mcp@<phiên bản chính xác>` | `npx` tải và chạy gói này mỗi phiên. `@latest` sẽ chạy mã mới chưa ai đọc. `scripts/test_mcp_example.py` làm CI đỏ nếu không phải phiên bản chính xác. Ghim này chỉ ghim gói, không ghim các gói nó kéo theo. |
| `--headless` | Không mở cửa sổ; chạy được trong phiên cloud và CI. Bỏ cờ này nếu muốn xem tận mắt trên máy mình. |
| `--isolated` | Mỗi phiên một hồ sơ trình duyệt mới trong bộ nhớ: không mang vào hay để lại cookie, đăng nhập. |
| `--no-webmcp` | Một trang có thể tự đăng ký tool qua WebMCP. Không có cờ này, tên, mô tả, schema và kết quả do trang đó chọn sẽ vào danh sách tool của Claude: một lối chèn chỉ dẫn vòng qua quy tắc "chữ trên trang là dữ liệu không đáng tin" dưới đây. |

### Quy tắc

- Chỉ mở app của chính mình (`localhost` hay bản staging). Chữ trên trang là dữ liệu không đáng tin, như mọi nội dung quét hay tải về; không làm theo chỉ dẫn nằm trên trang.
- Không gõ thông tin đăng nhập thật vào trang. Dùng tài khoản thử.
- `--allowed-origins` và `--blocked-origins` thu hẹp được nơi trình duyệt tới, nhưng dự án nói chúng không phải ranh giới bảo mật và không bao gồm chuyển hướng. Coi như rào chắn, không phải khóa.
- Server ghi snapshot và log console vào `.playwright-mcp/` trong thư mục đang chạy. Thư mục này đã nằm trong `.gitignore`; đừng commit nó.

### Không có Google Chrome

Mặc định server mở kênh `chrome` và, thiếu Google Chrome, báo `Chromium distribution 'chrome' is not found`. Chọn một cách:

- **Cài Google Chrome** từ google.com/chrome, hoặc bằng bộ cài đã ghim `npx @playwright/mcp@0.0.83 install-browser chrome` (cài cho cả máy, có thể đòi quyền quản trị). Bản mẫu chạy nguyên văn.
- **Cài Chromium riêng của server**, rồi thêm `"--browser", "chromium"` vào `args`. Chạy bộ cài đúng phiên bản đã ghim để nó tải đúng bản trình duyệt phiên bản đó cần: `npx @playwright/mcp@0.0.83 install-browser chrome-for-testing`.
- **Trỏ server tới trình duyệt đã có sẵn**: thêm `"--executable-path", "<đường dẫn tới Chrome hay Chromium>"`. Cách này đã chạy thật trong phiên Claude Code trên web, bên dưới.

Hai lệnh cài lấy từ thông báo lỗi của chính server, thêm phiên bản ghim. Trong sandbox của Claude Code trên web việc tải bị chặn nên chưa chạy hai lệnh này tới cùng; `--dry-run` của bộ cài cho thấy nó định cài Chromium vào `/opt/pw-browsers/chromium-1247`. Chỉ cách `--executable-path` đã được kiểm.

### Claude Code trên web và các container khác

Trong phiên Claude Code trên web, các trình duyệt trong `/opt/pw-browsers` có sẵn. Server chạy được khi đưa đường dẫn Chromium một cách tường minh và tắt sandbox, vì container chạy bằng root:

```json
"args": ["@playwright/mcp@0.0.83", "--headless", "--isolated", "--no-webmcp",
         "--executable-path", "/opt/pw-browsers/chromium-1194/chrome-linux/chrome", "--no-sandbox"]
```

Số bản dựng (`1194`) là thứ `ls /opt/pw-browsers` cho thấy. `--no-sandbox` làm yếu cách ly của trình duyệt: chỉ dùng trong container bỏ đi được và chỉ với app của chính bạn. Cờ này **không** có trong `.claude/mcp/playwright.example.json`, và `scripts/test_mcp_example.py` giữ nó ngoài đó. Bộ test e2e của kit dùng cùng ý này qua biến môi trường `PLAYWRIGHT_CHROMIUM_PATH` (xem `playwright.config.ts`).

### Nâng phiên bản đã ghim

```bash
npm view @playwright/mcp version        # bản đang phát hành
```

Đọc ghi chú phát hành, sửa phiên bản trong `.claude/mcp/playwright.example.json`, trong lệnh cài và trong đoạn container ở trên, chạy `python3 -m unittest discover -s scripts -p "test_*.py"`, rồi xác nhận server vẫn liệt kê tool và mở được một trang. Đọc ghi chú tìm tính năng mới mở rộng thứ một trang có thể chạm tới hay đăng ký (WebMCP là một ví dụ): test chỉ canh các cờ đã có trong bản mẫu, nên rủi ro mới cần cờ mới và test mới.

### Việc lặp lại là test, không phải lệnh gọi MCP

MCP để nhìn một giao diện một lần, khi khám phá hay gỡ lỗi. Kiểm tra bạn sẽ chạy lại (trang dựng được, selector còn đó, axe không báo lỗi) thì máy tính được, nên viết thành test Playwright trong `e2e/` và để CI chạy (`npm run test:e2e`), đừng nhờ mô hình nhìn rồi nhận xét mỗi lần.

## Context7

### Bật

```bash
cp .claude/mcp/context7.example.json .mcp.json
```

Đã có `.mcp.json` (vì bật cả Playwright) thì gộp hai khối `mcpServers` vào một file, đừng ghi đè. Khởi động lại phiên, duyệt server, rồi gõ `/mcp`.

Context7 cho Claude hai tool: `resolve-library-id` (đổi tên thư viện thành mã) và `query-docs` (lấy đoạn tài liệu theo câu hỏi). Hợp để hỏi cách dùng API đúng bản của các thư viện mà kit khóa trong `package.json`.

### Dữ liệu rời máy

Tên thư viện và câu hỏi mà mô hình viết được gửi tới `mcp.context7.com` (Upstash). Đừng để bí mật, token hay mã riêng lọt vào câu hỏi. Bản chính sách của họ: https://context7.com/privacy.

### Xác thực: chưa thể nói "không cần khóa"

Mã nguồn upstream (`upstash/context7`, commit `e004194`, đọc ngày 2026-10-17) mặc định từ chối request **không có thông tin xác thực** (`MCP_AUTH_ENFORCEMENT` mặc định là `required`); README của họ ghi khóa API là "nên có" để được giới hạn cao hơn. Dịch vụ đang chạy có thể cấu hình khác, và sandbox của phiên viết ví dụ này chặn `mcp.context7.com`, nên **chưa từng chạy thật** một lần đăng nhập hay một lần gọi tool. Upstream ghi hai cách (trang *All Clients* trong tài liệu của họ, file `resources/all-clients.mdx` ở commit trên). **OAuth**: đổi đường dẫn từ `/mcp` sang `/mcp/oauth`, rồi đăng nhập bằng trình duyệt. **Khóa API**: giữ `/mcp` và gửi tiêu đề `Authorization: Bearer <khóa>`. Bản mẫu dùng `/mcp/oauth`: sau khi thêm server, gõ `/mcp` trong Claude Code, chọn Context7 và làm theo bước đăng nhập. Cách này không để lại bí mật nào trong repo. `/mcp` trơn không phải đường dẫn OAuth theo tài liệu của họ, nên bản mẫu không dùng nó. Đăng nhập OAuth bằng Claude Code qua `/mcp/oauth` là chỗ **chưa được kiểm**.

Máy không mở được trình duyệt (SSH, CI) thì dùng khóa API: tạo khóa ở https://context7.com/dashboard, đặt vào **biến môi trường** `CONTEXT7_API_KEY`, và dùng bản có `headers` dưới đây (đường dẫn `/mcp`, không phải `/mcp/oauth`). Biến không đặt thì tiêu đề rỗng (`${VAR:-}` cho giá trị mặc định rỗng), và theo mã upstream server coi như không có khóa thay vì nhận chuỗi `${CONTEXT7_API_KEY}` nguyên văn như một khóa sai. Việc Claude Code mở rộng `${VAR:-}` trong `headers` là theo tài liệu của nó; chưa chạy thử ở đây.

```json
{
  "mcpServers": {
    "context7": {
      "type": "http",
      "url": "https://mcp.context7.com/mcp",
      "headers": { "Authorization": "Bearer ${CONTEXT7_API_KEY:-}" }
    }
  }
}
```

Không bao giờ ghi khóa thật vào `.mcp.json`, vào file này hay vào `.claude/`. `scripts/test_mcp_example.py` làm CI đỏ nếu một khối `headers` trong tài liệu hay trong bản mẫu chứa thứ gì khác một biến môi trường.

## Dùng ở repo khác

Chép `.claude/mcp/` (bản mẫu bạn cần), khối `permissions.deny` của `.claude/settings.json` (gộp vào file của repo đích nếu đã có `permissions.deny`, đừng ghi đè), hai dòng `/.mcp.json` và `/.playwright-mcp/` vào `.gitignore`, và file này. Chép bản mẫu Playwright mà không chép quy tắc chặn thì tool chạy mã tùy ý dùng được ngay khi bật server.
