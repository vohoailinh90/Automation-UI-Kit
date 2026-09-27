#if os(iOS)
import Foundation
import IdeaLabCore

extension StorageStatus {
    /// This phone's storage, for `CleanerHomeScreen`: its capacity, and the
    /// space free for what the person asks for, as Settings counts it
    /// (`volumeAvailableCapacityForImportantUsage`). `nil` when iOS does not
    /// say.
    public static func device() -> StorageStatus? {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? home.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let capacity = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return StorageStatus(capacity: Int64(capacity), available: available)
    }
}
#endif
