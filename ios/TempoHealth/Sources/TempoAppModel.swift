import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security
import UIKit

@MainActor
final class TempoAppModel: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var isConnected = false
    @Published private(set) var isBusy = false
    @Published private(set) var isLoadingDashboard = false
    @Published private(set) var isCoachLoading = false
    @Published private(set) var todayWaterMl = 0
    @Published private(set) var healthSyncEnabled = UserDefaults.standard.bool(forKey: "tempoHealthSyncEnabledV1")
    @Published private(set) var isHealthSyncing = false
    @Published private(set) var healthDays: [String: TempoHealthMetrics] = [:]
    @Published private(set) var healthLastSync: Date?
    @Published private(set) var healthError: String?
    @Published private(set) var dashboard: TempoDashboard?
    @Published private(set) var dashboardError: String?
    @Published private(set) var coachAnswer = ""
    @Published private(set) var coachPeriodDescription = ""
    @Published var status = "Strava hesabını bağlayarak başla."

    let dailyGoalMl = 2_000
    private let baseURL = URL(string: "https://apitempo.com")!
    private let healthStore = TempoHealthStore()
    private var webAuthSession: ASWebAuthenticationSession?
    private var pendingVerifier: String?
    private var lastDashboardRefresh: Date?
    private var accessToken: String? {
        didSet { isConnected = accessToken != nil }
    }

    override init() {
        super.init()
        accessToken = SecureTokenStore.read()
        if accessToken != nil {
            status = "Strava bağlı. Verilerin hazırlanıyor."
            Task { await reloadAll() }
        }
        if healthSyncEnabled {
            startHealthObservers()
            Task { await syncAppleHealth() }
        }
    }

    func connectStrava() {
        let verifier = Self.randomVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        pendingVerifier = verifier
        guard var components = URLComponents(url: URL(string: "/mobile/auth/start", relativeTo: baseURL)!, resolvingAgainstBaseURL: true) else { return }
        components.queryItems = [URLQueryItem(name: "code_challenge", value: challenge)]
        guard let url = components.url else { return }
        isBusy = true
        status = "Strava bağlantısı açılıyor…"
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "tempohealth") { [weak self] callbackURL, error in
            Task { @MainActor in
                guard let self else { return }
                self.isBusy = false
                if let error {
                    self.pendingVerifier = nil
                    self.status = "Strava bağlantısı tamamlanmadı: \(error.localizedDescription)"
                    return
                }
                guard let callbackURL,
                      URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.host == "auth",
                      let ticket = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "ticket" })?.value,
                      let verifier = self.pendingVerifier else {
                    self.pendingVerifier = nil
                    self.status = "Strava bağlantı bilgisi alınamadı. Yeniden dene."
                    return
                }
                self.pendingVerifier = nil
                await self.exchangeTicket(ticket, verifier: verifier)
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        webAuthSession = session
        if !session.start() {
            pendingVerifier = nil
            isBusy = false
            status = "Strava giriş ekranı açılamadı. Biraz sonra yeniden dene."
        }
    }

    func handleCallback(_ url: URL) {
        guard url.scheme == "tempohealth", url.host == "auth",
              let ticket = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "ticket" })?.value,
              let verifier = pendingVerifier else { return }
        pendingVerifier = nil
        Task { await exchangeTicket(ticket, verifier: verifier) }
    }

    func syncWhenActive() {
        guard accessToken != nil else { return }
        Task {
            if healthSyncEnabled { await syncAppleHealth() }
            else { await refreshWater() }
            if lastDashboardRefresh == nil || Date().timeIntervalSince(lastDashboardRefresh ?? .distantPast) > 300 {
                await refreshDashboard()
            }
        }
    }

    func reloadAll() async {
        await refreshDashboard()
        if healthSyncEnabled { await syncAppleHealth() }
        else { await refreshWater() }
    }

    func refreshDashboard() async {
        guard let accessToken, !isLoadingDashboard else { return }
        isLoadingDashboard = true
        dashboardError = nil
        defer { isLoadingDashboard = false }
        do {
            var request = URLRequest(url: URL(string: "/api/mobile/dashboard", relativeTo: baseURL)!)
            request.timeoutInterval = 45
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.server("Sunucudan yanıt alınamadı.") }
            if http.statusCode == 401 { expireSession(); return }
            guard (200..<300).contains(http.statusCode) else { throw APIError.server(Self.serverMessage(data, fallback: "Strava verileri alınamadı.")) }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            dashboard = try decoder.decode(TempoDashboard.self, from: data)
            lastDashboardRefresh = Date()
            status = "Strava verilerin güncel."
        } catch {
            dashboardError = error.localizedDescription
            status = "Veriler yenilenemedi: \(error.localizedDescription)"
        }
    }

    func addWater(_ amountMl: Int) {
        if healthSyncEnabled {
            addWaterToAppleHealth(amountMl)
            return
        }
        guard let accessToken, !isBusy else { return }
        isBusy = true
        status = "\(amountMl) ml ekleniyor…"
        Task {
            defer { isBusy = false }
            do {
                var request = URLRequest(url: URL(string: "/api/mobile/water/add", relativeTo: baseURL)!)
                request.httpMethod = "POST"
                request.timeoutInterval = 15
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(ManualWaterRequest(date: Self.localDay(), amountMl: amountMl))
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw APIError.server("Sunucudan yanıt alınamadı.") }
                if http.statusCode == 401 { expireSession(); return }
                let result = try JSONDecoder().decode(ManualWaterResponse.self, from: data)
                guard (200..<300).contains(http.statusCode), let total = result.totalMl else {
                    throw APIError.server(result.error ?? "Su miktarı eklenemedi.")
                }
                todayWaterMl = total
                status = "\(amountMl) ml eklendi. Bugünkü toplam: \(total) ml."
            } catch {
                status = "Su eklenemedi: \(error.localizedDescription)"
            }
        }
    }

    var healthAvailable: Bool { healthStore.isAvailable }

    var todayHealth: TempoHealthMetrics {
        healthDays[Self.localDay()] ?? TempoHealthMetrics(waterMl: Double(todayWaterMl))
    }

    var latestSleep: (day: String, minutes: Double)? {
        healthDays.compactMap { day, value in
            guard let minutes = value.sleepMinutes, minutes > 0 else { return nil }
            return (day, minutes)
        }.max { $0.0 < $1.0 }
    }

    var latestWeightKg: Double? {
        healthDays.sorted { $0.key > $1.key }.compactMap { $0.value.bodyMassKg }.first
    }

    func connectAppleHealth() {
        guard healthStore.isAvailable, !isHealthSyncing else {
            healthError = "Apple Sağlık bu cihazda kullanılamıyor."
            return
        }
        isHealthSyncing = true
        healthError = nil
        status = "Apple Sağlık izni bekleniyor…"
        Task {
            do {
                try await healthStore.requestAuthorization()
                healthSyncEnabled = true
                UserDefaults.standard.set(true, forKey: "tempoHealthSyncEnabledV1")
                startHealthObservers()
                isHealthSyncing = false
                await syncAppleHealth()
            } catch {
                isHealthSyncing = false
                healthError = error.localizedDescription
                status = "Apple Sağlık bağlanamadı: \(error.localizedDescription)"
            }
        }
    }

    func syncAppleHealth() async {
        guard healthSyncEnabled, healthStore.isAvailable, !isHealthSyncing else { return }
        isHealthSyncing = true
        healthError = nil
        defer { isHealthSyncing = false }
        do {
            let days = try await healthStore.readRecentDays()
            healthDays = days
            healthLastSync = Date()
            todayWaterMl = Int((days[Self.localDay()]?.waterMl ?? 0).rounded())
            if accessToken != nil { try await uploadHealth(days) }
            status = days.isEmpty
                ? "Apple Sağlık bağlı; paylaşılmış veri bulunamadı. Sağlık izinlerini kontrol edebilirsin."
                : "Apple Sağlık verilerin güncel."
        } catch {
            healthError = error.localizedDescription
            status = "Apple Sağlık eşitlenemedi: \(error.localizedDescription)"
        }
    }

    func disconnectAppleHealth() {
        healthStore.disableBackgroundDelivery()
        healthSyncEnabled = false
        UserDefaults.standard.set(false, forKey: "tempoHealthSyncEnabledV1")
        healthDays = [:]
        healthLastSync = nil
        todayWaterMl = 0
        Task {
            if let accessToken {
                var request = URLRequest(url: URL(string: "/api/mobile/health", relativeTo: baseURL)!)
                request.httpMethod = "DELETE"
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                _ = try? await URLSession.shared.data(for: request)
                await refreshWater()
            }
            status = "Apple Sağlık eşitlemesi kapatıldı. İzinleri iPhone Ayarlar’dan ayrıca değiştirebilirsin."
        }
    }

    func refreshWater() async {
        guard let accessToken else { return }
        do {
            var request = URLRequest(url: URL(string: "/api/mobile/water", relativeTo: baseURL)!)
            request.timeoutInterval = 15
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            if http.statusCode == 401 { expireSession(); return }
            guard (200..<300).contains(http.statusCode) else { return }
            let result = try JSONDecoder().decode(WaterStateResponse.self, from: data)
            todayWaterMl = Int((result.totals[Self.localDay()] ?? 0).rounded())
        } catch { }
    }

    func askCoach(period: String, question: String) {
        guard let accessToken, !isCoachLoading else { return }
        isCoachLoading = true
        coachAnswer = ""
        Task {
            defer { isCoachLoading = false }
            do {
                var request = URLRequest(url: URL(string: "/api/mobile/coach", relativeTo: baseURL)!)
                request.httpMethod = "POST"
                request.timeoutInterval = 90
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(CoachRequest(consent: true, question: question, period: period))
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw APIError.server("Koç yanıtı alınamadı.") }
                if http.statusCode == 401 { expireSession(); return }
                let result = try JSONDecoder().decode(TempoCoachResponse.self, from: data)
                guard (200..<300).contains(http.statusCode), let answer = result.answer else {
                    throw APIError.server(result.error ?? "Koç yanıtı alınamadı.")
                }
                coachAnswer = answer
                coachPeriodDescription = result.period ?? ""
            } catch {
                coachAnswer = "Yanıt alınamadı: \(error.localizedDescription)"
            }
        }
    }

    func disconnect() {
        guard !isBusy else { return }
        isBusy = true
        Task {
            if let accessToken { try? await revokeServerConnection(using: accessToken) }
            SecureTokenStore.delete()
            accessToken = nil
            dashboard = nil
            dashboardError = nil
            todayWaterMl = 0
            healthStore.disableBackgroundDelivery()
            healthSyncEnabled = false
            healthDays = [:]
            healthLastSync = nil
            healthError = nil
            UserDefaults.standard.set(false, forKey: "tempoHealthSyncEnabledV1")
            coachAnswer = ""
            isBusy = false
            status = "Strava bağlantısı kaldırıldı."
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    private func exchangeTicket(_ ticket: String, verifier: String) async {
        isBusy = true
        status = "Strava hesabı doğrulanıyor…"
        defer { isBusy = false }
        do {
            var request = URLRequest(url: URL(string: "/api/mobile/auth/exchange", relativeTo: baseURL)!)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(TicketRequest(ticket: ticket, verifier: verifier))
            let (data, response) = try await URLSession.shared.data(for: request)
            let result = try JSONDecoder().decode(TicketResponse.self, from: data)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let token = result.token else {
                throw APIError.server(result.error ?? "Strava doğrulaması başarısız oldu.")
            }
            guard SecureTokenStore.save(token) else { throw APIError.server("Giriş bilgisi iPhone’da güvenle saklanamadı.") }
            accessToken = token
            status = "Strava bağlı. Verilerin hazırlanıyor."
            await reloadAll()
        } catch {
            status = error.localizedDescription
        }
    }

    private func revokeServerConnection(using token: String) async throws {
        var request = URLRequest(url: URL(string: "/api/mobile/auth/logout", relativeTo: baseURL)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.server("Sunucu bağlantıyı kaldıramadı.")
        }
    }

    private func expireSession() {
        SecureTokenStore.delete()
        accessToken = nil
        dashboard = nil
        todayWaterMl = 0
        status = "Tempo bağlantısının süresi doldu. Strava ile yeniden giriş yap."
    }

    private func addWaterToAppleHealth(_ amountMl: Int) {
        guard !isBusy else { return }
        isBusy = true
        status = "\(amountMl) ml Apple Sağlık’a ekleniyor…"
        Task {
            defer { isBusy = false }
            do {
                try await healthStore.saveWater(amountMl: Double(amountMl))
                await syncAppleHealth()
                status = "\(amountMl) ml Apple Sağlık’a eklendi."
            } catch {
                healthError = error.localizedDescription
                status = "Su Apple Sağlık’a eklenemedi: \(error.localizedDescription)"
            }
        }
    }

    private func uploadHealth(_ days: [String: TempoHealthMetrics]) async throws {
        guard let accessToken else { return }
        var request = URLRequest(url: URL(string: "/api/mobile/health/sync", relativeTo: baseURL)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(TempoHealthSyncPayload(days: days))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.server("Sağlık verileri sunucuya eşitlenemedi.") }
        if http.statusCode == 401 { expireSession(); return }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(Self.serverMessage(data, fallback: "Sağlık verileri sunucuya eşitlenemedi."))
        }
    }

    private func startHealthObservers() {
        healthStore.startBackgroundDelivery { [weak self] in
            await self?.syncAppleHealth()
        }
    }

    private static func serverMessage(_ data: Data, fallback: String) -> String {
        (try? JSONDecoder().decode(ServerError.self, from: data).error) ?? fallback
    }

    private static func localDay() -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return Data(SHA256.hash(data: Data(UUID().uuidString.utf8))).base64URLEncodedString()
        }
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }
}

private struct TicketRequest: Encodable { let ticket: String; let verifier: String }
private struct TicketResponse: Decodable { let token: String?; let error: String? }
private struct ManualWaterRequest: Encodable { let date: String; let amountMl: Int }
private struct ManualWaterResponse: Decodable { let totalMl: Int?; let error: String? }
private struct WaterStateResponse: Decodable { let totals: [String: Double] }
private struct CoachRequest: Encodable { let consent: Bool; let question: String; let period: String }
private struct ServerError: Decodable { let error: String }

private enum APIError: LocalizedError {
    case server(String)
    var errorDescription: String? {
        switch self {
        case let .server(message): return message
        }
    }
}

private enum SecureTokenStore {
    private static let service = "com.apitempo.tempohealth"
    private static let account = "mobile-access-token"

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

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
