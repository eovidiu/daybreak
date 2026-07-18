import Foundation
import SwiftData

// The SwiftData store shared between the app, the widget, and the share extension via an
// App Group. Falls back to a local (non-shared) container when the App Group isn't
// available, so the app still runs without the entitlement provisioned.
enum SharedStore {
    static let appGroup = "group.com.eovidiu.daybreak"

    static var schema: Schema {
        Schema([TaskEntity.self, EventEntity.self, CaptureItem.self,
                ReviewItem.self, AuditRecord.self])
    }

    static func container() -> ModelContainer {
        for config in candidateConfigs() {
            if let container = try? ModelContainer(for: schema, configurations: config) {
                return container
            }
        }
        // Last resort: in-memory, so launch never crashes on a bad store.
        return try! ModelContainer(
            for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    // App Group store first (shared), then the default local store.
    private static func candidateConfigs() -> [ModelConfiguration] {
        var configs: [ModelConfiguration] = []
        if let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("Daybreak.store") {
            configs.append(ModelConfiguration(url: url))
        }
        configs.append(ModelConfiguration())
        return configs
    }
}
