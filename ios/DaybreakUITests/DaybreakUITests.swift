import XCTest

final class DaybreakUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func scrollTo(_ element: XCUIElement, maxSwipes: Int = 6) {
        var swipes = 0
        while !element.isHittable && swipes < maxSwipes {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
    }

    func signOutIfNeeded() {
        let menu = app.buttons["menuButton"]
        if menu.waitForExistence(timeout: 3) {
            menu.tap()
            app.buttons["Sign out"].tap()
        }
    }

    func signUpFreshAccount() -> String {
        let stamp = Int(Date().timeIntervalSince1970)
        let email = "ios-uitest-\(stamp)@daybreak.test"

        signOutIfNeeded()
        let toggle = app.buttons["authToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()  // switch to signup

        let name = app.textFields["nameField"]
        name.tap(); name.typeText("UITest")
        let emailField = app.textFields["emailField"]
        emailField.tap(); emailField.typeText(email)
        let pass = app.secureTextFields["passwordField"]
        pass.tap(); pass.typeText("uitest-pass-1")
        app.buttons["authSubmit"].tap()

        XCTAssertTrue(app.buttons["menuButton"].waitForExistence(timeout: 10),
                      "planner should appear after signup")
        return email
    }

    func addTask(_ title: String, bucket: String) {
        let field = app.textFields["addTask-\(bucket)"]
        scrollTo(field)
        field.tap()
        field.typeText(title)
        app.buttons["addTaskButton-\(bucket)"].tap()
        XCTAssertTrue(app.otherElements["task-\(title)"]
            .waitForExistence(timeout: 5), "task \(title) should appear")
    }

    func testFullPlannerFlow() throws {
        _ = signUpFreshAccount()

        // 1. Add one task per bucket
        addTask("Pay invoice", bucket: "urgent")
        addTask("Draft roadmap", bucket: "progress")
        addTask("Tidy desk", bucket: "extra")

        // 2. Complete a task
        app.buttons["toggle-Tidy desk"].tap()

        // 3. Edit + schedule a task at a time block
        let task = app.otherElements["task-Draft roadmap"]
        scrollTo(task)
        task.tap()
        let scheduledToggle = app.switches["scheduledToggle"]
        XCTAssertTrue(scheduledToggle.waitForExistence(timeout: 5))
        scheduledToggle.switches.firstMatch.tap()
        let note = app.textFields["editNote"]
        note.tap(); note.typeText("deep work block")
        app.buttons["saveItem"].tap()

        // 4. Scheduled task shows on the timeline
        let slot = app.otherElements["slot-Draft roadmap"]
        scrollTo(slot)
        XCTAssertTrue(slot.waitForExistence(timeout: 5), "scheduled task on timeline")

        // 5. Create an event and verify it on the timeline
        app.buttons["menuButton"].tap()
        app.buttons["Add event"].tap()
        let evTitle = app.textFields["newEventTitle"]
        XCTAssertTrue(evTitle.waitForExistence(timeout: 5))
        evTitle.tap(); evTitle.typeText("Team sync")
        app.steppers["startStepper"].buttons["Increment"].tap(withNumberOfTaps: 4,
                                                              numberOfTouches: 1)
        app.buttons["saveItem"].tap()
        let evSlot = app.otherElements["slot-Team sync"]
        scrollTo(evSlot)
        XCTAssertTrue(evSlot.waitForExistence(timeout: 5), "event on timeline")

        // 6. Edit the event: change duration
        evSlot.tap()
        let duration = app.steppers["durationStepper"]
        XCTAssertTrue(duration.waitForExistence(timeout: 5))
        duration.buttons["Increment"].tap(withNumberOfTaps: 2, numberOfTouches: 1)
        app.buttons["saveItem"].tap()
        XCTAssertTrue(app.otherElements["slot-Team sync"].waitForExistence(timeout: 5))

        // 7. Persistence: sign out, sign back in via the same account is covered by
        //    testSessionPersistence; here verify state survives a relaunch (cookie).
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["menuButton"].waitForExistence(timeout: 10),
                      "session cookie should survive relaunch")
        let persisted = app.otherElements["task-Pay invoice"]
        scrollTo(persisted)
        XCTAssertTrue(persisted.waitForExistence(timeout: 5), "tasks persist")

        // 8. Delete the event
        let slotAgain = app.otherElements["slot-Team sync"]
        scrollTo(slotAgain)
        slotAgain.tap()
        let delete = app.buttons["deleteItem"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertFalse(app.otherElements["slot-Team sync"]
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
        let back = app.otherElements["task-Pay invoice"]
        scrollTo(back)
        XCTAssertTrue(back.waitForExistence(timeout: 5), "back on today")
    }

    func testSignInWrongPasswordShowsError() throws {
        signOutIfNeeded()
        let emailField = app.textFields["emailField"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        emailField.tap(); emailField.typeText("smoke@daybreak.test")
        let pass = app.secureTextFields["passwordField"]
        pass.tap(); pass.typeText("definitely-wrong")
        app.buttons["authSubmit"].tap()
        XCTAssertTrue(app.staticTexts["authError"].waitForExistence(timeout: 8),
                      "wrong credentials show an error")
    }
}
