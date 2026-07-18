import XCTest
@testable import Daybreak

@MainActor
final class StoreTests: XCTestCase {
    func makeStore() -> (PlannerStore, MockApi) {
        let api = MockApi()
        return (PlannerStore(api: api), api)
    }

    // Drains the store's background Tasks so optimistic mutations settle.
    func settle() async {
        try? await Task.sleep(nanoseconds: 60_000_000)
    }

    func testBootstrapLoadsUserAndDay() async {
        let (store, api) = makeStore()
        api.tasks = [PlannerTask(id: "t1", day: store.day, bucket: .urgent, title: "X",
                                 note: "", done: false, scheduledStart: nil,
                                 scheduledMinutes: nil, position: 0)]
        await store.bootstrap()
        XCTAssertNotNil(store.user)
        XCTAssertTrue(store.checkedSession)
        XCTAssertEqual(store.data.tasks.count, 1)
    }

    func testBootstrapWithoutSession() async {
        let (store, api) = makeStore()
        api.user = nil
        await store.bootstrap()
        XCTAssertNil(store.user)
    }

    func testSignOutClearsState() async {
        let (store, _) = makeStore()
        await store.bootstrap()
        await store.signOut()
        XCTAssertNil(store.user)
        XCTAssertTrue(store.data.tasks.isEmpty)
    }

    func testAddAndToggleTask() async {
        let (store, _) = makeStore()
        await store.bootstrap()
        await store.addTask(bucket: .progress, title: "Ship")
        XCTAssertEqual(store.data.tasks.first?.title, "Ship")
        let task = store.data.tasks[0]
        store.toggle(task)
        XCTAssertTrue(store.data.tasks[0].done)
        await settle()
    }

    func testScheduleUpdateAndDeleteTask() async {
        let (store, _) = makeStore()
        await store.bootstrap()
        await store.addTask(bucket: .urgent, title: "Call")
        var task = store.data.tasks[0]
        store.schedule(task, start: 480, minutes: 30)
        XCTAssertEqual(store.data.tasks[0].scheduledStart, 480)
        task = store.data.tasks[0]
        store.update(task, title: "Call back", note: "urgent", bucket: .extra)
        XCTAssertEqual(store.data.tasks[0].title, "Call back")
        XCTAssertEqual(store.data.tasks[0].bucket, .extra)
        store.moveScheduled(store.data.tasks[0], toStart: 600)
        XCTAssertEqual(store.data.tasks[0].scheduledStart, 600)
        store.delete(store.data.tasks[0])
        XCTAssertTrue(store.data.tasks.isEmpty)
        await settle()
    }

    func testEventLifecycle() async {
        let (store, _) = makeStore()
        await store.bootstrap()
        await store.addEvent(title: "Sync", bucket: .progress, start: 540, minutes: 60)
        XCTAssertEqual(store.data.events.first?.title, "Sync")
        var ev = store.data.events[0]
        store.move(ev, toStart: 600)
        XCTAssertEqual(store.data.events[0].startMin, 600)
        ev = store.data.events[0]
        store.update(ev, title: "Sync v2", note: "n", bucket: .urgent, start: 660, minutes: 90)
        XCTAssertEqual(store.data.events[0].title, "Sync v2")
        XCTAssertEqual(store.data.events[0].durationMin, 90)
        store.delete(store.data.events[0])
        XCTAssertTrue(store.data.events.isEmpty)
        await settle()
    }

    func testSelectDayUsesCache() async {
        let (store, api) = makeStore()
        await store.bootstrap()
        let other = Day.add(store.day, 1)
        api.events = [PlannerEvent(id: "e1", day: other, bucket: .extra, title: "Later",
                                   note: "", startMin: 600, durationMin: 60)]
        store.select(day: other)
        await settle()
        XCTAssertEqual(store.day, other)
        XCTAssertEqual(store.data.events.first?.title, "Later")
        // Second select hits the cache path for instant render.
        store.select(day: store.day)
        await settle()
    }

    func testEarlierTrayPullAndDelete() async {
        let (store, api) = makeStore()
        api.earlierTasks = [
            EarlierTask(id: "e1", day: "2026-07-01", bucket: .urgent, title: "Old A", note: ""),
            EarlierTask(id: "e2", day: "2026-07-02", bucket: .extra, title: "Old B", note: ""),
        ]
        await store.bootstrap()
        XCTAssertEqual(store.earlier.count, 2)
        store.pullIntoToday(store.earlier[0])
        XCTAssertEqual(store.earlier.count, 1)
        store.deleteEarlier(store.earlier[0])
        XCTAssertTrue(store.earlier.isEmpty)
        await settle()
    }

    func testErrorSurfacesMessage() async {
        let (store, api) = makeStore()
        await store.bootstrap()
        api.failNext = true
        await store.addTask(bucket: .urgent, title: "will fail")
        XCTAssertNotNil(store.errorMessage)
    }

    func testUnauthorizedClearsUser() async {
        let (store, api) = makeStore()
        await store.bootstrap()
        api.unauthorized = true
        await store.load()
        XCTAssertNil(store.user)
    }

    // MARK: capture (F004)

    // Fresh UserDefaults per store so the auto-file threshold is the default 0.6 and
    // never leaks between tests (or from the shared simulator domain).
    private func captureStore(_ c: Classification) -> (PlannerStore, MockApi) {
        let api = MockApi()
        let name = "store-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (PlannerStore(api: api, classifier: StubClassifier(result: c),
                             defaults: defaults), api)
    }

    func testCaptureCreatesBucketedScheduledTask() async {
        let (store, _) = captureStore(
            Classification(bucket: .urgent, day: Day.today(), startMin: 900,
                           durationMin: 30, cleanedTitle: "Call the dentist", confidence: 0.9))
        await store.bootstrap()
        await store.capture("call the dentist at 3pm for 30 min")
        XCTAssertEqual(store.data.tasks.count, 1)
        let t = store.data.tasks[0]
        XCTAssertEqual(t.title, "Call the dentist")
        XCTAssertEqual(t.bucket, .urgent)
        XCTAssertEqual(t.scheduledStart, 900)
        XCTAssertEqual(t.scheduledMinutes, 30)
    }

    func testCaptureLeavesUntimedTaskUnscheduled() async {
        let (store, _) = captureStore(
            Classification(bucket: .progress, day: Day.today(), startMin: nil,
                           durationMin: nil, cleanedTitle: "Plan roadmap", confidence: 0.8))
        await store.bootstrap()
        await store.capture("plan the roadmap")
        XCTAssertEqual(store.data.tasks.first?.title, "Plan roadmap")
        XCTAssertNil(store.data.tasks.first?.scheduledStart)
    }

    func testCaptureForFutureDayPersistsButHidesFromToday() async {
        let (store, api) = captureStore(
            Classification(bucket: .urgent, day: Day.add(Day.today(), 1), startMin: nil,
                           durationMin: nil, cleanedTitle: "Gym", confidence: 0.7))
        await store.bootstrap()
        await store.capture("gym tomorrow")
        XCTAssertTrue(store.data.tasks.isEmpty)   // not in today's view
        XCTAssertEqual(api.tasks.count, 1)        // but persisted for tomorrow
    }

    func testCaptureIgnoresBlankInput() async {
        let (store, api) = captureStore(
            Classification(bucket: .extra, day: Day.today(), startMin: nil,
                           durationMin: nil, cleanedTitle: "x", confidence: 0.4))
        await store.bootstrap()
        await store.capture("   \n ")
        XCTAssertTrue(api.tasks.isEmpty)
    }

    func testCaptureErrorSurfaces() async {
        let (store, api) = captureStore(
            Classification(bucket: .urgent, day: Day.today(), startMin: nil,
                           durationMin: nil, cleanedTitle: "x", confidence: 0.9))
        await store.bootstrap()
        api.failNext = true
        await store.capture("something")
        XCTAssertNotNil(store.errorMessage)
    }

    func testCaptureLowConfidenceQueuesReview() async {
        let (store, _) = captureStore(
            Classification(bucket: .extra, day: Day.today(), startMin: nil,
                           durationMin: nil, cleanedTitle: "Maybe read", confidence: 0.4))
        await store.bootstrap()
        await store.capture("maybe read something")
        XCTAssertTrue(store.data.tasks.isEmpty)            // not auto-filed
        XCTAssertEqual(store.reviews.map(\.title), ["Maybe read"])
    }

    func testAcceptReviewFromStoreCreatesTask() async {
        let (store, _) = captureStore(
            Classification(bucket: .extra, day: Day.today(), startMin: nil,
                           durationMin: nil, cleanedTitle: "Read", confidence: 0.4))
        await store.bootstrap()
        await store.capture("read")
        let review = store.reviews[0]
        await store.acceptReview(review, bucket: .progress, day: Day.today(),
                                 title: "Read the book", start: 600, minutes: 30)
        XCTAssertTrue(store.reviews.isEmpty)
        XCTAssertEqual(store.data.tasks.first?.title, "Read the book")
    }

    func testDismissReviewFromStore() async {
        let (store, _) = captureStore(
            Classification(bucket: .extra, day: Day.today(), startMin: nil,
                           durationMin: nil, cleanedTitle: "Later", confidence: 0.4))
        await store.bootstrap()
        await store.capture("later maybe")
        await store.dismissReview(store.reviews[0])
        XCTAssertTrue(store.reviews.isEmpty)
        await settle()
    }

    func testDigestPopulatedOnLoad() async {
        let (store, api) = makeStore()
        api.tasks = [
            PlannerTask(id: "t1", day: Day.today(), bucket: .urgent, title: "Top one",
                        note: "", done: false, scheduledStart: nil, scheduledMinutes: nil,
                        position: 0),
        ]
        await store.bootstrap()
        XCTAssertEqual(store.digest.top3.map(\.title), ["Top one"])
    }

    func testDrainPendingClassifiesShareCaptures() async {
        let (store, api) = captureStore(
            Classification(bucket: .urgent, day: Day.today(), startMin: nil, durationMin: nil,
                           cleanedTitle: "Buy milk", confidence: 0.9))
        _ = try? await api.enqueueCapture(text: "buy milk", source: .share)  // as if by the extension
        await store.bootstrap()   // drains pending, then loads
        XCTAssertEqual(store.data.tasks.first?.title, "Buy milk")
        let stillPending = try? await api.pendingCaptures()
        XCTAssertTrue(stillPending?.isEmpty ?? false)
    }

    func testAuditHistoryPassesThrough() async {
        let (store, api) = makeStore()
        api.auditEntries = [
            AuditEntry(id: "a1", rawInput: "call bank", bucket: .urgent, confidence: 0.9,
                       autoFiled: true, tier: .ruleBased, createdAt: Date(), corrections: []),
        ]
        let history = await store.auditHistory()
        XCTAssertEqual(history.map(\.rawInput), ["call bank"])
    }
}
