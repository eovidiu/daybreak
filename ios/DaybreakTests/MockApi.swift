import Foundation
@testable import Daybreak

final class MockApi: PlannerApi, @unchecked Sendable {
    var user: User? = User(id: "u1", email: "a@b.co", name: "A")
    var tasks: [PlannerTask] = []
    var events: [PlannerEvent] = []
    var earlierTasks: [EarlierTask] = []
    var failNext = false
    var unauthorized = false

    private func guardOk() throws {
        if unauthorized { throw ApiError(message: "unauthorized") }
        if failNext { failNext = false; throw ApiError(message: "boom") }
    }

    func me() async throws -> User {
        try guardOk()
        guard let user else { throw ApiError(message: "unauthorized") }
        return user
    }

    func signIn(email: String, password: String) async throws { try guardOk() }
    func signUp(email: String, password: String, name: String) async throws { try guardOk() }
    func signOut() async throws {}

    func day(_ day: String) async throws -> DayData {
        try guardOk()
        return DayData(tasks: tasks.filter { $0.day == day },
                       events: events.filter { $0.day == day })
    }

    func earlier(before: String) async throws -> [EarlierTask] {
        try guardOk()
        return earlierTasks
    }

    func createTask(day: String, bucket: Bucket, title: String) async throws -> PlannerTask {
        try guardOk()
        let t = PlannerTask(id: UUID().uuidString, day: day, bucket: bucket, title: title,
                            note: "", done: false, scheduledStart: nil,
                            scheduledMinutes: nil, position: tasks.count)
        tasks.append(t)
        return t
    }

    func patchTask(_ id: String, _ patch: [String: Any?]) async throws { try guardOk() }
    func deleteTask(_ id: String) async throws { try guardOk() }

    func createEvent(day: String, bucket: Bucket, title: String,
                     startMin: Int, durationMin: Int) async throws -> PlannerEvent {
        try guardOk()
        let e = PlannerEvent(id: UUID().uuidString, day: day, bucket: bucket, title: title,
                             note: "", startMin: startMin, durationMin: durationMin)
        events.append(e)
        return e
    }

    func patchEvent(_ id: String, _ patch: [String: Any?]) async throws { try guardOk() }
    func deleteEvent(_ id: String) async throws { try guardOk() }
}
