#if os(iOS)
import IdeaLabNotifications
import UIKit

public extension DoseNotifications {
    /// Opens the app's notification settings, where alerts and Time Sensitive
    /// are turned back on. In the app only: an extension cannot open them.
    @MainActor
    static func openSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
#endif
