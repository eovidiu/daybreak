import Foundation
import SwiftData

// Writes a raw capture straight to the shared store, pending classification. The share
// extension calls this and returns; the app classifies it on next launch. No classifier
// here — the extension must stay light.
enum SharedCapture {
    @MainActor
    static func enqueue(_ text: String, into container: ModelContainer = SharedStore.container()) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let context = container.mainContext
        context.insert(CaptureItem(text: trimmed, source: .share, status: .pending, now: Date()))
        try? context.save()
    }
}
