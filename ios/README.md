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

- **Apple Health › Thuốc** (iOS 16+): cho chọn hình dạng và màu viên thuốc ([TidBITS](https://tidbits.com/2022/10/07/an-apple-a-day-ios-16-medications-feature-provides-alerts-logging-and-peace-of-mind/)), nhắc lại nếu 30 phút sau chưa ghi nhận, và cho bật Critical Alerts cho từng thuốc: lời nhắc vẫn hiện và kêu khi máy đang tắt tiếng hay bật Tập trung ([Apple](https://support.apple.com/guide/iphone/track-your-medications-iph811670c81/ios)).
- **Medisafe "Medfriend"**: người thân nhận thông báo khoảng 30 phút sau liều bị lỡ.
- **Mức ngắt quãng của thông báo** (iOS 15+, [HIG](https://developer.apple.com/design/human-interface-guidelines/managing-notifications)):
  - **Time Sensitive** ("Nhạy cảm thời gian"): thông tin cần người nhận chú ý ngay. Người dùng có thể cho loại này đi xuyên chế độ Tập trung và bản tóm tắt theo lịch.
  - Apple chỉ cho dùng mức này khi việc đang xảy ra hoặc sẽ xảy ra trong vòng một giờ, và **không bao giờ** cho quảng cáo. Lần đầu nhận, iOS giải thích và cho người dùng tắt; về sau iOS còn định kỳ hỏi lại.
  - App cần bật capability Time Sensitive Notifications ([WWDC21](https://developer.apple.com/videos/play/wwdc2021/10091/)).
  - **Critical** (kêu cả khi máy tắt tiếng) cần entitlement riêng xin từ Apple ([Apple](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.usernotifications.critical-alerts)). HIG gọi loại này là "cực hiếm", thường đến từ cơ quan nhà nước hay app giúp quản lý sức khoẻ, nhà cửa.
  - Mỗi app chỉ hẹn trước được **64** thông báo cùng lúc (kỹ sư Apple trả lời trên [diễn đàn](https://developer.apple.com/forums/thread/811171)).
- **Người lớn tuổi**:
  - Nghiên cứu trên 40 người cao tuổi thấy nút **14–17,5 mm** dễ bấm nhất ([Leitão & Silva 2012](http://shura.shu.ac.uk/7446/)), tức khoảng 84–105 pt trên iPhone.
  - Mức tương phản 4,5:1 của WCAG được tính cho thị lực ~20/40, "thị lực điển hình của người ~80 tuổi" ([W3C](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)).
- **Assistive Access** (chế độ giản lược của iOS, cho người khuyết tật nhận thức):
  - Từ iOS 17: khai `UISupportsFullScreenInAssistiveAccess` để giao diện thường của app chạy toàn màn hình trong chế độ này ([Apple](https://developer.apple.com/documentation/bundleresources/information-property-list/uisupportsfullscreeninassistiveaccess)).
  - Từ iOS 26: khai `UISupportsAssistiveAccess` ([Apple](https://developer.apple.com/documentation/bundleresources/information-property-list/uisupportsassistiveaccess)) và thêm scene `AssistiveAccess` để dựng giao diện riêng cho chế độ này ([Apple](https://developer.apple.com/documentation/swiftui/assistiveaccess)).
    - Trong scene đó, control SwiftUI chuẩn (nút, danh sách, tiêu đề) tự đổi sang kiểu to, rõ của chế độ, theo bố cục lưới hay hàng người dùng chọn.
    - Nút Quay lại của hệ thống đi ngược theo navigation stack của app.
    - `assistiveAccessNavigationIcon` đặt một icon cạnh tiêu đề.

    Nguồn: [WWDC25, "Customize your app for Assistive Access"](https://developer.apple.com/videos/play/wwdc2025/238/).
  - Nguyên tắc Apple nêu trong phiên đó:
    - chỉ giữ một hai chức năng chính, và ít lựa chọn mỗi lúc;
    - control hiện rõ, không cử chỉ ẩn;
    - **không có gì tự đổi hay biến mất sau một khoảng thời gian**;
    - đi từng bước;
    - chữ đi kèm hình;
    - hỏi lại trước việc khó hoàn tác.
  - Từ iOS 18: `accessibilityAssistiveAccessEnabled` cho biết chế độ đang bật ([Apple](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityassistiveaccessenabled)).

**→ Trong kit:**
- `LabDensity.senior`: nút chính cao 96 pt, nút thường 60 pt, và giữ cỡ chữ tối thiểu `xLarge` dù máy để chữ nhỏ.
- Màn hình của cha mẹ (`MedsTodayScreen`): **một** liều mỗi lúc, vẽ đúng hình và màu viên thuốc, một nút "ĐÃ UỐNG" thật to. Nút "Không uống liều này" chỉ là chữ, không nền, đặt tách dưới nút chính để khỏi bấm nhầm (vùng bấm vẫn rộng, cho tay run). Hoàn tác thuộc về app (demo dùng toast "Hoàn tác"), ghi bằng `DoseLog.undo(_:at:)`. Bấm xong, thẻ hiện "Đã uống …" **2 giây** rồi mới tới thuốc kế tiếp: tay run bấm đúp cũng không đánh dấu nhầm một viên chưa uống.
- Màn hình của người con (`CaregiverScreen`): trả lời "mẹ uống thuốc chưa?" trong một cái liếc. Chỉ khi có liều trễ quá 30 phút màn hình mới chuyển vàng và hiện nút "Gọi Mẹ".
- Thông báo (`DoseAlerts` lập kế hoạch, `DoseNotifications` hẹn với iOS ở mức Time Sensitive):
  - Máy cha mẹ nhắc lúc đến giờ, rồi "Nhắc lại" khi hết 30 phút mà chưa bấm ĐÃ UỐNG, như Apple Health.
  - Máy người nhà nhận "Mẹ chưa xác nhận thuốc lúc 07:00" đúng lúc màn hình của người con chuyển vàng. Loại này mới thật cần đi xuyên Tập trung (khi người con cho phép): đang họp vẫn biết.
  - Hai viên cùng giờ chỉ reo một lần. Trả lời ở máy nào thì thông báo về liều đó cũng rời màn hình khoá, khi app lập lại kế hoạch.
  - Máy người nhà chỉ biết những gì máy cha mẹ đã gửi, nên báo nói "chưa xác nhận" chứ không nói "chưa uống", và kèm "Máy của Mẹ cập nhật lần cuối lúc 06:58". Máy mẹ mất mạng thì người con thấy ngay tin đã cũ.
  - Kit chưa dùng Critical Alerts vì cần Apple cấp riêng. App thật có thể xin thêm cho lời nhắc của cha mẹ, như Apple Health.
- Người con biết khi máy mình sẽ **không** báo. `CaregiverScreen` có một thẻ cho từng trường hợp, kèm nút bật hay mở Cài đặt:
  - "Nhận báo khi Mẹ quên thuốc": chưa hỏi quyền.
  - "Thông báo đang tắt".
  - "Báo quên thuốc có thể đến muộn": thông báo được giao lặng lẽ, biểu ngữ đang tắt, hay "Nhạy cảm thời gian" đang tắt hoặc không có (app thiếu capability), nên Tập trung có thể giữ báo lại.

  Trước khi iOS hỏi quyền, `PermissionPrimerScreen` cho xem **chính thông báo** sẽ nhận (`DoseAlertBanner`, chữ lấy từ `DoseAlerts`).
- Màn của cha mẹ trong Assistive Access (`MedsAssistiveScreen`, cho scene `AssistiveAccess`) đi **mỗi lúc một bước**:
  - Trước hết là viên thuốc, tên, giờ uống, và một nút ĐÃ UỐNG.
  - Bấm xong thì màn hình hiện "Đã uống …" và **đứng yên** tới khi người dùng bấm "Thuốc tiếp theo" hay rời app. Màn thường thì tự chuyển sau 2 giây; chế độ này không cho gì tự đổi theo thời gian.
  - Không có "Không uống liều này" hay hoàn tác, cho bớt một lựa chọn. Liều không uống thì cứ để đó, người nhà vẫn thấy.
  - "Thuốc tiếp theo" nằm trong thẻ, không ở chỗ nút ĐÃ UỐNG vừa đứng: bấm đúp không trả lời nhầm viên sau.
  - Nút là nút của kit (cao 96 pt, có hình và chữ). Kiểu riêng của chế độ này chỉ áp cho control mặc định, còn nút của kit vốn đã đủ to và rõ ở mọi nơi.
- Màn thêm thuốc (`AddMedicationScreen`), cho người con thiết lập: tên cả nhà vẫn gọi, liều và cách uống (chạm một lần: "1 viên", "Sau ăn"...), **hình và màu viên** như trên vỉ thuốc (viên nang hai màu), giờ uống bật/tắt nhanh "Sáng / Trưa / Chiều / Tối" hoặc chọn giờ khác trên bánh xe (như đặt báo thức trong app Đồng hồ: danh sách chỉ đổi khi bấm "Xong", không nhảy chỗ khi đang xoay), và "Lâu dài" hay "Số ngày" (ghi rõ "Uống đến hết Thứ Năm, 8/10, tính cả hôm nay"). Viên thuốc được vẽ ngay ở đầu màn, đúng như cha mẹ sẽ thấy. Nút Lưu nói rõ còn thiếu gì thay vì chỉ mờ đi.
- Sửa thuốc đang dùng (cùng màn đó, `AddMedicationScreen(editing:in:)`, mở từ "Thuốc của Mẹ" ở cuối màn của người con):
  - Đổi giờ, liều hay cách uống thì **áp dụng từ ngày mai**, và màn hình nói rõ trước khi lưu: "Giờ, liều và cách uống mới áp dụng từ Thứ Bảy, 26/9. Hôm nay vẫn uống như cũ."
  - Thuốc chưa tới ngày bắt đầu thì **giữ ngày bắt đầu đã hẹn**, không bắt đầu sớm hơn: "Giờ, liều và cách uống mới áp dụng từ Thứ Năm, 1/10, ngày thuốc bắt đầu." Số ngày uống của thuốc đó tính từ ngày bắt đầu: "Uống từ Thứ Năm, 1/10 đến hết Thứ Bảy, 3/10."
  - Hôm nay và những ngày trước giữ nguyên lịch và câu trả lời. Đổi ngay giữa ngày thì phải đoán liều sáng nay ứng với giờ mới nào, và có thể nhắc uống thêm một viên đã uống rồi.
  - Đổi tên, hình viên hay số ngày thì sửa ngay, kể cả khi đổi cùng lúc với giờ hay liều. Đợt thuốc giữ ngày cuối dù form mở qua nửa đêm.
  - Đợt thuốc hết hôm nay thì giờ, liều hay cách uống mới không còn ngày nào để áp dụng. Nút Lưu nói rõ điều đó và chờ đợt thuốc được kéo dài, chứ không lưu phần còn lại rồi bỏ thay đổi đó đi.
  - Form để mở qua nửa đêm mà ngày cuối đã qua thì nút Lưu nói rõ lý do không lưu được, chứ không nói "Chưa có gì thay đổi": thuốc đã hết đợt, hoặc ngày cuối đã chọn đã qua và cần chọn lại số ngày.
  - "Ngừng thuốc" (có hỏi lại) dừng từ bây giờ: không nhắc thêm, kể cả liều đang chờ. Liều đó tính là không uống. Thuốc đã hết đợt thì không còn gì để ngừng: nút mờ đi, và không có lần ngừng nào được ghi.
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
- **Ảnh gần giống nhau** (`SimilarPhotosScreen`): mỗi khoảnh khắc chụp nhiều lần là một thẻ, **hiện đủ mọi tấm** và không làm mờ tấm nào, để còn so với nhau. Tấm nét nhất và ảnh yêu thích được giữ sẵn, các tấm còn lại được đánh dấu xoá. Chạm để giữ hay bỏ, hoặc "Giữ cả nhóm". Mỗi nhóm luôn giữ lại ít nhất một tấm.
- **Không xoá ảnh người dùng chưa thấy.** Dấu xoá ở màn ảnh gần giống là gợi ý của máy, nên nút xoá chỉ lấy những tấm **đã hiện trên màn hình** ("Xoá 4 ảnh đã xem · 11,1 MB"). Thanh xoá nhắc "Cuộn để xem nốt 12 ảnh sẽ xoá", nên nhóm chưa cuộn tới thì chưa bị xoá.
  - Một tấm tính là đã thấy khi **phần giữa** của nó nằm trong vùng không bị che (dưới thanh điều hướng, trên thanh xoá) **ít nhất 0,3 giây liền**, giống cách tính quảng cáo "đã được xem".
  - "Đã vẽ" thì chưa đủ: danh sách lười vẽ sẵn cả những tấm nằm sau thanh xoá và quá mép màn hình một chút.
  - Hiện lên một khoảnh khắc cũng chưa đủ: một lượt dàn trang có thể đưa tấm ảnh vào khung trong một khung hình, và vuốt mạnh thì ảnh lướt qua nhanh hơn mắt kịp nhìn.
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
| `.labToast` | Có Hoàn tác. Khi VoiceOver bật, toast **được đọc và không tự biến mất** (WCAG 2.2.1). Toast nằm **phía trên** các nút màn hình ghim ở đáy, không bao giờ che chúng: mọi thanh nút ghim ở đáy trong kit (Thu/Chi, Lưu, ĐÃ UỐNG ở cỡ chữ lớn, nút xoá ảnh, paywall...) đều gọi `labBottomBar()`, và màn hình tự làm nên làm theo |
| `labGlass`, `labCard`, `LabSectionHeader`, `SettingsIcon` | Bề mặt và tiêu đề |
| `PillView` | Viên thuốc vẽ đúng hình (tròn có vạch bẻ, bầu dục, dài, viên nang hai màu) và màu, có viền để viên trắng vẫn hiện trên nền trắng; VoiceOver đọc "viên nang cam và kem" |
| `DoseStatusBadge`, `DoseRow` | Trạng thái liều bằng chữ + màu + icon: "Đã uống 07:12", "Đến giờ uống", "Trễ 2 giờ 41 phút" (nền hổ phách, chữ tối), "12:00" |
| `DoseAlertBanner` | Một thông báo thuốc vẽ như trên điện thoại (icon app, tiêu đề đậm, nội dung), chữ lấy từ `DoseAlerts`: ví dụ cho màn xin quyền |
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
| `MedsAssistiveScreen` | Nhắc thuốc, phía cha mẹ trong Assistive Access (scene `AssistiveAccess`, iOS 26). Mỗi lúc một bước, không có gì đổi theo thời gian, mọi nút có hình và chữ, tiêu đề có icon (`assistiveAccessNavigationIcon`). Nút ĐÃ UỐNG ghim ở đáy; sau khi bấm, đáy để trống và nút "Thuốc tiếp theo" nằm trong thẻ |
| `MedsTodayScreen` | Nhắc thuốc, phía cha mẹ: lời chào theo buổi, liều đang chờ (to, có hình viên thuốc), nút "ĐÃ UỐNG", danh sách thuốc hôm nay. Liều 21:00 chưa trả lời vẫn được hỏi sau nửa đêm ("21:00 hôm qua"). Hết liều chờ thì nói rõ "Chưa đến giờ" và liều kế tiếp, không để màn hình trống; "Chúc ngủ ngon" chỉ khi đã tối. Ở cỡ chữ trợ năng, nút "ĐÃ UỐNG" được ghim ở đáy màn hình dưới tên thuốc nó trả lời, nên không bao giờ bị thẻ thuốc đẩy khuất; lời chào khi đó chỉ còn cho VoiceOver, và thẻ thuốc có sẵn hai thao tác trả lời cho VoiceOver |
| `CaregiverScreen` | Nhắc thuốc, phía người con: "Đã uống 1/3 liều đến giờ", "Cập nhật 07:00" theo lúc dữ liệu từ máy cha mẹ về thật (không theo đồng hồ), thẻ cảnh báo cho từng liều trễ (Gọi / Nhắc lại — nhắc xong nút thành "Đã nhắc lúc 08:42" trong 10 phút, bấm đúp không reo máy cha mẹ hai lần; app giữ `remindedAt`, nên đóng rồi mở lại màn hình cũng không reo lại), dòng thời gian hôm nay, vòng tuân thủ 7 ngày. Có `onAdd` / `onEdit` thì cuối màn có "Thuốc của Mẹ": các thuốc đang dùng, kèm "Thay đổi từ Thứ Bảy, 26/9", "Bắt đầu từ …" hay "Đến hết Thứ Năm, 1/10", chạm để sửa. Nhận `alerts` (`DoseNotifications.access()`): khi máy này chưa bật thông báo, đã tắt, hay để Tập trung giữ báo lại, một thẻ dưới các liều trễ nói rõ và có nút bật hay mở Cài đặt (không màu hổ phách: màu đó chỉ dành cho liều trễ) |
| `AddMedicationScreen` | Nhắc thuốc, thêm thuốc: xem trước viên thuốc, tên, liều + cách uống (có gợi ý một chạm), hình dáng và màu (viên nang hai màu), giờ uống (gợi ý bật/tắt + bánh xe trong sheet, xác nhận bằng "Xong"; giờ đã có thì không xác nhận được và được nói rõ), "Lâu dài" hay "Số ngày" kèm ngày cuối. Thuốc bắt đầu tính từ lúc lưu; lưu đúng một lần. `init(editing:in:)` là "Sửa thuốc": trả về danh sách thuốc đã đổi theo `MedicationChanges`, nói trước thay đổi áp dụng từ khi nào, có "Ngừng thuốc" |
| `CleanerHomeScreen` | Dọn ảnh: vòng dung lượng, "Nên dọn trước: Ảnh chụp màn hình · 1,7 GB" + nút Bắt đầu, số ảnh miễn phí còn lại, danh sách nhóm ảnh, dòng quyền riêng tư. Có trạng thái đang quét (hiện dần những gì đã tìm thấy) và trạng thái "đã gọn gàng" |
| `CleanupSwipeScreen` | Tiến độ "12/48", số ảnh và dung lượng sẽ xoá, bộ thẻ vuốt; hết thẻ thì mời "Xem lại trước khi xoá" |
| `CleanupReviewScreen` | Lưới ảnh sẽ xoá, chạm để giữ lại; nút xoá ghi rõ số ảnh và dung lượng; khi số ảnh chọn vượt số lượt miễn phí còn lại thì tách hai lựa chọn: xoá những ảnh đầu tiên trong lưới mà lượt miễn phí còn đủ ("Xoá 12 ảnh đầu tiên · 14 MB"), hoặc mở khoá. `onDelete` (async) gọi PhotoKit, iOS tự hỏi xác nhận, ghi số ảnh vừa xoá vào lượt miễn phí, rồi trả về id các ảnh không còn trong thư viện để chúng rời khỏi phiên; các nút khoá tới khi nó trả về nên bấm đúp không hỏi hai lần |
| `SimilarPhotosScreen` | Ảnh gần giống: mỗi khoảnh khắc là một thẻ ("5 ảnh · Thứ Tư, 23/9 · 19:12", giờ viết theo ngôn ngữ của máy: "7:12 PM" bằng tiếng Anh), đủ mọi tấm trong lưới. Tấm nét nhất có biểu tượng ✦ ở góc (dòng đầu màn hình giải thích biểu tượng này, VoiceOver đọc là "nét nhất"); tấm giữ có viền xanh và chữ "Giữ"; tấm sẽ xoá có dấu đỏ như lưới xem lại. Ở cỡ chữ trợ năng, lưới còn hai cột và ghi chú về việc xoá nằm sau các nhóm, để ảnh hiện ra sớm. Chạm để giữ hay bỏ; "Giữ cả nhóm", và "Gợi ý lại" khi gợi ý có bỏ tấm nào. Chạm vào ảnh yêu thích, hay tấm giữ cuối cùng của nhóm, thì màn hình nói lý do ngay dưới nhóm, kèm rung và lời đọc cho VoiceOver; gợi ý VoiceOver của hai tấm đó cũng nói trước lý do. Nút xoá **chỉ lấy ảnh đã hiện trên màn hình** ("Xoá 4 ảnh đã xem · 11,1 MB"), kèm dòng "Cuộn để xem nốt 12 ảnh sẽ xoá"; lượt miễn phí và `onDelete` giống `CleanupReviewScreen`. Các nhóm được vẽ dần khi cuộn tới, nên hàng nghìn nhóm vẫn mượt |
| `CleanupDoneScreen` | "Đã dọn 21 ảnh", số dung lượng lớn, lời giải thích về Đã xoá gần đây và nút mở ứng dụng Ảnh |
| `OnboardingScreen` | 3–4 trang, luôn có "Bỏ qua" |
| `PermissionPrimerScreen` | Giải thích **trước** khi iOS hỏi quyền; hộp thoại hệ thống chỉ hiện được một lần. Có chỗ cho một ví dụ (`example:`), như thông báo thật sẽ nhận |
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

**Thuốc** — `Medication`, `MedicationDraft`, `MedicationChanges`, `DoseSchedule`, `DoseLog`:
- Chỉ lưu **điều đã xảy ra** (đã uống / bỏ qua / hoàn tác, lúc nào). Sắp tới / đến giờ / trễ đều suy ra từ đồng hồ, nên không có trạng thái nào bị "kẹt".
- Đến giờ rồi thì 30 phút sau thành **trễ**: đó là lúc báo cho người nhà.
- Một liều chờ trả lời tới khi **liều kế tiếp của cùng thuốc** đến giờ, lâu nhất 12 tiếng; sau đó là **không xác nhận** (tính là không uống) và màn hình chuyển sang liều mới: "ĐÃ UỐNG" lúc 12:00 là cho viên trưa, không phải viên sáng. Liều 21:00 chưa trả lời vẫn được hỏi sau nửa đêm (`DoseSchedule.waiting`).
- Mọi máy trong nhà dùng **lịch của cha mẹ** (`calendar`): người con ở nước ngoài vẫn thấy 07:00 của mẹ là 07:00, đúng ngày của mẹ. Ngày đổi giờ mùa hè, giờ bị nhảy qua thì dời tới ngay sau bước nhảy (không bao giờ sang ngày khác, hay mất hẳn nếu bước nhảy kết thúc ngày), và hai giờ uống rơi vào cùng một thời điểm thì chỉ còn một liều.
- Thuốc có `startDate` / `endDate`: thêm thuốc lúc 09:41 thì liều 07:00 sáng nay không bị tính là bỏ lỡ; đợt kháng sinh 7 ngày hết đợt là thôi.
- Ghi lại cùng một liều thì câu trả lời **mới nhất** thắng, kể cả khi bản ghi cũ đồng bộ về muộn. So theo **giây** (mỗi nơi lưu một độ chính xác, ít nhất tới giây); cùng một giây thì đã uống > bỏ qua > hoàn tác, nên máy nào cũng ra cùng kết quả. Trên cùng một máy, câu trả lời mới luôn thay câu cũ: được đóng dấu sau nó **ít nhất một giây**, kể cả khi đồng hồ đứng yên hay lùi, nên nơi lưu cắt hay làm tròn giây cũng không đảo thứ tự. Bản ghi có ngày không phải số hay vô cực (ở liều hoặc lúc ghi) thì bị bỏ, như nhau trên mọi máy; mọi ngày khác được tính như một đồng hồ sai (đặt năm 2099, hay xa hơn nữa), và trả lời trên máy vẫn thay được nó.
- **Hoàn tác được lưu như một câu trả lời** (`.cleared`): nó đồng bộ sang máy khác, và bản ghi cũ về muộn không làm liều "sống lại". Lưu và đồng bộ `log.records`, gồm cả hoàn tác.
- Tỉ lệ tuân thủ chỉ tính những liều đã "chốt" (đã trả lời hoặc hết 30 phút); buổi sáng chưa tới liều nào thì là "chưa có", không phải 0%.
- Giờ uống (`TimeOfDay`) được kiểm khi đọc từ bộ nhớ: 25:00 là dữ liệu hỏng, không phải giờ.
- Form thêm thuốc (`MedicationDraft`): tên và liều được cắt khoảng trắng, giờ uống luôn được sắp xếp và không trùng (đổi một giờ sang giờ đã có thì không đổi gì), thuốc bắt đầu tính từ lúc lưu. Đợt "N ngày" tính hôm nay là ngày thứ nhất và kết thúc ở cuối ngày thứ N theo lịch của cha mẹ, kể cả ngày đổi giờ mùa hè dài 25 tiếng.
- Sửa thuốc (`MedicationChanges`): mỗi `Medication` là một phiên bản của thuốc, các phiên bản cùng `seriesID`.
  - Đổi giờ, liều hay cách uống: phiên bản đang dùng kết thúc cuối hôm nay, phiên bản mới bắt đầu đầu ngày mai theo lịch của cha mẹ. Phiên bản chờ ngày mai của một lần sửa trước bị thay. Tên và hình viên đổi cùng lúc thì vẫn đổi ngay trên phiên bản đang dùng; phiên bản đã qua giữ tên cũ.
  - Thuốc chưa bắt đầu thì phiên bản mới giữ ngày bắt đầu đã hẹn (`Effect.fromPlannedStart`), không bao giờ sớm hơn. Số ngày của đợt thuốc tính từ `courseStart`: hôm nay khi thuốc đang dùng, hoặc ngày bắt đầu khi thuốc chưa bắt đầu. Vì vậy chọn "3 ngày" cho một thuốc hẹn tuần sau không làm đợt thuốc hết trước khi nó bắt đầu.
  - Đợt thuốc hết trước ngày phiên bản mới bắt đầu (với thuốc đang dùng là hết hôm nay) thì không còn ngày cho nó: không lưu gì (`Effect.noDayLeft`), kể cả tên hay hình đổi cùng lúc, để thay đổi không bị bỏ đi mà không ai biết.
  - Đổi tên, hình hay số ngày: sửa tại chỗ các phiên bản đang dùng hoặc sắp dùng, không đụng phiên bản đã qua.
  - Một liều chờ trả lời tới liều kế tiếp **của cùng thuốc**, dù liều đó thuộc phiên bản nào: viên 21:00 tối nay chờ tới viên sáng mai của phiên bản mới, không bị hỏi song song với nó.
  - `stopping` ghi `stoppedAt`: từ lúc đó không còn liều nào và không hỏi liều nào. Liều đang chờ thành không uống, lịch sử trước đó giữ nguyên. Mọi phiên bản đã bắt đầu đều ghi lúc ngừng, kể cả phiên bản vừa kết thúc đêm qua mà viên 21:00 còn đang chờ. Thuốc không còn dùng (`isInUse` sai: đã hết đợt hoặc đã ngừng) thì `stopping` trả lại danh sách như cũ, nên ngừng lần nữa không dời lúc ngừng.

**Thông báo thuốc** — `DoseAlerts`, `DoseAlertPlan`:
- Máy cha mẹ (`.parent`): một thông báo lúc đến giờ, và "Nhắc lại" lúc hết 30 phút (`DoseSchedule.grace`) mà chưa trả lời. Máy người nhà (`.family`): chỉ lúc đó, khi liều thành **trễ**, không bao giờ lúc đến giờ.
- Các liều cùng thời điểm chung **một** thông báo, kể cả liều vừa đến giờ và liều khác vừa trễ: "Đến giờ uống thuốc" kèm dòng "Nhắc lại thuốc lúc 07:00: …".
- Chỉ liều **chưa trả lời** mới có thông báo. Liều hết chờ trước khi kịp trễ (liều kế tiếp của cùng thuốc đến trước, hay thuốc bị ngừng) thì không có lời nhắc lại và không báo người nhà, đúng như màn hình của người con không chuyển vàng vì nó.
- Kế hoạch có hai phần:
  - `upcoming`: những thông báo cần hẹn, sớm nhất trước. Tối đa `limit` cái, mặc định 64 như giới hạn của iOS, và xa nhất tới 30 ngày sau hôm nay.
  - `current`: những thông báo đã tới giờ hiện mà vẫn đúng, với lời lẽ đúng lúc này. Trên máy cha mẹ là thông báo về liều còn chờ. Trên máy người nhà là báo về liều đã trễ mà chưa ai trả lời, từ hôm qua tới nay: tin đó ở lại cả khi màn hình của cha mẹ đã chuyển sang liều sau. Thông báo đã hiện mà không còn đúng (liều đã được trả lời ở một máy nào đó, hay lời nhắc của cha mẹ đã hết chờ) thì rời màn hình khoá.

  Thông báo tới giờ đúng lúc lập kế hoạch vẫn nằm trong `current`, nên không bị huỷ ngay trước khi hiện. Nếu một liều trong nó vừa được trả lời, `DoseNotifications` thay nó bằng lời lẽ mới, để nó không nhắc một viên đã uống. Thông báo đã hiện mà một liều trong đó vừa được trả lời, hay thuốc vừa đổi tên, cũng hiện lại với lời lẽ mới, nhưng lặng lẽ (mức `passive`: không kêu, không sáng màn hình), vì đó là tin cập nhật chứ không phải tin mới. Riêng dòng "cập nhật lần cuối" của người nhà đổi thì không tính (`DoseAlert.gist`): dòng đó đổi mỗi lần đồng bộ.
- Id cố định theo thời điểm: lập lại kế hoạch thì **thay** thông báo cũ chứ không thêm cái thứ hai. Mọi id bắt đầu bằng một `prefix` riêng cho vai trò và `scope` (ví dụ id của người được theo dõi). Vì vậy áp dụng kế hoạch của Mẹ không đụng thông báo của Bố, hay thông báo khác của app.
- Ngày giờ ghi trong thông báo theo **lịch của cha mẹ**, còn lúc thông báo hiện là một thời điểm tuyệt đối: người con ở nước ngoài vẫn nhận đúng lúc 07:30 của mẹ. `DoseNotifications` hẹn bằng khoảng thời gian chứ không bằng giờ đồng hồ, vì lịch hẹn theo giờ đồng hồ trôi theo múi giờ của máy.
- Máy người nhà chỉ biết những gì máy cha mẹ đã gửi. Báo ghi "chưa xác nhận", và khi có `updatedAt` thì thêm "Máy của Mẹ cập nhật lần cuối lúc 06:58". Tin cũ hơn thì ghi "21:03 hôm qua" hay "21:03 ngày 22/9".

**Dọn ảnh** — `CleanupSession`, `SimilarGrouping`, `SimilarReview`, `SeenOnScreen`, `FreeAllowance`, `StorageStatus`, `ByteSize`:
- Phiên vuốt chỉ **ghi lại quyết định**; ảnh chỉ bị xoá khi app gọi PhotoKit sau bước xem lại. Hoàn tác trả thẻ về đúng chỗ, và xoá luôn lựa chọn "giữ lại" của thẻ đó ở bước xem lại.
- Ảnh được giữ lại ở bước xem lại **vẫn nằm trong lưới**, để chọn lại được.
- Ảnh yêu thích và id trùng không bao giờ vào bộ thẻ (một id có bản ghi nào là yêu thích thì bỏ cả id đó).
- Ảnh đã xoá thật **rời khỏi phiên** (`remove(_:)`): không còn trong lưới, số đếm hay hoàn tác, nên không bị đề nghị xoá lần nữa. Tiến độ vẫn tính chúng (`seenCount` / `totalCount`): "12/48" không lùi thành "4/40", và thẻ cuối nói "Đã xoá 21 ảnh" thay vì "Bạn giữ lại tất cả".
- Lượt miễn phí chỉ tính **ảnh đã xoá thật**, không tính ảnh vuốt thử. `onDelete` ghi số ảnh vừa xoá vào lượt miễn phí **trước khi trả về**: chỉ app phân biệt được ảnh vừa xoá với ảnh đã mất từ trước, và màn xem lại đọc lại lượt còn lại ngay khi nó trả về, nên không bao giờ xoá quá số lượt còn lại.
- Đọc lượt miễn phí từ bộ nhớ: chỉ nhận đúng thứ app đã ghi (số nguyên không âm). Mọi thứ khác (số âm, số lẻ, số quá lớn, NaN, thiếu, `null`, sai kiểu) là dữ liệu hỏng: **coi như đã hết lượt**, không bao giờ cấp lại 100 lượt hay thành không giới hạn, và không làm app dừng. Không đọc được cả khối dữ liệu thì cũng vậy: `FreeAllowance(used: .max)`.
- **Ảnh gần giống** (`SimilarGrouping.groups`), xét theo thứ tự chụp: một ảnh vào nhóm khi chụp cách ảnh mới nhất của nhóm không quá 2 phút (tuỳ chỉnh) **và giống mọi ảnh trong nhóm**. "Giống nhau" do app đo trên máy, ví dụ khoảng cách giữa hai `VNFeaturePrintObservation` nhỏ hơn một ngưỡng.
  - Phải giống mọi ảnh, không chỉ ảnh cuối: nếu chỉ so với ảnh cuối, một lượt lia máy chậm sẽ nối những ảnh chẳng giống nhau vào một nhóm, và tấm được giữ không đại diện được cho tấm nào.
  - Chụp xen kẽ hai đối tượng vẫn ra hai nhóm. Mỗi ảnh được thử với tối đa 16 nhóm gần nhất (`openGroupLimit`): ảnh nhập cùng lúc có thể trùng giờ chụp cả nghìn tấm, và thử hết mọi nhóm thì thời gian tăng theo bình phương số ảnh. Nhóm chỉ có một ảnh thì bỏ qua.
  - Dữ liệu hỏng không làm sai nhóm: ngày chụp không phải số hữu hạn được coi là `Date.distantPast`, độ nét NaN được coi là mờ nhất.
- **Gợi ý giữ** (`SimilarGroup.suggestedKeep`): **tấm nét nhất và mọi ảnh yêu thích**. Độ nét do app đo, thang nào cũng được, miễn là cao hơn thì nét hơn. Bằng nhau thì chọn file lớn hơn, rồi tấm chụp trước. Nếu ảnh yêu thích mờ hơn, cả hai đều được giữ, nên gợi ý không bao giờ xoá tấm đẹp nhất.
- **`SimilarReview`**: ảnh yêu thích luôn được giữ, và **mỗi nhóm luôn giữ ít nhất một tấm**. Ảnh đã xoá thật rời khỏi nhóm; nhóm chỉ còn một tấm thì coi như xong. Nếu tấm đang giữ bị xoá ở nơi khác, nhóm quay về gợi ý mới thay vì đề nghị xoá hết phần còn lại.
  - Một ảnh có trong nhiều nhóm thì ở lại nhóm đầu tiên được giữ, và là ảnh yêu thích nếu bản ghi nào của nó là yêu thích, dù bản ghi đó nằm ở nhóm sau. Nhóm còn dưới hai tấm thì bị bỏ, và không lấy mất ảnh của các nhóm sau.
- **`SeenOnScreen`**: những mục đã hiện trên màn hình, tức là phần giữa đã nằm trong vùng không bị che đủ lâu (`dwell`, mặc định 0,3 giây). Rời khung thì tính lại từ đầu.
  - Khung của từng mục và vùng nhìn thấy đến theo thứ tự nào cũng được: khi vùng nhìn thấy đổi, các khung đã báo được xét lại.
  - Màn hình đứng yên thì không có khung mới nào báo về, nên `nextSettle` cho biết lúc nào cần gọi `settle(at:)`.
  - Khung chỉ được báo khi đổi, nên một mục không có khung mới từ lúc vào vùng nhìn là đã nằm yên ở đó. Khi nó rời đi, bị thanh xoá che, hay bị danh sách bỏ ra, thời gian nó đã nằm đủ vẫn được tính, dù lượt `settle` bị chậm.
  - Vùng nhìn rỗng (`.null`) thì không mục nào đang được xem. `SimilarPhotosScreen` dùng điều này khi app không ở trạng thái active (chạy nền, bị Trung tâm điều khiển hay hộp thoại hệ thống che): thời gian chờ dừng lại và tính lại từ đầu khi app quay lại, nên thời gian app nằm nền không bao giờ được tính.
  - Khung của mục đã rời danh sách thì bỏ, để không bị tính ở chỗ cũ. Đã thấy thì giữ nguyên.
- **Nút xoá chỉ xoá những gì nó đã đếm** (`CleanupMath.stillMarked`): những ảnh nút đếm lúc được vẽ, trừ ảnh đã bỏ đánh dấu trước cú chạm. Một cú chạm có thể tới trước khi nút kịp vẽ lại, nhưng "Xoá 4 ảnh" không bao giờ xoá tấm thứ năm, kể cả ảnh vừa được đánh dấu hay vừa được tính là đã xem. Áp dụng cho cả lưới xem lại và màn ảnh gần giống.
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
   App nhắc thuốc cũng vậy, với **lịch của cha mẹ** trên mọi máy. Thêm nữa: truyền `now` từ `TimelineView(.everyMinute)` để liều tự chuyển đến giờ / trễ; thêm thuốc bằng `AddMedicationScreen` (hoặc tự đặt `startDate` là lúc thêm); sửa hay ngừng bằng `AddMedicationScreen(editing:in:)` rồi lưu danh sách nó trả về (hoặc gọi `MedicationChanges`), không sửa thẳng `Medication` đang dùng; hoàn tác bằng `DoseLog.undo(_:at:)`.

   Thông báo thuốc: bật capability **Time Sensitive Notifications** trong Signing & Capabilities. Lập và áp dụng lại kế hoạch mỗi khi log hay danh sách thuốc đổi (câu trả lời từ máy khác, hoàn tác, sửa thuốc), và mỗi lần app chạy:

   ```swift
   let plan = DoseAlerts.plan(
       for: .family(personName: "Mẹ"), scope: mother.id.uuidString,
       medications: medications, log: log, now: .now, calendar: parentCalendar,
       updatedAt: lastSync  // lúc log từ máy mẹ về lần cuối
   )
   try await DoseNotifications.apply(plan)
   ```

   - Máy người nhà cần được đánh thức khi máy cha mẹ gửi câu trả lời, ví dụ bằng subscription CloudKit gửi silent push, để kịp rút báo trễ. Không thì báo vẫn đến, kèm dòng "cập nhật lần cuối" cho thấy tin đã cũ.
   - Đọc `DoseNotifications.access()` mỗi khi app trở lại foreground, rồi truyền cho `CaregiverScreen(alerts:onAlerts:)`.

   Assistive Access (iOS 26): khai `UISupportsAssistiveAccess` = YES trong Info.plist, rồi thêm scene. App vẫn chạy được từ iOS 17: `if #available` là cách `SceneBuilder` cho phép.

   ```swift
   var body: some Scene {
       WindowGroup { RootView() }
       if #available(iOS 26.0, *) {
           AssistiveAccess {
               NavigationStack {
                   TimelineView(.everyMinute) { context in
                       MedsAssistiveScreen(medications: medications, log: log, now: context.date,
                                           calendar: parentCalendar) { dose in record(.taken, dose) }
                   }
               }
               .labTheme(.meds)
           }
       }
   }
   ```
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

// Ảnh gần giống: độ nét và "giống nhau" do app đo bằng Vision.
// Ảnh chưa đo được độ nét: NaN, coi như mờ nhất. Số 0 có thể nét hơn
// một điểm âm, ví dụ điểm thẩm mỹ của Vision đi từ -1 tới 1.
let photos = similarItems.map { SimilarPhoto($0, sharpness: sharpness[$0.id] ?? .nan) }
var similar = SimilarReview(photos: photos) { a, b in
    looksAlike(a.id, b.id)  // khoảng cách VNFeaturePrintObservation dưới ngưỡng
}
SimilarPhotosScreen(review: $similar, allowance: allowance) { photo in
    PhotoThumbnail(id: photo.id)
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
- **App demo mở thẳng một màn hình** khi chạy với `-screen <id>`. Ví dụ `-screen ledger-home` — danh sách id nằm trong `DemoScreen`. Thêm `-scroll bottom` thì màn hình mở sẵn ở cuối trang, kể cả sheet nó mở, để chụp các thẻ cuối của một màn dài (ảnh `<id>.end.*.png`). Giờ và dữ liệu cố định (09:41, 25/09/2026, giờ Việt Nam), nên ảnh chụp giữa các lần so sánh được với nhau.
- **CI** chỉ chạy khi `ios/**` đổi:
  - Test lõi trên Linux (`.github/workflows/ios-core.yml`) theo công tắc `CI_RUNNER` như CI web, nên vẫn chạy trên VPS khi hết phút GitHub. Luôn dùng Swift 6.4.0: image `swift:6.4.0-noble` nếu máy chạy có Docker, không thì `ios/scripts/setup-swift-linux.sh` tải bản chính thức từ swift.org, đúng hệ điều hành của máy (VPS đang là Ubuntu 26.04), một lần vào tool cache của runner (không cần root, giống `setup-node`). Máy thiếu gói hệ thống của Swift thì job in đúng một lệnh `sudo apt-get install` để cài một lần.
  - Build app demo cho iOS Simulator (`.github/workflows/ios.yml`) cần macOS, vì phần SwiftUI chỉ biên dịch được trên macOS, nên vẫn chạy trên máy của GitHub.
  - Phút macOS đắt gấp ~10 lần Linux ([GitHub](https://docs.github.com/en/billing/reference/actions-runner-pricing)), nên có lọc đường dẫn và huỷ lần chạy cũ khi có push mới.
- **Chụp ảnh** (`.github/workflows/ios-previews.yml`) chỉ chạy khi gọi: gắn nhãn `ios-previews` vào PR, hoặc bấm tay trong tab Actions.
  - Chia hai job: `render` chạy code của PR với token **chỉ đọc** và tải ảnh lên dạng artifact; `publish` không chạy code nào của PR, chỉ đẩy ảnh lên nhánh `ios-previews` để xem ngay trên GitHub (bỏ qua với PR từ fork).
  - Mỗi lần chạy mất khoảng 5–15 phút macOS, tuỳ máy GitHub cấp.
  - Mỗi ảnh chỉ được chụp khi màn hình đã sẵn sàng và đứng yên:
    - App demo tạo file `Library/Caches/demo-ready` khi màn cần chụp đã hiện ra (`DemoLaunch.markReady`). Với màn mở sheet (`DemoScreen.opensSheet`), đó là lúc sheet hiện ra.
    - Script chờ file này, rồi chụp mỗi giây tới khi hai ảnh liên tiếp giống nhau và không còn là màn khởi động trống.

    Vì vậy simulator chậm không làm ra ảnh trắng, hay ảnh màn phía sau khi sheet chưa mở. Sau một phút mà app chưa báo sẵn sàng, hay màn hình chưa đứng yên, script báo lỗi thay vì đăng ảnh sai.

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

| Nhắc thuốc: phía cha mẹ | Phía người con | Cha mẹ, chữ cực lớn (AX-L) |
| --- | --- | --- |
| <img src="docs/screenshots/meds-today.light.png" width="200" alt="Nhắc thuốc, phía cha mẹ: liều trễ 2 giờ 41 phút, hình viên thuốc, tên thuốc tiểu đường, nút ĐÃ UỐNG rất to"> | <img src="docs/screenshots/meds-caregiver.light.png" width="200" alt="Phía người con: đã uống 1/3 liều đến giờ, thẻ cảnh báo liều trễ với nút Gọi Mẹ và Nhắc lại, dòng thời gian hôm nay"> | <img src="docs/screenshots/meds-today.large-text.png" width="200" alt="Phía cha mẹ ở cỡ chữ cực lớn: nút ĐÃ UỐNG ghim ở đáy màn hình, dưới tên thuốc và giờ uống mà nó trả lời"> |

Toàn bộ 61 ảnh (thêm chế độ tối, chữ lớn, phần cuối của màn dài, màn màu & thành phần) nằm ở nhánh `ios-previews` sau mỗi lần chạy workflow.

## 5. Lộ trình

1. **Dọn ảnh, phần còn lại**: nối `CleanupItem` và `SimilarPhoto` với PhotoKit + Vision trong app thật: đo độ nét và feature print để nhóm ảnh gần giống.
2. Đọc lại số tiền bằng giọng nói sau khi lưu (kiểu loa MoMo), và test ảnh chụp giao diện (snapshot) trong CI.
