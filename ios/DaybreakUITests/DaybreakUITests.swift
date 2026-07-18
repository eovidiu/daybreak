import XCTest

final class DaybreakUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["UITEST_RESET"]  // start each test with an empty local store
        app.launch()
    }

    // Type-agnostic element lookup: SwiftUI surfaces identified stacks with
    // varying element types, so never query a specific type.
    func elem(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func scrollTo(_ element: XCUIElement, maxSwipes: Int = 6) {
        var swipes = 0
        while !element.isHittable && swipes < maxSwipes {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
    }

    // Local-first: the app opens directly to the planner (no account/auth).
    func openPlanner() {
        XCTAssertTrue(app.buttons["menuButton"].waitForExistence(timeout: 10),
                      "planner should appear on launch")
    }

    func addTask(_ title: String, bucket: String) {
        let field = app.textFields["addTask-\(bucket)"]
        scrollTo(field)
        field.tap()
        field.typeText(title)
        app.buttons["addTaskButton-\(bucket)"].tap()
        XCTAssertTrue(elem("task-\(title)")
            .waitForExistence(timeout: 5), "task \(title) should appear")
    }

    func testFullPlannerFlow() throws {
        openPlanner()

        // 1. Add one task per bucket
        addTask("Pay invoice", bucket: "urgent")
        addTask("Draft roadmap", bucket: "progress")
        addTask("Tidy desk", bucket: "extra")

        // 2. Complete a task
        elem("toggle-Tidy desk").tap()

        // 3. Edit + schedule a task at a time block
        let task = elem("task-Draft roadmap")
        scrollTo(task)
        task.tap()
        let scheduledToggle = app.switches["scheduledToggle"]
        XCTAssertTrue(scheduledToggle.waitForExistence(timeout: 5))
        scheduledToggle.switches.firstMatch.tap()
        let note = app.textFields["editNote"]
        note.tap(); note.typeText("deep work block")
        app.buttons["saveItem"].tap()

        // 4. Scheduled task shows on the timeline
        let slot = elem("slot-Draft roadmap")
        scrollTo(slot)
        XCTAssertTrue(slot.waitForExistence(timeout: 5), "scheduled task on timeline")

        // 5. Create an event and verify it on the timeline
        app.buttons["menuButton"].tap()
        app.buttons["Add event"].tap()
        let evTitle = app.textFields["newEventTitle"]
        XCTAssertTrue(evTitle.waitForExistence(timeout: 5))
        evTitle.tap(); evTitle.typeText("Team sync")
        app.buttons["startStepper-Increment"].tap(withNumberOfTaps: 4,
                                                  numberOfTouches: 1)
        app.buttons["saveItem"].tap()
        let evSlot = elem("slot-Team sync")
        scrollTo(evSlot)
        XCTAssertTrue(evSlot.waitForExistence(timeout: 5), "event on timeline")

        // 6. Edit the event: change duration
        evSlot.tap()
        let duration = app.buttons["durationStepper-Increment"]
        XCTAssertTrue(duration.waitForExistence(timeout: 5))
        duration.tap(withNumberOfTaps: 2, numberOfTouches: 1)
        app.buttons["saveItem"].tap()
        XCTAssertTrue(elem("slot-Team sync").waitForExistence(timeout: 5))

        // 7. Persistence: relaunch WITHOUT the reset flag; local data survives.
        app.terminate()
        app.launchArguments = app.launchArguments.filter { $0 != "UITEST_RESET" }
        app.launch()
        XCTAssertTrue(app.buttons["menuButton"].waitForExistence(timeout: 10),
                      "planner should reappear on relaunch")
        let persisted = elem("task-Pay invoice")
        scrollTo(persisted)
        XCTAssertTrue(persisted.waitForExistence(timeout: 5), "tasks persist locally")

        // 8. Delete the event
        let slotAgain = elem("slot-Team sync")
        scrollTo(slotAgain)
        slotAgain.tap()
        let delete = app.buttons["deleteItem"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertFalse(elem("slot-Team sync")
            .waitForExistence(timeout: 3), "event deleted")

        // 9. Day navigation: yesterday, then back to today
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let yesterday = fmt.string(from: Date().addingTimeInterval(-86400))
        let chip = app.buttons["day-\(yesterday)"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.tap()
        let todayButton = app.buttons["todayButton"]
        XCTAssertTrue(todayButton.isEnabled, "Today button enabled off-today")
        todayButton.tap()
        let back = elem("task-Pay invoice")
        scrollTo(back)
        XCTAssertTrue(back.waitForExistence(timeout: 5), "back on today")
    }

    // Exercises the earlier tray: a task left on a past day surfaces on today,
    // can be pulled forward, and another can be dropped.
    func testEarlierTrayAndDayNavigation() throws {
        openPlanner()

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let yesterday = fmt.string(from: Date().addingTimeInterval(-86400))

        // Go to yesterday and leave two unfinished tasks there.
        app.buttons["day-\(yesterday)"].tap()
        addTask("Overdue report", bucket: "urgent")
        addTask("Old cleanup", bucket: "extra")

        // Back to today — the earlier tray should offer both.
        app.buttons["todayButton"].tap()
        let pull = app.buttons["pull-Overdue report"].firstMatch
        XCTAssertTrue(pull.waitForExistence(timeout: 8), "earlier tray appears")
        scrollTo(pull)
        pull.tap()
        XCTAssertTrue(elem("task-Overdue report").waitForExistence(timeout: 5),
                      "pulled task appears in today")
        app.buttons["dropEarlier-Old cleanup"].firstMatch.tap()
    }

    // Exercises the timeline long-press drag (SlotBlock.onEnded) and deletion.
    func testTimelineDragAndDelete() throws {
        openPlanner()

        app.buttons["menuButton"].tap()
        app.buttons["Add event"].tap()
        let evTitle = app.textFields["newEventTitle"]
        XCTAssertTrue(evTitle.waitForExistence(timeout: 5))
        evTitle.tap(); evTitle.typeText("Standup")
        app.buttons["saveItem"].tap()

        let slot = elem("slot-Standup")
        scrollTo(slot)
        XCTAssertTrue(slot.waitForExistence(timeout: 5))

        // Long-press then drag downward ~one hour.
        let start = slot.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let end = slot.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            .withOffset(CGVector(dx: 0, dy: 90))
        start.press(forDuration: 0.6, thenDragTo: end)

        XCTAssertTrue(elem("slot-Standup").waitForExistence(timeout: 5),
                      "event still present after drag")

        // Delete it via the editor. On device a tap immediately after a drag can be
        // dropped, so open the editor with a short retry and confirm it appeared.
        let delete = app.buttons["deleteItem"]
        let editTitle = app.textFields["editTitle"]
        for _ in 0..<3 where !editTitle.waitForExistence(timeout: 2) {
            let slot = elem("slot-Standup")
            if slot.isHittable { slot.tap() }
        }
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertFalse(elem("slot-Standup").waitForExistence(timeout: 3))
    }

    // A pre-8am event opens the timeline scrolled to it; also covers schedule + unschedule.
    func testEarlyEventScrollAndUnschedule() throws {
        openPlanner()

        addTask("Morning prep", bucket: "progress")
        let task = elem("task-Morning prep")
        scrollTo(task)
        task.tap()
        app.switches["scheduledToggle"].switches.firstMatch.tap()
        // Step the start down to 05:00 from the 09:00 default (16 x 15min);
        // XCUITest caps a single call at 10 taps.
        let decrement = app.buttons["startStepper-Decrement"]
        decrement.tap(withNumberOfTaps: 10, numberOfTouches: 1)
        decrement.tap(withNumberOfTaps: 6, numberOfTouches: 1)
        app.buttons["saveItem"].tap()

        XCTAssertTrue(elem("slot-Morning prep").waitForExistence(timeout: 5),
                      "early scheduled task appears")

        // Unschedule it again.
        elem("task-Morning prep").tap()
        app.switches["scheduledToggle"].switches.firstMatch.tap()
        app.buttons["saveItem"].tap()
        XCTAssertTrue(elem("task-Morning prep").waitForExistence(timeout: 5))
    }

    // Daybreak commits to a light "paper" look; it must render light even when the
    // system is in Dark Mode, so field text never goes white-on-white.
    //
    // PRECONDITION: run with the host simulator in Dark appearance, e.g.
    //   xcrun simctl ui <sim> appearance dark
    // Under a dark simulator this is a true red/green: without the .preferredColorScheme
    // pin the app follows the system (probe reports "appearance-dark" → this test fails);
    // with the pin it stays light (probe reports "appearance-light" → passes).
    func testAppStaysLightWhenSystemIsDark() {
        XCTAssertTrue(
            app.otherElements["appearance-light"].waitForExistence(timeout: 10),
            "app should resolve to a light appearance even when the system is in Dark Mode")
        XCTAssertFalse(
            app.otherElements["appearance-dark"].exists,
            "app must not render in dark appearance")
    }
}
