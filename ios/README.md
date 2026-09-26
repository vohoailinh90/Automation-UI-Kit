# IdeaLab UI — bộ giao diện iOS (SwiftUI)

Bộ nền giao diện cho các app iOS sẽ làm ở repo **app-idea-lab**: một Swift package (`IdeaLabKit`), một app demo để xem mọi thứ chạy thật, và bản khảo sát "giao diện iOS đẹp nhất hiện nay" làm căn cứ cho từng quyết định thiết kế.

Mục tiêu giống web kit ở thư mục gốc: app mới **không phải dựng giao diện từ đầu**. Chép package vào, gọi `.labTheme(.ledger)`, thay dữ liệu mẫu bằng dữ liệu thật.

| Thư mục | Là gì |
| --- | --- |
| `IdeaLabKit/` | Swift package: `IdeaLabCore` (Foundation, test được cả trên Linux) + `IdeaLabUI` (SwiftUI, iOS 17+) |
| `IdeaLabDemo/` | App gallery: mở từng thành phần, từng màn hình mẫu, đổi bảng màu, bật chế độ chữ lớn |
| `scripts/render-previews.sh` | Chụp mọi màn hình demo trên simulator (sáng, tối, chữ cực lớn) |

> Ảnh chụp thật từ simulator: xem mục [Ảnh chụp](#ảnh-chụp). Muốn chụp lại: gắn nhãn `ios-previews` vào PR, hoặc Actions → **iOS previews** → Run workflow.

---

## 1. Khảo sát: giao diện iOS đẹp nhất, 09/2026

Tóm tắt từ tài liệu chính thức của Apple, các app đoạt giải và các báo cáo ngành. Mỗi kết luận ở đây đều đi thẳng vào một quyết định trong kit (mục 2).

### 1.1 Ngôn ngữ thiết kế hiện tại: Liquid Glass, đã sang iOS 27

- **iOS 26 (WWDC25)** đưa vào **Liquid Glass**: thanh điều hướng, tab bar, toolbar, sheet thành lớp kính nổi trên nội dung. Build bằng SDK mới là các control chuẩn **tự đổi sang giao diện mới** ([Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)). API cho phần tự vẽ: `glassEffect(_:in:)`, `GlassEffectContainer`, `.buttonStyle(.glass)`, đều từ iOS 26 ([glassEffect](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:))).
- **iOS 27 đã phát hành ngày 14/09/2026** ([Apple](https://developer.apple.com/news/releases/?id=09142026a)). WWDC26 chỉnh Liquid Glass: làm mờ nội dung phía sau mạnh hơn, viền tối hơn, và người dùng có thanh trượt từ "rất trong" tới "phủ màu hẳn" ([WWDC26](https://developer.apple.com/news/?id=yi8qj25k)).
  - Hệ quả: **độ trong của kính do người dùng quyết định**. Chữ đặt trên kính không thể giả định một mức tương phản cố định.
- **Không lùi lại được nữa**: khoá `UIDesignRequiresCompatibility` (giữ giao diện cũ) **bị bỏ qua khi build bằng SDK iOS 27** ([Apple](https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility)). Từ 28/04/2026 bản nộp phải build bằng Xcode 26; từ **04/2027** phải dùng SDK iOS 27 ([yêu cầu sắp tới](https://developer.apple.com/news/upcoming-requirements/), [tin 2027](https://developer.apple.com/news/?id=k1mtkt1k)).
- **Nguyên tắc HIG**: kính dành cho **lớp điều khiển nổi phía trên** nội dung (thanh, nút nổi), **không** dùng cho chính nội dung.

**→ Trong kit:** `labGlass(in:)` dùng Liquid Glass trên iOS 26+ và material trên iOS 17–25; chỉ khay nút "Thu/Chi" và nút đóng paywall dùng kính. Thẻ nội dung, toast, bàn phím số đều **đặc** để chữ giữ đúng tương phản đã kiểm.

### 1.2 Apple Design Awards 2025–2026: app thắng giải giống nhau ở đâu

| Năm | Hạng mục | Thắng giải | Đáng học cho ta |
| --- | --- | --- | --- |
| 2026 | Interaction | **Moonlitt** | Apple khen "tích hợp Liquid Glass tốt nhất" |
| 2026 | Visuals & Graphics | **Tide Guide** | Dữ liệu biểu đồ đẹp mà vẫn đọc nhanh, cũng dùng Liquid Glass |
| 2026 | Inclusivity | **Guitar Wiz** (chung kết: **Structured**, Hearing Buddy) | Tiếp cận là một hạng mục giải riêng, không phải phần phụ |
| 2025 | Inclusivity | **Speechify** | Dựng quanh người đọc khó khăn |
| 2025 | Delight & Fun | **CapWords** | Một tương tác chính, làm thật kỹ |
| 2025 | Social Impact | **Watch Duty** | Thông tin khẩn cấp phải rõ trong một cái liếc |

Nguồn: [ADA 2026](https://developer.apple.com/design/awards/), [ADA 2025](https://developer.apple.com/design/awards/2025/). Hai năm này **không có app tài chính** nào. Tham chiếu tài chính tốt nhất là **Copilot Money** (chung kết ADA 2024): hoàn toàn native, biểu đồ dòng tiền vẽ bằng Swift Charts ([Apple](https://developer.apple.com/articles/copilot-money)).

**Điểm chung:**
- Dùng component hệ thống làm nền, chỉ tự vẽ đúng một hai chỗ tạo dấu ấn.
- Mỗi màn hình có **một** việc chính.
- Tiếp cận (chữ lớn, VoiceOver, giảm chuyển động) được làm từ đầu, không phải vá sau.

### 1.3 Tham chiếu cho từng app trong app-idea-lab

**A. Sổ thu chi 10 giây** (ý tưởng #1, đang có template đầy đủ)

- **Đối thủ trực tiếp: [Sổ Thu Chi MISA](https://sothuchi.misa.vn/)**. Đã có ghi bằng giọng nói, chat, AI đọc hoá đơn, liên kết ngân hàng.
  - Muốn thắng thì không thể thêm tính năng. Phải **đơn giản hơn hẳn**: hai nút to, một bàn phím, xong.
- **Money Lover** do Finsify làm tại Hà Nội ([Vietcetera](https://vietcetera.com/en/money-lover-a-vietnamese-built-fintech-mobile-app-going-global)). **Toshl** nổi tiếng ghi một khoản trong 4 chạm.
  - **Cashew** mã nguồn mở nhưng giấy phép **GPL-3.0**: chỉ nên xem để học, **không chép mã** ([GitHub](https://github.com/jameskokoska/Cashew)).
- Loa báo chuyển khoản của **MoMo/ZaloPay** đọc to số tiền nhận được ([MoMo](https://www.momo.vn/loa-thong-bao-chuyen-khoan)). Người bán hàng đã quen "nghe lại số tiền".
  - Gợi ý cho bản sau: đọc lại "Đã ghi thu 450 nghìn" sau khi lưu.

**→ Trong kit:** nút Thu/Chi cao 84–96 pt luôn nằm dưới ngón cái. Bàn phím có phím "000" (gõ 450.000 = `4` `5` `0` `000`). Ô ghi chú hiểu "bán 3 thùng nước 450k". Biểu đồ phân kỳ (thu lên, chi xuống). Báo cáo theo **quý**, vì hộ kinh doanh kê khai theo quý. Ghi chú rõ "không tư vấn thuế".

**B. Nhắc thuốc cho cha mẹ** (có template)

- **Apple Health › Thuốc** (iOS 16+): cho chọn hình dạng và màu viên thuốc ([TidBITS](https://tidbits.com/2022/10/07/an-apple-a-day-ios-16-medications-feature-provides-alerts-logging-and-peace-of-mind/)), nhắc lại nếu 30 phút sau chưa ghi nhận ([Apple](https://support.apple.com/guide/iphone/track-your-medications-iph811670c81/ios)).
- **Medisafe "Medfriend"**: người thân nhận thông báo khoảng 30 phút sau liều bị lỡ.
- **Người lớn tuổi**:
  - Nghiên cứu trên 40 người cao tuổi thấy nút **14–17,5 mm** dễ bấm nhất ([Leitão & Silva 2012](http://shura.shu.ac.uk/7446/)), tức khoảng 84–105 pt trên iPhone.
  - Mức tương phản 4,5:1 của WCAG được tính cho thị lực ~20/40, "thị lực điển hình của người ~80 tuổi" ([W3C](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)).
- **Assistive Access** (chế độ giản lược của iOS):
  - Từ iOS 17: khai `UISupportsFullScreenInAssistiveAccess` để app chạy toàn màn hình trong chế độ này ([Apple](https://developer.apple.com/documentation/bundleresources/information-property-list/uisupportsfullscreeninassistiveaccess)).
  - Từ iOS 26: có scene `AssistiveAccess` để dựng giao diện riêng cho chế độ này ([Apple](https://developer.apple.com/documentation/swiftui/assistiveaccess)).

**→ Trong kit:**
- `LabDensity.senior`: nút chính cao 96 pt, nút thường 60 pt, và giữ cỡ chữ tối thiểu `xLarge` dù máy để chữ nhỏ.
- Màn hình của cha mẹ (`MedsTodayScreen`): **một** liều mỗi lúc, vẽ đúng hình và màu viên thuốc, một nút "ĐÃ UỐNG" thật to. Nút "Không uống liều này" chỉ là chữ, không nền, đặt tách dưới nút chính để khỏi bấm nhầm (vùng bấm vẫn rộng, cho tay run). Hoàn tác thuộc về app (demo dùng toast "Hoàn tác"), ghi bằng `DoseLog.undo(_:at:)`. Bấm xong, thẻ hiện "Đã uống …" **2 giây** rồi mới tới thuốc kế tiếp: tay run bấm đúp cũng không đánh dấu nhầm một viên chưa uống.
- Màn hình của người con (`CaregiverScreen`): trả lời "mẹ uống thuốc chưa?" trong một cái liếc. Chỉ khi có liều trễ quá 30 phút màn hình mới chuyển vàng và hiện nút "Gọi Mẹ".
- Quy tắc 30 phút giống Apple Health: `DoseSchedule.grace`.

**C. Dọn ảnh bằng AI, mua một lần** (có template)

- **Slidebox**: vuốt từng ảnh, rồi **xem lại trước khi xoá vĩnh viễn** — bước an toàn nên chép.
- **Cleanup** và nhiều app "cleaner" khác bị chê vì dùng thử 7 ngày rồi tự chuyển sang **gói tuần ~9,99 USD** ([phân tích](https://connortumbleson.com/2025/01/13/predatory-ios-cleanup-applications/)).
  - Chính là khoảng trống của ý tưởng C: **mua đứt, riêng tư**.
- iOS giữ ảnh đã xoá trong **Đã xoá gần đây 30 ngày**; dung lượng chỉ trở lại khi album đó được dọn. App nào không nói điều này sẽ nhận đánh giá "xoá rồi mà không thấy trống thêm".
- Ý tưởng dễ bị xem là **4.3 (spam)** nếu giống các app cleaner khác, nên phải khác biệt rõ ở cách trình bày.

**→ Trong kit:**
- Trang chủ (`CleanerHomeScreen`) **không doạ**: không "máy bạn đang gặp nguy", chỉ có số thật. Vòng dung lượng đánh dấu phần dọn được, mỗi nhóm ảnh có số ảnh, dung lượng và thanh tỉ lệ, cùng một dòng "ảnh không rời khỏi máy".
- Bộ thẻ vuốt (`SwipeDeck`): vuốt trái xoá, phải giữ, **luôn có nút bấm** Xoá / Hoàn tác / Giữ. VoiceOver có hành động riêng, bàn phím dùng ← → ⌘Z.
- **Không xoá gì khi vuốt.** Bước xem lại (`CleanupReviewScreen`) là lưới ảnh, chạm để giữ lại. Nút ghi rõ số ảnh và dung lượng: "Xoá 21 ảnh · 23,9 MB" ở bản đầy đủ, hoặc "Xoá 12 ảnh đầu tiên · 14 MB" khi lượt miễn phí chỉ còn 12 (như trong demo).
- **Miễn phí 100 ảnh đầu** (`FreeAllowance`), chỉ tính khi xoá thật. Khi số ảnh chọn vượt phần miễn phí, màn xem lại đưa **cả hai lựa chọn**: xoá phần miễn phí ngay, hoặc mở khoá, thay vì chặn bằng paywall vào phút chót.
- Ảnh yêu thích **không bao giờ** được đề xuất xoá.
- Màn hình xong việc (`CleanupDoneScreen`) nói rõ chuyện "Đã xoá gần đây", kèm nút mở ứng dụng Ảnh.

**D. Paywall (dùng chung)**

- **Số liệu ngành** ([RevenueCat 2026](https://www.revenuecat.com/blog/growth/subscription-app-trends-benchmarks-2026), [Adapty 2026](https://adapty.io/blog/mobile-app-monetization-2026/)):
  - 89,4% lượt dùng thử bắt đầu ngay **ngày đầu tiên**, nên paywall trong onboarding quan trọng nhất.
  - Gói năm còn giữ ~28% người dùng sau một năm, gói tuần chỉ ~3%.
  - Tỉ trọng mua một lần đang tăng: 6,4% (2023) → 10,3% (2025).
- **Quy định của Apple** ([Guideline 3.1.2](https://developer.apple.com/app-store/review/guidelines/), [trang đăng ký gói](https://developer.apple.com/app-store/subscriptions/)):
  - Giá **thực trả** phải là giá nổi bật nhất trên màn hình.
  - Phải ghi rõ thời hạn và giá sau dùng thử.
  - Phải có Khôi phục mua hàng, Điều khoản và Quyền riêng tư.

**→ Trong kit:** `PaywallScreen` làm đúng các điều trên. Giá theo tháng quy đổi chỉ là dòng phụ, chữ nhỏ. Nút đóng luôn hiện, không trì hoãn. Giá lấy từ StoreKit, kit không tự định dạng.

### 1.4 Xem giao diện thật ở đâu

| Nguồn | Có gì | Miễn phí? |
| --- | --- | --- |
| [Mobbin](https://mobbin.com) | Kho lớn nhất: màn hình và luồng thật của iOS/Android/web; có MCP server cho AI (05/2026) | Có gói free giới hạn |
| [Refero](https://refero.design) | Web + iOS, tìm theo từ khoá/thành phần, có MCP | Có bản free; Pro ~20 USD/tháng |
| [ScreensDesign](https://screensdesign.com) | Chỉ iOS: video onboarding, **paywall**, ước tính doanh thu. Đã mua lại UI Sources, Design Vault; Scrnshts cũng chuyển về đây | Trả phí |
| [Page Flows](https://pageflows.com) | Video từng luồng (đăng ký, thanh toán...) | ~99 USD/năm |
| [Apple Design Resources](https://developer.apple.com/design/resources/) | **UI Kit iOS 27** cho Figma/Sketch, mẫu icon, SF Symbols (7.000+ biểu tượng) | **Miễn phí** |

### 1.5 Thư viện SwiftUI mã nguồn mở đáng dùng

Kit **không phụ thuộc thư viện ngoài nào**. Khi app cần thêm, đây là những thư viện còn được duy trì, giấy phép thoáng (kiểm tra 09/2026):

| Thư viện | Dùng khi | License | Bản mới nhất |
| --- | --- | --- | --- |
| [Pow](https://github.com/EmergeTools/Pow) (EmergeTools) | Hiệu ứng chuyển cảnh, "khen thưởng" khi xong việc | MIT | 1.0.6 (02/2026) |
| [Vortex](https://github.com/twostraws/Vortex) | Pháo hoa, confetti, hạt | MIT | 1.0.4 |
| [ConfettiSwiftUI](https://github.com/simibac/ConfettiSwiftUI) | Confetti đơn giản | MIT | 3.0.0 (01/2026) |
| [Lottie](https://github.com/airbnb/lottie-ios) | Animation từ After Effects | Apache-2.0 | 4.6.1 |
| [RevenueCat](https://github.com/RevenueCat/purchases-ios) (+ RevenueCatUI) | Quản lý gói, paywall từ xa; miễn phí tới 2.500 USD doanh thu/tháng | MIT | 5.91.0 (09/2026) |
| [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) | Test ảnh chụp giao diện | MIT | 1.19.6 (09/2026) |
| [PopupView](https://github.com/exyte/PopupView) | Popup, toast phức tạp | MIT | 5.0.6 (iOS 17+) |

**Tránh** (ngừng cập nhật từ 2023–2024), đã có cách native thay thế:

| Thư viện | Dùng thay |
| --- | --- |
| SwiftUI-Shimmer | `.redacted(reason: .placeholder)` |
| FluidGradient | `MeshGradient` (iOS 18) |
| Drops | Toast trong kit |
| CardStackView | `SwipeDeck` trong kit |

**Native trước, thư viện sau:**
- Paywall: `SubscriptionStoreView` / `ProductView` (StoreKit, iOS 17+) ([Apple](https://developer.apple.com/documentation/storekit/subscriptionstoreview)).
- Haptic: `sensoryFeedback`. Mẹo gợi ý: TipKit.
- Biểu đồ: Swift Charts.

---

## 2. Bộ kit: `IdeaLabKit`

### 2.1 Màu: một bảng, ba app, có kiểm chứng

Component **không bao giờ tự chọn mã màu**. Nó hỏi một *vai trò* (`label`, `positive`, `accent`...), còn `LabPalette` trả lời. Ba bảng dựng sẵn dùng chung nền trung tính, chỉ khác màu thương hiệu:

| Bảng | Màu thương hiệu | Vì sao |
| --- | --- | --- |
| `.ledger` | Xanh dương `#0B5FD0` | Cảm giác ngân hàng; nhường **xanh lá = thu, đỏ = chi** |
| `.meds` | Xanh ngọc `#00756D` | Sức khoẻ, bình tĩnh; không mượn màu đỏ "nguy hiểm" |
| `.cleaner` | Tím `#6236D8` | Cảm giác "AI thông minh" |

**Lời hứa của bảng màu** (test `PaletteContrastTests` kiểm cho cả ba bảng × sáng/tối × Increase Contrast; ai chỉnh màu làm vỡ là CI đỏ):
- Mọi màu chữ ≥ **4,5:1** trên mọi nền; chữ chính ≥ **7:1** (AAA).
- Chữ trên mảng màu (nút) ≥ 4,5:1.
- Chế độ Increase Contrast **không bao giờ** làm tương phản tệ đi.

Ba chỗ cố ý khác mặc định của iOS:

1. **`secondaryLabel` đậm hơn của hệ thống.** Màu chữ phụ của iOS chỉ đạt ~3,4:1 trên nền trắng. Đọc lướt thì được, nhưng người dùng của các app này lớn tuổi.
2. **Tách `accent` (mảng nút) khỏi `accentText` (chữ, link).** Ở dark mode, **không màu nào làm được cả hai việc**: đủ sáng để đọc trên nền `#1C1C1E` thì lại quá sáng để mang chữ trắng (tính ra: cần độ chói ≤ 0,18 và ≥ 0,23 cùng lúc). Vì thế `.tint` của hệ thống dùng `accentText`, còn nút đặc dùng `.buttonStyle(.labFilled)` thay cho `.borderedProminent`.
3. **Màu nhạt `tonal(...)` là màu đặc, không phải lớp phủ trong suốt.** Lớp phủ 12% đổi tương phản theo thứ nằm dưới nó: trên nền xám, chữ xanh ledger chỉ còn 4,44:1.

### 2.2 Mật độ: `.regular` và `.senior`

| | Nút thường | Nút chính (hero) | Cỡ chữ tối thiểu |
| --- | --- | --- | --- |
| `.regular` | 50 pt | 84 pt | theo máy |
| `.senior` | 60 pt | 96 pt | `xLarge`, kể cả khi máy để chữ nhỏ |

`LabTheme.meds` mặc định `.senior`. App nào cũng có thể bật qua công tắc "Chữ và nút lớn" (có sẵn trong `SettingsScreen`).

### 2.3 Thành phần

| Thành phần | Ghi chú |
| --- | --- |
| `BigActionButton` | Nút vuông to có icon, haptic mỗi lần bấm |
| `.labFilled`, `.labTonal` | Hai kiểu nút, tự co theo mật độ, tôn trọng Reduce Motion |
| `AmountText`, `AmountDisplay` | Số tiền: có dấu `+`/`−` thật (không chỉ màu); VoiceOver đọc "Thu 450.000 đồng"; số cuộn khi đổi |
| `AmountKeypad` | Bàn phím đồng: 1–9, **000**, 0, xoá; giữ nút xoá (hoặc thao tác VoiceOver "Xoá hết") để xoá hết; rung báo lỗi khi bấm thừa |
| `KindPicker` | Công tắc Thu/Chi, bên đang chọn có màu **và** dấu +/− |
| `LedgerRow`, `StatTile` | Ở cỡ chữ trợ năng, tự xếp dọc thay vì cắt chữ |
| `CashFlowChart` + `CashFlowLegend` | Biểu đồ phân kỳ: thu lên trên, chi xuống dưới. Trả lời ngay "hôm nào lỗ?" |
| (ngày giờ) | `LedgerRow`, `CashFlowChart` và các màn hình mẫu nhận `calendar`: gom cột và in giờ theo **lịch của sổ**, không theo múi giờ của máy. Simulator CI chạy giờ UTC từng làm mọi cột lệch một ngày |
| `.labToast` | Có Hoàn tác. Khi VoiceOver bật, toast **được đọc và không tự biến mất** (WCAG 2.2.1) |
| `labGlass`, `labCard`, `LabSectionHeader`, `SettingsIcon` | Bề mặt và tiêu đề |
| `PillView` | Viên thuốc vẽ đúng hình (tròn có vạch bẻ, bầu dục, dài, viên nang hai màu) và màu, có viền để viên trắng vẫn hiện trên nền trắng; VoiceOver đọc "viên nang cam và kem" |
| `DoseStatusBadge`, `DoseRow` | Trạng thái liều bằng chữ + màu + icon: "Đã uống 07:12", "Đến giờ uống", "Trễ 2 giờ 41 phút" (nền hổ phách, chữ tối), "12:00" |
| `StorageRing`, `StorageLegend` | Vòng bộ nhớ: đã dùng, phần dọn được (màu nhấn, nét dày hơn để lát mỏng vẫn thấy), còn trống; giữa vòng là số GB dọn được. Chú thích nói lại mọi màu bằng chữ |
| `CleanupCategoryRow` | Một nhóm ảnh: icon, tên, "1.284 ảnh · 1,7 GB", thanh tỉ lệ so với tổng dọn được |
| `SwipeDeck` | Thẻ vuốt giữ/xoá có hai thẻ ló phía sau; dấu "XOÁ"/"GIỮ" hiện dần theo tay kéo; thẻ bay theo hướng đã chọn (chỉ mờ đi khi bật Reduce Motion); Hoàn tác đưa thẻ về từ đúng phía nó đi. Nút bấm, hành động VoiceOver và phím tắt làm đúng những việc như cử chỉ |
| `ReviewTile` | Ô ảnh trong bước xem lại: dấu check đỏ là sẽ xoá; chạm để "Giữ lại" (mờ đi, có nhãn), chạm lần nữa để chọn lại |

### 2.4 Màn hình mẫu

| Màn hình | Ghi chú |
| --- | --- |
| `LedgerHomeScreen` | Lãi/lỗ hôm nay, biểu đồ tháng, 5 khoản gần nhất; khay Thu/Chi trên kính |
| `QuickEntryScreen` | Sheet nhập trong 10 giây: bàn phím số, gợi ý ghi chú một chạm, chọn ngày (ghi bù hôm qua), hiểu cả câu "bán 3 thùng nước 450k". Đã bấm bàn phím thì **bàn phím quyết định**: sửa ghi chú không bao giờ lặng lẽ đổi số đã bấm, số khác trong ghi chú chỉ hiện thành nút "Dùng … trong ghi chú". Nút Lưu chỉ bấm được **một lần**: chạm hai lần, hay chạm lúc sheet đang đóng, không tạo hai khoản |
| `LedgerReportScreen` | Tháng này / tháng trước / quý này, xuất PDF/Excel (callback) |
| `MedsTodayScreen` | Nhắc thuốc, phía cha mẹ: lời chào theo buổi, liều đang chờ (to, có hình viên thuốc), nút "ĐÃ UỐNG", danh sách thuốc hôm nay. Liều 21:00 chưa trả lời vẫn được hỏi sau nửa đêm ("21:00 hôm qua"). Hết liều chờ thì nói rõ "Chưa đến giờ" và liều kế tiếp, không để màn hình trống; "Chúc ngủ ngon" chỉ khi đã tối |
| `CaregiverScreen` | Nhắc thuốc, phía người con: "Đã uống 1/3 liều đến giờ", "Cập nhật 07:00" theo lúc dữ liệu từ máy cha mẹ về thật (không theo đồng hồ), thẻ cảnh báo cho từng liều trễ (Gọi / Nhắc lại — nhắc xong nút thành "Đã nhắc lúc 08:42" trong 10 phút, bấm đúp không reo máy cha mẹ hai lần; app giữ `remindedAt`, nên đóng rồi mở lại màn hình cũng không reo lại), dòng thời gian hôm nay, vòng tuân thủ 7 ngày |
| `CleanerHomeScreen` | Dọn ảnh: vòng dung lượng, "Nên dọn trước: Ảnh chụp màn hình · 1,7 GB" + nút Bắt đầu, số ảnh miễn phí còn lại, danh sách nhóm ảnh, dòng quyền riêng tư. Có trạng thái đang quét (hiện dần những gì đã tìm thấy) và trạng thái "đã gọn gàng" |
| `CleanupSwipeScreen` | Tiến độ "12/48", số ảnh và dung lượng sẽ xoá, bộ thẻ vuốt; hết thẻ thì mời "Xem lại trước khi xoá" |
| `CleanupReviewScreen` | Lưới ảnh sẽ xoá, chạm để giữ lại; nút xoá ghi rõ số ảnh và dung lượng; khi số ảnh chọn vượt số lượt miễn phí còn lại thì tách hai lựa chọn: xoá những ảnh đầu tiên trong lưới mà lượt miễn phí còn đủ ("Xoá 12 ảnh đầu tiên · 14 MB"), hoặc mở khoá. `onDelete` (async) gọi PhotoKit, iOS tự hỏi xác nhận, ghi số ảnh vừa xoá vào lượt miễn phí, rồi trả về id các ảnh không còn trong thư viện để chúng rời khỏi phiên; các nút khoá tới khi nó trả về nên bấm đúp không hỏi hai lần |
| `CleanupDoneScreen` | "Đã dọn 21 ảnh", số dung lượng lớn, lời giải thích về Đã xoá gần đây và nút mở ứng dụng Ảnh |
| `OnboardingScreen` | 3–4 trang, luôn có "Bỏ qua" |
| `PermissionPrimerScreen` | Giải thích **trước** khi iOS hỏi quyền; hộp thoại hệ thống chỉ hiện được một lần |
| `PaywallScreen` | Đúng quy định 3.1.2, xem mục 1.3-D. Dòng giá (sau dùng thử trả bao nhiêu) luôn ghim ngay trên nút, kể cả ở cỡ chữ lớn nhất |
| `SettingsScreen` | Gói & khôi phục, chữ lớn, xuất dữ liệu, hỗ trợ/pháp lý, **xoá tài khoản** (5.1.1(v)): dòng này chỉ hiện khi app truyền `onDeleteAccount`, để không bao giờ có nút xoá mà không xoá gì |
| (gói) | `PaywallScreen` tự chọn lại gói mỗi khi danh sách gói đổi: gói người dùng đã chạm (nếu còn), rồi gói chọn sẵn, rồi gói đầu tiên. Gói từ StoreKit thường về **sau** khi màn hình đã hiện |

### 2.5 Lõi `IdeaLabCore`: phần dễ sai nhất, đã có test

**Tiền Việt Nam** — `VND.string(450_000)` → `450.000 ₫`:
- Luôn theo kiểu Việt Nam dù máy đặt vùng nào: dấu chấm ngăn nghìn, ký hiệu đứng sau.
- Dùng khoảng trắng không ngắt (NBSP), nên số và ký hiệu không bao giờ rớt dòng.
- Dấu âm là U+2212, rộng bằng dấu `+`.
- Dạng gọn cho trục biểu đồ: `12,5k`, `1,2tr`, `1,5 tỷ`. Số tròn lên đủ 1.000 đơn vị thì nhảy sang đơn vị kế: 999.999 → `1tr`, không phải `1.000k`.

**Bàn phím** — `AmountInput`:
- Tối đa 999.999.999.999 ₫.
- Bấm thừa thì bị **từ chối và báo lại**, không âm thầm bỏ qua: keypad rung báo lỗi.

**Đọc số tiền trong câu** — `AmountParser`:

| Gõ / nói | Hiểu là |
| --- | --- |
| `450k`, `450 nghìn`, `450 ngàn`, `450.000đ` | 450.000 |
| `1tr2`, `1 triệu 2`, `1 triệu 200 nghìn`, `1,2 triệu` | 1.200.000 |
| `2 triệu rưỡi` | 2.500.000 |
| `1 triệu 2 trăm`, `2 trăm 50 nghìn` | 1.200.000 / 250.000 |
| `bán 3 thùng nước 450k` | 450.000, ghi chú "bán 3 thùng nước" (số 3 là số lượng) |
| `chi 1 triệu 2 thùng sơn`, `thuê xe 1 triệu 2 ngày` | 1.000.000 — số 2 đứng trước danh từ đếm/thời gian nên là số lượng |
| `bán 1 triệu 2 rồi` | 1.200.000 — "rồi", "nữa", "nhé"... chỉ kết câu |
| `450k 25/9`, `450k 12:30`, `450k 25 %`, `450k 25-9`, `450k 25 . 9` | 450.000, ghi chú giữ `25/9`, `12:30`, `25 %`, `25-9`, `25. 9` — số theo sau là "/", ":", "%" (có dấu cách hay không), gạch dính vào một bên (`25-9`, `25 -9`), hay dấu chấm/phẩy có dấu cách phía trước (`25 . 9`, `25 , 9`) rồi đến số là ngày, giờ, phần trăm, số thập phân, không phải đuôi của số tiền |
| `bán được 1 triệu 2 hôm qua` | **không đọc** — 1,2 triệu hay 1 triệu và 2 thứ gì đó? |
| `1 triệu 2, 3 người`, `chi 1 triệu 2. 3 ngày nữa trả`, `1 triệu 2 - 3 người`, `450k 25 - 9` | **không đọc** — dấu phẩy/chấm dính vào đuôi rồi cách ra, hay gạch có dấu cách hai bên, có thể kết một vế câu mà cũng có thể nối hai số: 1,2 triệu và 3 người, hay 1 triệu và 2, 3 người? Đuôi dính vào đơn vị thì vẫn là đuôi: `1tr2, 3 người` → 1.200.000 |
| `5kg đường 100k`, `2 trà sữa 60k` | 100.000 / 60.000 — "k" trong "kg", "tr" trong "trà" không phải đơn vị |
| `150k một thùng, tổng 450k`, `tiền hàng 1tr, ship 25k`, `450k, tổng 500000`, `450000 + 500000`, `450k+500000`, `450k, 1 500 000` | **không đọc** — hai số tiền trong một câu thì không đoán; người dùng bấm số tiền trên bàn phím. Số trần từ 1.000 trở lên đứng riêng ở **bất kỳ đâu** cũng tính là một số tiền (kể cả viết cách nhóm ba số như `1 500 000`, cách bằng khoảng trắng nào cũng vậy, hay dính sau dấu `+`, `=`, `-`, `,`, `;`, `/` như `450k+500000`, `450k =500000`), trừ khi theo sau là danh từ đếm (`1500 cái`) hay tiền nước khác. Dấu gạch, phẩy, gạch chéo nằm giữa hai chữ số thì vẫn là một số hay một ngày (`25-9-2025`, `0912-345678`), còn `+84912345678` là số điện thoại. Số đứng sau dấu như vậy chỉ được đếm, không được đọc riêng (`tổng=450000` không đọc). Số trần nhỏ như `450k bán 3` (3 thứ gì đó) thì không |
| `450000 bán 3`, `tiền nhà 3500000 tháng 9`, `thu 1 500 000`, `gọi 84912345678` | **không đọc** — số trần chỉ được lấy làm số tiền khi đứng cuối câu và có tối đa 9 chữ số (10 chữ số trở lên là số tài khoản, số điện thoại; tiền tỷ thì viết `3.500.000.000` hay `3,5 tỷ`); số viết cách nhóm thì không bao giờ được lấy (`bán 3 450` có thể là 3 thứ gì đó) |
| `tiền nhà tháng 9 3.500.000`, `450.000 bán 3`, `bán 1.500 cái`, `chi 1.500 đô` | 3.500.000 / 450.000 / **không đọc** / **không đọc** — số có dấu chấm ngàn đọc được ở bất kỳ đâu, nhưng dấu chấm thôi chưa đủ là tiền: sau nó là danh từ đếm hay tiền nước khác thì không phải (`#12.345` cũng không) |
| `150k một thùng`, `150k năm mươi cái`, `trứng 30k một chục` | 150.000 / 30.000 — số viết bằng chữ mà theo sau là danh từ (hoặc "chục") thì là số lượng |
| `450k in 2 nghìn tờ rơi`, `150k cho 1 triệu cây` | 450.000 / 150.000 — "nghìn/triệu" + danh từ đếm là **số lượng**. Riêng "k", "tr" vẫn là giá (`trà sữa 30k ly`) |
| `chi 2 nghìn đô` | **không đọc** — đô la, không phải đồng |
| `5 nghìn 500 đồng` | 5.500 |
| `thu 450` | 450.000 kèm cờ `assumedThousands`, để giao diện hỏi lại "Hiểu là 450.000 ₫?" |
| `tip 10%`, `ngày 25/9`, `hẹn 7:30` | **không đọc** — số trần phải đứng riêng mới được coi là tiền |
| `450k, mã đơn hàng 12345`, `450k, SĐT 912.345.678`, `450k, SĐT 0912345678`, `đóng học phí năm học 2025 hết 5tr` | 450.000 / 450.000 / 450.000 / 5.000.000 — số có số 0 đứng đầu, số đứng sau nhãn mã ("mã đơn (hàng)", "số điện thoại", "số tài khoản", "số lượng", "SĐT", "STK"...; nhãn nhiều chữ, có thể kèm ":", "=", gạch nối hay "là": `mã đơn: 12345`, `mã đơn=12345`, `SĐT=+84912345678`), hay năm (`năm 2025`, `năm học 2025`, `năm tài chính 2025`, `tháng 9 năm 2025`, `quý 2 năm 2025`; còn `phí mỗi năm 2000`, `phí hai năm 2000`, `phí 2 năm 2000`, `chi phí năm nay 2000` là phí) là **mã/số điện thoại/năm**, không phải số tiền — kể cả khi có dấu chấm (`912.345.678`) hay đơn vị (`số lượng 2 nghìn`). Phần sau của một số điện thoại/mã viết cách cũng vậy, kể cả lẫn dấu chấm, dấu phẩy, gạch nối (cả các loại gạch trong văn bản đã định dạng: –, ‑, —, −): `0912 345 678`, `0912.345 678`, `0912-345 678`, `(024) 3825 2509`, `(024)-3825 2509`, `hotline 1900 - 1234` (gạch có dấu cách chỉ nối các nhóm ngắn 1–4 chữ số của một số điện thoại — có số 0 hay "+" đứng đầu, hay sau nhãn "SĐT", "hotline", "số điện thoại" — nên `SĐT 0912345678 - 450000`, `SĐT 0912345678 - 2500` vẫn đọc số tiền, và `mã đơn 12345 - 2500` đọc 2.500; sau chữ chỉ *có thể* là nhãn như "zalo", "điện thoại" thì phần nối bằng gạch có dấu cách vẫn có thể là số điện thoại nên không đọc: `zalo 912 - 345 - 678`), `+84 912.345.678`, `hotline 1900 1234`. Đứng một mình (`gọi 0912345678`, `mã đơn hàng 12345`, `năm 2025`) thì không đọc |
| `phòng 1204`, `số 12`, `đơn hàng 12345`, `điện thoại 912345678`, `code 12.345` | **không đọc** — có thể là mã (sau "phòng", "số", "đơn (hàng)", "điện thoại", "tài khoản", "code", "id"...), dù có dấu chấm ngàn. Nhưng vẫn **tính là một số tiền** khi đếm, vì cũng có thể là tiền: `đơn 450000, ship 30k` không đọc. Có "tiền", "giá", "phí", "thuê", "cọc", "tổng", "mua", "bán", "nạp", "thanh toán", "chốt", "hóa" đứng trước thì là số tiền: `tiền phòng 3.500.000` → 3.500.000, `chốt đơn 450000` → 450.000, `mua điện thoại 4500000` → 4.500.000. Có đơn vị thì luôn là tiền: `mua code 50k`, `phòng 450k` |
| `chi 1 triệu hai`, `1 triệu 2500`, `1 triệu 2 rưỡi` | **không đọc** (`nil`). Cụm số tiền đi tiếp theo cách không hiểu được thì bỏ cả câu, thay vì lưu thiếu "1 triệu" |
| `1 triệu 2500 đồng`, `1 triệu 2 đồng` | **không đọc** — trước chữ "đồng", phần đuôi có thể là đồng lẻ (1.000.002) hoặc nhóm tiếp theo (1.200.000) |
| `năm trăm nghìn`, `hai chục nghìn`, `hai muoi nghin` | **không đọc** — số tiền viết toàn bằng chữ (có dấu hay không); bỏ qua nó thì số tiền còn lại trong câu trông như số duy nhất và bị lấy nhầm |
| `3 x 150k`, `ba thùng x 150k`, `nam chai x 150k`, `150k/cái x 3`, `150k × 3`, `x2 450000` | **không đọc** — đơn giá nhân số lượng (dấu nhân ở bất kỳ đâu trong mệnh đề, số lượng ở bên nào của chữ x cũng được, có dấu hay không dấu); lưu 150.000 sẽ sai tổng. Chữ "X" hoa trong tên máy (`ốp iPhone X 150k`, `ốp Galaxy X2 150k`) vẫn đọc 150.000 |
| `ăn với 3 đồng nghiệp 450k`, `khám ba triệu chứng 150k`, `450k mua 3 đồng tiền cổ` | 450.000 / 150.000 / 450.000 — "đồng nghiệp", "triệu chứng", "đồng tiền", "tỷ lệ"... là danh từ, không phải tiền |
| `.5 triệu` | **không đọc** — thiếu số 0 đầu; đọc từ số 5 sẽ ra gấp mười |

**Sổ** — `LedgerMath`:
- Mỗi khoản nằm trong 1…999.999.999.999 ₫, giống giới hạn của bàn phím. Dữ liệu đọc từ bộ nhớ ngoài khoảng đó bị coi là hỏng; sửa số tiền phải qua `setAmount(_:)`, hàm này từ chối số ngoài khoảng. Nhờ vậy phép cộng không bao giờ tràn số.
- Cộng theo ngày, tháng, quý **theo lịch được truyền vào**. Ví dụ 00:30 ngày 25/09 giờ Việt Nam vẫn là 24/09 giờ UTC.
- Khoảng thời gian gồm điểm đầu, **không gồm** điểm cuối, nên không đếm trùng.
- Quý tính từ tháng, không dựa vào `dateInterval(of: .quarter)` của Foundation.

**Thuốc** — `Medication`, `DoseSchedule`, `DoseLog`:
- Chỉ lưu **điều đã xảy ra** (đã uống / bỏ qua / hoàn tác, lúc nào). Sắp tới / đến giờ / trễ đều suy ra từ đồng hồ, nên không có trạng thái nào bị "kẹt".
- Đến giờ rồi thì 30 phút sau thành **trễ**: đó là lúc báo cho người nhà.
- Một liều chờ trả lời tới khi **liều kế tiếp của cùng thuốc** đến giờ, lâu nhất 12 tiếng; sau đó là **không xác nhận** (tính là không uống) và màn hình chuyển sang liều mới: "ĐÃ UỐNG" lúc 12:00 là cho viên trưa, không phải viên sáng. Liều 21:00 chưa trả lời vẫn được hỏi sau nửa đêm (`DoseSchedule.waiting`).
- Mọi máy trong nhà dùng **lịch của cha mẹ** (`calendar`): người con ở nước ngoài vẫn thấy 07:00 của mẹ là 07:00, đúng ngày của mẹ. Ngày đổi giờ mùa hè, giờ bị nhảy qua thì dời tới ngay sau bước nhảy (không bao giờ sang ngày khác, hay mất hẳn nếu bước nhảy kết thúc ngày), và hai giờ uống rơi vào cùng một thời điểm thì chỉ còn một liều.
- Thuốc có `startDate` / `endDate`: thêm thuốc lúc 09:41 thì liều 07:00 sáng nay không bị tính là bỏ lỡ; đợt kháng sinh 7 ngày hết đợt là thôi.
- Ghi lại cùng một liều thì câu trả lời **mới nhất** thắng, kể cả khi bản ghi cũ đồng bộ về muộn. So theo **giây** (mỗi nơi lưu một độ chính xác, ít nhất tới giây); cùng một giây thì đã uống > bỏ qua > hoàn tác, nên máy nào cũng ra cùng kết quả. Trên cùng một máy, câu trả lời mới luôn thay câu cũ: được đóng dấu sau nó **ít nhất một giây**, kể cả khi đồng hồ đứng yên hay lùi, nên nơi lưu cắt hay làm tròn giây cũng không đảo thứ tự. Bản ghi có ngày không phải số hay vô cực (ở liều hoặc lúc ghi) thì bị bỏ, như nhau trên mọi máy; mọi ngày khác được tính như một đồng hồ sai (đặt năm 2099, hay xa hơn nữa), và trả lời trên máy vẫn thay được nó.
- **Hoàn tác được lưu như một câu trả lời** (`.cleared`): nó đồng bộ sang máy khác, và bản ghi cũ về muộn không làm liều "sống lại". Lưu và đồng bộ `log.records`, gồm cả hoàn tác.
- Tỉ lệ tuân thủ chỉ tính những liều đã "chốt" (đã trả lời hoặc hết 30 phút); buổi sáng chưa tới liều nào thì là "chưa có", không phải 0%.
- Giờ uống (`TimeOfDay`) được kiểm khi đọc từ bộ nhớ: 25:00 là dữ liệu hỏng, không phải giờ.

**Dọn ảnh** — `CleanupSession`, `FreeAllowance`, `StorageStatus`, `ByteSize`:
- Phiên vuốt chỉ **ghi lại quyết định**; ảnh chỉ bị xoá khi app gọi PhotoKit sau bước xem lại. Hoàn tác trả thẻ về đúng chỗ, và xoá luôn lựa chọn "giữ lại" của thẻ đó ở bước xem lại.
- Ảnh được giữ lại ở bước xem lại **vẫn nằm trong lưới**, để chọn lại được.
- Ảnh yêu thích và id trùng không bao giờ vào bộ thẻ (một id có bản ghi nào là yêu thích thì bỏ cả id đó).
- Ảnh đã xoá thật **rời khỏi phiên** (`remove(_:)`): không còn trong lưới, số đếm hay hoàn tác, nên không bị đề nghị xoá lần nữa. Tiến độ vẫn tính chúng (`seenCount` / `totalCount`): "12/48" không lùi thành "4/40", và thẻ cuối nói "Đã xoá 21 ảnh" thay vì "Bạn giữ lại tất cả".
- Lượt miễn phí chỉ tính **ảnh đã xoá thật**, không tính ảnh vuốt thử. `onDelete` ghi số ảnh vừa xoá vào lượt miễn phí **trước khi trả về**: chỉ app phân biệt được ảnh vừa xoá với ảnh đã mất từ trước, và màn xem lại đọc lại lượt còn lại ngay khi nó trả về, nên không bao giờ xoá quá số lượt còn lại.
- Đọc lượt miễn phí từ bộ nhớ: chỉ nhận đúng thứ app đã ghi (số nguyên không âm). Mọi thứ khác (số âm, số lẻ, số quá lớn, NaN, thiếu, `null`, sai kiểu) là dữ liệu hỏng: **coi như đã hết lượt**, không bao giờ cấp lại 100 lượt hay thành không giới hạn, và không làm app dừng. Không đọc được cả khối dữ liệu thì cũng vậy: `FreeAllowance(used: .max)`.
- Dung lượng theo **đơn vị thập phân** như Cài đặt của iOS (1 GB = 1.000.000.000 byte), dấu phẩy thập phân kiểu Việt: "1,2 GB", "350 MB". Làm tròn lên tới 1.000 thì chuyển đơn vị: "1 GB", không phải "1000 MB".

**Gói** — `PlanMath`:
- Giá quy đổi theo tháng, % tiết kiệm **làm tròn xuống** để không hứa quá mức.
- Tính bằng `Decimal`, nên 20% ra đúng 20, không ra 19.

---

## 3. Dùng trong app-idea-lab

Hai repo đều **private**. Cách chắc chắn nhất là **chép** (giống web kit), vì CI của repo app không cần quyền đọc repo này:

1. Chép `ios/IdeaLabKit/` vào repo app, ví dụ `Packages/IdeaLabKit/`.
2. Trong Xcode: **File → Add Package Dependencies → Add Local…** → chọn thư mục đó → thêm `IdeaLabUI` (kéo theo `IdeaLabCore`).
3. Ở gốc app:

```swift
import IdeaLabUI

@main
struct SoThuChiApp: App {
    @AppStorage("largeText") private var largeText = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .labTheme(largeText ? LabTheme(palette: .ledger, density: .senior) : .ledger)
        }
    }
}
```

4. Dùng màn hình mẫu, thay `LedgerSamples` bằng dữ liệu thật (SwiftData, file...). Xem `IdeaLabDemo/IdeaLabDemo/DemoScreens.swift` để biết cách nối sheet, toast và hoàn tác.
5. Truyền **cùng một `calendar`** (lịch của sổ) cho mọi màn hình mẫu: `LedgerHomeScreen`, `QuickEntryScreen`, `LedgerReportScreen`. Ngày trong sổ được gom và hiển thị theo lịch này, không theo múi giờ của máy; nếu mỗi màn một lịch, khoản ghi lúc nửa đêm có thể rơi sang ngày khác.
   App nhắc thuốc cũng vậy, với **lịch của cha mẹ** trên mọi máy. Thêm nữa: truyền `now` từ `TimelineView(.everyMinute)` để liều tự chuyển đến giờ / trễ; khi thêm thuốc đặt `startDate` là lúc thêm; hoàn tác bằng `DoseLog.undo(_:at:)`.
6. App dọn ảnh: `CleanupItem.id` là `PHAsset.localIdentifier`. Màn hình mẫu nhận ảnh qua closure, còn việc xoá thì giao cho PhotoKit, iOS sẽ tự hỏi xác nhận:

```swift
CleanupSwipeScreen(session: $session) { item in
    PhotoThumbnail(id: item.id)  // PHCachingImageManager, .resizable().scaledToFill()
} onReview: { showReview = true }

CleanupReviewScreen(session: $session, allowance: allowance) { item in
    PhotoThumbnail(id: item.id)
} onDelete: { items in
    await delete(items)
} onUnlock: { showPaywall = true }

/// Id các ảnh không còn trong thư viện: vừa xoá, hoặc đã mất từ trước.
func delete(_ items: [CleanupItem]) async -> Set<CleanupItem.ID> {
    let ids = items.map(\.id)
    let existing = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).count
    do {
        // Chỉ đưa id (Sendable) vào khối thay đổi, không đưa PHFetchResult.
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil))
        }
    } catch {
        return []  // người dùng bấm "Không cho phép", hoặc lỗi: chưa xoá gì
    }
    allowance.use(existing)  // chỉ đếm ảnh vừa xoá thật, và trước khi trả về
    return Set(ids)
}
```

Muốn nhận cập nhật tự động thì dùng **package từ xa**. SwiftPM đòi `Package.swift` ở **gốc repo**, nên cần thêm một manifest ở gốc trỏ `path:` vào `ios/IdeaLabKit/Sources/...`, rồi cấp cho CI của app một token đọc được repo này. Chưa làm ở đây vì chép đơn giản hơn cho một người làm.

Mỗi file trong `IdeaLabUI` đều bọc `#if os(iOS)`, nên package build được trên macOS/Linux (phần UI thành rỗng) và `swift test` chạy được ở mọi nơi.

---

## 4. Chạy, test, chụp ảnh

```bash
cd ios/IdeaLabKit && swift test          # test lõi: macOS hoặc Linux, Swift 6
open ios/IdeaLabDemo/IdeaLabDemo.xcodeproj   # chạy app gallery (Xcode 26+)
ios/scripts/render-previews.sh           # chụp mọi màn hình vào ios/previews/ (cần Xcode)
```

- **Project demo** sinh bằng [XcodeGen](https://github.com/yonaskolb/XcodeGen) từ `IdeaLabDemo/project.yml`, và file `.xcodeproj` được commit sẵn. Sửa `project.yml` thì chạy `xcodegen generate` trong thư mục đó rồi commit cả hai.
- **App demo mở thẳng một màn hình** khi chạy với `-screen <id>`. Ví dụ `-screen ledger-home` — danh sách id nằm trong `DemoScreen`. Giờ và dữ liệu cố định (09:41, 25/09/2026, giờ Việt Nam), nên ảnh chụp giữa các lần so sánh được với nhau.
- **CI** (`.github/workflows/ios.yml`) chỉ chạy khi `ios/**` đổi:
  - Job Linux chạy test lõi.
  - Job macOS build app demo cho iOS Simulator, vì phần SwiftUI chỉ biên dịch được trên macOS.
  - Phút macOS đắt gấp ~10 lần Linux ([GitHub](https://docs.github.com/en/billing/reference/actions-runner-pricing)), nên có lọc đường dẫn và huỷ lần chạy cũ khi có push mới.
- **Chụp ảnh** (`.github/workflows/ios-previews.yml`) chỉ chạy khi gọi: gắn nhãn `ios-previews` vào PR, hoặc bấm tay trong tab Actions.
  - Chia hai job: `render` chạy code của PR với token **chỉ đọc** và tải ảnh lên dạng artifact; `publish` không chạy code nào của PR, chỉ đẩy ảnh lên nhánh `ios-previews` để xem ngay trên GitHub (bỏ qua với PR từ fork).
  - Mỗi lần chạy mất ~4 phút macOS.

## Ảnh chụp

Chụp từ simulator iPhone 17 Pro (iOS 26.5, Xcode 26.6) bằng workflow **iOS previews**, dữ liệu mẫu cố định lúc 09:41 ngày 25/09/2026.

| Trang chủ sổ | Nhập nhanh 10 giây | Báo cáo tháng/quý | Paywall |
| --- | --- | --- | --- |
| <img src="docs/screenshots/ledger-home.light.png" width="200" alt="Trang chủ sổ thu chi: lãi hôm nay, biểu đồ tháng, hai nút Thu và Chi"> | <img src="docs/screenshots/ledger-entry.light.png" width="200" alt="Sheet nhập nhanh: công tắc Thu/Chi, số tiền, ghi chú, bàn phím số"> | <img src="docs/screenshots/ledger-report.light.png" width="200" alt="Báo cáo: lãi tháng, tổng thu, tổng chi, biểu đồ theo ngày"> | <img src="docs/screenshots/paywall.light.png" width="200" alt="Paywall: lợi ích, gói năm tiết kiệm 36%, điều khoản, nút dùng thử"> |

| Chế độ tối | Chữ cực lớn (AX-L) | Giới thiệu | Cài đặt |
| --- | --- | --- | --- |
| <img src="docs/screenshots/ledger-home.dark.png" width="200" alt="Trang chủ sổ ở chế độ tối"> | <img src="docs/screenshots/ledger-home.large-text.png" width="200" alt="Trang chủ sổ ở cỡ chữ trợ năng lớn"> | <img src="docs/screenshots/onboarding.light.png" width="200" alt="Màn hình giới thiệu: ghi sổ trong 10 giây"> | <img src="docs/screenshots/settings.light.png" width="200" alt="Cài đặt: gói, chữ lớn, dữ liệu, hỗ trợ"> |

| Dọn ảnh: trang chủ | Vuốt giữ/xoá | Xem lại trước khi xoá | Xong |
| --- | --- | --- | --- |
| <img src="docs/screenshots/cleaner-home.light.png" width="200" alt="Trang chủ dọn ảnh: vòng dung lượng, 3,3 GB có thể giải phóng, nên dọn trước ảnh chụp màn hình, còn 12 ảnh xoá miễn phí"> | <img src="docs/screenshots/cleaner-swipe.light.png" width="200" alt="Vuốt giữ hoặc xoá: tiến độ 12/48, thẻ ảnh chụp màn hình với hai thẻ ló phía sau, nút Xoá, Hoàn tác, Giữ"> | <img src="docs/screenshots/cleaner-review.light.png" width="200" alt="Xem lại: 21 ảnh, 23,9 MB, lưới ảnh sẽ xoá có hai ảnh giữ lại, nút mở khoá và nút xoá 12 ảnh đầu tiên"> | <img src="docs/screenshots/cleaner-done.light.png" width="200" alt="Xong: đã dọn 21 ảnh, 23,9 MB, lời giải thích về Đã xoá gần đây và nút mở ứng dụng Ảnh"> |

Toàn bộ 38 ảnh (thêm chế độ tối, chữ lớn, màn màu & thành phần) nằm ở nhánh `ios-previews` sau mỗi lần chạy workflow.

## 5. Lộ trình

1. **Nhắc thuốc, phần còn lại**: màn thêm thuốc (chọn hình/màu viên, giờ uống), thông báo `timeSensitive` cho người nhà, và giao diện riêng cho Assistive Access (scene `AssistiveAccess`, iOS 26+).
2. **Dọn ảnh, phần còn lại**: nhóm ảnh gần giống (gợi ý giữ tấm nét nhất), và nối `CleanupItem` với PhotoKit + Vision trong app thật.
3. Đọc lại số tiền bằng giọng nói sau khi lưu (kiểu loa MoMo), và test ảnh chụp giao diện (snapshot) trong CI.
