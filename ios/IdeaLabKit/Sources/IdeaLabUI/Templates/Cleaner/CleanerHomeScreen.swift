#if os(iOS)
import IdeaLabCore
import SwiftUI

/// Home of "Dọn ảnh": how full the phone is, how much of it is photos nobody
/// needs, grouped by why they were picked — and nothing that frightens.
///
/// Cleaner apps are known for fake "your phone is at risk" alarms and weekly
/// subscriptions behind a trial. This screen does the opposite: real numbers,
/// the categories that explain them, the free allowance in plain words, and a
/// note that the photos never leave the phone.
public struct CleanerHomeScreen: View {
    private let storage: StorageStatus
    private let summaries: [CategorySummary]
    private let scanProgress: Double?
    private let allowance: FreeAllowance?
    private let onOpen: (CleanupCategory) -> Void
    private let onUpgrade: () -> Void
    @Environment(\.labTheme) private var theme

    /// - Parameters:
    ///   - summaries: from `CleanupMath.summary(of:)`.
    ///   - scanProgress: `0...1` while photos are still being sorted on the
    ///     device, `nil` once done. What is found so far is shown meanwhile.
    ///   - allowance: the free tier's deletions left, `nil` for the full version.
    public init(
        storage: StorageStatus,
        summaries: [CategorySummary],
        scanProgress: Double? = nil,
        allowance: FreeAllowance?,
        onOpen: @escaping (CleanupCategory) -> Void,
        onUpgrade: @escaping () -> Void
    ) {
        self.storage = storage
        self.summaries = summaries
        // Clamped once: a NaN from a 0/0 count would otherwise trap in `Int(_:)`.
        self.scanProgress = scanProgress.map { $0.isNaN ? 0 : min(max($0, 0), 1) }
        self.allowance = allowance
        self.onOpen = onOpen
        self.onUpgrade = onUpgrade
    }

    private var freeable: Int64 {
        summaries.reduce(0) { total, summary in
            let (sum, overflow) = total.addingReportingOverflow(summary.bytes)
            return overflow ? .max : sum
        }
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: LabSpacing.md) {
                heroCard
                if let allowance {
                    allowanceCard(allowance)
                }
                categoriesCard
                privacyNote
            }
            .padding(.horizontal, LabSpacing.md)
            .padding(.vertical, LabSpacing.sm)
        }
        .background(theme.canvas.ignoresSafeArea())
    }

    private var heroCard: some View {
        VStack(spacing: LabSpacing.md) {
            StorageRing(storage: storage, freeable: freeable)
                .padding(.top, LabSpacing.xs)
            StorageLegend(storage: storage, freeable: freeable)
            if let scanProgress {
                VStack(alignment: .leading, spacing: LabSpacing.xxs) {
                    ProgressView(value: scanProgress)
                        .tint(theme.fill(.accent))
                    Text(verbatim: "Đang phân loại ngay trên máy… \(Int((scanProgress * 100).rounded()))%")
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryLabel)
                }
            }
            if let biggest = summaries.max(by: { $0.bytes < $1.bytes }) {
                VStack(spacing: LabSpacing.xs) {
                    Text(verbatim: "Nên dọn trước: \(biggest.category.title) · \(ByteSize.string(biggest.bytes))")
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryLabel)
                        .multilineTextAlignment(.center)
                    Button {
                        onOpen(biggest.category)
                    } label: {
                        Label {
                            Text(verbatim: "Bắt đầu dọn")
                        } icon: {
                            Image(systemName: "sparkles")
                        }
                    }
                    .buttonStyle(.labFilled)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .labCard(padding: LabSpacing.lg)
    }

    private func allowanceTitle(_ allowance: FreeAllowance) -> String {
        if allowance.remaining > 0 {
            return "Còn \(VietnameseNumber.grouped(allowance.remaining)) ảnh xoá miễn phí"
        }
        // No number for a limit of zero (none offered, or a corrupt stored
        // allowance): "Đã dùng hết 0 ảnh" would make no sense.
        return allowance.limit > 0
            ? "Đã dùng hết \(VietnameseNumber.grouped(allowance.limit)) ảnh miễn phí"
            : "Đã hết lượt xoá miễn phí"
    }

    private func allowanceCard(_ allowance: FreeAllowance) -> some View {
        HStack(alignment: .top, spacing: LabSpacing.sm) {
            Image(systemName: "gift.fill")
                .font(.title3)
                .foregroundStyle(theme.accentText)
                .frame(width: 40, height: 40)
                .background(theme.tonalFill(.accent), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: LabSpacing.xxs) {
                Text(verbatim: allowanceTitle(allowance))
                    .font(.headline)
                    .foregroundStyle(theme.label)
                Text(verbatim: "Mua một lần để dọn không giới hạn. Không gói tuần, không tự gia hạn.")
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    onUpgrade()
                } label: {
                    Text(verbatim: "Xem bản đầy đủ")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.accentText)
            }
            Spacer(minLength: 0)
        }
        .labCard()
    }

    @ViewBuilder
    private var categoriesCard: some View {
        if summaries.isEmpty, scanProgress == nil {
            ContentUnavailableView {
                Label {
                    Text(verbatim: "Thư viện đã gọn gàng")
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(theme.text(.positive))
                }
            } description: {
                Text(verbatim: "Không còn ảnh nào cần dọn. Quay lại sau vài tuần nhé.")
            }
            .labCard()
        } else {
            VStack(alignment: .leading, spacing: LabSpacing.xs) {
                LabSectionHeader("Nhóm ảnh có thể dọn")
                ForEach(summaries) { summary in
                    Button {
                        onOpen(summary.category)
                    } label: {
                        CleanupCategoryRow(summary, share: freeable > 0 ? Double(summary.bytes) / Double(freeable) : 0)
                    }
                    .buttonStyle(.plain)
                    if summary.id != summaries.last?.id {
                        Divider().overlay(theme.separator)
                    }
                }
            }
            .labCard()
        }
    }

    private var privacyNote: some View {
        Label {
            Text(verbatim: "Ảnh không rời khỏi máy: việc phân loại chạy ngay trên iPhone, không cần mạng.")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(theme.text(.positive))
        }
        .font(.footnote)
        .foregroundStyle(theme.secondaryLabel)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, LabSpacing.xs)
    }
}
#endif
