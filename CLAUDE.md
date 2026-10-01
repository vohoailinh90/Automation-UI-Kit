# Automation UI Kit — ghi chú cho Claude

## Skill `design-taste-frontend` (taste-skill)

`.claude/skills/design-taste-frontend/` là bản chép **đã pin** của skill `design-taste-frontend` từ [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill) (MIT, commit `ce26fc2`; nguồn và SHA-256 ở [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md#taste-skill--mit)). Kit chưa có mẫu landing page, và skill này bù đúng chỗ đó.

Khi người dùng không yêu cầu khác, ưu tiên như sau:

1. **UI ứng dụng theo kit, không theo skill**: dashboard, bảng dữ liệu, form, settings, tool nội bộ, và mọi màn hình dựng từ `src/components/`. Skill tự nhận không dành cho loại này (§13 của nó), nên đừng theo các gợi ý của nó như chuyển sang Fluent/Carbon/Atlassian/Polaris, đổi `lucide-react` sang Phosphor, bỏ card, hay sửa primitive của kit vì "shadcn không được để mặc định".
   - "Portfolio" trong skill là trang portfolio cá nhân/studio, không phải dashboard danh mục cổ phiếu `src/pages/portfolio.tsx`.
   - Chỉnh giao diện một màn hình có sẵn của kit không phải "redesign" theo §11 của skill.
2. **Landing page, portfolio cá nhân, trang marketing** thì dùng skill cho bố cục, typography, copy, hero và motion. Nếu trang dùng component của kit: giữ `lucide-react` (một bộ icon cho cả repo), và đừng sửa token dùng chung trong `src/index.css` hay primitive trong `src/components/ui/` cho hợp trang. Cần màu nhấn hay bo góc riêng thì đặt biến CSS (`--primary`, `--radius`...) trên phần tử bọc trang. Biến màu phải đặt cho cả hai theme (ví dụ `.landing` và `.dark .landing`, vì class `.dark` nằm trên `<html>`), và đổi `--primary` thì đổi luôn `--primary-foreground`. axe chỉ quét các route có trong mảng `pages` của `e2e/dashboards-a11y.spec.ts`, nên thêm route của trang mới vào đó.
3. **iOS (`ios/`)** nằm ngoài phạm vi skill (native mobile, §13): theo `LabTheme` / `LabPalette` trong `ios/IdeaLabKit`.

Giữ bản pin:

- Không cập nhật bằng `npx skills add` (lệnh này lấy HEAD, mà bản v2 còn "experimental"), và không cài cả bộ taste-skill, nhất là `full-output-enforcement` (skill tự áp cho bất kỳ task nào cần output dài).
- Không sửa trực tiếp file đã chép; quy tắc riêng của kit viết ở file này.
- Nâng phiên bản: tải `skills/taste-skill/SKILL.md` và `LICENSE` ở commit mới, đọc diff, rồi cập nhật commit và SHA-256 trong `THIRD_PARTY_NOTICES.md`.
