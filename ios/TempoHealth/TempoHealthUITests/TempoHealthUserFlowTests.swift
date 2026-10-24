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
        try enter(email, into: "auth.email", in: app)
        try enter(username, into: "auth.username", in: app)
        try enter(password, into: "auth.password", in: app)
        try tapButton("auth.submit", in: app)

        let onboarding = element("onboarding.profile.title", in: app)
        try require(onboarding.waitForExistence(timeout: 50), "Real registration did not reach onboarding. \(accountError(in: app))", in: app)
        dismissPasswordSavePrompt(in: app, timeout: 5)
        capture(app, named: "Live account created - onboarding")
        try tapButton("onboarding.profile.continue", in: app)
        let sport = element("sport.selection.run", in: app)
        try require(sport.waitForExistence(timeout: 30), "Real profile save did not advance to sports", in: app)
        sport.tap()
        try tapButton("onboarding.sports.continue", in: app)
        try require(element("onboarding.finish", in: app).waitForExistence(timeout: 30), "Real sports save did not advance to connections", in: app)
        try tapButton("onboarding.finish", in: app)
        try require(element("screen.summary", in: app).waitForExistence(timeout: 30), "Onboarding should finish without requiring Strava or Apple Health", in: app)
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
            try enter(identifier, into: "auth.email", in: app)
            try enter(password, into: "auth.password", in: app)
            try tapButton("auth.submit", in: app)
            try require(element("screen.summary", in: app).waitForExistence(timeout: 50), "Real \(name) sign-in failed. \(accountError(in: app))", in: app)
            dismissPasswordSavePrompt(in: app, timeout: 5)
            capture(app, named: "Live sign-in by " + name)
        }
        try await connectAndVerifyNativeHealth(in: app, email: email, password: password)
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


    func testNotificationsInboxPreferencesAndPermission() {
        let app = launchApp(authenticated: true)
        XCTAssertTrue(element("home.notifications", in: app).waitForExistence(timeout: 15))
        element("home.notifications", in: app).tap()
        XCTAssertTrue(element("notifications.settings", in: app).waitForExistence(timeout: 8))
        capture(app, named: "Notifications inbox")
        element("notifications.settings", in: app).tap()
        let friends = element("notifications.friends", in: app)
        XCTAssertTrue(friends.waitForExistence(timeout: 8))
        XCTAssertTrue(element("notifications.challenges", in: app).exists)
        friends.tap()
        capture(app, named: "Notification preferences")
        let enable = element("notifications.enable", in: app)
        if enable.exists {
            enable.tap()
            let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
            if allow.waitForExistence(timeout: 5) { allow.tap() }
            XCTAssertTrue(enable.waitForNonExistence(timeout: 8), "The permission request should resolve")
        }
        app.swipeUp()
        XCTAssertTrue(element("notifications.daily", in: app).waitForExistence(timeout: 5))
        capture(app, named: "Notification reminder options")
    }

    func testRepeatedPrimaryTabSwitchesKeepNavigationVisible() {
        let app = launchApp(authenticated: true)
        XCTAssertTrue(element("tab.0", in: app).waitForExistence(timeout: 15))
        for index in [1, 2, 3, 4, 0, 3, 1, 4, 2, 0] {
            element("tab.\(index)", in: app).tap()
            XCTAssertTrue(element("tab.0", in: app).isHittable)
            XCTAssertTrue(element("tab.4", in: app).isHittable)
        }
        XCTAssertTrue(element("screen.summary", in: app).waitForExistence(timeout: 8))
        capture(app, named: "Stable shell after repeated tab transitions")
    }


    func testWorkoutLedgerTotalsSportsAndActivityFiltersAgree() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-authenticated", "--ui-testing-workout-ledger", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(element("screen.summary", in: app).waitForExistence(timeout: 15))
        func reveal(_ id: String) -> XCUIElement {
            let target = element(id, in: app)
            for _ in 0..<7 where !target.isHittable { app.swipeUp() }
            XCTAssertTrue(target.exists && target.isHittable, "Missing workout control \(id)")
            return target
        }
        XCTAssertEqual(reveal("home.week.workouts").value as? String, "3", "Phone + Health copies must count once")
        XCTAssertEqual(element("home.week.duration", in: app).value as? String, "1 hr 30 min")
        XCTAssertEqual(element("home.week.distance", in: app).value as? String, "3.2 km")
        capture(app, named: "Workout ledger - consistent weekly totals")
        element("tab.1", in: app).tap()
        let tennis = element("activity.filter.sport:tennis", in: app)
        for _ in 0..<5 where !element("activity.filter.all", in: app).isHittable { app.swipeUp() }
        let bar = element("activity.filters", in: app)
        for _ in 0..<4 where !tennis.isHittable { bar.swipeLeft() }
        XCTAssertTrue(tennis.isHittable)
        tennis.tap()
        _ = reveal("workout.record.tennis")
        XCTAssertTrue(app.staticTexts["Fixture Health tennis"].exists)
        XCTAssertFalse(element("workout.record.run", in: app).exists)
        capture(app, named: "Workout ledger - Apple Health tennis filter")
        element("tab.2", in: app).tap()
        reveal("sport.open.basketball").tap()
        XCTAssertEqual(reveal("sport.total.workouts").value as? String, "1", "A performed sport must appear even if it was not selected in profile")
        capture(app, named: "Workout ledger - basketball imported into Sports")
    }

    @MainActor
    func testRealFriendRequestAppearsInNotificationInbox() async throws {
        let suffix = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)).lowercased()
        let password = "Tu!9" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let email = "tempo.notice.a." + suffix + "@example.com"
        let secondEmail = "tempo.notice.b." + suffix + "@example.com"
        let username = "uitestna" + suffix
        let secondUsername = "uitestnb" + suffix
        addTeardownBlock {
            var firstError: Error?
            for address in [email, secondEmail] {
                do { try await Self.deleteDisposableAccount(email: address, password: password) }
                catch { if firstError == nil { firstError = error } }
            }
            if let firstError { throw firstError }
        }
        let alice = try await Self.notificationAPI("/api/account/signup", body: ["email": email, "username": username, "password": password])
        let bob = try await Self.notificationAPI("/api/account/signup", body: ["email": secondEmail, "username": secondUsername, "password": password])
        guard let aliceToken = alice["token"] as? String, let bobToken = bob["token"] as? String else { XCTFail("Disposable notification accounts were not created"); return }
        _ = try await Self.notificationAPI("/api/account/profile", method: "PATCH", token: aliceToken, body: ["onboardingComplete": true, "sports": ["walking"]])
        _ = try await Self.notificationAPI("/api/account/social/friends", token: bobToken, body: ["username": username])
        var ready = false
        for _ in 0..<15 {
            let inbox = try await Self.notificationAPI("/api/account/notifications", method: "GET", token: aliceToken)
            if let notices = inbox["notifications"] as? [[String: Any]], notices.contains(where: { $0["type"] as? String == "friend_request" }) { ready = true; break }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        XCTAssertTrue(ready, "A real saved friend request must create an account-scoped inbox entry")
        let app = launchApp()
        try tapButton("auth.signIn", in: app)
        try enter(email, into: "auth.email", in: app)
        try enter(password, into: "auth.password", in: app)
        try tapButton("auth.submit", in: app)
        try require(element("home.notifications", in: app).waitForExistence(timeout: 40), "Real notification recipient could not sign in", in: app)
        dismissPasswordSavePrompt(in: app, timeout: 3)
        element("home.notifications", in: app).tap()
        let request = element("notification.friend_request", in: app)
        try require(request.waitForExistence(timeout: 25), "Real friend request did not appear in native notification inbox", in: app)
        capture(app, named: "Real friend request notification inbox")
        request.tap()
        try require(element("social.sections", in: app).waitForExistence(timeout: 10), "Notification should open Social", in: app)
        capture(app, named: "Notification opened social destination")
    }

    private static func notificationAPI(_ path: String, method: String = "POST", token: String? = nil, body: [String: Any]? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://apitempo.com" + path)!)
        request.httpMethod = method
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw NSError(domain: "TempoNotificationLiveTest", code: status, userInfo: [NSLocalizedDescriptionKey: "Notification test request failed: " + path]) }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
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

    @MainActor
    private func connectAndVerifyNativeHealth(in app: XCUIApplication, email: String, password: String) async throws {
        try tapButton("tab.3", in: app)
        let connect = app.buttons["Connect Apple Health"]
        try require(connect.waitForExistence(timeout: 10), "The real account should offer Apple Health connection", in: app)
        connect.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let emptyRead = app.staticTexts["Apple Health is connected, but no shared data was found. Check your Health permissions."]
        let synced = app.staticTexts["Your Apple Health data is up to date."]
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline && !emptyRead.exists && !synced.exists {
            for host in [app, springboard] {
                let all = host.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Turn On All")).firstMatch
                if all.exists && all.isHittable { all.tap() }
                let allow = host.buttons["Allow"]
                if allow.exists && allow.isHittable && allow.isEnabled { allow.tap() }
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        try require(emptyRead.exists || synced.exists, "Production Apple Health connection and sync did not complete", in: app)
        capture(app, named: "Real account production Apple Health connection")

        // A non-null server timestamp proves the production UI sent its native
        // Health snapshot with this real account's bearer token, even on a clean
        // simulator with no shared measurements. Do not invent missing values.
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var login = URLRequest(url: URL(string: "https://apitempo.com/api/account/login")!)
        login.httpMethod = "POST"
        login.timeoutInterval = 20
        login.setValue("application/json", forHTTPHeaderField: "Content-Type")
        login.httpBody = try JSONSerialization.data(withJSONObject: ["identifier": email, "password": password])
        let (loginData, loginResponse) = try await session.data(for: login)
        let loginObject = try JSONSerialization.jsonObject(with: loginData) as? [String: Any]
        guard (loginResponse as? HTTPURLResponse)?.statusCode == 200, let token = loginObject?["token"] as? String else {
            throw NSError(domain: "TempoNativeHealthSync", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not verify the disposable native Health session."])
        }
        var read = URLRequest(url: URL(string: "https://apitempo.com/api/account/health")!)
        read.timeoutInterval = 20
        read.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let (healthData, healthResponse) = try await session.data(for: read)
        let snapshot = try JSONSerialization.jsonObject(with: healthData) as? [String: Any]
        try require((healthResponse as? HTTPURLResponse)?.statusCode == 200 && snapshot?["updatedAt"] is String && snapshot?["days"] is [String: Any], "Native Health sync must reach the real account's server snapshot", in: app)
    }
    private func launchApp(authenticated: Bool = false, preserveSession: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
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

    private func enter(_ text: String, into identifier: String, in app: XCUIApplication) throws {
        let textField = app.textFields.matching(identifier: identifier).firstMatch
        let secureField = app.secureTextFields.matching(identifier: identifier).firstMatch
        let containers = app.descendants(matching: .any).matching(identifier: identifier)
        try require(textField.exists || secureField.exists || containers.firstMatch.waitForExistence(timeout: 8), "Missing input \(identifier)", in: app)

        // SwiftUI may propagate the HStack identifier to both its icon and input.
        // Prefer typed queries; an arbitrary firstMatch can be the icon.
        var resolved: XCUIElement?
        let deadline = Date().addingTimeInterval(8)
        repeat {
            if textField.exists {
                resolved = textField
            } else if secureField.exists {
                resolved = secureField
            } else {
                for container in containers.allElementsBoundByIndex {
                    let nestedText = container.descendants(matching: .textField).firstMatch
                    let nestedSecure = container.descendants(matching: .secureTextField).firstMatch
                    if nestedText.exists { resolved = nestedText; break }
                    if nestedSecure.exists { resolved = nestedSecure; break }
                }
            }
            if resolved == nil { Thread.sleep(forTimeInterval: 0.1) }
        } while resolved == nil && Date() < deadline

        try require(resolved != nil, "Input \(identifier) must contain a text field", in: app)
        guard let field = resolved else { return } // require above throws before this fallback.
        field.tap()
        field.typeText(text)
    }

    private func tapButton(_ identifier: String, in app: XCUIApplication) throws {
        let button = app.buttons.matching(identifier: identifier).firstMatch
        try require(button.waitForExistence(timeout: 8), "Missing action \(identifier)", in: app)
        if !button.isHittable { dismissPasswordSavePrompt(in: app, timeout: 2) }
        for _ in 0..<6 where !button.isHittable { app.swipeUp() }
        try require(button.isEnabled, "Action \(identifier) should be enabled", in: app)
        try require(button.isHittable, "Action \(identifier) should be reachable", in: app)
        button.tap()
    }

    private func dismissPasswordSavePrompt(in app: XCUIApplication, timeout: TimeInterval) {
        // Password AutoFill presents its own sheet after successful credentials.
        // Exercise the normal system UI without storing disposable test passwords.
        let prompt = app.sheets.matching(NSPredicate(format: "label == %@", "Save Password?")).firstMatch
        guard prompt.waitForExistence(timeout: timeout) else { return }
        let notNow = prompt.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 3), notNow.isHittable { notNow.tap() }
    }
    private func require(_ condition: Bool, _ message: String, in app: XCUIApplication) throws {
        guard !condition else { return }
        capture(app, named: "Account flow failure")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Account failure accessibility hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTFail(message)
        throw NSError(domain: "TempoLiveAccountFlow", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
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
