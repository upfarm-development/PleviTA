
import Foundation

public enum OfflineNetworkPolicy {
    public static func shouldStartNow(allowsCellular: Bool, isExpensiveConnection: Bool) -> Bool {
        allowsCellular || !isExpensiveConnection
    }
}
