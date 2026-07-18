#if canImport(FoundationModels)
import Foundation
import FoundationModels

// Structured output schema for the on-device model. Optionals aren't used because the
// model fills every field; sentinels (-1) mean "none" and are normalized afterwards.
@available(iOS 26, *)
@Generable
struct CaptureGuess {
    @Guide(description: "Priority, exactly one of: urgent, progress, extra")
    let bucket: String
    @Guide(description: "The date the item is for, formatted yyyy-MM-dd")
    let day: String
    @Guide(description: "Start time as minutes from midnight 0-1439, or -1 if no time given")
    let startMin: Int
    @Guide(description: "Duration in minutes, or -1 if none given")
    let durationMin: Int
    @Guide(description: "A concise title with any date, time, or duration words removed")
    let cleanedTitle: String
    @Guide(description: "Confidence from 0.0 to 1.0 in the bucket choice")
    let confidence: Double
}

@available(iOS 26, *)
extension CaptureGuess {
    // Normalizes the model's raw fields into a Classification: unknown bucket names
    // fall back to .extra, and the -1 sentinels become nil. Pure, so it's unit-tested
    // across every branch independently of the (non-deterministic) model output.
    func asClassification() -> Classification {
        Classification(
            bucket: Bucket(rawValue: bucket.lowercased()) ?? .extra,
            day: day,
            startMin: startMin >= 0 ? startMin : nil,
            durationMin: durationMin > 0 ? durationMin : nil,
            cleanedTitle: cleanedTitle,
            confidence: confidence)
    }
}

@available(iOS 26, *)
enum FoundationModelClassifier {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static func classify(_ text: String, today: String) async throws -> Classification {
        let session = LanguageModelSession {
            """
            You sort a captured note into a daily planner. Buckets: "urgent" (things with
            teeth — deadlines, calls, payments), "progress" (long-game work — projects,
            learning), "extra" (nice to have — tidying, reading). Today is \(today).
            """
        }
        return try await session.respond(
            to: "Classify this note: \"\(text)\"",
            generating: CaptureGuess.self).content.asClassification()
    }
}
#endif
