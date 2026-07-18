import Foundation

// A morning glance: the few things that matter today, one nudge about something stuck,
// and one recent win to feel good about.
struct Digest: Equatable {
    var top3: [PlannerTask]
    var stuck: PlannerTask?
    var smallWin: PlannerTask?
    var todayEvents: [PlannerEvent]
}

enum DigestService {
    // Pure and deterministic: same inputs always yield the same digest.
    static func digest(tasks: [PlannerTask], events: [PlannerEvent], today: String) -> Digest {
        let incomplete = tasks.filter { !$0.done }

        let top3 = incomplete
            .sorted { rankKey($0, today: today) < rankKey($1, today: today) }
            .prefix(3)

        let stuck = incomplete
            .filter { $0.day < today }
            .min { stuckKey($0) < stuckKey($1) }

        let smallWin = tasks
            .filter { isRecentWin($0, today: today) }
            .max { winKey($0) < winKey($1) }

        let todayEvents = events.filter { $0.day == today }

        return Digest(top3: Array(top3), stuck: stuck, smallWin: smallWin,
                      todayEvents: todayEvents)
    }

    // MARK: ordering

    private static func bucketRank(_ bucket: Bucket) -> Int {
        switch bucket {
        case .urgent: 0
        case .progress: 1
        case .extra: 2
        }
    }

    // 0 overdue, 1 today, 2 future — string compare is valid for yyyy-MM-dd.
    private static func dayCategory(_ day: String, today: String) -> Int {
        if day < today { 0 } else if day == today { 1 } else { 2 }
    }

    // Top-3 order: overdue < today < future, then bucket priority, then position, then id.
    private static func rankKey(_ t: PlannerTask, today: String) -> (Int, Int, Int, String) {
        (dayCategory(t.day, today: today), bucketRank(t.bucket), t.position, t.id)
    }

    // Oldest stuck task: earliest day, then position, then id.
    private static func stuckKey(_ t: PlannerTask) -> (String, Int, String) {
        (t.day, t.position, t.id)
    }

    // Most recent win: latest completion, then id for a stable tie-break.
    private static func winKey(_ t: PlannerTask) -> (Date, String) {
        (t.completedAt ?? .distantPast, t.id)
    }

    // MARK: recency

    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()

    // A win counts if it was completed no earlier than 3 days before midnight today.
    private static func isRecentWin(_ t: PlannerTask, today: String) -> Bool {
        guard let completedAt = t.completedAt, let cutoff = cutoffDate(today: today) else {
            return false
        }
        return completedAt >= cutoff
    }

    private static func cutoffDate(today: String) -> Date? {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        guard let start = f.date(from: today) else { return nil }
        return calendar.date(byAdding: .day, value: -3, to: start)
    }
}
