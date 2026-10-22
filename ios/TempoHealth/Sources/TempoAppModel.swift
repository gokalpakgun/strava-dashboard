import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security
import UIKit

@MainActor
final class TempoAppModel: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var isConnected = false
    @Published private(set) var isRestoringConnection = true
    @Published private(set) var isBusy = false
    @Published private(set) var isLoadingDashboard = false
    @Published private(set) var isCoachLoading = false
    @Published private(set) var todayWaterMl = 0
    @Published private(set) var healthSyncEnabled = false
    @Published private(set) var isHealthSyncing = false
    @Published private(set) var healthDays: [String: TempoHealthMetrics] = [:]
    @Published private(set) var manualWorkouts: [TempoManualWorkout] = []
    @Published private(set) var healthLastSync: Date?
    @Published private(set) var healthError: String?
    @Published private(set) var dashboard: TempoDashboard?
    @Published private(set) var dashboardError: String?
    @Published private(set) var dashboardErrorDetails: String?
    @Published var status = "Apple Sağlık ana kaynağın; Strava isteğe bağlı."

    let dailyGoalMl = 2_000
    private let baseURL = URL(string: "https://apitempo.com")!
    private let healthStore = TempoHealthStore()
    private var webAuthSession: ASWebAuthenticationSession?
    private var pendingVerifier: String?
    private var pendingOAuthAccountId: String?
    private var isCompletingAuthorization = false
    private var hasAttemptedAccountRestore = false
    private var accountAccessToken: String?
    private var activeTempoAccountId: String?
    private var lastManualWorkoutAccountId: String?
    private var lastDashboardRefresh: Date?
    private static let apiSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 18
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: configuration)
    }()
    // Strava permits only a short-lived cache. A one-day local window also
    // gives deleted or edited activities time to disappear well before the
    // policy's 48-hour deletion-reflection limit.
    private static let dashboardCacheLifetime: TimeInterval = 24 * 60 * 60
    private static let stravaSkippedKey = "tempoStravaSkippedV1"
    private var accessToken: String? {
        didSet { isConnected = accessToken != nil }
    }

    override init() {
        super.init()
#if DEBUG
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
#else
        let isUITesting = false
#endif
        if !isUITesting { Self.prewarmAPI() }
        let storedToken = isUITesting ? nil : SecureTokenStore.read()
        accessToken = storedToken
        isConnected = storedToken != nil
        isRestoringConnection = !isUITesting && storedToken == nil && !UserDefaults.standard.bool(forKey: Self.stravaSkippedKey)
        if storedToken != nil { status = "Strava bağlı. Verilerin hazırlanıyor." }
        Self.clearLegacyGlobalCaches()
    }

    func restoreConnectionIfNeeded(accountToken: String?, accountId: String?) async {
        guard let accountId, !accountId.isEmpty else {
            isRestoringConnection = false
            return
        }
        if activeTempoAccountId != accountId { setTempoAccount(accountId) }
        accountAccessToken = accountToken
        if healthSyncEnabled, accountToken != nil, activeTempoAccountId != nil {
            startHealthObservers()
            Task { await syncAppleHealth() }
        }
        guard !hasAttemptedAccountRestore else {
            isRestoringConnection = false
            return
        }
        guard let accountToken, !accountToken.isEmpty else {
            isRestoringConnection = false
            return
        }

        if accessToken == nil, UserDefaults.standard.bool(forKey: Self.stravaSkippedKey) {
            isRestoringConnection = false
            hasAttemptedAccountRestore = true
            return
        }

        hasAttemptedAccountRestore = true
        let hadLocalToken = accessToken != nil
        isRestoringConnection = !hadLocalToken

        do {
            var request = URLRequest(url: URL(string: "/api/mobile/auth/restore", relativeTo: baseURL)!)
            request.httpMethod = "POST"
            request.timeoutInterval = 12
            request.setValue("Bearer \(accountToken)", forHTTPHeaderField: "Authorization")
            if let accessToken {
                request.setValue(accessToken, forHTTPHeaderField: "X-Tempo-Mobile-Token")
            }

            let (data, response) = try await Self.apiSession.data(for: request)
            guard activeTempoAccountId == accountId, accountAccessToken == accountToken else { return }
            guard let http = response as? HTTPURLResponse else {
                throw APIError.server("Sunucudan yanıt alınamadı.")
            }
            let result = try? JSONDecoder().decode(TicketResponse.self, from: data)

            if http.statusCode == 200, let restoredToken = result?.token {
                guard SecureTokenStore.save(restoredToken) else {
                    throw APIError.server("Bağlantı iPhone’da saklanamadı.")
                }
                accessToken = restoredToken
                UserDefaults.standard.set(false, forKey: Self.stravaSkippedKey)
                isConnected = true
                status = "Strava bağlantın hazır."
                isRestoringConnection = false
                if dashboard == nil, let activeTempoAccountId { dashboard = Self.loadCachedDashboard(accountId: activeTempoAccountId) }
                Task { await reloadAll() }
                return
            }

            if http.statusCode == 404 {
                isRestoringConnection = false
                if hadLocalToken {
                    SecureTokenStore.delete()
                    accessToken = nil
                    dashboard = nil
                    Self.clearCachedDashboard(accountId: accountId)
                    skipStravaForNow()
                } else {
                    skipStravaForNow()
                }
                return
            }

            if http.statusCode == 401 {
                isRestoringConnection = false
                if hadLocalToken { Task { await reloadAll() } }
                return
            }

            throw APIError.server(result?.error ?? "Strava bağlantısı geri yüklenemedi.")
        } catch {
            guard activeTempoAccountId == accountId, accountAccessToken == accountToken else { return }
            isRestoringConnection = false
            hasAttemptedAccountRestore = false
            if hadLocalToken {
                Task { await reloadAll() }
            } else {
                status = "Kayıtlı Strava bağlantısı şu anda doğrulanamadı. Yeniden deneyebilirsin."
            }
        }
    }

    func setTempoAccount(_ accountId: String?) {
        guard activeTempoAccountId != accountId else { return }
        webAuthSession?.cancel()
        webAuthSession = nil
        pendingVerifier = nil
        pendingOAuthAccountId = nil
        isCompletingAuthorization = false
        OAuthVerifierStore.delete()
        healthStore.disableBackgroundDelivery()
        activeTempoAccountId = accountId
        accountAccessToken = nil
        hasAttemptedAccountRestore = false
        dashboard = nil
        healthDays = [:]
        healthLastSync = nil
        todayWaterMl = 0
        healthSyncEnabled = false
        healthError = nil
        lastDashboardRefresh = nil
        isLoadingDashboard = false
        isCoachLoading = false
        if let accountId {
            lastManualWorkoutAccountId = accountId
            healthSyncEnabled = UserDefaults.standard.bool(forKey: Self.healthSyncKey(accountId: accountId))
            healthLastSync = UserDefaults.standard.object(forKey: Self.healthLastSyncKey(accountId: accountId)) as? Date
            if healthSyncEnabled {
                healthDays = Self.loadCachedHealthDays(accountId: accountId)
                todayWaterMl = Int((healthDays[Self.localDay()]?.waterMl ?? 0).rounded())
            }
            if UserDefaults.standard.bool(forKey: "tempoHealthOptInNeedsRenewalV2") {
                healthError = "Apple Sağlık iznini bu Tempo hesabı için yeniden aç."
                UserDefaults.standard.set(false, forKey: "tempoHealthOptInNeedsRenewalV2")
            }
            if accessToken != nil { dashboard = Self.loadCachedDashboard(accountId: accountId) }
            if healthSyncEnabled, accountAccessToken != nil {
                startHealthObservers()
                Task { await syncAppleHealth() }
            }
        }
        manualWorkouts = accountId.map(Self.loadManualWorkouts) ?? []
    }

    func manualWorkoutPhotoURL(for workout: TempoManualWorkout) -> URL? {
        guard let accountId = activeTempoAccountId, let filename = workout.photoFilename else { return nil }
        return Self.manualWorkoutDirectory(accountId: accountId).appendingPathComponent(filename)
    }

    func addManualWorkout(
        sportId: String,
        sportTitle: String,
        title: String,
        startedAt: Date,
        durationMinutes: Int,
        notes: String,
        photoData: Data?,
        perceivedEffort: Int? = nil,
        enjoyment: Int? = nil
    ) async throws {
        guard let accountId = activeTempoAccountId, !accountId.isEmpty else {
            throw APIError.server("Antrenmanı kaydetmek için Tempo hesabına giriş yap.")
        }
        let safeDuration = min(max(durationMinutes, 1), 24 * 60)
        guard startedAt.addingTimeInterval(Double(safeDuration) * 60) <= Date() else {
            throw APIError.server("Antrenman bitiş zamanı gelecekte olamaz.")
        }
        var healthSignal: TempoWorkoutHealthSignal?
        var healthSignalError: String?
        do {
            healthSignal = try await healthStore.workoutHealthSignal(start: startedAt, durationMinutes: safeDuration)
        } catch {
            healthSignalError = error.localizedDescription.tempoLocalized
        }
        guard activeTempoAccountId == accountId else {
            throw APIError.server("Tempo hesabı değişti. Antrenman bu hesapta kaydedilmedi.")
        }

        guard healthSignal?.hasSupportingMeasurement == true else {
            let baseMessage = "Fotoğraf tek başına yeterli değil. Antrenman saatinde anlamlı adım/hareket, yeterli nabız veya solunum artışı ya da egzersiz/enerji ve Sağlık antrenmanı sinyalleri bulunamadı."
            if let healthSignalError {
                throw APIError.server("Fotoğraf tek başına yeterli değil. Sağlık veya iPhone hareket sinyali okunamadı: %@".tempoFormatted(healthSignalError))
            }
            throw APIError.server(baseMessage)
        }

        let directory = Self.manualWorkoutDirectory(accountId: accountId)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Self.excludeFromDeviceBackup(directory)
        let filename = photoData == nil ? nil : "\(UUID().uuidString).jpg"
        if let filename, let photoData {
            let photoURL = directory.appendingPathComponent(filename)
            try photoData.write(to: photoURL, options: .atomic)
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: photoURL.path)
        }

        let workout = TempoManualWorkout(
            id: UUID(),
            sportId: sportId,
            sportTitle: sportTitle,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? sportTitle : title.trimmingCharacters(in: .whitespacesAndNewlines),
            startedAt: startedAt,
            durationMinutes: safeDuration,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            photoFilename: filename,
            healthSignal: healthSignal,
            durationSeconds: nil,
            distanceKm: nil,
            routeCoordinates: nil,
            recordSource: "health-supported-manual",
            perceivedEffort: perceivedEffort.map { min(max($0, 1), 5) },
            enjoyment: enjoyment.map { min(max($0, 1), 5) }
        )
        var updated = manualWorkouts
        updated.insert(workout, at: 0)
        try Self.saveManualWorkouts(updated, accountId: accountId)
        manualWorkouts = updated
    }

    func addPhoneTrackedWorkout(
        sportId: String,
        sportTitle: String,
        startedAt: Date,
        durationSeconds: Int,
        distanceKm: Double,
        routeCoordinates: [TempoCoordinate],
        notes: String = "",
        perceivedEffort: Int? = nil,
        enjoyment: Int? = nil
    ) throws {
        guard let accountId = activeTempoAccountId, !accountId.isEmpty else {
            throw APIError.server("Antrenmanı kaydetmek için Tempo hesabına giriş yap.")
        }
        let safeSeconds = min(max(durationSeconds, 1), 24 * 60 * 60)
        let cleanRoute = Array(routeCoordinates.prefix(12_000)).filter {
            $0.latitude.isFinite && $0.longitude.isFinite
                && (-90...90).contains($0.latitude)
                && (-180...180).contains($0.longitude)
        }
        guard startedAt <= Date(), safeSeconds >= 60,
              distanceKm.isFinite, distanceKm > 0, distanceKm <= 500,
              cleanRoute.count >= 2 else {
            throw APIError.server("GPS kaydı için en az 1 dakika ve iki konum noktası gerekiyor.")
        }

        let workout = TempoManualWorkout(
            id: UUID(),
            sportId: sportId,
            sportTitle: sportTitle,
            title: sportTitle,
            startedAt: startedAt,
            durationMinutes: max(1, Int((Double(safeSeconds) / 60).rounded())),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            photoFilename: nil,
            healthSignal: nil,
            durationSeconds: safeSeconds,
            distanceKm: distanceKm,
            routeCoordinates: cleanRoute,
            recordSource: "phone-gps",
            perceivedEffort: perceivedEffort.map { min(max($0, 1), 5) },
            enjoyment: enjoyment.map { min(max($0, 1), 5) }
        )
        var updated = manualWorkouts
        updated.insert(workout, at: 0)
        try Self.saveManualWorkouts(updated, accountId: accountId)
        manualWorkouts = updated
    }

    func deleteManualWorkout(_ workout: TempoManualWorkout) {
        guard let accountId = activeTempoAccountId else { return }
        let updated = manualWorkouts.filter { $0.id != workout.id }
        do {
            try Self.saveManualWorkouts(updated, accountId: accountId)
            if let filename = workout.photoFilename {
                try? FileManager.default.removeItem(at: Self.manualWorkoutDirectory(accountId: accountId).appendingPathComponent(filename))
            }
            manualWorkouts = updated
        } catch {
            status = "Antrenman silinemedi: %@".tempoFormatted(error.localizedDescription.tempoLocalized)
        }
    }

    func connectStrava() {
        guard !isBusy, !isCompletingAuthorization else { return }
        guard let accountId = activeTempoAccountId,
              let accountToken = accountAccessToken,
              !accountToken.isEmpty else {
            status = "Strava’yı bağlamak için önce Tempo hesabına giriş yap."
            return
        }
        webAuthSession?.cancel()

        let verifier = Self.randomVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        pendingVerifier = verifier
        pendingOAuthAccountId = accountId
        OAuthVerifierStore.save(verifier, accountId: accountId)
        guard var components = URLComponents(url: URL(string: "/mobile/auth/start", relativeTo: baseURL)!, resolvingAgainstBaseURL: true) else { return }
        components.queryItems = [URLQueryItem(name: "code_challenge", value: challenge)]
        guard let url = components.url else { return }

        isBusy = true
        status = "Strava bağlantısı açılıyor…"
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "tempohealth") { [weak self] callbackURL, error in
            Task { @MainActor in
                guard let self else { return }
                self.webAuthSession = nil

                if let callbackURL {
                    self.processAuthorizationCallback(callbackURL)
                    return
                }
                if self.isCompletingAuthorization { return }

                self.pendingVerifier = nil
                self.pendingOAuthAccountId = nil
                OAuthVerifierStore.delete()
                self.isBusy = false
                self.status = error == nil
                    ? "Strava bağlantı yanıtı alınamadı. Yeniden dene."
                    : "Strava bağlantısı tamamlanmadı: %@".tempoFormatted(error!.localizedDescription.tempoLocalized)
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        webAuthSession = session
        if !session.start() {
            webAuthSession = nil
            pendingVerifier = nil
            pendingOAuthAccountId = nil
            OAuthVerifierStore.delete()
            isBusy = false
            status = "Strava giriş ekranı açılamadı. Biraz sonra yeniden dene."
        }
    }

    func skipStravaForNow() {
        guard accessToken == nil else { return }
        UserDefaults.standard.set(true, forKey: Self.stravaSkippedKey)
        isRestoringConnection = false
        hasAttemptedAccountRestore = true
        status = "Strava olmadan devam ediyorsun. İstediğin zaman Profil bölümünden bağlayabilirsin."
    }

    func handleCallback(_ url: URL) {
        guard url.scheme == "tempohealth", url.host == "auth" else { return }
        processAuthorizationCallback(url)
    }

    private func processAuthorizationCallback(_ url: URL) {
        guard !isCompletingAuthorization else { return }
        guard let ticket = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "ticket" })?.value,
              let verifier = pendingVerifier ?? OAuthVerifierStore.read(),
              let oauthAccountId = pendingOAuthAccountId ?? OAuthVerifierStore.readAccountId(),
              activeTempoAccountId == oauthAccountId,
              accountAccessToken != nil else {
            if accessToken == nil {
                isBusy = false
                status = "Strava bağlantı bilgisi veya Tempo oturumu doğrulanamadı. Yeniden dene."
            }
            pendingOAuthAccountId = nil
            OAuthVerifierStore.delete()
            return
        }

        isCompletingAuthorization = true
        pendingVerifier = nil
        isBusy = true
        webAuthSession = nil

        Task {
            await exchangeTicket(ticket, verifier: verifier, accountId: oauthAccountId)
            OAuthVerifierStore.delete()
            pendingOAuthAccountId = nil
            isCompletingAuthorization = false
        }
    }

    func syncWhenActive() {
        if healthSyncEnabled {
            Task { await syncAppleHealth() }
        }
        guard accessToken != nil else {
            if let accountAccessToken, !hasAttemptedAccountRestore {
                Task { await restoreConnectionIfNeeded(accountToken: accountAccessToken, accountId: activeTempoAccountId) }
            }
            return
        }
        Task {
            if healthSyncEnabled { await syncAppleHealth() }
            else { await refreshWater() }
            if lastDashboardRefresh == nil || Date().timeIntervalSince(lastDashboardRefresh ?? .distantPast) > 300 {
                await refreshDashboard()
            }
        }
    }

    func reloadAll() async {
        async let dashboardRefresh: Void = refreshDashboard()
        if healthSyncEnabled {
            async let healthRefresh: Void = syncAppleHealth()
            _ = await (dashboardRefresh, healthRefresh)
        } else {
            async let waterRefresh: Void = refreshWater()
            _ = await (dashboardRefresh, waterRefresh)
        }
    }

    func refreshDashboard() async {
        guard let accessToken, let accountId = activeTempoAccountId, !isLoadingDashboard else { return }
        isLoadingDashboard = true
        dashboardError = nil
        dashboardErrorDetails = nil
        defer { isLoadingDashboard = false }

        // Retry transient network/server failures once. Repeating 4xx errors,
        // JSON decode failures, or a Strava rate limit only delays the screen.
        let retryDelays: [UInt64] = [0, 300_000_000]
        for attempt in retryDelays.indices {
            if retryDelays[attempt] > 0 {
                try? await Task.sleep(nanoseconds: retryDelays[attempt])
            }
            guard activeTempoAccountId == accountId, self.accessToken == accessToken else { return }
            var attemptDiagnostic: String?
            do {
                var request = URLRequest(url: URL(string: "/api/mobile/dashboard", relativeTo: baseURL)!)
                request.timeoutInterval = 30
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                let (data, response) = try await Self.apiSession.data(for: request)
                guard activeTempoAccountId == accountId, self.accessToken == accessToken else { return }
                guard let http = response as? HTTPURLResponse else { throw APIError.server("Sunucudan yanıt alınamadı.") }
                attemptDiagnostic = Self.dashboardDiagnostic(http)

                if http.statusCode == 401 {
                    if attempt < retryDelays.count - 1 { continue }
                    expireSession()
                    return
                }
                if http.statusCode >= 500, attempt < retryDelays.count - 1 { continue }
                guard (200..<300).contains(http.statusCode) else {
                    throw APIError.server(Self.serverMessage(data, fallback: "Strava verileri alınamadı."))
                }

                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let decoded = try decoder.decode(TempoDashboard.self, from: data)
                dashboard = decoded
                Self.saveCachedDashboard(decoded, accountId: accountId)
                lastDashboardRefresh = Date()
                status = "Strava verilerin güncel."
                return
            } catch {
                guard activeTempoAccountId == accountId, self.accessToken == accessToken else { return }
                if attempt < retryDelays.count - 1, !(error is APIError), !(error is DecodingError) { continue }
                dashboardError = error.localizedDescription.tempoLocalized
                dashboardErrorDetails = attemptDiagnostic ?? Self.networkDiagnostic(error)
                status = "Veriler yenilenemedi: %@".tempoFormatted(error.localizedDescription.tempoLocalized)
            }
        }
    }

    func addWater(_ amountMl: Int) {
        if healthSyncEnabled {
            addWaterToAppleHealth(amountMl)
            return
        }
        guard let accessToken, !isBusy else { return }
        guard let accountId = activeTempoAccountId else { return }
        isBusy = true
                status = "%d ml ekleniyor…".tempoFormatted(amountMl)
        Task {
            defer { isBusy = false }
            do {
                var request = URLRequest(url: URL(string: "/api/mobile/water/add", relativeTo: baseURL)!)
                request.httpMethod = "POST"
                request.timeoutInterval = 15
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(ManualWaterRequest(date: Self.localDay(), amountMl: amountMl))
                let (data, response) = try await Self.apiSession.data(for: request)
                guard activeTempoAccountId == accountId, self.accessToken == accessToken else { return }
                guard let http = response as? HTTPURLResponse else { throw APIError.server("Sunucudan yanıt alınamadı.") }
                if http.statusCode == 401 { expireSession(); return }
                let result = try JSONDecoder().decode(ManualWaterResponse.self, from: data)
                guard (200..<300).contains(http.statusCode), let total = result.totalMl else {
                    throw APIError.server(result.error ?? "Su miktarı eklenemedi.")
                }
                todayWaterMl = total
                status = "%d ml eklendi. Bugünkü toplam: %d ml.".tempoFormatted(amountMl, total)
            } catch {
                guard activeTempoAccountId == accountId, self.accessToken == accessToken else { return }
                status = "Su eklenemedi: %@".tempoFormatted(error.localizedDescription.tempoLocalized)
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

    var tempoAchievement: TempoAchievement {
        TempoAchievementFactory.make(workouts: manualWorkouts, healthDays: healthDays)
    }

    var tempoBalance: TempoBalanceScore? {
        let records = healthDays.sorted { $0.key > $1.key }
        var weightedFactors: [(factor: TempoBalanceFactor, weight: Double)] = []

        func values(_ keyPath: KeyPath<TempoHealthMetrics, Double?>) -> [Double] {
            records.compactMap { $0.value[keyPath: keyPath] }.filter { $0.isFinite && $0 > 0 }
        }

        func average(_ values: ArraySlice<Double>) -> Double? {
            guard !values.isEmpty else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }

        func bounded(_ value: Double) -> Int {
            Int(min(max(value, 0), 100).rounded())
        }

        func number(_ value: Double, digits: Int = 0) -> String {
            value.formatted(
                .number
                    .locale(.autoupdatingCurrent)
                    .precision(.fractionLength(digits))
            )
        }

        if let sleepRecord = records.first(where: { ($0.value.sleepMinutes ?? 0) > 0 }),
           let sleep = sleepRecord.value.sleepMinutes,
           let assessment = TempoSleepAssessment.evaluate(sleepRecord.value) {
            weightedFactors.append((
                TempoBalanceFactor(id: "sleep", title: "Uyku", value: TempoFormat.duration(sleep * 60), score: assessment.value, symbol: "moon.zzz.fill", tint: "blue"),
                0.32
            ))
        }

        let hrvValues = values(\.hrvMs)
        if let current = hrvValues.first {
            let baseline = average(hrvValues.dropFirst().prefix(21))
            let score = baseline.map { bounded(90 + ((current / max($0, 1)) - 1) * 100) } ?? 82
            let comparison = baseline.map { " · ort. %@".tempoFormatted(number($0)) } ?? ""
            weightedFactors.append((
                TempoBalanceFactor(id: "hrv", title: "HRV", value: "\(number(current)) \("ms".tempoLocalized)\(comparison)", score: score, symbol: "waveform.path.ecg", tint: "purple"),
                0.26
            ))
        }

        let restingValues = values(\.restingHeartRateBpm)
        if let current = restingValues.first {
            let baseline = average(restingValues.dropFirst().prefix(21))
            let score = baseline.map { reference in
                let difference = current - reference
                return bounded(difference <= 0 ? 92 + abs(difference) * 2 : 92 - difference * 7)
            } ?? 82
            let comparison = baseline.map { " · ort. %@".tempoFormatted(number($0)) } ?? ""
            weightedFactors.append((
                TempoBalanceFactor(id: "resting-heart", title: "Dinlenik nabız", value: "\(number(current)) \("atım/dk".tempoLocalized)\(comparison)", score: score, symbol: "heart.fill", tint: "pink"),
                0.22
            ))
        }

        let energyValues = values(\.activeEnergyKcal)
        if let current = energyValues.first {
            let baseline = average(energyValues.dropFirst().prefix(14))
            let score = baseline.map { reference in
                let ratio = current / max(reference, 1)
                if ratio > 1.8 { return bounded(100 - (ratio - 1.8) * 42) }
                if ratio > 1.25 { return bounded(92 - (ratio - 1.25) * 35) }
                if ratio < 0.25 { return 76 }
                return 92
            } ?? 82
            weightedFactors.append((
                TempoBalanceFactor(id: "load", title: "Hareket yükü", value: "\(number(current)) kcal", score: score, symbol: "flame.fill", tint: "orange"),
                0.12
            ))
        }

        let respiratoryValues = values(\.respiratoryRate)
        if let current = respiratoryValues.first {
            let baseline = average(respiratoryValues.dropFirst().prefix(21))
            let score = baseline.map { reference in
                bounded(94 - abs(current - reference) * 10)
            } ?? 82
            weightedFactors.append((
                TempoBalanceFactor(id: "respiratory", title: "Solunum ritmi", value: "\(number(current, digits: 1)) \("nefes/dk".tempoLocalized)", score: score, symbol: "lungs.fill", tint: "blue"),
                0.08
            ))
        }

        let temperatureValues = values(\.wristTemperatureC)
        if let current = temperatureValues.first {
            let baseline = average(temperatureValues.dropFirst().prefix(21))
            let score = baseline.map { reference in
                bounded(94 - abs(current - reference) * 35)
            } ?? 82
            weightedFactors.append((
                TempoBalanceFactor(id: "temperature", title: "Bilek sıcaklığı", value: "\(number(current, digits: 1)) °C", score: score, symbol: "thermometer.medium", tint: "orange"),
                0.06
            ))
        }

        let oxygenValues = values(\.oxygenSaturationPct)
        if let current = oxygenValues.first {
            let score = bounded(70 + (current - 92) * 6)
            weightedFactors.append((
                TempoBalanceFactor(id: "oxygen", title: "Kandaki oksijen", value: "\(number(current, digits: 1))%", score: score, symbol: "lungs.fill", tint: "green"),
                0.05
            ))
        }

        let waterValues = values(\.waterMl)
        if let current = waterValues.first {
            let score = bounded((current / Double(dailyGoalMl)) * 100)
            weightedFactors.append((
                TempoBalanceFactor(id: "water", title: "Sıvı dengesi", value: "\(number(current)) ml", score: score, symbol: "drop.fill", tint: "blue"),
                0.08
            ))
        }

        guard !weightedFactors.isEmpty else { return nil }
        let totalWeight = weightedFactors.reduce(0) { $0 + $1.weight }
        let value = bounded(weightedFactors.reduce(0) { $0 + Double($1.factor.score) * $1.weight } / totalWeight)
        let state: String
        let recommendation: String
        switch value {
        case 85...:
            state = "Yüksek ritim"
            recommendation = "Vücudunun işaretleri güçlü. Planındaki kaliteli veya yoğun antrenman için uygun bir gün."
        case 70..<85:
            state = "Dengeli"
            recommendation = "Normal antrenman planını sürdürebilirsin; ısınma sırasında nasıl hissettiğini kontrol et."
        case 55..<70:
            state = "Kontrollü tempo"
            recommendation = "Orta şiddet, teknik çalışma veya kısa bir seans bugün daha dengeli olabilir."
        default:
            state = "Toparlanma odağı"
            recommendation = "Hafif hareket, mobilite ve dinlenmeye ağırlık vermek daha uygun görünüyor."
        }
        let confidence = weightedFactors.count >= 4 ? "Güçlü veri" : (weightedFactors.count >= 3 ? "Orta veri" : "Sınırlı veri")
        return TempoBalanceScore(value: value, state: state, recommendation: recommendation, confidence: confidence, factors: weightedFactors.map { $0.factor })
    }

    func connectAppleHealth() {
        guard let accountId = activeTempoAccountId,
              let accountToken = accountAccessToken,
              !accountToken.isEmpty else {
            healthError = "Apple Sağlık eşitlemesi için önce Tempo hesabına giriş yap."
            return
        }
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
                guard activeTempoAccountId == accountId, accountAccessToken == accountToken else {
                    throw APIError.server("Tempo hesabı değişti. Apple Sağlık eşitlemesi başlatılmadı.")
                }
                healthSyncEnabled = true
                UserDefaults.standard.set(true, forKey: Self.healthSyncKey(accountId: accountId))
                startHealthObservers()
                isHealthSyncing = false
                await syncAppleHealth()
            } catch {
                guard activeTempoAccountId == accountId, accountAccessToken == accountToken else { return }
                isHealthSyncing = false
                healthError = error.localizedDescription.tempoLocalized
                status = "Apple Sağlık bağlanamadı: %@".tempoFormatted(error.localizedDescription.tempoLocalized)
            }
        }
    }

    func syncAppleHealth() async {
        guard healthSyncEnabled, healthStore.isAvailable, !isHealthSyncing,
              let accountId = activeTempoAccountId,
              let accountToken = accountAccessToken else { return }
        isHealthSyncing = true
        healthError = nil
        defer { isHealthSyncing = false }
        do {
            let days = try await healthStore.readRecentDays()
            guard activeTempoAccountId == accountId else { return }
            healthDays = days
            healthLastSync = Date()
            Self.saveCachedHealthDays(days, accountId: accountId)
            UserDefaults.standard.set(healthLastSync, forKey: Self.healthLastSyncKey(accountId: accountId))
            todayWaterMl = Int((days[Self.localDay()]?.waterMl ?? 0).rounded())
            if !days.isEmpty {
                do {
                    try await uploadHealth(days, using: accountToken, for: accountId)
                    guard activeTempoAccountId == accountId else { return }
                } catch {
                    guard activeTempoAccountId == accountId, accountAccessToken == accountToken else { return }
                    status = days.isEmpty
                        ? "Apple Sağlık bağlı; paylaşılmış veri bulunamadı. Sağlık izinlerini kontrol edebilirsin."
                        : "Apple Sağlık cihazında güncel. Sunucu eşitlemesi daha sonra yeniden denenecek."
                    return
                }
            }
            status = days.isEmpty
                ? "Apple Sağlık bağlı; paylaşılmış veri bulunamadı. Sağlık izinlerini kontrol edebilirsin."
                : "Apple Sağlık verilerin güncel."
        } catch {
            guard activeTempoAccountId == accountId, accountAccessToken == accountToken else { return }
            healthError = error.localizedDescription.tempoLocalized
            status = "Apple Sağlık eşitlenemedi: %@".tempoFormatted(error.localizedDescription.tempoLocalized)
        }
    }

    func disconnectAppleHealth() {
        let accountId = activeTempoAccountId
        let accountToken = accountAccessToken
        healthStore.disableBackgroundDelivery()
        healthSyncEnabled = false
        if let accountId {
            UserDefaults.standard.set(false, forKey: Self.healthSyncKey(accountId: accountId))
            Self.clearCachedHealthDays(accountId: accountId)
        }
        healthDays = [:]
        healthLastSync = nil
        todayWaterMl = 0
        Task {
            if let accountToken {
                var request = URLRequest(url: URL(string: "/api/account/health", relativeTo: baseURL)!)
                request.httpMethod = "DELETE"
                request.setValue("Bearer \(accountToken)", forHTTPHeaderField: "Authorization")
                _ = try? await Self.apiSession.data(for: request)
            }
            guard activeTempoAccountId == accountId else { return }
            status = "Apple Sağlık eşitlemesi kapatıldı. İzinleri iPhone Ayarlar’dan ayrıca değiştirebilirsin."
        }
    }

    func refreshWater() async {
        guard let accessToken, let accountId = activeTempoAccountId else { return }
        do {
            var request = URLRequest(url: URL(string: "/api/mobile/water", relativeTo: baseURL)!)
            request.timeoutInterval = 15
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await Self.apiSession.data(for: request)
            guard activeTempoAccountId == accountId, self.accessToken == accessToken else { return }
            guard let http = response as? HTTPURLResponse else { return }
            if http.statusCode == 401 { expireSession(); return }
            guard (200..<300).contains(http.statusCode) else { return }
            let result = try JSONDecoder().decode(WaterStateResponse.self, from: data)
            todayWaterMl = Int((result.totals[Self.localDay()] ?? 0).rounded())
        } catch { }
    }

    func askSportsChat(messages: [TempoCoachMessage], includeHealth: Bool) async throws -> String {
        guard let accountId = activeTempoAccountId,
              let accountAccessToken, !accountAccessToken.isEmpty else {
            throw APIError.server("Tempo hesabına yeniden giriş yapman gerekiyor.")
        }
        guard !isCoachLoading else { throw APIError.server("Bir yanıt hazırlanıyor; biraz bekle.") }
        isCoachLoading = true
        defer { isCoachLoading = false }
        var request = URLRequest(url: URL(string: "/api/account/sports-chat", relativeTo: baseURL)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(accountAccessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Bundle.main.preferredLocalizations.first ?? "en", forHTTPHeaderField: "Accept-Language")
        request.httpBody = try JSONEncoder().encode(SportsChatRequest(
            messages: messages.map { SportsChatTurn(role: $0.role, content: $0.content) },
            includeHealth: includeHealth
        ))
        let (data, response) = try await Self.apiSession.data(for: request)
        guard activeTempoAccountId == accountId, self.accountAccessToken == accountAccessToken else {
            throw APIError.server("Tempo hesabı değişti. Koç yanıtı bu ekranda gösterilmedi.")
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.server("Koç yanıtı alınamadı.") }
        let result = try JSONDecoder().decode(TempoCoachResponse.self, from: data)
        guard (200..<300).contains(http.statusCode), let answer = result.answer else {
            throw APIError.server(result.error ?? "Koç yanıtı alınamadı.")
        }
        return answer
    }

    func disconnect() {
        guard !isBusy, let accountId = activeTempoAccountId else { return }
        let token = accessToken
        isBusy = true
        Task {
            var stravaRevoked = true
            do {
                if let token { stravaRevoked = try await revokeServerConnection(using: token) }
            } catch {
                guard activeTempoAccountId == accountId else { return }
                isBusy = false
                status = "Strava bağlantısı sunucudan kaldırılamadı: %@".tempoFormatted(error.localizedDescription.tempoLocalized)
                return
            }
            guard activeTempoAccountId == accountId, self.accessToken == token else { return }
            SecureTokenStore.delete()
            accessToken = nil
            dashboard = nil
            if let activeTempoAccountId { Self.clearCachedDashboard(accountId: activeTempoAccountId) }
            dashboardError = nil
            dashboardErrorDetails = nil
            todayWaterMl = 0
            UserDefaults.standard.set(true, forKey: Self.stravaSkippedKey)
            hasAttemptedAccountRestore = true
            isRestoringConnection = false
            isBusy = false
            status = stravaRevoked
                ? "Strava bağlantısı kaldırıldı."
                : "Tempo’daki Strava verileri silindi; yetki iptal edilemedi. Strava ayarlarından Tempo erişimini de kaldır."
        }
    }

    func clearLocalStateForTempoSignOut() {
        clearLocalAccountData()
        // Keep the server-side Strava link attached to the Tempo account so it
        // can be restored after the user signs back in without another OAuth flow.
        UserDefaults.standard.set(false, forKey: Self.stravaSkippedKey)
        hasAttemptedAccountRestore = false
        status = "Tempo hesabından çıkış yapıldı."
    }

    func clearLocalStateAfterAccountDeletion() {
        clearLocalAccountData(deleteManualWorkouts: true)
        UserDefaults.standard.set(true, forKey: Self.stravaSkippedKey)
        hasAttemptedAccountRestore = true
        status = "Tempo hesabı silindi."
    }

    private func clearLocalAccountData(deleteManualWorkouts: Bool = false) {
        let accountId = activeTempoAccountId ?? lastManualWorkoutAccountId
        if deleteManualWorkouts, let accountId = activeTempoAccountId ?? lastManualWorkoutAccountId {
            try? FileManager.default.removeItem(at: Self.manualWorkoutDirectory(accountId: accountId))
        }
        if let accountId {
            Self.clearCachedDashboard(accountId: accountId)
            Self.clearCachedHealthDays(accountId: accountId)
            if deleteManualWorkouts {
                UserDefaults.standard.removeObject(forKey: Self.healthSyncKey(accountId: accountId))
                UserDefaults.standard.removeObject(forKey: Self.healthLastSyncKey(accountId: accountId))
            }
        }
        activeTempoAccountId = nil
        lastManualWorkoutAccountId = nil
        manualWorkouts = []
        SecureTokenStore.delete()
        accessToken = nil
        accountAccessToken = nil
        dashboard = nil
        dashboardError = nil
        dashboardErrorDetails = nil
        healthStore.disableBackgroundDelivery()
        healthSyncEnabled = false
        healthDays = [:]
        healthLastSync = nil
        todayWaterMl = 0
        isRestoringConnection = false
        isBusy = false
    }

    private static func manualWorkoutDirectory(accountId: String) -> URL {
        let digest = SHA256.hash(data: Data(accountId.utf8)).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ManualWorkouts", isDirectory: true)
            .appendingPathComponent(digest, isDirectory: true)
    }

    private static func loadManualWorkouts(accountId: String) -> [TempoManualWorkout] {
        let url = manualWorkoutDirectory(accountId: accountId).appendingPathComponent("workouts.json")
        guard let data = try? Data(contentsOf: url), let workouts = try? JSONDecoder().decode([TempoManualWorkout].self, from: data) else { return [] }
        return workouts.sorted { $0.startedAt > $1.startedAt }
    }

    private static func saveManualWorkouts(_ workouts: [TempoManualWorkout], accountId: String) throws {
        let directory = manualWorkoutDirectory(accountId: accountId)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        excludeFromDeviceBackup(directory)
        let data = try JSONEncoder().encode(workouts)
        let url = directory.appendingPathComponent("workouts.json")
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
    }

    private static func excludeFromDeviceBackup(_ directory: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var protectedURL = directory
        try? protectedURL.setResourceValues(values)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    private func exchangeTicket(_ ticket: String, verifier: String, accountId: String) async {
        guard activeTempoAccountId == accountId,
              let accountToken = accountAccessToken,
              !accountToken.isEmpty else { return }
        isBusy = true
        status = "Strava hesabı doğrulanıyor…"
        defer { isBusy = false }

        let retryDelays: [UInt64] = [0, 180_000_000, 500_000_000]
        for attempt in retryDelays.indices {
            if retryDelays[attempt] > 0 {
                status = "Strava bağlantısı tamamlanıyor…"
                try? await Task.sleep(nanoseconds: retryDelays[attempt])
            }
            guard activeTempoAccountId == accountId, accountAccessToken == accountToken else { return }
            do {
                var request = URLRequest(url: URL(string: "/api/mobile/auth/exchange", relativeTo: baseURL)!)
                request.httpMethod = "POST"
                request.timeoutInterval = 12
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(accountToken)", forHTTPHeaderField: "Authorization")
                request.httpBody = try JSONEncoder().encode(TicketRequest(ticket: ticket, verifier: verifier))
                let (data, response) = try await Self.apiSession.data(for: request)
                guard activeTempoAccountId == accountId, accountAccessToken == accountToken else { return }
                guard let http = response as? HTTPURLResponse else {
                    throw APIError.server("Sunucudan yanıt alınamadı.")
                }
                let result = try? JSONDecoder().decode(TicketResponse.self, from: data)

                if http.statusCode == 200, let token = result?.token {
                    guard SecureTokenStore.save(token) else {
                        throw APIError.server("Giriş bilgisi iPhone’da güvenle saklanamadı.")
                    }
                    accessToken = token
                    UserDefaults.standard.set(false, forKey: Self.stravaSkippedKey)
                    status = "Strava bağlı. Verilerin hazırlanıyor."
                    if let activeTempoAccountId { dashboard = Self.loadCachedDashboard(accountId: activeTempoAccountId) }
                    Task { await reloadAll() }
                    return
                }

                let message = result?.error ?? "Strava doğrulaması başarısız oldu."
                let retryable = http.statusCode == 401 || http.statusCode == 408 || http.statusCode == 429 || http.statusCode >= 500
                if retryable, attempt < retryDelays.count - 1 { continue }
                throw APIError.server(message)
            } catch {
                guard activeTempoAccountId == accountId, accountAccessToken == accountToken else { return }
                if attempt < retryDelays.count - 1 { continue }
                status = "Strava bağlantısı tamamlanamadı: %@".tempoFormatted(error.localizedDescription.tempoLocalized)
            }
        }
    }

    private func revokeServerConnection(using token: String) async throws -> Bool {
        var request = URLRequest(url: URL(string: "/api/mobile/auth/logout", relativeTo: baseURL)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await Self.apiSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.server("Sunucu bağlantıyı kaldıramadı.")
        }
        return (try? JSONDecoder().decode(StravaDisconnectResponse.self, from: data).stravaRevoked) ?? true
    }

    private func expireSession() {
        guard let accountId = activeTempoAccountId else { return }
        SecureTokenStore.delete()
        accessToken = nil
        dashboard = nil
        Self.clearCachedDashboard(accountId: accountId)
        lastDashboardRefresh = nil
        dashboardError = "Strava oturumuna geçici olarak ulaşılamadı."
        if let accountAccessToken {
            hasAttemptedAccountRestore = false
            status = "Strava bağlantısı Tempo hesabından yenileniyor…"
            Task { await restoreConnectionIfNeeded(accountToken: accountAccessToken, accountId: accountId) }
        } else {
            status = "Strava bağlantısının yenilenmesi için Tempo hesabına giriş yap."
        }
    }

    private func addWaterToAppleHealth(_ amountMl: Int) {
        guard !isBusy, let accountId = activeTempoAccountId,
              let accountToken = accountAccessToken else { return }
        isBusy = true
        status = "%d ml Apple Sağlık’a ekleniyor…".tempoFormatted(amountMl)
        Task {
            defer { isBusy = false }
            do {
                try await healthStore.saveWater(amountMl: Double(amountMl))
                guard activeTempoAccountId == accountId, self.accountAccessToken == accountToken else { return }
                await syncAppleHealth()
                guard activeTempoAccountId == accountId, self.accountAccessToken == accountToken else { return }
                status = "%d ml Apple Sağlık’a eklendi.".tempoFormatted(amountMl)
            } catch {
                guard activeTempoAccountId == accountId, self.accountAccessToken == accountToken else { return }
                healthError = error.localizedDescription.tempoLocalized
                status = "Su Apple Sağlık’a eklenemedi: %@".tempoFormatted(error.localizedDescription.tempoLocalized)
            }
        }
    }

    private func uploadHealth(_ days: [String: TempoHealthMetrics], using accountToken: String, for accountId: String) async throws {
        guard activeTempoAccountId == accountId, accountAccessToken == accountToken else {
            throw APIError.server("Tempo hesabı değişti. Sağlık verileri eşitlenmedi.")
        }
        var request = URLRequest(url: URL(string: "/api/account/health", relativeTo: baseURL)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(accountToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(TempoHealthSyncPayload(days: days))
        let (data, response) = try await Self.apiSession.data(for: request)
        guard activeTempoAccountId == accountId, self.accountAccessToken == accountToken else {
            throw APIError.server("Tempo hesabı değişti. Sağlık verileri bu ekranda gösterilmedi.")
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.server("Sağlık verileri sunucuya eşitlenemedi.") }
        if http.statusCode == 401 { throw APIError.server("Tempo oturumunun süresi doldu. Yeniden giriş yapıp tekrar eşitle.") }
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

    private static func dashboardDiagnostic(_ response: HTTPURLResponse) -> String {
        var parts = ["HTTP \(response.statusCode)"]
        if let upstream = response.value(forHTTPHeaderField: "X-Tempo-Diagnostic"), !upstream.isEmpty {
            parts.append(upstream)
        }
        if let ray = response.value(forHTTPHeaderField: "CF-Ray"), !ray.isEmpty {
            parts.append("CF-Ray \(ray)")
        }
        return parts.joined(separator: " · ")
    }

    private static func networkDiagnostic(_ error: Error) -> String {
        "Network \((error as NSError).code)"
    }

    private static func prewarmAPI() {
        Task.detached(priority: .utility) {
            guard let url = URL(string: "https://apitempo.com/api/mobile/ping") else { return }
            var request = URLRequest(url: url)
            request.timeoutInterval = 6
            request.cachePolicy = .reloadIgnoringLocalCacheData
            _ = try? await apiSession.data(for: request)
        }
    }

    private static func localDay() -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func loadCachedDashboard(accountId: String) -> TempoDashboard? {
        let cacheURL = cacheFileURL("tempo-dashboard-v2.json", accountId: accountId)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
              let modifiedAt = attributes[.modificationDate] as? Date,
              Date().timeIntervalSince(modifiedAt) >= 0,
              Date().timeIntervalSince(modifiedAt) < dashboardCacheLifetime,
              let data = try? Data(contentsOf: cacheURL) else {
            clearCachedDashboard(accountId: accountId)
            return nil
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(TempoDashboard.self, from: data)
    }

    private static func saveCachedDashboard(_ dashboard: TempoDashboard, accountId: String) {
        guard let data = try? JSONEncoder().encode(dashboard) else { return }
        let cacheURL = cacheFileURL("tempo-dashboard-v2.json", accountId: accountId)
        try? data.write(to: cacheURL, options: .atomic)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: cacheURL.path)
    }

    private static func clearCachedDashboard(accountId: String) {
        try? FileManager.default.removeItem(at: cacheFileURL("tempo-dashboard-v2.json", accountId: accountId))
    }

    private static func loadCachedHealthDays(accountId: String) -> [String: TempoHealthMetrics] {
        let cacheURL = cacheFileURL("tempo-health-days-v1.json", accountId: accountId)
        guard let data = try? Data(contentsOf: cacheURL) else { return [:] }
        return (try? JSONDecoder().decode([String: TempoHealthMetrics].self, from: data)) ?? [:]
    }

    private static func saveCachedHealthDays(_ days: [String: TempoHealthMetrics], accountId: String) {
        guard let data = try? JSONEncoder().encode(days) else { return }
        let cacheURL = cacheFileURL("tempo-health-days-v1.json", accountId: accountId)
        try? data.write(to: cacheURL, options: .atomic)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: cacheURL.path)
    }

    private static func clearCachedHealthDays(accountId: String) {
        try? FileManager.default.removeItem(at: cacheFileURL("tempo-health-days-v1.json", accountId: accountId))
        UserDefaults.standard.removeObject(forKey: healthLastSyncKey(accountId: accountId))
    }

    private static func healthSyncKey(accountId: String) -> String {
        "tempoHealthSyncEnabledV2." + accountCacheIdentifier(accountId)
    }

    private static func healthLastSyncKey(accountId: String) -> String {
        "tempoHealthLastSyncV2." + accountCacheIdentifier(accountId)
    }

    private static func cacheFileURL(_ filename: String, accountId: String) -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TempoAccountCache", isDirectory: true)
            .appendingPathComponent(accountCacheIdentifier(accountId), isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        excludeFromDeviceBackup(directory)
        return directory.appendingPathComponent(filename)
    }

    private static func accountCacheIdentifier(_ accountId: String) -> String {
        SHA256.hash(data: Data(accountId.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func clearLegacyGlobalCaches() {
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: cacheDirectory.appendingPathComponent("tempo-dashboard-v2.json"))
        try? FileManager.default.removeItem(at: cacheDirectory.appendingPathComponent("tempo-health-days-v1.json"))
        if UserDefaults.standard.bool(forKey: "tempoHealthSyncEnabledV1") {
            UserDefaults.standard.set(true, forKey: "tempoHealthOptInNeedsRenewalV2")
        }
        UserDefaults.standard.removeObject(forKey: "tempoHealthSyncEnabledV1")
        UserDefaults.standard.removeObject(forKey: "tempoHealthLastSyncV1")
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
private struct SportsChatRequest: Encodable { let messages: [SportsChatTurn]; let includeHealth: Bool }
private struct SportsChatTurn: Encodable { let role: String; let content: String }
private struct StravaDisconnectResponse: Decodable { let stravaRevoked: Bool? }
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
    private static let fallbackKey = "tempoMobileAccessTokenBackupV3"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let token = String(data: data, encoding: .utf8),
           !token.isEmpty {
            // Remove credentials left by older builds. Bearer tokens belong in Keychain only.
            UserDefaults.standard.removeObject(forKey: fallbackKey)
            return token
        }

        guard let fallback = UserDefaults.standard.string(forKey: fallbackKey),
              !fallback.isEmpty else { return nil }
        // One-time migration from legacy builds. If Keychain is unavailable, fail closed and
        // require the user to sign in again instead of continuing with a plaintext token.
        guard saveToKeychain(fallback) else {
            UserDefaults.standard.removeObject(forKey: fallbackKey)
            return nil
        }
        UserDefaults.standard.removeObject(forKey: fallbackKey)
        return fallback
    }

    static func save(_ token: String) -> Bool {
        let keychainSaved = saveToKeychain(token)
        UserDefaults.standard.removeObject(forKey: fallbackKey)
        return keychainSaved
    }

    static func delete() {
        UserDefaults.standard.removeObject(forKey: fallbackKey)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func saveToKeychain(_ token: String) -> Bool {
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(match as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        var add = match
        attributes.forEach { add[$0.key] = $0.value }
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}

private enum OAuthVerifierStore {
    private static let verifierKey = "tempoPendingOAuthVerifierV1"
    private static let createdAtKey = "tempoPendingOAuthVerifierCreatedAtV1"
    private static let accountIdKey = "tempoPendingOAuthAccountIdV1"

    static func save(_ verifier: String, accountId: String) {
        UserDefaults.standard.set(verifier, forKey: verifierKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: createdAtKey)
        UserDefaults.standard.set(accountId, forKey: accountIdKey)
    }

    static func read() -> String? {
        let createdAt = UserDefaults.standard.double(forKey: createdAtKey)
        guard createdAt > 0, Date().timeIntervalSince1970 - createdAt < 15 * 60 else {
            delete()
            return nil
        }
        return UserDefaults.standard.string(forKey: verifierKey)
    }

    static func readAccountId() -> String? {
        let createdAt = UserDefaults.standard.double(forKey: createdAtKey)
        guard createdAt > 0, Date().timeIntervalSince1970 - createdAt < 15 * 60 else {
            delete()
            return nil
        }
        return UserDefaults.standard.string(forKey: accountIdKey)
    }

    static func delete() {
        UserDefaults.standard.removeObject(forKey: verifierKey)
        UserDefaults.standard.removeObject(forKey: createdAtKey)
        UserDefaults.standard.removeObject(forKey: accountIdKey)
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
