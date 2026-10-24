import Combine
import Foundation
import SwiftUI
import UIKit
import UserNotifications

final class TempoNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in await TempoNotifications.shared.receivedDeviceToken(token) }
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in TempoNotifications.shared.registrationFailed() }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in await TempoNotifications.shared.refresh() }
        completionHandler([.banner, .sound, .list])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo["tempo"] as? [String: String]
        Task { @MainActor in
            TempoNotifications.shared.open(destination: info?["destination"] ?? "notifications")
            await TempoNotifications.shared.refresh()
        }
        completionHandler()
    }
}

struct TempoNotice: Codable, Identifiable, Equatable {
    let id: String
    let type: String
    let createdAt: String
    var read: Bool
    let destination: String
    var title: String {
        switch type {
        case "friend_request": return "Yeni arkadaşlık isteği".tempoLocalized
        case "friend_accepted": return "Artık arkadaşsınız".tempoLocalized
        case "challenge_invite": return "Yeni yarış daveti".tempoLocalized
        case "achievement": return "Yeni bir dönüm noktası".tempoLocalized
        default: return "Hareket zamanı".tempoLocalized
        }
    }
    var message: String {
        switch type {
        case "friend_request": return "Gelen isteği görmek için sosyal bölümünü aç.".tempoLocalized
        case "friend_accepted": return "Birlikte hareket etmek için ortak bir hedef belirleyebilirsiniz.".tempoLocalized
        case "challenge_invite": return "Davetin ayrıntılarına göz at; katılmak sana bağlı.".tempoLocalized
        case "achievement": return "İlerlemeni başarımlar bölümünde görebilirsin.".tempoLocalized
        default: return "Kısa bir yürüyüş veya esneme de iyi bir başlangıç.".tempoLocalized
        }
    }
    var date: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: createdAt) ?? ISO8601DateFormatter().date(from: createdAt)
    }
    var icon: String {
        switch type {
        case "friend_request", "friend_accepted": return "person.2.fill"
        case "challenge_invite": return "flag.checkered"
        case "achievement": return "medal.fill"
        default: return "figure.walk"
        }
    }
}

struct TempoNotificationPreferences: Codable, Equatable {
    var friends = true
    var challenges = true
    var dailyReminder = false
    var weeklyReview = false
    var achievements = false
    var hour = 18
    var minute = 0
}

@MainActor
final class TempoNotifications: ObservableObject {
    static let shared = TempoNotifications()
    @Published var authorization: UNAuthorizationStatus = .notDetermined
    @Published var preferences = TempoNotificationPreferences()
    @Published var notices: [TempoNotice] = []
    @Published var route: String?
    @Published var message = ""
    @Published var busy = false
    @Published var pushAvailable = false
    private var deviceToken: String?
    private var userId: String?
    private var accountToken: String?
    private var lastRegistration = ""
    private var loading = false
    private var registering = false
    private var registerAgain = false
    private let center = UNUserNotificationCenter.current()
    var unreadCount: Int { notices.filter { !$0.read }.count }
    var allowed: Bool { authorization == .authorized || authorization == .provisional || authorization == .ephemeral }
    private var preferenceKey: String { "tempo.notification.preferences." + (userId ?? "none") }
    private var inboxKey: String { "tempo.notification.inbox." + (userId ?? "none") }
    private var apnsEnvironment: String {
#if DEBUG
        return "development"
#else
        return "production"
#endif
    }

    func bind(account: TempoAccountStore) async {
        let next = account.profile?.id
        if userId != next {
            // Cancel the previous account's reminders before loading the next.
            center.removePendingNotificationRequests(withIdentifiers: ["tempo.daily", "tempo.weekly"])
            center.removeAllDeliveredNotifications()
            userId = next
            notices = []
            preferences = (UserDefaults.standard.data(forKey: preferenceKey).flatMap { try? JSONDecoder().decode(TempoNotificationPreferences.self, from: $0) }) ?? TempoNotificationPreferences()
            if let data = UserDefaults.standard.data(forKey: inboxKey), let cache = try? JSONDecoder().decode([TempoNotice].self, from: data) { notices = cache }
            lastRegistration = ""
            pushAvailable = false
        }
        accountToken = account.authorizationToken
        await refreshPermission()
        guard userId != nil, accountToken != nil else { return }
        if allowed {
#if !targetEnvironment(simulator)
            UIApplication.shared.registerForRemoteNotifications()
#endif
            await registerDevice()
        }
        await scheduleReminders()
        await refresh()
    }

    func refreshPermission() async {
        authorization = await center.notificationSettings().authorizationStatus
    }
    func enable() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshPermission()
            if allowed {
#if !targetEnvironment(simulator)
                UIApplication.shared.registerForRemoteNotifications()
#endif
                await registerDevice(force: true)
                await scheduleReminders()
                message = "Bildirim tercihlerin kaydedildi.".tempoLocalized
            } else { message = "Bildirim iznini iPhone Ayarları’ndan açabilirsin.".tempoLocalized }
        } catch { message = "Bildirim izni şu anda alınamadı. Tekrar deneyebilirsin.".tempoLocalized }
    }
    func receivedDeviceToken(_ token: String) async {
        deviceToken = token
        await registerDevice()
    }
    func registrationFailed() {
        message = "Anlık bildirim bağlantısı kurulamadı. Uygulamayı yeniden açtığında tekrar denenecek.".tempoLocalized
    }
    func savePreferences() async {
        guard userId != nil else { return }
        if let data = try? JSONEncoder().encode(preferences) { UserDefaults.standard.set(data, forKey: preferenceKey) }
        await registerDevice(force: true)
        await scheduleReminders()
    }
    func refresh() async {
        guard !loading, let token = accountToken, let owner = userId else { return }
        loading = true
        defer { loading = false }
        do {
            let data = try await api(path: "/api/account/notifications", method: "GET", token: token)
            let result = try JSONDecoder().decode(Inbox.self, from: data)
            guard userId == owner, accountToken == token else { return }
            let local = notices.filter { $0.type == "achievement" }
            notices = Array((result.notifications + local).sorted { $0.createdAt > $1.createdAt }.prefix(70))
            pushAvailable = result.pushAvailable
            saveInbox()
        } catch {
            guard userId == owner else { return }
            message = "Bildirimler yüklenemedi. Yenilemek için aşağı çek.".tempoLocalized
        }
    }
    func markRead(_ notice: TempoNotice) async {
        if let i = notices.firstIndex(where: { $0.id == notice.id }) { notices[i].read = true; saveInbox() }
        if notice.type != "achievement", let token = accountToken {
            _ = try? await api(path: "/api/account/notifications/read", method: "POST", token: token, body: ["id": notice.id])
        }
    }
    func open(destination: String) {
        route = ["social", "sports", "achievements", "summary", "notifications"].contains(destination) ? destination : "notifications"
    }
    func detach(eraseAccountData: Bool = false) {
        if eraseAccountData, let userId {
            UserDefaults.standard.removeObject(forKey: preferenceKey)
            UserDefaults.standard.removeObject(forKey: inboxKey)
            UserDefaults.standard.removeObject(forKey: "tempo.notification.earned." + userId)
        }
        center.removePendingNotificationRequests(withIdentifiers: ["tempo.daily", "tempo.weekly"])
        center.removeAllDeliveredNotifications()
        accountToken = nil
        userId = nil
        deviceToken = nil
        lastRegistration = ""
        notices = []
        route = nil
    }
    func recordAchievement(ids: [String]) async {
        guard let userId else { return }
        let key = "tempo.notification.earned." + userId
        let previous = UserDefaults.standard.stringArray(forKey: key)
        UserDefaults.standard.set(ids, forKey: key)
        // Establish a baseline first; do not announce historical achievements.
        guard let previous, ids.contains(where: { !previous.contains($0) }), preferences.achievements else { return }
        let notice = TempoNotice(id: UUID().uuidString, type: "achievement", createdAt: ISO8601DateFormatter().string(from: Date()), read: false, destination: "achievements")
        notices.insert(notice, at: 0)
        notices = Array(notices.prefix(70)); saveInbox()
        if allowed {
            let content = UNMutableNotificationContent()
            content.title = notice.title; content.body = notice.message; content.sound = .default
            content.userInfo = ["tempo": ["destination": "achievements"]]
            try? await center.add(UNNotificationRequest(identifier: "tempo.achievement." + notice.id, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
        }
    }
    private func registerDevice(force: Bool = false) async {
        guard allowed, let token = deviceToken, let auth = accountToken, let owner = userId else { return }
        if registering { registerAgain = true; return }
        registering = true
        defer {
            registering = false
            if registerAgain {
                registerAgain = false
                Task {
                    try? await Task.sleep(nanoseconds: 1_100_000_000)
                    await registerDevice(force: true)
                }
            }
        }
        let language = Locale.preferredLanguages.first?.hasPrefix("tr") == true ? "tr" : "en"
        let fingerprint = owner + auth + token + language + String(preferences.friends) + String(preferences.challenges)
        guard force || fingerprint != lastRegistration else { return }
        do {
            let data = try await api(path: "/api/account/push/devices", method: "POST", token: auth, body: ["token": token, "environment": apnsEnvironment, "language": language, "friends": preferences.friends, "challenges": preferences.challenges])
            guard accountToken == auth else { return }
            lastRegistration = fingerprint
            pushAvailable = (try? JSONDecoder().decode(PushResult.self, from: data).pushAvailable) ?? false
        } catch { message = "Anlık bildirim bağlantısı kurulamadı. Uygulamayı yeniden açtığında tekrar denenecek.".tempoLocalized }
    }
    private func scheduleReminders() async {
        center.removePendingNotificationRequests(withIdentifiers: ["tempo.daily", "tempo.weekly"])
        guard userId != nil, allowed else { return }
        if preferences.dailyReminder {
            await schedule(id: "tempo.daily", title: "Kendine biraz hareket ayır".tempoLocalized, body: "Zamanına ve enerjine uygun bir antrenman seçebilirsin.".tempoLocalized, date: DateComponents(hour: preferences.hour, minute: preferences.minute), destination: "sports")
        }
        if preferences.weeklyReview {
            await schedule(id: "tempo.weekly", title: "Haftana bir göz at".tempoLocalized, body: "Hareket düzenini ve gelişimini Tempo’da inceleyebilirsin.".tempoLocalized, date: DateComponents(hour: 18, minute: 0, weekday: 1), destination: "summary")
        }
    }
    private func schedule(id: String, title: String, body: String, date: DateComponents, destination: String) async {
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        content.userInfo = ["tempo": ["destination": destination]]
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: true)))
    }
    private func saveInbox() {
        if let data = try? JSONEncoder().encode(notices) { UserDefaults.standard.set(data, forKey: inboxKey) }
    }
    private func api(path: String, method: String, token: String, body: [String: Any]? = nil) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://apitempo.com" + path)!)
        request.httpMethod = method; request.timeoutInterval = 12
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else { throw URLError(.badServerResponse) }
        return data
    }
    private struct Inbox: Decodable { let notifications: [TempoNotice]; let pushAvailable: Bool }
    private struct PushResult: Decodable { let pushAvailable: Bool }
}

struct TempoNotificationsScreen: View {
    @ObservedObject private var notifications = TempoNotifications.shared
    var body: some View {
        TempoPage {
            PageTitle(title: "Bildirimler", subtitle: "SANA ÖZEL")
            NavigationLink(destination: TempoNotificationSettingsScreen()) {
                Label("Bildirim tercihleri", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(TempoSecondaryButtonStyle()).accessibilityIdentifier("notifications.settings")
            if notifications.notices.isEmpty {
                TempoCard {
                    VStack(spacing: 12) {
                        Image(systemName: "bell.badge").font(.largeTitle).foregroundStyle(TempoTheme.green)
                        Text("Henüz bildirim yok").font(.headline)
                        Text("Arkadaşlık istekleri, yarış davetleri ve yeni başarımların burada görünür.").font(.subheadline).foregroundStyle(TempoTheme.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).padding(.vertical, 24)
                }
            } else {
                ForEach(notifications.notices) { notice in
                    Button {
                        Task { await notifications.markRead(notice); notifications.open(destination: notice.destination) }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: notice.icon).foregroundStyle(TempoTheme.green).frame(width: 38, height: 38).background(TempoTheme.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(notice.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                Text(notice.message).font(.caption).foregroundStyle(TempoTheme.secondary)
                                if let date = notice.date { Text(date, style: .relative).font(.caption2).foregroundStyle(TempoTheme.secondary) }
                            }
                            Spacer(minLength: 2)
                            if !notice.read { Circle().fill(TempoTheme.green).frame(width: 7, height: 7) }
                        }.padding(15).background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 20))
                    }.buttonStyle(.plain).accessibilityIdentifier("notification.\(notice.type)")
                }
            }
            if !notifications.message.isEmpty { Text(notifications.message).font(.caption).foregroundStyle(TempoTheme.secondary) }
        }
        .accessibilityIdentifier("screen.notifications")
        .navigationTitle("Bildirimler").navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
        .task { await notifications.refresh() }
        .refreshable { await notifications.refresh() }
    }
}

struct TempoNotificationSettingsScreen: View {
    @ObservedObject private var notifications = TempoNotifications.shared
    private var reminderTime: Binding<Date> {
        Binding(get: { Calendar.current.date(from: DateComponents(hour: notifications.preferences.hour, minute: notifications.preferences.minute)) ?? Date() }, set: { date in
            notifications.preferences.hour = Calendar.current.component(.hour, from: date)
            notifications.preferences.minute = Calendar.current.component(.minute, from: date)
        })
    }
    var body: some View {
        TempoPage {
            PageTitle(title: "Bildirim tercihleri", subtitle: "SENİN RİTMİN")
            TempoCard {
                VStack(alignment: .leading, spacing: 13) {
                    Label(notifications.allowed ? "Bildirimler açık".tempoLocalized : "Bildirimleri aç".tempoLocalized, systemImage: notifications.allowed ? "bell.badge.fill" : "bell.slash").font(.headline)
                    Text("Sosyal davetler ve seçtiğin hatırlatmalar için kullanılır. Sağlık ölçümlerin bildirim metnine eklenmez.").font(.caption).foregroundStyle(TempoTheme.secondary)
                    if !notifications.allowed {
                        Button(notifications.authorization == .denied ? "iPhone Ayarları’nı aç".tempoLocalized : "Bildirim izni ver".tempoLocalized) {
                            if notifications.authorization == .denied, let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            else { Task { await notifications.enable() } }
                        }.buttonStyle(TempoPrimaryButtonStyle()).disabled(notifications.busy).accessibilityIdentifier("notifications.enable")
                    }
                    if notifications.allowed && !notifications.pushAvailable {
                        Text("Anlık bildirim hizmeti henüz hazır değil; uygulama içi bildirimlerini burada görebilirsin.").font(.caption).foregroundStyle(TempoTheme.secondary)
                    }
                }
            }
            TempoCard {
                VStack(spacing: 16) {
                    Toggle("Arkadaşlık istekleri", isOn: $notifications.preferences.friends).accessibilityIdentifier("notifications.friends")
                    Divider().overlay(.white.opacity(0.06))
                    Toggle("Yarış davetleri", isOn: $notifications.preferences.challenges).accessibilityIdentifier("notifications.challenges")
                    Divider().overlay(.white.opacity(0.06))
                    Toggle("Yeni başarımlar", isOn: $notifications.preferences.achievements).accessibilityIdentifier("notifications.achievements")
                }.tint(TempoTheme.green)
            }
            TempoCard {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Günlük hareket hatırlatması", isOn: $notifications.preferences.dailyReminder).accessibilityIdentifier("notifications.daily")
                    if notifications.preferences.dailyReminder { DatePicker("Hatırlatma saati", selection: reminderTime, displayedComponents: .hourAndMinute) }
                    Divider().overlay(.white.opacity(0.06))
                    Toggle("Haftalık değerlendirme", isOn: $notifications.preferences.weeklyReview)
                    Text("Haftalık hatırlatma pazar günü 18.00’de gelir. Hatırlatmalar internet olmadan da çalışır.").font(.caption).foregroundStyle(TempoTheme.secondary)
                }.tint(TempoTheme.green)
            }
            if !notifications.message.isEmpty { Text(notifications.message).font(.caption).foregroundStyle(TempoTheme.secondary) }
        }.accessibilityIdentifier("screen.notificationSettings")
        .navigationTitle("Bildirim tercihleri").navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
        .task { await notifications.refreshPermission() }
        .onChange(of: notifications.preferences) { _, _ in Task { await notifications.savePreferences() } }
    }
}
