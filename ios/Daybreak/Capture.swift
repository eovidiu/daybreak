import Foundation

// Result of classifying a captured line into a plan item.
struct Classification: Equatable {
    var bucket: Bucket
    var day: String
    var startMin: Int?
    var durationMin: Int?
    var cleanedTitle: String
    var confidence: Double
}

protocol CaptureClassifier {
    func classify(_ text: String, today: String) async -> Classification
}

// Deterministic on-device classifier: keyword scoring for the bucket + a
// date/time/duration parser. Used below iOS 26 or when Foundation Models is
// unavailable. Pure and fully unit-testable.
struct RuleBasedClassifier: CaptureClassifier {
    static let keywords: [Bucket: Set<String>] = [
        .urgent: ["call", "reply", "email", "send", "pay", "invoice", "deadline",
                  "due", "urgent", "asap", "today", "tonight", "fix", "submit"],
        .progress: ["plan", "build", "write", "draft", "design", "learn", "study",
                    "review", "prepare", "project", "goal", "research", "ship"],
        .extra: ["tidy", "clean", "organize", "read", "watch", "browse", "someday",
                 "maybe", "later", "sort", "archive"],
    ]

    func classify(_ text: String, today: String) async -> Classification {
        classifySync(text, today: today)
    }

    // Synchronous core, exposed for tests.
    func classifySync(_ text: String, today: String) -> Classification {
        let lower = text.lowercased()
        var phrases: [String] = []
        let (durationMin, dPhrase) = DateTimeParser.duration(in: lower)
        if let dPhrase { phrases.append(dPhrase) }
        let (startMin, tPhrase) = DateTimeParser.time(in: lower)
        if let tPhrase { phrases.append(tPhrase) }
        let (day, datePhrase, tonight) = DateTimeParser.date(in: lower, today: today)
        if let datePhrase { phrases.append(datePhrase) }
        let (bucket, confidence) = Self.bucket(for: lower)

        var resolvedStart = startMin
        if resolvedStart == nil && tonight { resolvedStart = 20 * 60 }

        let cleaned = DateTimeParser.cleanTitle(original: text, remove: phrases)
        return Classification(bucket: bucket, day: day ?? today, startMin: resolvedStart,
                              durationMin: durationMin, cleanedTitle: cleaned,
                              confidence: confidence)
    }

    // Whole-token, case-insensitive scoring; ties break urgent > progress > extra.
    static func bucket(for lower: String) -> (Bucket, Double) {
        let tokens = Set(lower.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        var scores: [Bucket: Int] = [:]
        for (bucket, words) in keywords {
            scores[bucket] = tokens.intersection(words).count
        }
        let order: [Bucket] = [.urgent, .progress, .extra]
        let top = order.map { scores[$0] ?? 0 }.max() ?? 0
        if top == 0 { return (.extra, 0.40) }
        let winner = order.first { (scores[$0] ?? 0) == top }!  // priority tie-break
        let second = order.filter { $0 != winner }.map { scores[$0] ?? 0 }.max() ?? 0
        let confidence = min(0.95, max(0.30, 0.5 + 0.45 * Double(top - second) / Double(max(top, 1))))
        return (winner, confidence)
    }
}
