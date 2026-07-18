import Foundation

// Plain value types shared by the app, the tests, and the extensions. Kept free of the
// PlannerApi protocol and the classifier so the share extension can include just these
// (plus the @Model entities) without pulling in the whole app.

enum Bucket: String, Codable, CaseIterable, Identifiable {
    case urgent, progress, extra
    var id: String { rawValue }
    var title: String {
        switch self {
        case .urgent: "Urgent"
        case .progress: "Progress"
        case .extra: "Extras"
        }
    }
    var subtitle: String {
        switch self {
        case .urgent: "things with teeth"
        case .progress: "the long game"
        case .extra: "if there's room"
        }
    }
}

struct PlannerTask: Codable, Identifiable, Equatable {
    let id: String
    var day: String
    var bucket: Bucket
    var title: String
    var note: String
    var done: Bool
    var scheduledStart: Int?
    var scheduledMinutes: Int?
    var position: Int
    var completedAt: Date? = nil

    enum CodingKeys: String, CodingKey {
        case id, day, bucket, title, note, done, position
        case scheduledStart = "scheduled_start"
        case scheduledMinutes = "scheduled_minutes"
        case completedAt = "completed_at"
    }
}

struct PlannerEvent: Codable, Identifiable, Equatable {
    let id: String
    var day: String
    var bucket: Bucket
    var title: String
    var note: String
    var startMin: Int
    var durationMin: Int

    enum CodingKeys: String, CodingKey {
        case id, day, bucket, title, note
        case startMin = "start_min"
        case durationMin = "duration_min"
    }
}

struct EarlierTask: Codable, Identifiable, Equatable {
    let id: String
    var day: String
    var bucket: Bucket
    var title: String
    var note: String
}

struct DayData: Codable, Equatable {
    var tasks: [PlannerTask]
    var events: [PlannerEvent]
}

// A capture awaiting classification (e.g. written by the share extension).
struct PendingCapture: Identifiable, Equatable {
    let id: String
    let text: String
}

struct User: Codable, Equatable {
    let id: String
    let email: String
    let name: String
}

struct ApiError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// UI-facing view of a low-confidence capture queued for review.
struct Review: Identifiable, Equatable {
    let id: String
    let title: String
    let bucket: Bucket
    let day: String
    let start: Int?
    let minutes: Int?
    let confidence: Double
}

// Outcome of filing a capture: auto-filed as a task, or queued for review.
enum CaptureResult: Equatable {
    case filed(PlannerTask)
    case queued(Review)
}
