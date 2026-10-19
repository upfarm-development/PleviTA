
import Foundation

public enum OfflineDiskSpace {
    private static let safetyMargin = 1.1


    public static func availableCapacity() -> Int? {
        #if os(iOS)
        guard let root = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) else { return nil }
        guard let capacity = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        else { return nil }
        return Int(capacity)
        #else
        return nil
        #endif
    }

    public static func hasEnoughFreeSpace(estimatedByteCount: Int?, availableCapacity: Int) -> Bool {
        guard let estimatedByteCount, estimatedByteCount > 0 else { return true }
        let required = Int(Double(estimatedByteCount) * safetyMargin)
        return availableCapacity >= required
    }
}
