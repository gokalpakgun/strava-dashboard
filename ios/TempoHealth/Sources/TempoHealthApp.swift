import SwiftUI

@main
@MainActor
struct TempoHealthApp: App {
    @UIApplicationDelegateAdaptor(TempoNotificationDelegate.self) private var notificationDelegate
    @StateObject private var model = TempoAppModel()
    @StateObject private var account = TempoAccountStore()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(TempoAppearance.storageKey) private var appearance = TempoAppearance.system.rawValue

    init() { TempoWorkoutDetection.shared.bootstrap() }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(account)
                .preferredColorScheme((TempoAppearance(rawValue: appearance) ?? .system).colorScheme)
                .onOpenURL(perform: model.handleCallback)
                .task(id: [account.profile?.id ?? "", model.activityAccountID ?? "", String(model.healthSyncEnabled), model.activitySessionID.uuidString, String(model.manualWorkouts.count), model.healthLastSync?.description ?? ""]) {
                    let owner = account.profile?.id == model.activityAccountID ? model.activityAccountID : nil
                    let known = model.activityWorkouts.map { DetectionInterval(start: $0.startedAt, end: $0.sourceEndedAt ?? $0.endedAt) }
                    TempoWorkoutDetection.shared.bind(owner: owner, healthEnabled: model.healthSyncEnabled, known: known)
                    await TempoWorkoutDetection.shared.scan()
                }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    while !Task.isCancelled {
                        await TempoWorkoutDetection.shared.scan()
                        do { try await Task.sleep(nanoseconds: 180_000_000_000) } catch { return }
                    }
                }
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
