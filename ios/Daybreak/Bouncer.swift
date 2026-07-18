import Foundation

// The confidence gate: a capture auto-files when its confidence clears the threshold.
enum Bouncer {
    static func autoFiles(confidence: Double, threshold: Double) -> Bool {
        confidence >= threshold
    }
}

// The user's auto-file threshold, persisted and clamped to a sane band.
enum CaptureThreshold {
    static let key = "captureThreshold"
    static let range = 0.3...0.9
    static let defaultValue = 0.6

    static func clamp(_ value: Double) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }

    static func load(_ store: UserDefaults = .standard) -> Double {
        guard store.object(forKey: key) != nil else { return defaultValue }
        return clamp(store.double(forKey: key))
    }

    static func save(_ value: Double, _ store: UserDefaults = .standard) {
        store.set(clamp(value), forKey: key)
    }
}
