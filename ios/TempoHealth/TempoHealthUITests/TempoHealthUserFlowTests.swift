import XCTest

final class TempoHealthUserFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWelcomeSignupAndSignInForms() {
        let app = launchApp()

        let createAccount = element("auth.createAccount", in: app)
        XCTAssertTrue(createAccount.waitForExistence(timeout: 10), "Welcome screen should offer account creation")
        createAccount.tap()

        XCTAssertTrue(element("auth.email", in: app).waitForExistence(timeout: 5), "Sign-up form should show email input")
        XCTAssertTrue(element("auth.username", in: app).exists, "Sign-up form should show username input")
        XCTAssertTrue(element("auth.password", in: app).exists, "Sign-up form should show password input")
        XCTAssertFalse(element("auth.submit", in: app).isEnabled, "Empty sign-up form must not submit")
        capture(app, named: "Sign-up form")

        element("auth.switchMode", in: app).tap()
        XCTAssertTrue(element("auth.forgotPassword", in: app).waitForExistence(timeout: 5), "Sign-in form should offer password reset")
        XCTAssertTrue(element("auth.email", in: app).exists, "Sign-in form should show email or username input")
        XCTAssertFalse(element("auth.submit", in: app).isEnabled, "Empty sign-in form must not submit")
        capture(app, named: "Sign-in form")
    }

    func testPasswordResetSheetOpensAndClosesWithoutSending() {
        let app = launchApp()
        element("auth.signIn", in: app).tap()

        let forgotPassword = element("auth.forgotPassword", in: app)
        XCTAssertTrue(forgotPassword.waitForExistence(timeout: 5))
        forgotPassword.tap()

        XCTAssertTrue(element("auth.passwordReset.email", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("auth.passwordReset.submit", in: app).isEnabled, "Password reset must require an email")
        capture(app, named: "Password reset")

        element("auth.passwordReset.close", in: app).tap()
        XCTAssertTrue(element("auth.forgotPassword", in: app).waitForExistence(timeout: 5), "Closing reset should return to sign-in")
    }

    func testAuthenticatedUserCanVisitEveryPrimaryTabAndSocialFriends() {
        let app = launchApp(authenticated: true)

        let tabExpectations: [(String, String)] = [
            ("tab.0", "screen.summary"),
            ("tab.1", "page.title.Aktiviteler"),
            ("tab.2", "screen.sports"),
            ("tab.3", "page.title.Apple Sağlık"),
            ("tab.4", "page.title.Profil ve araçlar")
        ]

        for (tabID, screenID) in tabExpectations {
            let tab = element(tabID, in: app)
            XCTAssertTrue(tab.waitForExistence(timeout: 10), "Missing primary tab \(tabID)")
            tab.tap()
            let screen = element(screenID, in: app)
            XCTAssertTrue(screen.waitForExistence(timeout: 8), "Tab \(tabID) did not show expected screen \(screenID)")
            capture(app, named: screenID)

            if tabID == "tab.1" {
                let addManualWorkout = element("activity.manual.add", in: app)
                XCTAssertTrue(addManualWorkout.waitForExistence(timeout: 5), "Activity screen should offer manual workout entry")
                addManualWorkout.tap()
                let manualForm = element("activity.manual.form", in: app)
                XCTAssertTrue(manualForm.waitForExistence(timeout: 5) || app.navigationBars["Antrenman ekle"].exists, "Manual workout form should open")
                capture(app, named: "Manual workout form")
                element("activity.manual.cancel", in: app).tap()
                XCTAssertTrue(screen.waitForExistence(timeout: 5), "Canceling manual entry should return to Activities")
            }
        }

        let social = element("more.social", in: app)
        for _ in 0..<4 where !social.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(social.waitForExistence(timeout: 5), "More screen should contain the Social entry")
        social.tap()

        let friendsSection = element("social.section.friends", in: app)
        XCTAssertTrue(friendsSection.waitForExistence(timeout: 5), "Social screen should offer its Friends section")
        friendsSection.tap()
        XCTAssertTrue(element("social.friendUsername", in: app).waitForExistence(timeout: 5), "Friends section should allow a username entry")
        XCTAssertFalse(element("social.sendFriendRequest", in: app).isEnabled, "Friend request should require a username")
        capture(app, named: "Social friends")
    }

    private func launchApp(authenticated: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        if authenticated {
            app.launchArguments.append("--ui-testing-authenticated")
        }
        app.launch()
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func capture(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
