import Foundation

extension Classification {
    // A classification is usable only if every field is in range. Used to gate the
    // (non-deterministic) Foundation Models output before trusting it.
    var isInRange: Bool {
        guard day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
        else { return false }
        if let s = startMin, !(0..<24 * 60).contains(s) { return false }
        if let d = durationMin, d <= 0 { return false }
        return (0.0...1.0).contains(confidence)
    }
}

// Runs a primary classifier (e.g. Foundation Models) and falls back to the
// deterministic rule-based one whenever the primary is absent, throws, or returns
// out-of-range output. The primary is a closure so the fallback path is testable.
struct CaptureEngine: CaptureClassifier {
    let fallback = RuleBasedClassifier()
    let primary: ((String, String) async throws -> Classification)?

    init(primary: ((String, String) async throws -> Classification)? = nil) {
        self.primary = primary
    }

    func classify(_ text: String, today: String) async -> Classification {
        if let primary {
            if let result = try? await primary(text, today), result.isInRange {
                return result
            }
        }
        return fallback.classifySync(text, today: today)
    }
}

// Chooses the best available classifier: Foundation Models on iOS 26+ when the
// system model is available, else the rule-based fallback.
enum Capture {
    static func makeClassifier() -> CaptureClassifier {
        #if canImport(FoundationModels)
        if #available(iOS 26, *), FoundationModelClassifier.isAvailable {
            return CaptureEngine(primary: { text, today in
                try await FoundationModelClassifier.classify(text, today: today)
            })
        }
        #endif
        return RuleBasedClassifier()
    }
}
