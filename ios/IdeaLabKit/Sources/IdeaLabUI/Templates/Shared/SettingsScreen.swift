#if os(iOS)
import IdeaLabCore
import SwiftUI

/// iOS Settings-style row icon: a white symbol on a small coloured squircle.
public struct SettingsIcon: View {
    private let systemImage: String
    private let tint: LabTint
    @Environment(\.labTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 30

    public init(_ systemImage: String, tint: LabTint = .accent) {
        self.systemImage = systemImage
        self.tint = tint
    }

    public var body: some View {
        // Resizable + fit: wide symbols (two speech bubbles) stay inside the
        // squircle instead of spilling over its edges.
        Image(systemName: systemImage)
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
            .foregroundStyle(theme.onFill)
            .frame(width: size * 0.6, height: size * 0.6)
            .frame(width: size, height: size)
            .background(theme.fill(tint), in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The settings every small paid app needs, in App Review's order of
/// concern: purchases (with Restore), display, data, help, legal — plus
/// account deletion, which Guideline 5.1.1(v) requires inside the app for any
/// app that lets people create an account. Pass `onDeleteAccount` for such
/// an app: the row only exists with a handler that really deletes.
///
/// When the App Store could not charge for the renewal of the customer's
/// subscription (`billingNotice`), an amber card tops the screen with the
/// button that fixes it (`BillingIssueBanner`), and a plan on hold says so
/// rather than offering to upgrade.
public struct SettingsScreen: View {
    private let isPro: Bool
    private let billingNotice: BillingNotice?
    @Binding private var largeText: Bool
    private let privacyURL: URL
    private let termsURL: URL
    private let appVersion: String
    private let onUpgrade: () -> Void
    private let onRestore: () -> Void
    private let onExport: () -> Void
    private let onContact: () -> Void
    private let onDeleteAccount: (() -> Void)?
    @State private var confirmingDeletion = false
    @Environment(\.labTheme) private var theme

    /// - Parameters:
    ///   - isPro: whether the customer may use Pro (`LabStore.owns(anyOf:)`).
    ///   - billingNotice: a renewal the App Store could not charge for
    ///     (`StoreCopy.billingNotice(for:plans:)`), if any.
    public init(
        isPro: Bool,
        billingNotice: BillingNotice? = nil,
        largeText: Binding<Bool>,
        privacyURL: URL,
        termsURL: URL,
        appVersion: String,
        onUpgrade: @escaping () -> Void,
        onRestore: @escaping () -> Void,
        onExport: @escaping () -> Void,
        onContact: @escaping () -> Void,
        onDeleteAccount: (() -> Void)? = nil
    ) {
        self.isPro = isPro
        self.billingNotice = billingNotice
        _largeText = largeText
        self.privacyURL = privacyURL
        self.termsURL = termsURL
        self.appVersion = appVersion
        self.onUpgrade = onUpgrade
        self.onRestore = onRestore
        self.onExport = onExport
        self.onContact = onContact
        self.onDeleteAccount = onDeleteAccount
    }

    public var body: some View {
        Form {
            if let billingNotice {
                Section {
                    BillingIssueBanner(notice: billingNotice)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                if isPro {
                    LabeledContent {
                        Text(verbatim: "Đang dùng")
                            .foregroundStyle(theme.text(.positive))
                    } label: {
                        Label { Text(verbatim: "Gói Pro") } icon: { SettingsIcon("star.fill", tint: .positive) }
                    }
                } else if let billingNotice {
                    // On hold, not gone: the paywall says what it takes.
                    Button {
                        onUpgrade()
                    } label: {
                        rowLabel(
                            "Gói Pro", icon: "star.fill", tint: .accent, trailing: "chevron.right",
                            value: billingNotice.issue == .retrying ? "Tạm dừng" : "Chưa gia hạn được"
                        )
                    }
                } else {
                    row("Nâng cấp Pro", icon: "star.fill", tint: .accent) { onUpgrade() }
                }
                row("Khôi phục mua hàng", icon: "arrow.clockwise", tint: .accent) { onRestore() }
            } header: {
                Text(verbatim: "Gói của bạn")
            }

            Section {
                Toggle(isOn: $largeText) {
                    Label { Text(verbatim: "Chữ và nút lớn") } icon: { SettingsIcon("textformat.size", tint: .accent) }
                }
                .frame(minHeight: 44)
            } header: {
                Text(verbatim: "Hiển thị")
            } footer: {
                Text(verbatim: "Luôn dùng cỡ chữ lớn và nút to hơn, kể cả khi cỡ chữ của máy đang nhỏ.")
            }

            Section {
                row("Xuất dữ liệu", icon: "square.and.arrow.up", tint: .accent) { onExport() }
            } header: {
                Text(verbatim: "Dữ liệu")
            }

            Section {
                row("Liên hệ hỗ trợ", icon: "bubble.left.and.bubble.right.fill", tint: .accent) { onContact() }
                Link(destination: privacyURL) {
                    rowLabel("Quyền riêng tư", icon: "hand.raised.fill", tint: .accent, trailing: "arrow.up.right")
                }
                Link(destination: termsURL) {
                    rowLabel("Điều khoản sử dụng", icon: "doc.text.fill", tint: .accent, trailing: "arrow.up.right")
                }
            } header: {
                Text(verbatim: "Hỗ trợ & pháp lý")
            }

            if onDeleteAccount != nil {
                Section {
                    Button(role: .destructive) {
                        confirmingDeletion = true
                    } label: {
                        Label { Text(verbatim: "Xoá tài khoản") } icon: { SettingsIcon("trash.fill", tint: .negative) }
                    }
                    .frame(minHeight: 44)
                    .foregroundStyle(theme.text(.negative))
                } footer: {
                    Text(verbatim: "Xoá vĩnh viễn tài khoản và dữ liệu đồng bộ. Gói đã mua qua App Store cần huỷ riêng trong Cài đặt của máy.")
                }
            }

            Section {
            } footer: {
                Text(verbatim: "Phiên bản \(appVersion)")
                    .frame(maxWidth: .infinity)
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.canvas.ignoresSafeArea())
        .confirmationDialog(
            Text(verbatim: "Xoá tài khoản?"),
            isPresented: $confirmingDeletion,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                onDeleteAccount?()
            } label: {
                Text(verbatim: "Xoá vĩnh viễn")
            }
        } message: {
            Text(verbatim: "Không thể hoàn tác.")
        }
    }

    private func row(_ title: String, icon: String, tint: LabTint, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowLabel(title, icon: icon, tint: tint, trailing: "chevron.right")
        }
    }

    /// Icon, title, a value that needs attention if any, and a trailing
    /// hint: a chevron for screens inside the app, an arrow for links that
    /// leave it.
    private func rowLabel(_ title: String, icon: String, tint: LabTint, trailing: String, value: String? = nil) -> some View {
        HStack {
            Label { Text(verbatim: title) } icon: { SettingsIcon(icon, tint: tint) }
                .foregroundStyle(theme.label)
            Spacer()
            if let value {
                Text(verbatim: value)
                    .foregroundStyle(theme.warning)
            }
            Image(systemName: trailing)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(theme.secondaryLabel)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
#endif
