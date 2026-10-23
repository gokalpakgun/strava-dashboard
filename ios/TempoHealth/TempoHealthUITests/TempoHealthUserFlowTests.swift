import Foundation
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

    @MainActor
    func testRealAccountRegistrationOnboardingAndUsernameEmailSignIn() async throws {
        // These credentials belong only to this run. Never use a person's
        // account or send email; the teardown removes the generated account.
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let username = "uitest" + String(suffix.prefix(12))
        let email = "tempo.ui." + suffix + "@example.com"
        let password = "Tu!9" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        addTeardownBlock {
            try await Self.deleteDisposableAccount(email: email, password: password)
        }

        var app = launchApp()
        let create = element("auth.createAccount", in: app)
        XCTAssertTrue(create.waitForExistence(timeout: 15))
        create.tap()
        enter(email, into: "auth.email", in: app)
        enter(username, into: "auth.username", in: app)
        enter(password, into: "auth.password", in: app)
        tapButton("auth.submit", in: app)

        let onboarding = element("onboarding.profile.title", in: app)
        XCTAssertTrue(onboarding.waitForExistence(timeout: 50), "Real registration did not reach onboarding. \(accountError(in: app))")
        capture(app, named: "Live account created - onboarding")
        tapButton("onboarding.profile.continue", in: app)
        let sport = element("sport.selection.run", in: app)
        XCTAssertTrue(sport.waitForExistence(timeout: 30), "Real profile save did not advance to sports")
        sport.tap()
        tapButton("onboarding.sports.continue", in: app)
        XCTAssertTrue(element("onboarding.finish", in: app).waitForExistence(timeout: 30), "Real sports save did not advance to connections")
        tapButton("onboarding.finish", in: app)
        XCTAssertTrue(element("screen.summary", in: app).waitForExistence(timeout: 30), "Onboarding should finish without requiring Strava or Apple Health")
        capture(app, named: "Live account onboarding completed")

        app.terminate()
        app = launchApp(preserveSession: true)
        XCTAssertTrue(element("screen.summary", in: app).waitForExistence(timeout: 30), "Relaunch should restore the real Keychain session without another login. \(accountError(in: app))")
        XCTAssertFalse(element("auth.signIn", in: app).exists, "A stored real session must not return to the sign-in screen")
        capture(app, named: "Live Keychain session preserved after relaunch")

        for (identifier, name) in [(username, "username"), (email, "email")] {
            app.terminate()
            app = launchApp()
            let signIn = element("auth.signIn", in: app)
            XCTAssertTrue(signIn.waitForExistence(timeout: 15), "UI test restart must begin independently of Keychain state")
            signIn.tap()
            enter(identifier, into: "auth.email", in: app)
            enter(password, into: "auth.password", in: app)
            tapButton("auth.submit", in: app)
            XCTAssertTrue(element("screen.summary", in: app).waitForExistence(timeout: 50), "Real \(name) sign-in failed. \(accountError(in: app))")
            capture(app, named: "Live sign-in by " + name)
        }
        app.terminate()
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

    func testRealHealthKitAuthorizationWriteReadAndCleanup() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-authenticated", "--ui-testing-healthkit", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let healthTab = element("tab.3", in: app)
        XCTAssertTrue(healthTab.waitForExistence(timeout: 15))
        healthTab.tap()
        let start = element("healthkit.integration.start", in: app)
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        start.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let result = element("healthkit.integration.result", in: app)
        let deadline = Date().addingTimeInterval(100)
        var capturedPermission = false
        while Date() < deadline {
            if result.exists && (result.label.hasPrefix("HEALTHKIT_PASS") || result.label.hasPrefix("HEALTHKIT_FAIL")) { break }
            for host in [app, springboard] {
                for label in ["Turn On All", "Allow All", "Turn On All Categories", "Tümünü Aç", "Tümüne İzin Ver"] {
                    let control = host.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
                    if control.exists && control.isHittable {
                        if !capturedPermission { capture(app, named: "Real HealthKit permission sheet"); capturedPermission = true }
                        control.tap()
                    }
                }
                for label in ["Allow", "İzin Ver"] {
                    let control = host.buttons[label]
                    if control.exists && control.isHittable && control.isEnabled { control.tap() }
                }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        capture(app, named: "Real HealthKit read-write result")
        XCTAssertTrue(result.exists && result.label.hasPrefix("HEALTHKIT_PASS"), "Real HealthKit integration did not pass: \(result.exists ? result.label : app.debugDescription)")
    }

    private func launchApp(authenticated: Bool = false, preserveSession: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        if authenticated {
            app.launchArguments.append("--ui-testing-authenticated")
        }
        if preserveSession {
            app.launchArguments.append("--ui-testing-preserve-session")
        }
        app.launch()
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func enter(_ text: String, into identifier: String, in app: XCUIApplication) {
        let container = element(identifier, in: app)
        XCTAssertTrue(container.waitForExistence(timeout: 8), "Missing input \(identifier)")
        let field: XCUIElement
        if container.elementType == .textField || container.elementType == .secureTextField {
            field = container
        } else if container.descendants(matching: .textField).firstMatch.exists {
            field = container.descendants(matching: .textField).firstMatch
        } else {
            field = container.descendants(matching: .secureTextField).firstMatch
        }
        XCTAssertTrue(field.exists, "Input \(identifier) must contain a text field")
        field.tap()
        field.typeText(text)
    }

    private func tapButton(_ identifier: String, in app: XCUIApplication) {
        let button = element(identifier, in: app)
        for _ in 0..<6 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 8), "Missing action \(identifier)")
        XCTAssertTrue(button.isEnabled, "Action \(identifier) should be enabled")
        button.tap()
    }

    private func accountError(in app: XCUIApplication) -> String {
        let error = element("auth.error", in: app)
        return error.exists ? error.label : "No account error was shown."
    }

    private static func deleteDisposableAccount(email: String, password: String) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var login = URLRequest(url: URL(string: "https://apitempo.com/api/account/login")!)
        login.httpMethod = "POST"
        login.setValue("application/json", forHTTPHeaderField: "Content-Type")
        login.httpBody = try JSONSerialization.data(withJSONObject: ["identifier": email, "password": password])
        let (data, response) = try await session.data(for: login)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { return } // Registration may have failed before creating a user.
        guard status == 200,
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = result["token"] as? String else {
            throw NSError(domain: "TempoDisposableAccountCleanup", code: status, userInfo: [NSLocalizedDescriptionKey: "Could not authenticate the disposable UI test account for cleanup."])
        }
        var deletion = URLRequest(url: URL(string: "https://apitempo.com/api/account")!)
        deletion.httpMethod = "DELETE"
        deletion.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let (_, deletionResponse) = try await session.data(for: deletion)
        let deletionStatus = (deletionResponse as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(deletionStatus) else {
            throw NSError(domain: "TempoDisposableAccountCleanup", code: deletionStatus, userInfo: [NSLocalizedDescriptionKey: "Could not delete the disposable UI test account."])
        }
    }

    private func capture(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
