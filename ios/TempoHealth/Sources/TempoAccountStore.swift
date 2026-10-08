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
        case .run: return "Koşu"
        case .cycling: return "Bisiklet"
        case .walking: return "Yürüyüş"
        case .hiking: return "Doğa yürüyüşü"
        case .swimming: return "Yüzme"
        case .fitness: return "Fitness"
        case .tennis: return "Tenis"
        case .basketball: return "Basketbol"
        case .football: return "Futbol"
        case .volleyball: return "Voleybol"
        case .padel: return "Padel"
        case .badminton: return "Badminton"
        case .yoga: return "Yoga"
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

    var facilitySearchQuery: String? {
        switch self {
        case .tennis: return "tennis court"
        case .basketball: return "basketball court"
        case .football: return "football field"
        case .volleyball: return "volleyball court"
        case .padel: return "padel court"
        case .badminton: return "badminton court"
        case .swimming: return "swimming pool"
        case .fitness: return "gym"
        default: return nil
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
    @Published var errorMessage = ""

    private let baseURL = URL(string: "https://apitempo.com")!
    private var sessionToken: String?

    var isAuthenticated: Bool { profile != nil && sessionToken != nil }

    init() {
        sessionToken = AccountTokenStore.read()
        isRestoring = sessionToken != nil
        if sessionToken != nil {
            Task { await restoreSession() }
        }
    }

    @discardableResult
    func signUp(email: String, username: String, password: String) async -> Bool {
        await authenticate(path: "/api/account/signup", payload: AccountCredentials(email: email, username: username, password: password))
    }

    @discardableResult
    func signIn(email: String, password: String) async -> Bool {
        await authenticate(path: "/api/account/login", payload: AccountCredentials(email: email, username: nil, password: password))
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

    @discardableResult
    func deleteAccount() async -> Bool {
        guard sessionToken != nil, !isBusy else { return false }
        isBusy = true
        errorMessage = ""
        defer { isBusy = false }
        do {
            _ = try await request(path: "/api/account", method: "DELETE", body: EmptyPayload(), authenticated: true)
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
        } catch {
            clearLocalSession()
        }
    }

    private func authenticate(path: String, payload: AccountCredentials) async -> Bool {
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
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        if authenticated {
            guard let sessionToken else { throw AccountError.server("Tempo oturumunun süresi doldu.") }
            request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AccountError.server("Sunucudan yanıt alınamadı.") }
        let envelope = (try? JSONDecoder().decode(AccountEnvelope.self, from: data)) ?? AccountEnvelope(token: nil, user: nil, error: nil)
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 && authenticated { clearLocalSession() }
            throw AccountError.server(envelope.error ?? "İşlem tamamlanamadı.")
        }
        return envelope
    }

    private func clearLocalSession() {
        AccountTokenStore.delete()
        sessionToken = nil
        profile = nil
        isRestoring = false
    }
}

private struct AccountCredentials: Encodable {
    let email: String
    let username: String?
    let password: String
}

private struct ProfileUpdate: Encodable {
    let displayName: String?
    let username: String?
    let avatarBase64: String?
    let sports: [String]?
    let onboardingComplete: Bool?
}

private struct EmptyPayload: Encodable {}
private struct AccountEnvelope: Decodable {
    let token: String?
    let user: TempoUserProfile?
    let error: String?
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