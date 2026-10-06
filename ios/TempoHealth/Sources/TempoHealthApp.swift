import SwiftUI

@main
struct TempoHealthApp: App {
    @StateObject private var model = TempoAppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .onOpenURL(perform: model.handleCallback)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        model.syncWhenActive()
                    }
                }
        }
    }
}
