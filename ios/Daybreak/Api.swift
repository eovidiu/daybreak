import Foundation

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

    enum CodingKeys: String, CodingKey {
        case id, day, bucket, title, note, done, position
        case scheduledStart = "scheduled_start"
        case scheduledMinutes = "scheduled_minutes"
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

struct User: Codable, Equatable {
    let id: String
    let email: String
    let name: String
}

struct ApiError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct ApiClient {
    let base: URL

    init() {
        let env = ProcessInfo.processInfo.environment["DAYBREAK_API"]
        base = URL(string: env ?? "https://daybreak.eovidiu.workers.dev")!
    }

    private func request<T: Decodable>(
        _ method: String, _ path: String, body: [String: Any?]? = nil, as type: T.Type
    ) async throws -> T {
        var req = URLRequest(url: base.appending(path: path))
        req.httpMethod = method
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = try JSONSerialization.data(
                withJSONObject: body.mapValues { $0 ?? NSNull() })
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw ApiError(message: "unauthorized") }
        guard (200..<300).contains(status) else {
            let err = try? JSONDecoder().decode([String: String].self, from: data)
            throw ApiError(message: err?["error"] ?? "request failed (\(status))")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    struct Ok: Codable { let ok: Bool }
    struct Providers: Codable { let providers: [String] }
    struct Earlier: Codable { let tasks: [EarlierTask] }

    func me() async throws -> User { try await request("GET", "/api/me", as: User.self) }

    func signIn(email: String, password: String) async throws {
        _ = try await request("POST", "/api/auth/signin",
                              body: ["email": email, "password": password], as: Ok.self)
    }

    func signUp(email: String, password: String, name: String) async throws {
        _ = try await request("POST", "/api/auth/signup",
                              body: ["email": email, "password": password, "name": name],
                              as: Ok.self)
    }

    func signOut() async throws {
        _ = try await request("POST", "/api/auth/signout", as: Ok.self)
    }

    func day(_ day: String) async throws -> DayData {
        try await request("GET", "/api/day/\(day)", as: DayData.self)
    }

    func earlier(before: String) async throws -> [EarlierTask] {
        try await request("GET", "/api/earlier?before=\(before)", as: Earlier.self).tasks
    }

    func createTask(day: String, bucket: Bucket, title: String) async throws -> PlannerTask {
        try await request("POST", "/api/tasks",
                          body: ["day": day, "bucket": bucket.rawValue, "title": title],
                          as: PlannerTask.self)
    }

    func patchTask(_ id: String, _ patch: [String: Any?]) async throws {
        _ = try await request("PATCH", "/api/tasks/\(id)", body: patch, as: Ok.self)
    }

    func deleteTask(_ id: String) async throws {
        _ = try await request("DELETE", "/api/tasks/\(id)", as: Ok.self)
    }

    func createEvent(day: String, bucket: Bucket, title: String,
                     startMin: Int, durationMin: Int) async throws -> PlannerEvent {
        try await request("POST", "/api/events", body: [
            "day": day, "bucket": bucket.rawValue, "title": title,
            "start_min": startMin, "duration_min": durationMin,
        ], as: PlannerEvent.self)
    }

    func patchEvent(_ id: String, _ patch: [String: Any?]) async throws {
        _ = try await request("PATCH", "/api/events/\(id)", body: patch, as: Ok.self)
    }

    func deleteEvent(_ id: String) async throws {
        _ = try await request("DELETE", "/api/events/\(id)", as: Ok.self)
    }
}

enum Day {
    static func today() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    static func add(_ day: String, _ delta: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: day),
              let moved = Calendar.current.date(byAdding: .day, value: delta, to: d)
        else { return day }
        return f.string(from: moved)
    }

    static func label(_ day: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: day) else { return day }
        let out = DateFormatter()
        out.dateFormat = "EEEE, MMMM d"
        return out.string(from: d)
    }

    static func shortLabel(_ day: String) -> (weekday: String, dayNum: String) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: day) else { return (day, "") }
        let wd = DateFormatter(); wd.dateFormat = "EEE"
        let dn = DateFormatter(); dn.dateFormat = "d"
        return (wd.string(from: d), dn.string(from: d))
    }

    static func time(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}
