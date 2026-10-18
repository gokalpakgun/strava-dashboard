import Combine
import Foundation
import Security

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

    var facilitySearchQueries: [String] {
        switch self {
        case .run: return ["koşu parkuru", "atletizm pisti", "running track"]
        case .cycling: return ["bisiklet parkuru", "bisiklet parkı", "velodrom", "cycling track"]
        case .walking: return ["yürüyüş parkuru", "yürüyüş yolu", "walking trail"]
        case .hiking: return ["doğa yürüyüşü parkuru", "parkur başlangıcı", "trailhead"]
        case .swimming: return ["yüzme havuzu", "kapalı yüzme havuzu", "olimpik havuz", "swimming pool"]
        case .fitness: return ["spor salonu", "fitness merkezi", "gym", "crossfit salonu"]
        case .tennis: return ["tenis kortu", "tenis kulübü", "tennis court", "tennis club"]
        case .basketball: return ["basketbol sahası", "basketbol salonu", "basketball court", "spor kompleksi"]
        case .football: return ["halı saha", "futbol sahası", "stadyum", "football field"]
        case .volleyball: return ["voleybol sahası", "voleybol salonu", "beach volleyball court", "spor salonu"]
        case .padel: return ["padel kortu", "padel kulübü", "padel court", "raket sporları"]
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
    private static let apiSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 18
        configuration.timeoutIntervalForResource = 25
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: configuration)
    }()

    var isAuthenticated: Bool { profile != nil && sessionToken != nil }
    var authorizationToken: String? { sessionToken }

    init() {
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
        isBusy = true
        errorMessage = ""
        defer { isBusy = false }
        do {
            _ = try await request(
                path: "/api/account/password/forgot",
                method: "POST",
                body: PasswordResetRequest(email: email),
                authenticated: false
            )
            return true
        } catch {
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
        isBusy = true
        errorMessage = ""
        defer { isBusy = false }
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
            guard let user = envelope.user else { throw AccountError.server("Profil kaydedilemedi.") }
            profile = user
            AccountProfileCache.save(user)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func signOut() async {
        if sessionToken != nil {
            _ = try? await request(path: "/api/account/logout", method: "POST", body: EmptyPayload(), authenticated: true)
        }
        clearLocalSession()
    }

    func loadSocial() async throws -> TempoSocialSnapshot {
        let data = try await socialRequest(path: "/api/account/social", method: "GET", body: Optional<EmptyPayload>.none)
        return try JSONDecoder().decode(TempoSocialSnapshot.self, from: data)
    }

    func sendFriendRequest(username: String) async throws {
        _ = try await socialRequest(path: "/api/account/social/friends", method: "POST", body: SocialFriendRequest(username: username))
    }

    func respondToFriendRequest(id: String, accept: Bool) async throws {
        _ = try await socialRequest(path: "/api/account/social/requests", method: "POST", body: SocialFriendResponse(requestId: id, action: accept ? "accept" : "decline"))
    }

    func createSocialChallenge(title: String, metric: TempoSocialMetric, friendIds: [String]) async throws {
        _ = try await socialRequest(path: "/api/account/social/challenges", method: "POST", body: SocialChallengeCreate(title: title, metric: metric.rawValue, friendIds: friendIds))
    }

    func respondToSocialChallenge(id: String, action: String) async throws {
        _ = try await socialRequest(path: "/api/account/social/challenges/\(id)", method: "POST", body: SocialChallengeAction(action: action))
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

    func setSocialChallengeHealthSharing(id: String, enabled: Bool) async throws {
        _ = try await socialRequest(path: "/api/account/social/challenges/\(id)", method: "POST", body: SocialChallengeAction(action: "share", share: enabled))
    }

    func restoreSessionIfNeeded() {
        guard sessionToken != nil, profile == nil, !isRestoring, !isBusy else { return }
        isRestoring = true
        Task { await restoreSession() }
    }

    @discardableResult
    func deleteAccount() async -> Bool {
        guard sessionToken != nil, !isBusy else { return false }
        isBusy = true
        errorMessage = ""
        stravaRevocationFailed = false
        defer { isBusy = false }
        do {
            let envelope = try await request(path: "/api/account", method: "DELETE", body: EmptyPayload(), authenticated: true)
            stravaRevocationFailed = envelope.stravaRevoked == false
            clearLocalSession()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func restoreSession() async {
        defer { isRestoring = false }
        do {
            let envelope = try await request(path: "/api/account/me", method: "GET", body: Optional<EmptyPayload>.none, authenticated: true)
            guard let user = envelope.user else { throw AccountError.server("Hesap bilgisi alınamadı.") }
            profile = user
            AccountProfileCache.save(user)
        } catch {
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
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await Self.apiSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AccountError.server("Sosyal bölümden yanıt alınamadı.") }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(AccountEnvelope.self, from: data)
            throw AccountError.server(envelope?.error ?? "Sosyal işlem tamamlanamadı.")
        }
        return data
    }

    private func authenticate<Payload: Encodable>(path: String, payload: Payload) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        errorMessage = ""
        defer { isBusy = false }
        do {
            let envelope = try await request(path: path, method: "POST", body: payload, authenticated: false)
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
        request.timeoutInterval = 18
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "X-Tempo-Request-ID")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        if authenticated {
            guard let sessionToken else { throw AccountError.server("Tempo oturumunun süresi doldu.") }
            request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        }
        let retryDelays: [UInt64] = [0, 350_000_000, 900_000_000]
        var lastError: Error = AccountError.server("Sunucudan yanıt alınamadı.")

        for attempt in retryDelays.indices {
            if retryDelays[attempt] > 0 {
                try? await Task.sleep(nanoseconds: retryDelays[attempt])
            }
            do {
                let (data, response) = try await Self.apiSession.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw AccountError.server("Sunucudan yanıt alınamadı.")
                }
                let envelope = (try? JSONDecoder().decode(AccountEnvelope.self, from: data)) ?? AccountEnvelope(token: nil, user: nil, error: nil, message: nil, stravaRevoked: nil)
                guard (200..<300).contains(http.statusCode) else {
                    if http.statusCode == 401 && authenticated { clearLocalSession() }
                    let message = envelope.error ?? envelope.message ?? "İşlem tamamlanamadı."
                    let retryable = http.statusCode == 408 || http.statusCode >= 500
                    if retryable, attempt < retryDelays.count - 1 {
                        lastError = AccountError.server(message)
                        continue
                    }
                    throw AccountError.server(message)
                }
                return envelope
            } catch {
                lastError = error
                if error is AccountError { throw error }
                if attempt < retryDelays.count - 1 { continue }
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

    private func clearLocalSession() {
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
private struct SocialFriendResponse: Encodable { let requestId: String; let action: String }
private struct SocialBlockAction: Encodable { let userId: String; let action: String }
private struct SocialReportRequest: Encodable { let userId: String?; let challengeId: String?; let category: String }
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
        delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
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
