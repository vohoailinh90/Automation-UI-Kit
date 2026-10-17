# Kho skill giao diện

Bản chép **đã ghim** của các skill giao diện cho agent (Claude Code và các agent đọc `SKILL.md`), để các repo khác lấy từ một chỗ thay vì mỗi nơi cài một kiểu bằng `npx skills add` (lệnh đó lấy HEAD, nên bản nào cũng có thể đổi dưới chân bạn).

Phần lớn skill dưới đây nằm ở `skills/`, **không nằm trong `.claude/skills/`**, nên Claude làm việc ở kit này **không tự nạp** chúng: chúng chỉ là kho. Riêng `design-taste-frontend` và `swiftui-liquid-glass` đang bật ở kit: hai skill này nằm ở `.claude/skills/` (xem [CLAUDE.md](../CLAUDE.md)) và được ghi vào cùng manifest để kiểm cùng một cách.

## Có gì trong kho

| Skill | Hợp với | Nguồn @ commit | Giấy phép | Mã chạy được |
| --- | --- | --- | --- | --- |
| `frontend-design` | Trang mới hoặc làm lại giao diện: chọn hướng thẩm mỹ, typography, copy. Chỉ ~9 KB; có bước lập kế hoạch rồi tự phê bình | [anthropics/skills](https://github.com/anthropics/skills) @ `dbd4588` (2026-10-09) | Apache-2.0 | Không |
| `design-taste-frontend` | Landing page, portfolio, làm lại giao diện. Tự nhận không dành cho dashboard. **Đang bật ở kit này**, nằm ở `.claude/skills/` | [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill) @ `ce26fc2` (2026-09-26) | MIT | Không |
| `ui-ux-pro-max` | Tra cứu bằng dữ liệu: 79 style, 192 bảng màu, 74 cặp font, 119 hướng dẫn UX, 25 loại chart, 22 stack (số liệu theo mô tả của skill) | [nextlevelbuilder/ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) @ `56ea9cf` (2026-10-14) | MIT | Có: 4 script Python, chỉ thư viện chuẩn, đọc CSV cục bộ |
| `swiftui-liquid-glass` | SwiftUI iOS 26+: API Liquid Glass đúng cách, có nhánh dự phòng cho iOS cũ. **Đang bật ở kit này**, nằm ở `.claude/skills/`; kit quyết định *chỗ nào* được dùng kính, skill chỉ dạy gọi API cho đúng | [Dimillian/Skills](https://github.com/Dimillian/Skills) @ `05ba982` (2026-03-29) | MIT | Không |
| `swiftui-design-skill` | SwiftUI: hướng thiết kế, tránh giao diện "AI slop", rà soát 5 chiều | [Wholiver/swiftui-design-skill](https://github.com/Wholiver/swiftui-design-skill) @ `2c82638` (2026-05-01) | MIT | Không |

Ngày trong bảng là ngày tác giả của commit; GitHub hay `git log --format=%cd` có thể hiện lệch một ngày theo múi giờ hoặc vì ngày committer khác. Commit đầy đủ, SHA-256 từng file và các file upstream **cố ý không chép** nằm ở [`MANIFEST.json`](MANIFEST.json). Nguồn và giấy phép: [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

Vài điều cần biết về `ui-ux-pro-max`:

- Script chỉ tra cứu và in kết quả; chỉ khi bạn thêm `--persist` nó mới ghi file (thư mục `design-system/` trong dự án).
- Không chép `scripts/tests/` và `scripts/validate_data.py` của upstream: đó là bộ kiểm tra dữ liệu của tác giả, có gọi mạng và chạy lệnh con, không cần để tra cứu.
- `SKILL.md` của nó viết đường dẫn theo `${CLAUDE_PLUGIN_ROOT}`, đúng khi cài như plugin. Chép làm skill dự án thì chạy: `python3 .claude/skills/ui-ux-pro-max/scripts/search.py "<truy vấn>" --domain style`. Đã thử chạy script này từ bản chép trong kho. Nội dung gốc không sửa.

## Chưa chép, và vì sao

| Của ai | Tình trạng | Lý do |
| --- | --- | --- |
| [pbakaus/impeccable](https://github.com/pbakaus/impeccable) (Apache-2.0, skill 4.6.0, `6af45ac`, 2026-10-16) | Không chép | Bước đầu bắt buộc của `SKILL.md` là chạy `scripts/impeccable context`; launcher này chạy một file thực thi theo nền tảng và, **nếu chưa có file đó cạnh nó, tải về từ kênh phát hành của tác giả** ở lần chạy đầu (bản trong repo của tác giả không kèm sẵn file thực thi); bộ cài còn thêm hook chạy ở mỗi lần sửa file. Ghim bản chép không ghim được file tải về lúc chạy (chưa đọc hết launcher để biết nó kiểm checksum thế nào), nên chép nó vào kho dùng chung là quyết định tin cậy của chủ repo, không phải việc của một lần chép file. Muốn dùng: tự đọc rồi cài thẳng từ upstream (`/plugin marketplace add pbakaus/impeccable`) ở repo cần |
| [VoltAgent/awesome-design-md](https://github.com/VoltAgent/awesome-design-md) | Không chép | Là bộ file `DESIGN.md` mô tả hệ thiết kế của các thương hiệu, tức dữ liệu tham chiếu chứ không phải skill. Chưa kiểm giấy phép |
| Các skill còn lại trong `ui-ux-pro-max-skill` (`design`, `design-system`, `brand`, `banner-design`, `slides`, `ui-styling`) | Không chép | Ngoài phạm vi giao diện ứng dụng, và `ui-styling` riêng đã nặng 5,8 MB |

## Dùng ở repo khác

1. Lấy kit về: trong phiên Claude Code của repo đích gắn `vohoailinh90/Automation-UI-Kit` (quyền đọc đủ vì repo công khai) rồi clone, hoặc `git clone --depth 1 https://github.com/vohoailinh90/Automation-UI-Kit`.
2. Chép **cả thư mục** skill, giấy phép đi kèm: `cp -r <kit>/skills/frontend-design <repo-đích>/.claude/skills/frontend-design`. Đường dẫn thật của từng skill là `path` trong `MANIFEST.json`: `skills/<tên>`, trừ hai skill đang bật ở kit nằm ở `.claude/skills/<tên>`. Không chép riêng `SKILL.md`, không dùng symlink, không `npx skills add`.
3. Ghi vào `CLAUDE.md` của repo đích skill nào áp dụng cho loại màn hình nào, như `CLAUDE.md` của kit làm với taste-skill, để các skill không giẫm lên nhau.

Cách chọn (đây là khuyến nghị của kit, không phải của tác giả các skill):

- Với cùng một việc chỉ bật **một** skill định hướng thẩm mỹ: `frontend-design` (ngắn) **hoặc** `design-taste-frontend` (dài, thiên landing/portfolio). Cả hai là skill chống "hàng mặc định" theo cách riêng, nên bật cùng lúc dễ cho chỉ dẫn chồng chéo.
- `ui-ux-pro-max` dùng như từ điển tra cứu khi cần số liệu (màu, font, chart), không đặt làm chỉ dẫn mặc định cho mọi việc về UI: mô tả của nó khớp rất rộng.
- Màn hình ứng dụng nội bộ dựng từ `src/components/` của kit thì theo kit, không theo skill định hướng.
- SwiftUI: `swiftui-liquid-glass` cho API, `swiftui-design-skill` cho hướng thiết kế. `ios/IdeaLabKit` có `LabTheme` / `LabPalette` và `labGlass` riêng, ưu tiên chúng: ở chính kit, quy tắc "kính chỉ cho lớp điều khiển nổi, thẻ nội dung giữ đặc" thắng gợi ý của skill (xem [CLAUDE.md](../CLAUDE.md)).

## Giữ bản ghim

- `python3 scripts/check_skills.py` kiểm từng file với SHA-256 trong manifest, tên thư mục với `name:` trong `SKILL.md`, file giấy phép, commit 40 ký tự và việc README này nhắc tên mọi skill. Mọi thư mục dưới `skills/` **và** `.claude/skills/` phải có trong manifest: gỡ một mục khỏi manifest không đưa skill đó ra khỏi vòng kiểm mà làm CI đỏ (hiện kit chưa có skill tự viết dưới `.claude/skills/`; khi có thì phải bàn lại quy tắc này). CI chạy lệnh này; file đổi một byte, thiếu hay thừa đều làm CI đỏ, kể cả `__pycache__` hay `.DS_Store` bị `git add -f` vào (chạy script của skill ngay trong kho thì xóa `__pycache__` trước khi kiểm). Script bắt thay đổi vô ý hoặc lẻ tẻ; ai sửa cả file lẫn SHA-256 trong cùng một commit thì chỉ lộ ra ở diff của PR, nên diff của `MANIFEST.json` phải được đọc.
- **Không sửa file đã chép.** Quy tắc riêng của kit viết ở CLAUDE.md hoặc README này.
- **Bật hay tắt một skill ở kit** là `git mv` giữa `skills/<tên>` và `.claude/skills/<tên>` (không chép: manifest không cho trùng tên), rồi sửa `path` và `active_in_this_repo` trong `MANIFEST.json`, bảng và đoạn mở đầu ở đây, THIRD_PARTY_NOTICES.md và CLAUDE.md. `check_skills.py` bắt cờ `active_in_this_repo` lệch với chỗ skill nằm (true chỉ khi dưới `.claude/skills/`) và thư mục không có trong manifest.
- **Nâng phiên bản** (cố ý, có đọc diff): clone upstream ở commit mới vào thư mục trống, đọc diff, nhất là mã chạy được và chỉ dẫn mới; chép đúng các file đã liệt kê; chạy `python3 scripts/check_skills.py --update <tên> --commit <sha đầy đủ>` (`--commit` là bắt buộc, và script từ chối khi file đổi mà commit vẫn là commit đang ghim, để manifest không gán bản mới cho commit của bản cũ); sửa commit và ngày trong THIRD_PARTY_NOTICES.md và bảng trên; mở PR.
- **Thêm skill mới**: giấy phép phải cho phép chép lại và được mang theo; đọc toàn bộ `SKILL.md`; quét ký tự Unicode ẩn, cụm chỉ dẫn đáng ngờ và mã gọi mạng hoặc chạy lệnh; không chép hook hay launcher tải file thực thi; ghi file bỏ lại vào `omitted` của manifest.
- Các skill này là chỉ dẫn mà agent của repo đích sẽ làm theo, nên coi bản chép mới như mã mới: quét và đọc trước khi nhận.
