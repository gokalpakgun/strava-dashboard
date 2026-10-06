import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import HealthKit
import Security
import UIKit

@MainActor
final class TempoAppModel: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var isConnected = false
    @Published private(set) var healthSyncEnabled = false
    @Published private(set) var isBusy = false
    @Published var status = "Strava hesabını bağlayarak başla."

    private let baseURL = URL(string: "https://apitempo.com")!
    private let healthStore = HKHealthStore()
    private var webAuthSession: ASWebAuthenticationSession?
    private var observerQuery: HKObserverQuery?
    private var pendingVerifier: String?
    private var isSyncingWater = false
    private var accessToken: String? {
        didSet { isConnected = accessToken != nil }
    }
    private var waterType: HKQuantityType? {
        HKObjectType.quantityType(forIdentifier: .dietaryWater)
    }

    override init() {
        super.init()
        accessToken = SecureTokenStore.read()
        let savedSyncPreference = UserDefaults.standard.bool(forKey: "tempoHealthSyncEnabled")
        let hasCloudConsent = UserDefaults.standard.bool(forKey: "tempoCloudSyncConsent")
        healthSyncEnabled = savedSyncPreference && hasCloudConsent
        if savedSyncPreference && !hasCloudConsent {
            UserDefaults.standard.set(false, forKey: "tempoHealthSyncEnabled")
            UserDefaults.standard.set(true, forKey: "tempoPendingWaterDeletion")
        }
        if accessToken != nil {
            status = healthSyncEnabled ? "Strava bağlı. Su verisi eşitleniyor." : "Strava bağlı. Apple Sağlık eşitlemesini etkinleştir."
            if healthSyncEnabled {
                startWaterObserver()
                Task { await syncWater() }
            } else if UserDefaults.standard.bool(forKey: "tempoPendingWaterDeletion") {
                Task { await retryPendingWaterDeletion() }
            }
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
                      let ticket = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "ticket" })?.value else {
                    self.pendingVerifier = nil
                    self.status = "Strava bağlantı bilgisi alınamadı. Yeniden dene."
                    return
                }
                guard let verifier = self.pendingVerifier else {
                    self.status = "Uygulama doğrulama bilgisi bulunamadı. Yeniden dene."
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
        guard url.scheme == "tempohealth",
              url.host == "auth",
              let ticket = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "ticket" })?.value,
              let verifier = pendingVerifier else { return }
        pendingVerifier = nil
        Task { await exchangeTicket(ticket, verifier: verifier) }
    }

    func enableHealthSync() {
        guard UserDefaults.standard.bool(forKey: "tempoCloudSyncConsent") else {
            status = "Eşitlemeyi açmak için veri gönderme onayını işaretle."
            return
        }
        guard let waterType else {
            status = "Bu iPhone’da Apple Sağlık verisi kullanılamıyor."
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else {
            status = "Apple Sağlık bu cihazda kullanılamıyor."
            return
        }
        isBusy = true
        status = "Su verisi için Apple Sağlık izni isteniyor…"
        healthStore.requestAuthorization(toShare: [], read: [waterType]) { [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }
                self.isBusy = false
                if let error {
                    self.status = "Sağlık izni alınamadı: \(error.localizedDescription)"
                    return
                }
                guard success else {
                    self.status = "Apple Sağlık isteği tamamlanamadı. Yeniden dene."
                    return
                }
                self.healthSyncEnabled = true
                UserDefaults.standard.set(true, forKey: "tempoHealthSyncEnabled")
                self.startWaterObserver()
                await self.syncWater()
            }
        }
    }

    func syncWhenActive() {
        guard accessToken != nil else { return }
        if UserDefaults.standard.bool(forKey: "tempoPendingWaterDeletion"), !healthSyncEnabled {
            Task { await retryPendingWaterDeletion() }
            return
        }
        guard healthSyncEnabled else { return }
        Task { await syncWater() }
    }

    func disableHealthSync() {
        guard healthSyncEnabled else { return }
        healthSyncEnabled = false
        UserDefaults.standard.set(false, forKey: "tempoHealthSyncEnabled")
        UserDefaults.standard.set(true, forKey: "tempoPendingWaterDeletion")
        if let observerQuery { healthStore.stop(observerQuery) }
        observerQuery = nil
        if let waterType {
            healthStore.disableBackgroundDelivery(for: waterType) { _, _ in }
        }
        guard let accessToken else {
            status = "Apple Sağlık eşitlemesi kapatıldı."
            return
        }
        Task {
            while self.isSyncingWater {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            do {
                try await deleteServerWater(using: accessToken)
                UserDefaults.standard.set(false, forKey: "tempoPendingWaterDeletion")
                status = "Apple Sağlık eşitlemesi kapatıldı; sunucudaki su toplamları silindi."
            } catch {
                status = "Eşitleme durdu. Su verisini silmek için internet gelince uygulamayı tekrar aç."
            }
        }
    }

    func disconnect() {
        isBusy = true
        healthSyncEnabled = false
        UserDefaults.standard.set(false, forKey: "tempoHealthSyncEnabled")
        if let observerQuery { healthStore.stop(observerQuery) }
        observerQuery = nil
        if let waterType {
            healthStore.disableBackgroundDelivery(for: waterType) { _, _ in }
        }
        Task {
            while self.isSyncingWater {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            do {
                if let accessToken { try await revokeServerConnection(using: accessToken) }
                SecureTokenStore.delete()
                accessToken = nil
                UserDefaults.standard.set(false, forKey: "tempoHealthSyncEnabled")
                UserDefaults.standard.set(false, forKey: "tempoCloudSyncConsent")
                UserDefaults.standard.set(false, forKey: "tempoPendingWaterDeletion")
                isBusy = false
                status = "Bağlantı kaldırıldı; sunucudaki su toplamları silindi."
            } catch {
                isBusy = false
                status = "Sunucu bağlantısı kesilemedi. İnternete bağlanıp yeniden dene."
            }
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
        do {
            var request = URLRequest(url: URL(string: "/api/mobile/auth/exchange", relativeTo: baseURL)!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(TicketRequest(ticket: ticket, verifier: verifier))
            let (data, response) = try await URLSession.shared.data(for: request)
            let result = try JSONDecoder().decode(TicketResponse.self, from: data)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let token = result.token else {
                throw APIError.server(result.error ?? "Strava doğrulaması başarısız oldu.")
            }
            guard SecureTokenStore.save(token) else {
                throw APIError.server("Giriş bilgisi iPhone’da güvenle saklanamadı. Yeniden dene.")
            }
            accessToken = token
            status = "Strava bağlı. Şimdi Apple Sağlık iznini ver."
        } catch {
            status = error.localizedDescription
        }
        isBusy = false
    }

    private func startWaterObserver() {
        guard observerQuery == nil, let waterType else { return }
        let query = HKObserverQuery(sampleType: waterType, predicate: nil) { [weak self] _, completion, error in
            guard error == nil else { completion(); return }
            Task { @MainActor in
                await self?.syncWater()
                completion()
            }
        }
        observerQuery = query
        healthStore.execute(query)
        healthStore.enableBackgroundDelivery(for: waterType, frequency: .immediate) { [weak self] _, error in
            if let error {
                Task { @MainActor in self?.status = "Arka plan bildirimi açılamadı; uygulama açıkken eşitleme sürer. \(error.localizedDescription)" }
            }
        }
    }

    private func syncWater() async {
        guard !isSyncingWater, let accessToken, healthSyncEnabled,
              UserDefaults.standard.bool(forKey: "tempoCloudSyncConsent"), let waterType else { return }
        isSyncingWater = true
        defer { isSyncingWater = false }
        do {
            let totals = try await readDailyTotals(type: waterType)
            guard healthSyncEnabled, self.accessToken == accessToken else { return }
            var request = URLRequest(url: URL(string: "/api/mobile/water/sync", relativeTo: baseURL)!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(WaterSyncRequest(totals: totals))
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.server("Sunucudan yanıt alınamadı.") }
            if http.statusCode == 401 {
                SecureTokenStore.delete()
                self.accessToken = nil
                healthSyncEnabled = false
                UserDefaults.standard.set(false, forKey: "tempoHealthSyncEnabled")
                if let observerQuery { healthStore.stop(observerQuery) }
                observerQuery = nil
                if let waterType {
                    healthStore.disableBackgroundDelivery(for: waterType) { _, _ in }
                }
                status = "Tempo bağlantısının süresi doldu. Strava ile yeniden giriş yap."
                return
            }
            guard (200..<300).contains(http.statusCode) else { throw APIError.server("Su verisi eşitlenemedi (\(http.statusCode)).") }
            UserDefaults.standard.set(false, forKey: "tempoPendingWaterDeletion")
            let latest = totals.keys.sorted().last
            let amount = latest.flatMap { totals[$0] } ?? 0
            status = totals.isEmpty
                ? "Apple Sağlık’ta eşitlenecek su kaydı bulunamadı."
                : "Günlük su toplamı eşitlendi: \(Int(amount.rounded())) ml."
        } catch {
            status = "Eşitleme başarısız: \(error.localizedDescription)"
        }
    }

    private func readDailyTotals(type: HKQuantityType) async throws -> [String: Double] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -89, to: today) else { return [:] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let formatter = DateFormatter()
                formatter.calendar = calendar
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = calendar.timeZone
                formatter.dateFormat = "yyyy-MM-dd"
                let waterSamples = samples as? [HKQuantitySample] ?? []
                guard !waterSamples.isEmpty else {
                    continuation.resume(returning: [:])
                    return
                }
                var totals: [String: Double] = [:]
                for offset in 0..<90 {
                    if let day = calendar.date(byAdding: .day, value: -offset, to: today) {
                        totals[formatter.string(from: day)] = 0
                    }
                }
                for sample in waterSamples {
                    let day = formatter.string(from: sample.startDate)
                    totals[day, default: 0] += sample.quantity.doubleValue(for: .literUnit(with: .milli))
                }
                continuation.resume(returning: totals)
            }
            healthStore.execute(query)
        }
    }

    private func retryPendingWaterDeletion() async {
        guard UserDefaults.standard.bool(forKey: "tempoPendingWaterDeletion"), let accessToken else { return }
        do {
            try await deleteServerWater(using: accessToken)
            UserDefaults.standard.set(false, forKey: "tempoPendingWaterDeletion")
            status = "Sunucudaki Apple Sağlık su toplamları silindi."
        } catch {
            status = "Sunucudaki su verisi silinmeyi bekliyor. İnternet gelince tekrar denenecek."
        }
    }

    private func deleteServerWater(using token: String) async throws {
        var request = URLRequest(url: URL(string: "/api/mobile/water/sync", relativeTo: baseURL)!)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.server("Sunucu su verisini silemedi.")
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

private struct TicketResponse: Decodable {
    let token: String?
    let error: String?
}

private struct WaterSyncRequest: Encodable { let totals: [String: Double] }

private enum APIError: LocalizedError {
    case server(String)
    var errorDescription: String? {
        if case let .server(message) = self { return message }
        return nil
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
