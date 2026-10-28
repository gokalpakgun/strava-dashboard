import Combine
import Foundation
import Security
import OSLog

struct TempoUserProfile: Codable, Equatable {
    let id: String
    let email: String
    var username: String
    var displayName: String
    var avatarBase64: String?
    var sports: [String]
    var onboardingComplete: Bool
    let createdAt: String?
}

enum TempoSportChoice: String, CaseIterable, Codable, Identifiable {
    case run
    case cycling
    case walking
    case hiking
    case swimming
    case fitness
    case tennis
    case basketball
    case football
    case volleyball
    case padel
    case badminton
    case yoga

    var id: String { rawValue }

    var title: String {
        switch self {
        case .run: return "Koşu".tempoLocalized
        case .cycling: return "Bisiklet".tempoLocalized
        case .walking: return "Yürüyüş".tempoLocalized
        case .hiking: return "Doğa yürüyüşü".tempoLocalized
        case .swimming: return "Yüzme".tempoLocalized
        case .fitness: return "Fitness".tempoLocalized
        case .tennis: return "Tenis".tempoLocalized
        case .basketball: return "Basketbol".tempoLocalized
        case .football: return "Futbol".tempoLocalized
        case .volleyball: return "Voleybol".tempoLocalized
        case .padel: return "Padel".tempoLocalized
        case .badminton: return "Badminton".tempoLocalized
        case .yoga: return "Yoga".tempoLocalized
        }
    }

    var symbol: String {
        switch self {
        case .run: return "figure.run"
        case .cycling: return "bicycle"
        case .walking: return "figure.walk"
        case .hiking: return "figure.hiking"
        case .swimming: return "figure.pool.swim"
        case .fitness: return "dumbbell.fill"
        case .tennis: return "tennis.racket"
        case .basketball: return "basketball.fill"
        case .football: return "soccerball"
        case .volleyball: return "volleyball.fill"
        case .padel: return "figure.racquetball"
        case .badminton: return "figure.badminton"
        case .yoga: return "figure.yoga"
        }
    }

    var supportsDistance: Bool { TempoSport(rawValue: rawValue).supportsDistance }
    func distanceText(_ kilometres: Double) -> String { TempoSport(rawValue: rawValue).distanceText(kilometres) }

    var facilitySearchQueries: [String] {
        switch self {
        case .run: return ["koşu parkuru", "atletizm pisti", "running track"]
        case .cycling: return ["bisiklet parkuru", "bisiklet parkı", "velodrom", "cycling track"]
        case .walking: return ["yürüyüş parkuru", "yürüyüş yolu", "walking trail"]
        case .hiking: return ["doğa yürüyüşü parkuru", "parkur başlangıcı", "trailhead"]
        case .swimming: return ["yüzme havuzu", "kapalı yüzme havuzu", "olimpik havuz", "swimming pool"]
        case .fitness: return ["spor salonu", "fitness merkezi", "gym", "crossfit salonu"]
        case .tennis: return ["tenis kortu", "tenis kulübü", "tennis court", "tennis club"]
        case .basketball: return ["basketbol sahası", "basketbol salonu", "basketball court"]
        case .football: return ["halı saha", "futbol sahası", "stadyum", "football field"]
        case .volleyball: return ["voleybol sahası", "voleybol salonu", "beach volleyball court"]
        case .padel: return ["padel kortu", "padel kulübü", "padel court"]
        case .badminton: return ["badminton salonu", "badminton kortu", "badminton court", "badminton club"]
        case .yoga: return ["yoga stüdyosu", "yoga merkezi", "yoga studio"]
        }
    }

    var facilitySearchQuery: String? { facilitySearchQueries.first }

    var openStreetMapSelectors: [String] {
        switch self {
        case .run:
            return ["[\"sport\"~\"running|athletics\"]", "[\"leisure\"=\"track\"][\"sport\"~\"running|athletics\"]"]
        case .cycling:
            return ["[\"sport\"~\"cycling|bmx\"]", "[\"leisure\"=\"track\"][\"sport\"=\"cycling\"]"]
        case .walking, .hiking:
            return ["[\"information\"=\"trailhead\"]", "[\"information\"=\"guidepost\"]"]
        case .swimming:
            return ["[\"leisure\"=\"swimming_pool\"]", "[\"sport\"~\"(^|;)swimming(;|$)\"]", "[\"swimming_pool\"]"]
        case .fitness:
            return ["[\"leisure\"=\"fitness_centre\"]", "[\"leisure\"=\"fitness_station\"]", "[\"sport\"~\"fitness|weightlifting|crossfit\"]"]
        case .tennis:
            return ["[\"sport\"~\"(^|;)tennis(;|$)\"]"]
        case .basketball:
            return ["[\"sport\"~\"(^|;)basketball(;|$)\"]"]
        case .football:
            return ["[\"sport\"~\"(^|;)(soccer|football)(;|$)\"]"]
        case .volleyball:
            return ["[\"sport\"~\"(^|;)(volleyball|beachvolleyball)(;|$)\"]"]
        case .padel:
            return ["[\"sport\"~\"(^|;)(padel|paddle_tennis)(;|$)\"]"]
        case .badminton:
            return ["[\"sport\"~\"(^|;)badminton(;|$)\"]"]
        case .yoga:
            return ["[\"sport\"~\"(^|;)yoga(;|$)\"]"]
        }
    }

    // Apple natural-language search can return adjacent or generic sports venues.
    // Keep only explicit name matches; OSM sport tags can still identify unnamed courts.
    func matchesFacilityName(_ name: String) -> Bool {
        let text = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().replacingOccurrences(of: "ı", with: "i")
        let keywords: [String]
        switch self {
        case .run: keywords = ["kosu", "atletizm", "athletic", "running"]
        case .cycling:
            if ["motorcycling", "motorcycle", "motorbike", "motocross", "motokros", "motosiklet"].contains(where: { text.contains($0) }) && !["bisiklet", "bicycle", "bmx", "velodrom"].contains(where: { text.contains($0) }) { return false }
            keywords = ["bisiklet", "cycling", "velodrom", "bmx", "bike park", "cycle track", "bicycle"]
        case .walking: keywords = ["yuruyus", "walking", "walkway", "nature trail"]
        case .hiking: keywords = ["doga yuruyus", "hiking", "trailhead", "trekking", "yuruyus parkur", "nature trail"]
        case .swimming:
            if ["bilardo", "billiard", "pool hall", "pool bar"].contains(where: { text.contains($0) }) { return false }
            if text.split(whereSeparator: { !$0.isLetter }).contains("pool") { return true }
            keywords = ["yuzme", "havuz", "swimming", "aquatic"]
        case .fitness:
            let explicitFitness = ["fitness", "crossfit", "strength", "pilates", "calisthenics"]
            if explicitFitness.contains(where: { text.contains($0) }) { return true }
            if ["basket", "voley", "volley", "futbol", "soccer", "tenis", "tennis", "badminton", "padel"].contains(where: { text.contains($0) }) { return false }
            keywords = ["gym", "spor salonu", "antrenman salonu"]
        case .tennis:
            let courtName = ["masa tenisi", "table tennis", "paddle tennis", "padel tennis", "padel tenis"].reduce(text) { $0.replacingOccurrences(of: $1, with: "") }
            return courtName.contains("tenis") || courtName.contains("tennis")
        case .basketball: keywords = ["basketbol", "basketball", "basket sahas", "basket court"]
        case .football: keywords = ["futbol", "football", "soccer", "hali saha", "halisaha"]
        case .volleyball: keywords = ["voleybol", "volleyball", "beachvolley"]
        case .padel: keywords = ["padel", "paddle tennis"]
        case .badminton: keywords = ["badminton"]
        case .yoga: keywords = ["yoga"]
        }
        return keywords.contains { text.contains($0) }
    }

    func matchesFacilityTags(_ tags: [String: String]) -> Bool {
        let sports = Set((tags["sport"] ?? "").lowercased().split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        switch self {
        case .run: return !sports.isDisjoint(with: ["running", "athletics", "trail_running"])
        case .cycling: return !sports.isDisjoint(with: ["cycling", "bmx", "bicycle"])
        case .walking, .hiking:
            guard tags["foot"] != "no", tags["hiking"] != "no" else { return false }
            guard sports.isEmpty || !sports.isDisjoint(with: ["walking", "hiking", "running"]) else { return false }
            return ["trailhead", "guidepost"].contains(tags["information"] ?? "")
        case .swimming: return tags["leisure"] == "swimming_pool" || sports.contains("swimming")
        case .fitness: return ["fitness_centre", "fitness_station"].contains(tags["leisure"] ?? "") || !sports.isDisjoint(with: ["fitness", "weightlifting", "crossfit", "calisthenics"])
        case .tennis: return sports.contains("tennis")
        case .basketball: return sports.contains("basketball")
        case .football: return !sports.isDisjoint(with: ["soccer", "football"])
        case .volleyball: return !sports.isDisjoint(with: ["volleyball", "beachvolleyball"])
        case .padel: return !sports.isDisjoint(with: ["padel", "paddle_tennis"])
        case .badminton: return sports.contains("badminton")
        case .yoga: return sports.contains("yoga")
        }
    }

    func matches(activityType: String?) -> Bool {
        let value = (activityType ?? "").lowercased()
        switch self {
        case .run: return value.contains("run")
        case .cycling: return value.contains("ride") || value.contains("cycl") || value.contains("bike")
        case .walking: return value.contains("walk")
        case .hiking: return value.contains("hike")
        case .swimming: return value.contains("swim")
        case .fitness: return value.contains("workout") || value.contains("weight") || value.contains("crossfit")
        case .tennis: return value.contains("tennis")
        case .basketball: return value.contains("basketball")
        case .football: return value.contains("soccer") || value.contains("football")
        case .volleyball: return value.contains("volleyball")
        case .padel: return value.contains("padel")
        case .badminton: return value.contains("badminton")
        case .yoga: return value.contains("yoga")
        }
    }
}

@MainActor
final class TempoAccountStore: ObservableObject {
    @Published private(set) var profile: TempoUserProfile?
    @Published private(set) var isRestoring: Bool
    @Published private(set) var isBusy = false
    @Published private(set) var stravaRevocationFailed = false
    @Published var errorMessage = ""

    private let baseURL = URL(string: "https://apitempo.com")!
    private var sessionToken: String?
    private var operationGeneration = UUID()
#if DEBUG
    private static let networkLog = Logger(subsystem: "com.apitempo.tempohealth.account-network", category: "requests")
#endif
    private static let apiSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: configuration)
    }()

    // Challenge names can require server-side moderation. Keep this bounded
    // session separate from the faster account login/registration transport.
    private static let socialSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 35
        configuration.timeoutIntervalForResource = 45
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    var isAuthenticated: Bool { profile != nil && sessionToken != nil }
    var authorizationToken: String? { sessionToken }

    init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-authenticated") {
            sessionToken = "ui-test-session"
            profile = TempoUserProfile(
                id: "ui-test-account",
                email: "tester@example.com",
                username: "tempo_tester",
                displayName: "Tempo Tester",
                avatarBase64: nil,
                sports: ["run", "tennis"],
                onboardingComplete: true,
                createdAt: nil
            )
            isRestoring = false
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           !ProcessInfo.processInfo.arguments.contains("--ui-testing-preserve-session") {
            // UI tests start independently of any real session saved by an
            // earlier test. The explicit preserve flag exercises normal
            // Keychain/cache loading and session restoration after relaunch.
            sessionToken = nil
            profile = nil
            isRestoring = false
            return
        }
#endif
        let storedToken = AccountTokenStore.read()
        let cachedProfile = storedToken == nil ? nil : AccountProfileCache.read()
        sessionToken = storedToken
        profile = cachedProfile
        isRestoring = storedToken != nil && cachedProfile == nil
        if storedToken != nil {
            Task { await restoreSession() }
        }
    }

    @discardableResult
    func signUp(email: String, username: String, password: String) async -> Bool {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return await authenticate(path: "/api/account/signup", payload: AccountCredentials(email: cleanEmail, username: cleanUsername, password: password))
    }

    @discardableResult
    func signIn(identifier: String, password: String) async -> Bool {
        await authenticate(
            path: "/api/account/login",
            payload: AccountLoginRequest(identifier: identifier, password: password)
        )
    }

    @discardableResult
    func requestPasswordReset(email: String) async -> Bool {
        guard !isBusy else { return false }
        let operation = beginOperation()
        errorMessage = ""
        defer { finishOperation(operation) }
        do {
            _ = try await request(
                path: "/api/account/password/forgot",
                method: "POST",
                body: PasswordResetRequest(email: email),
                authenticated: false
            )
            guard operationGeneration == operation, !Task.isCancelled else { return false }
            return true
        } catch {
            guard operationGeneration == operation else { return false }
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func updateProfile(
        displayName: String? = nil,
        username: String? = nil,
        sports: Set<TempoSportChoice>? = nil,
        avatarData: Data? = nil,
        onboardingComplete: Bool? = nil
    ) async -> Bool {
        guard sessionToken != nil, !isBusy else { return false }
        let operation = beginOperation()
        errorMessage = ""
        defer { finishOperation(operation) }
        let avatar = avatarData.map { "data:image/jpeg;base64," + $0.base64EncodedString() }
        let payload = ProfileUpdate(
            displayName: displayName,
            username: username,
            avatarBase64: avatar,
            sports: sports.map { $0.map(\.rawValue).sorted() },
            onboardingComplete: onboardingComplete
        )
        do {
            let envelope = try await request(path: "/api/account/profile", method: "PATCH", body: payload, authenticated: true)
            guard operationGeneration == operation, !Task.isCancelled else { return false }
            guard let user = envelope.user else { throw AccountError.server("Profil kaydedilemedi.") }
            profile = user
            AccountProfileCache.save(user)
            return true
        } catch {
            guard operationGeneration == operation else { return false }
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }

    func signOut() async {
        let signingOutToken = sessionToken
        TempoNotifications.shared.detach()
        if sessionToken != nil {
            _ = try? await request(path: "/api/account/logout", method: "POST", body: EmptyPayload(), authenticated: true)
        }
        guard sessionToken == signingOutToken else { return }
        clearLocalSession()
    }

    func loadSocial() async throws -> TempoSocialSnapshot {
        let data = try await socialRequest(path: "/api/account/social", method: "GET", body: Optional<EmptyPayload>.none)
        return try JSONDecoder().decode(TempoSocialSnapshot.self, from: data)
    }

    func sendFriendRequest(username: String) async throws -> Bool {
        let data = try await socialRequest(path: "/api/account/social/friends", method: "POST", body: SocialFriendRequest(username: username))
        return (try? JSONDecoder().decode(SocialFriendRequestResult.self, from: data).accepted) ?? false
    }

    func respondToFriendRequest(id: String, accept: Bool) async throws {
        _ = try await socialRequest(path: "/api/account/social/requests", method: "POST", body: SocialFriendResponse(requestId: id, action: accept ? "accept" : "decline"))
    }

    func createSocialChallenge(title: String, metric: TempoSocialMetric, friendIds: [String]) async throws -> TempoSocialChallenge {
        let data = try await socialRequest(path: "/api/account/social/challenges", method: "POST", body: SocialChallengeCreate(title: title, metric: metric.rawValue, friendIds: friendIds))
        return try JSONDecoder().decode(SocialChallengeCreated.self, from: data).challenge
    }

    @discardableResult
    func respondToSocialChallenge(id: String, action: String) async throws -> TempoSocialChallenge {
        let data = try await socialRequest(path: "/api/account/social/challenges/\(id)", method: "POST", body: SocialChallengeAction(action: action))
        return try JSONDecoder().decode(SocialChallengeCreated.self, from: data).challenge
    }

    func setSocialBlock(userId: String, blocked: Bool) async throws {
        _ = try await socialRequest(path: "/api/account/social/blocks", method: "POST", body: SocialBlockAction(userId: userId, action: blocked ? "block" : "unblock"))
    }

    func reportSocialUser(userId: String, category: String = "inappropriate") async throws {
        _ = try await socialRequest(path: "/api/account/social/reports", method: "POST", body: SocialReportRequest(userId: userId, challengeId: nil, category: category))
    }

    func reportSocialChallenge(id: String, category: String = "inappropriate") async throws {
        _ = try await socialRequest(path: "/api/account/social/reports", method: "POST", body: SocialReportRequest(userId: nil, challengeId: id, category: category))
    }

    @discardableResult
    func setSocialChallengeHealthSharing(id: String, enabled: Bool) async throws -> TempoSocialChallenge {
        let data = try await socialRequest(path: "/api/account/social/challenges/\(id)", method: "POST", body: SocialChallengeAction(action: "share", share: enabled))
        return try JSONDecoder().decode(SocialChallengeCreated.self, from: data).challenge
    }

    func restoreSessionIfNeeded() {
        guard sessionToken != nil, profile == nil, !isRestoring, !isBusy else { return }
        isRestoring = true
        Task { await restoreSession() }
    }

    @discardableResult
    func deleteAccount() async -> Bool {
        guard sessionToken != nil, !isBusy else { return false }
        let operation = beginOperation()
        errorMessage = ""
        stravaRevocationFailed = false
        defer { finishOperation(operation) }
        do {
            let envelope = try await request(path: "/api/account", method: "DELETE", body: EmptyPayload(), authenticated: true)
            guard operationGeneration == operation, !Task.isCancelled else { return false }
            stravaRevocationFailed = envelope.stravaRevoked == false
            TempoNotifications.shared.detach(eraseAccountData: true)
            clearLocalSession()
            return true
        } catch {
            guard operationGeneration == operation else { return false }
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func restoreSession() async {
        let restoringToken = sessionToken
        defer { if sessionToken == restoringToken { isRestoring = false } }
        do {
            let envelope = try await request(path: "/api/account/me", method: "GET", body: Optional<EmptyPayload>.none, authenticated: true)
            // A slower response from the old session must not replace the
            // profile after the user signs out or signs in to another account.
            guard sessionToken == restoringToken else { return }
            guard let user = envelope.user else { throw AccountError.server("Hesap bilgisi alınamadı.") }
            profile = user
            AccountProfileCache.save(user)
        } catch {
            guard sessionToken == restoringToken, !(error is CancellationError) else { return }
            // A temporary connection problem must not sign the user out. The
            // request method clears the session only when the server returns 401.
            if profile == nil, sessionToken != nil {
                errorMessage = "Hesabına şu anda ulaşılamadı. Bağlantı yeniden kurulunca otomatik olarak denenecek."
            }
        }
    }

    private func socialRequest<Body: Encodable>(path: String, method: String, body: Body?) async throws -> Data {
        guard let sessionToken, !sessionToken.isEmpty else { throw AccountError.server("Tempo hesabına yeniden giriş yapman gerekiyor.") }
        var request = URLRequest(url: URL(string: path, relativeTo: baseURL)!)
        request.httpMethod = method
        request.timeoutInterval = 35
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Bundle.main.preferredLocalizations.first ?? "en", forHTTPHeaderField: "Accept-Language")
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await Self.socialSession.data(for: request)
        try Task.checkCancellation()
        guard self.sessionToken == sessionToken else { throw CancellationError() }
        guard let http = response as? HTTPURLResponse else { throw AccountError.server("Sosyal bölümden yanıt alınamadı.") }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401, self.sessionToken == sessionToken { clearLocalSession() }
            let envelope = try? JSONDecoder().decode(AccountEnvelope.self, from: data)
            throw AccountError.server(envelope?.error ?? "Sosyal işlem tamamlanamadı.")
        }
        return data
    }

    private func authenticate<Payload: Encodable>(path: String, payload: Payload) async -> Bool {
        guard !isBusy else { return false }
        let operation = beginOperation()
        errorMessage = ""
        defer { finishOperation(operation) }
        do {
            let envelope = try await request(path: path, method: "POST", body: payload, authenticated: false)
            guard operationGeneration == operation, !Task.isCancelled else { return false }
            guard let token = envelope.token, let user = envelope.user else {
                throw AccountError.server("Hesap oturumu başlatılamadı.")
            }
            guard AccountTokenStore.save(token) else {
                throw AccountError.server("Oturum anahtarı iPhone’da güvenle saklanamadı.")
            }
            sessionToken = token
            profile = user
            AccountProfileCache.save(user)
            return true
        } catch {
            guard operationGeneration == operation else { return false }
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func request<Body: Encodable>(
        path: String,
        method: String,
        body: Body?,
        authenticated: Bool
    ) async throws -> AccountEnvelope {
        var request = URLRequest(url: URL(string: path, relativeTo: baseURL)!)
        request.httpMethod = method
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Bundle.main.preferredLocalizations.first ?? "en", forHTTPHeaderField: "Accept-Language")
        request.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "X-Tempo-Request-ID")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let requestSessionToken = authenticated ? sessionToken : nil
        if authenticated {
            guard let sessionToken else { throw AccountError.server("Tempo oturumunun süresi doldu.") }
            request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        }
        // Two bounded attempts keep the account UI responsive on a stalled route.
        let retryDelays: [UInt64] = [0, 350_000_000]
        // Signup has a request ID and the other listed operations can safely
        // be repeated. A lost response must not automatically send several
        // reset emails or repeat an account deletion.
        let canRetry = method == "GET" || ["/api/account/signup", "/api/account/login", "/api/account/logout"].contains(path)
        var lastError: Error = AccountError.server("Sunucudan yanıt alınamadı.")

        for attempt in retryDelays.indices {
            try Task.checkCancellation()
            if authenticated && sessionToken != requestSessionToken { throw CancellationError() }
            if retryDelays[attempt] > 0 {
                try await Task.sleep(nanoseconds: retryDelays[attempt])
            }
            if authenticated && sessionToken != requestSessionToken { throw CancellationError() }
            do {
#if DEBUG
                Self.networkLog.info("begin \(method, privacy: .public) \(path, privacy: .public) attempt=\(attempt + 1)")
#endif
                let (data, response) = try await Self.apiSession.data(for: request)
                try Task.checkCancellation()
                if authenticated && sessionToken != requestSessionToken { throw CancellationError() }
                guard let http = response as? HTTPURLResponse else {
                    throw AccountError.server("Sunucudan yanıt alınamadı.")
                }
#if DEBUG
                Self.networkLog.info("response \(method, privacy: .public) \(path, privacy: .public) status=\(http.statusCode)")
#endif
                let envelope = try? JSONDecoder().decode(AccountEnvelope.self, from: data)
                guard (200..<300).contains(http.statusCode) else {
                    if http.statusCode == 401 && authenticated && sessionToken == requestSessionToken { clearLocalSession() }
                    let message = envelope?.error ?? envelope?.message ?? "İşlem tamamlanamadı."
                    let retryable = http.statusCode == 408 || http.statusCode >= 500
                    let shortRetry = http.statusCode == 429 && http.value(forHTTPHeaderField: "Retry-After") == "1"
                    if canRetry, retryable || shortRetry, attempt < retryDelays.count - 1 {
                        lastError = AccountError.server(message)
                        if shortRetry { try await Task.sleep(nanoseconds: 1_000_000_000) }
                        continue
                    }
                    throw AccountError.server(message)
                }
                if http.statusCode == 204 {
                    return AccountEnvelope(token: nil, user: nil, error: nil, message: nil, stravaRevoked: nil)
                }
                guard let envelope else { throw AccountError.server("Sunucudan yanıt alınamadı.") }
                return envelope
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
#if DEBUG
                Self.networkLog.info("failure \(method, privacy: .public) \(path, privacy: .public) code=\((error as NSError).code)")
#endif
                lastError = error
                if error is AccountError { throw error }
                if canRetry, attempt < retryDelays.count - 1 { continue }
                break
            }
        }
        if let urlError = lastError as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost:
                throw AccountError.server("Bağlantı kurulamadı. İnternetini kontrol edip tekrar dene.")
            default: break
            }
        }
        throw lastError
    }

    private func beginOperation() -> UUID {
        let id = UUID()
        operationGeneration = id
        isBusy = true
        return id
    }

    private func finishOperation(_ id: UUID) {
        if operationGeneration == id { isBusy = false }
    }

    private func clearLocalSession() {
        operationGeneration = UUID()
        isBusy = false
        AccountTokenStore.delete()
        AccountProfileCache.delete()
        sessionToken = nil
        profile = nil
        isRestoring = false
    }
}

private enum AccountProfileCache {
    private static let key = "tempoAccountProfileCacheV1"

    static func read() -> TempoUserProfile? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TempoUserProfile.self, from: data)
    }

    static func save(_ profile: TempoUserProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func delete() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

private struct AccountCredentials: Encodable {
    let email: String
    let username: String?
    let password: String
}

private struct AccountLoginRequest: Encodable {
    let identifier: String
    let password: String
}

private struct PasswordResetRequest: Encodable {
    let email: String
}

private struct ProfileUpdate: Encodable {
    let displayName: String?
    let username: String?
    let avatarBase64: String?
    let sports: [String]?
    let onboardingComplete: Bool?
}

private struct EmptyPayload: Encodable {}
private struct SocialFriendRequest: Encodable { let username: String }
private struct SocialFriendRequestResult: Decodable { let accepted: Bool? }
private struct SocialFriendResponse: Encodable { let requestId: String; let action: String }
private struct SocialBlockAction: Encodable { let userId: String; let action: String }
private struct SocialReportRequest: Encodable { let userId: String?; let challengeId: String?; let category: String }
private struct SocialChallengeCreated: Decodable { let challenge: TempoSocialChallenge }
private struct SocialChallengeCreate: Encodable { let title: String; let metric: String; let friendIds: [String] }
private struct SocialChallengeAction: Encodable { let action: String; var share: Bool? = nil }
private struct AccountEnvelope: Decodable {
    let token: String?
    let user: TempoUserProfile?
    let error: String?
    let message: String?
    let stravaRevoked: Bool?
}

private enum AccountError: LocalizedError {
    case server(String)
    var errorDescription: String? {
        switch self {
        case let .server(message): return message
        }
    }
}

private enum AccountTokenStore {
    private static let service = "com.apitempo.tempohealth"
    private static let account = "tempo-account-access-token"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        return SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
