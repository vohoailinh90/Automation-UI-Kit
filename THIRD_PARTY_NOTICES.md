# Third-party notices

Kit này (MIT, xem [LICENSE](./LICENSE)) có chứa mã chép hoặc chỉnh sửa từ các dự án dưới đây. License gốc của từng dự án áp dụng cho phần mã đó — khi copy các file này sang repo khác, **mang theo file này** (hoặc đúng đoạn license tương ứng).

Chỉ liệt kê mã **nằm trong repo**. Thư viện cài qua npm (`recharts`, `@radix-ui/*`, `lightweight-charts`, `@tanstack/react-table`, `cmdk`...) đi kèm license riêng trong `node_modules`.

## shadcn/ui — MIT

- Nguồn: https://github.com/shadcn-ui/ui (registry `new-york-v4`, commit `98a1fe6`, 2026-09-25)
- Áp dụng cho `src/components/ui/*`:
  - `chart.tsx` — gần nguyên văn (chỉ đổi import `cn`, bỏ `"use client"`).
  - `toggle.tsx`, `toggle-group.tsx` — theo API của shadcn, chỉnh focus ring, màu hover và trạng thái bật cho đủ tương phản (chi tiết trong chú thích đầu file).
  - Các primitive còn lại (`button`, `card`, `badge`, `tabs`, `table`...) viết tay theo đúng API/convention của shadcn.

```
MIT License

Copyright (c) 2023 shadcn

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Tremor — chỉ cảm hứng thiết kế, không chép mã

`src/components/dashboard/{tracker,bar-list,category-bar,progress-ring}.tsx` lấy **ý tưởng hình ảnh** từ Tracker, BarList, CategoryBar và ProgressCircle của [Tremor](https://github.com/tremorlabs/tremor) (Apache-2.0), nhưng được viết lại từ đầu theo token và convention của kit — không có dòng mã nào chép từ Tremor, nên không kéo theo nghĩa vụ của Apache-2.0. Nếu sau này port nguyên văn một component của Tremor, phải giữ license Apache-2.0 cho file đó, ghi rõ đã sửa gì (§4b), và giữ các notice sẵn có (§4c).
