import SwiftUI

@main
@MainActor
struct TempoHealthApp: App {
    @UIApplicationDelegateAdaptor(TempoNotificationDelegate.self) private var notificationDelegate
    @StateObject private var model = TempoAppModel()
    @StateObject private var account = TempoAccountStore()
    @ObservedObject private var detector = TempoWorkoutDetection.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(TempoAppearance.storageKey) private var appearance = TempoAppearance.system.rawValue

    init() { TempoWorkoutDetection.shared.bootstrap(); TempoPassiveGym.shared.bootstrap() }
    var body: some Scene { WindowGroup { notificationContent } }

    // Ayrı opaque View sınırları, büyüyen yaşam döngüsü zincirinin tür denetimini sınırlar.
    private var baseContent: some View {
        ContentView()
            .environmentObject(model)
            .environmentObject(account)
            .preferredColorScheme((TempoAppearance(rawValue: appearance) ?? .system).colorScheme)
            .onOpenURL(perform: model.handleCallback)
    }
    private var detectionContent: some View {
        baseContent
            .task(id: detectionKey) { await bindDetection() }
            .task(id: scenePhase) { await runWhileActive() }
            .task(id: responseKey) { bindResponses() }
    }
    private var circleContent: some View {
        detectionContent.task(id: circleKey) {
            await TempoCircleStore.shared.sync(account: account, model: model)
        }
    }
    private var notificationContent: some View {
        circleContent
            .task(id: (account.profile?.id ?? "") + (account.authorizationToken ?? "")) {
#if DEBUG
                guard !ProcessInfo.processInfo.arguments.contains("--ui-testing-authenticated") else { return }
#endif
                await TempoNotifications.shared.bind(account: account)
                guard !Task.isCancelled, let owner = account.profile?.id, model.activityAccountID == owner else { return }
                await TempoNotifications.shared.recordAchievement(ids: model.tempoAchievement.unlockedBadges.map(\.id), for: owner)
            }
            .task(id: achievementKey) {
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
    private var circleKey: [String] {
        [account.profile?.id ?? "", model.activityAccountID ?? "", model.healthLastSync?.description ?? "",
         model.healthWorkoutReadAt?.description ?? "", String(model.healthSyncEnabled), detector.lastScan?.description ?? ""]
    }
    private var detectionKey: [String] {
        [account.profile?.id ?? "", model.activityAccountID ?? "", String(account.isRestoring),
         String(model.healthSyncEnabled), model.activitySessionID.uuidString, String(model.manualWorkouts.count),
         model.healthLastSync?.description ?? ""]
    }
    private var responseKey: [String] {
        [account.profile?.id ?? "", model.activityAccountID ?? "", String(account.isRestoring),
         String(account.isAuthenticated), String(model.isRestoringConnection), String(detector.responseRevision), String(detector.enabled)]
    }
    private var achievementKey: [String] {
        [account.profile?.id ?? "", model.activityAccountID ?? ""] + model.tempoAchievement.unlockedBadges.map(\.id)
    }
    private func bindDetection() async {
        // Arka plan açılışında hesap geri yüklenirken kayıtlı bölgeyi kapatma.
        guard !account.isRestoring, !(account.isAuthenticated && model.activityAccountID == nil) else { return }
        let owner = account.profile?.id == model.activityAccountID ? model.activityAccountID : nil
        let known = model.activityWorkouts.map { DetectionInterval(start: $0.startedAt, end: $0.sourceEndedAt ?? $0.endedAt) }
        detector.bind(owner: owner, healthEnabled: model.healthSyncEnabled, known: known)
        TempoPassiveGym.shared.bind(owner: owner)
        if account.isAuthenticated { model.processPassiveResponses() }
        await detector.scan()
    }
    private func bindResponses() {
        guard !account.isRestoring, !(account.isAuthenticated && model.activityAccountID == nil) else { return }
        let owner = account.isAuthenticated && account.profile?.id == model.activityAccountID ? model.activityAccountID : nil
        TempoPassiveGym.shared.bind(owner: owner)
        if owner != nil { model.processPassiveResponses() }
    }
    private func runWhileActive() async {
        guard scenePhase == .active else { return }
        while !Task.isCancelled {
            if account.isAuthenticated { model.processPassiveResponses() }
            TempoPassiveGym.shared.refreshStatus()
            await detector.scan()
            await TempoCircleStore.shared.sync(account: account, model: model)
            do { try await Task.sleep(nanoseconds: 180_000_000_000) } catch { return }
        }
    }
}

