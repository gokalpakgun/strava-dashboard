import SwiftUI

@main
@MainActor
struct TempoHealthApp: App {
    @UIApplicationDelegateAdaptor(TempoNotificationDelegate.self) private var notificationDelegate
    @StateObject private var model = TempoAppModel()
    @StateObject private var account = TempoAccountStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(account)
                .onOpenURL(perform: model.handleCallback)
                .task(id: (account.profile?.id ?? "") + (account.authorizationToken ?? "")) {
#if DEBUG
                    guard !ProcessInfo.processInfo.arguments.contains("--ui-testing-authenticated") else { return }
#endif
                    await TempoNotifications.shared.bind(account: account)
                    guard !Task.isCancelled, let owner = account.profile?.id, model.activityAccountID == owner else { return }
                    await TempoNotifications.shared.recordAchievement(ids: model.tempoAchievement.unlockedBadges.map(\.id), for: owner)
                }
                .task(id: [account.profile?.id ?? "", model.activityAccountID ?? ""] + model.tempoAchievement.unlockedBadges.map(\.id)) {
                    guard let owner = account.profile?.id, model.activityAccountID == owner else { return }
                    await TempoNotifications.shared.recordAchievement(ids: model.tempoAchievement.unlockedBadges.map(\.id), for: owner)
                }
                .onChange(of: scenePhase) { _, phase in
#if DEBUG
                    guard !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
#endif
                    if phase == .active {
                        account.restoreSessionIfNeeded()
                        model.syncWhenActive()
                        Task { await TempoNotifications.shared.bind(account: account) }
                    }
                }
        }
    }
}
