import SwiftUI

@main
struct TempoHealthApp: App {
    @StateObject private var model = TempoAppModel()
    @StateObject private var account = TempoAccountStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(account)
                .onOpenURL(perform: model.handleCallback)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        model.syncWhenActive()
                    }
                }
        }
    }
}
