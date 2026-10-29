import SwiftUI
import Combine

extension StrengthSessionFocus {
    var title: String { ("cross.focus." + rawValue).tempoLocalized }
}

extension ActiveSportContext {
    static func selected(_ sportID: String, focus: StrengthSessionFocus = .unspecified) -> ActiveSportContext {
        let archetype = SportMapper().map(stravaType: sportID) ?? .endurance
        return ActiveSportContext(sportID: TempoSportChoice(rawValue: sportID) == nil ? "general" : sportID,
            archetype: archetype, strengthFocus: archetype == .strengthAndHypertrophy ? focus : .unspecified, isMindBody: sportID == "yoga")
    }
}

@MainActor
enum CrossSportInputAdapter {
    static func workouts(_ records: [TempoManualWorkout], store: SportMetricsStore, includeHealth: Bool) -> [CrossSportWorkout] {
        records.compactMap { workout in
            let record = store.applying(to: WorkoutPayloadAdapter.record(workout))
            guard record.source != .strava, record.source != .health || includeHealth,
                  let input = StrainInputAdapter.input(record) else { return nil }
            return CrossSportWorkout(workout: input, hasLowerBodyImpact: record.hasLowerBodyImpact)
        }
    }
}

@MainActor
struct InterferenceWarningView: View {
    let warning: InterferenceWarning
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("cross.warningTitle".tempoLocalized, systemImage: "figure.strengthtraining.traditional").font(.subheadline.weight(.semibold))
            Text(("cross.reason." + warning.reason.rawValue).tempoFormatted(max(1, warning.hoursSinceWorkout)))
            Text("cross.adjustment".tempoFormatted(warning.suggestedVolumeReductionPercent, warning.suggestedRPECap))
            if warning.limitedEvidence { Text("cross.limited".tempoLocalized).font(.caption) }
            Text("cross.warningNote".tempoLocalized).font(.caption)
        }.font(.subheadline).foregroundStyle(TempoTheme.primary).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(TempoTheme.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
            .accessibilityIdentifier("cross.warning")
    }
}

@MainActor
struct CrossSportPreparationView: View {
    let sportID: String
    @EnvironmentObject private var model: TempoAppModel
    @EnvironmentObject private var account: TempoAccountStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = SportMetricsStore()
    @State private var focus: StrengthSessionFocus = .unspecified
    @State private var warning: InterferenceWarning?
    private var active: ActiveSportContext { .selected(sportID, focus: focus) }
    var body: some View {
        TempoCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("cross.preparation".tempoLocalized).font(.headline)
                if active.archetype == .strengthAndHypertrophy {
                    Picker("cross.focusTitle".tempoLocalized, selection: $focus) {
                        ForEach(StrengthSessionFocus.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.menu).tint(TempoTheme.green)
                }
                if let warning { InterferenceWarningView(warning: warning) }
                else { Text((active.archetype == .strengthAndHypertrophy && focus == .unspecified ? "cross.chooseFocus" : "cross.noWarning").tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary) }
                NavigationLink(destination: CoachScreen(sportContext: active)) {
                    Label("cross.askCoach".tempoLocalized, systemImage: "sparkles").frame(maxWidth: .infinity)
                }.buttonStyle(TempoSecondaryButtonStyle()).accessibilityIdentifier("cross.coach")
                Text("cross.localNote".tempoLocalized).font(.caption2).foregroundStyle(TempoTheme.secondary)
            }
        }
        .task(id: account.profile?.id) { store.bind(account.profile?.id); refresh() }
        .onAppear { store.reload(); refresh() }
        .onChange(of: focus) { _, _ in refresh() }
        .onChange(of: store.revision) { _, _ in refresh() }
        .onChange(of: model.activityWorkouts) { _, _ in refresh() }
        .onChange(of: model.healthSyncEnabled) { _, _ in refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in refresh() }
    }
    private func refresh() {
        warning = InterferenceAnalyzer().warning(for: active, workouts: CrossSportInputAdapter.workouts(model.activityWorkouts, store: store, includeHealth: model.healthSyncEnabled))
    }
}
