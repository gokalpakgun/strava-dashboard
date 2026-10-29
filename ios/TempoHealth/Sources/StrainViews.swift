import SwiftUI
import Combine

extension HybridAxis {
    var title: String { ("strain.axis." + rawValue).tempoLocalized }
    var color: Color {
        switch self { case .strength: return TempoTheme.orange; case .aerobic: return TempoTheme.blue; case .anaerobic: return TempoTheme.purple; case .mobility: return TempoTheme.green }
    }
    var symbol: String {
        switch self { case .strength: return "dumbbell.fill"; case .aerobic: return "heart.fill"; case .anaerobic: return "bolt.fill"; case .mobility: return "figure.flexibility" }
    }
}

enum StrainInputAdapter {
    static func input(_ record: ArchetypeWorkoutRecord) -> StrainWorkout? {
        guard record.source != .strava, let payload = record.payload else { return nil }
        let evidence = record.automaticZones.flatMap { seconds in payload.heartRateZones?.seconds == seconds.map(Optional.some) ? record.zoneEvidence : nil }
        return StrainWorkout(id: record.id, startedAt: record.date, durationSeconds: record.durationSeconds, payload: payload, source: record.source == .health ? .health : .tempo, isMindBody: record.isMindBody, userEntered: record.userEdited, effortIsEstimated: record.effortIsEstimated && payload.loadInputs.sessionRPE == record.automaticEffort, heartRateZoneEvidence: evidence, sourceEndedAt: record.sourceEndedAt)
    }
}

struct StrainDashboardState: Sendable {
    let summary: StrainWindowSummary
    let balance: HybridAthleteBalance
    let recent: [ArchetypeWorkoutRecord]
    let scores: [String: UniversalStrainScore]
    let missingDailyRecords: Int
    let muscleRecovery: MuscleRecoverySummary
    let acwr: ACWRSummary
}

@MainActor
final class StrainDashboardViewModel: ObservableObject {
    @Published private(set) var state: StrainDashboardState?
    func update(records: [ArchetypeWorkoutRecord], now: Date = Date()) {
        let engine = UniversalStrainEngine()
        var seen = Set<String>()
        let local = records.filter { $0.source != .strava && $0.durationSeconds.isFinite && (1...604_800).contains($0.durationSeconds) && $0.date.timeIntervalSince1970.isFinite && $0.endedAt <= now && seen.insert($0.id).inserted }
        let inputs = local.compactMap(StrainInputAdapter.input)
        let dailyStart = now.addingTimeInterval(-86_400)
        let summary = engine.summary(inputs, since: dailyStart, until: now)
        let recent = Array(local.filter { $0.endedAt > now.addingTimeInterval(-7 * 86_400) }.sorted { $0.date > $1.date }.prefix(30))
        var scores: [String: UniversalStrainScore] = [:]
        for record in recent {
            if let input = StrainInputAdapter.input(record), let value = engine.score(for: input, history: inputs) { scores[record.id] = value }
        }
        let dailyCount = local.filter { $0.endedAt > dailyStart }.count
        state = StrainDashboardState(summary: summary, balance: engine.hybridBalance(inputs, now: now), recent: recent, scores: scores, missingDailyRecords: max(0, dailyCount - summary.workoutsWithScore), muscleRecovery: MuscleRecoveryCalculator().summary(inputs, now: now), acwr: engine.acwrSummary(inputs, now: now))
    }
}

@MainActor
struct StrainDashboardScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    @EnvironmentObject private var account: TempoAccountStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = SportMetricsStore()
    @StateObject private var viewModel = StrainDashboardViewModel()
    var body: some View {
        TempoPage {
            PageTitle(title: "strain.title", subtitle: "strain.subtitle")
            if let state = viewModel.state {
                StrainScorePanel(value: state.summary.value, cardio: state.summary.cardioLoad, muscle: state.summary.muscleLoad)
                Text("strain.scoredCount".tempoFormatted(state.summary.workoutsWithScore, state.missingDailyRecords)).font(.caption).foregroundStyle(TempoTheme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if state.summary.hasLimitedEvidence || state.missingDailyRecords > 0 || state.summary.value == nil {
                    Label("strain.partial".tempoLocalized, systemImage: "info.circle").font(.subheadline).foregroundStyle(TempoTheme.secondary)
                }
                NavigationLink(destination: PolymorphicWorkoutLibraryScreen()) {
                    Label("strain.addInputs".tempoLocalized, systemImage: "slider.horizontal.3").frame(maxWidth: .infinity)
                }.buttonStyle(TempoSecondaryButtonStyle())
                MuscleRecoveryCard(summary: state.muscleRecovery)
                AcuteChronicLoadCard(summary: state.acwr)
                TempoCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("strain.balanceTitle".tempoLocalized).font(.headline)
                        Text("strain.balanceSubtitle".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
                        RadarChartView(balance: state.balance)
                        if !state.balance.leastRepresentedAxes.isEmpty {
                            Text("strain.least".tempoFormatted(state.balance.leastRepresentedAxes.map(\.title).joined(separator: ", "))).font(.subheadline).foregroundStyle(TempoTheme.secondary)
                        }
                        Text("strain.radarNote".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !state.recent.isEmpty {
                    SectionHeading(title: "strain.recent", caption: "strain.recentCaption", padding: false)
                    ForEach(state.recent) { record in
                        NavigationLink(destination: PolymorphicWorkoutDetailScreen(record: record, store: store)) {
                            HStack(spacing: 12) {
                                Image(systemName: record.payload?.archetype.symbol ?? "figure.mixed.cardio").foregroundStyle(TempoTheme.green).frame(width: 30)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.title).font(.subheadline.weight(.medium)).foregroundStyle(TempoTheme.primary)
                                    Text(record.sourceTitle + " · " + record.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(TempoTheme.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Text(state.scores[record.id].map { String($0.value) + "/100" } ?? "—").font(.subheadline.monospacedDigit()).foregroundStyle(TempoTheme.blue)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(TempoTheme.secondary)
                            }.padding(16).background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 20))
                        }.buttonStyle(.plain)
                    }
                }
            }
            if let error = store.error { Text(error).font(.footnote).foregroundStyle(TempoTheme.orange) }
            TempoDisclosureSection(title: "strain.howTitle", icon: "questionmark.circle") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("strain.howBody".tempoLocalized)
                    Text("strain.modelNote".tempoLocalized)
                    Text("strain.sources".tempoLocalized)
                }.font(.footnote).foregroundStyle(TempoTheme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.navigationTitle("strain.title".tempoLocalized).navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
            .task(id: account.profile?.id) { store.bind(account.profile?.id); refresh() }
            .onAppear { store.reload(); refresh() }
            .onChange(of: model.activityWorkouts) { _, _ in refresh() }
            .onChange(of: store.revision) { _, _ in refresh() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in refresh() }
    }
    private func refresh() {
        viewModel.update(records: model.activityWorkouts.map { store.applying(to: WorkoutPayloadAdapter.record($0)) })
    }
}

@MainActor
struct StrainScorePanel: View {
    let value: Int?
    let cardio: Int?
    let muscle: Int?
    private var band: String {
        guard let value else { return "strain.noScore" }
        switch value { case ..<30: return "strain.light"; case ..<60: return "strain.moderate"; case ..<80: return "strain.high"; default: return "strain.veryHigh" }
    }
    var body: some View {
        TempoCard {
            VStack(spacing: 18) {
                Text("strain.title".tempoLocalized).font(.headline)
                ZStack {
                    Circle().stroke(TempoTheme.primary.opacity(0.08), lineWidth: 9)
                    if let value {
                        Circle().trim(from: 0, to: CGFloat(value) / 100).stroke(AngularGradient(colors: [TempoTheme.blue, TempoTheme.purple], center: .center), style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
                    }
                    VStack(spacing: 4) {
                        Text(value.map({ String($0) }) ?? "—").font(.system(size: 42, weight: .medium, design: .rounded).monospacedDigit())
                        Text("/ 100").font(.caption).foregroundStyle(TempoTheme.secondary)
                    }
                }.frame(width: 150, height: 150).accessibilityElement(children: .ignore)
                    .accessibilityLabel("strain.title".tempoLocalized).accessibilityValue(value.map { "\($0)/100" } ?? "strain.noScore".tempoLocalized)
                Text(band.tempoLocalized).font(.title3.weight(.semibold)).foregroundStyle(TempoTheme.blue)
                Text("strain.scoreMeaning".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary).multilineTextAlignment(.center)
                TempoMetricGrid(columns: 2) {
                    component("strain.cardio", value: cardio, icon: "heart.fill")
                    component("strain.muscle", value: muscle, icon: "dumbbell.fill")
                }
            }.frame(maxWidth: .infinity)
        }
    }
    private func component(_ title: String, value: Int?, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title.tempoLocalized, systemImage: icon).font(.caption).foregroundStyle(TempoTheme.secondary)
            Text(value.map { "\($0)/100" } ?? "—").font(.title3.weight(.medium).monospacedDigit())
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(TempoTheme.raised, in: RoundedRectangle(cornerRadius: 16))
    }
}

@MainActor
struct RadarChartView: View {
    let balance: HybridAthleteBalance
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        VStack(spacing: 14) {
            if !textSize.isAccessibilitySize {
                GeometryReader { geometry in
                    let size = min(geometry.size.width, geometry.size.height)
                    let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    let radius = size * 0.34
                    ZStack {
                        ForEach(1...4, id: \.self) { step in
                            polygon(center: center, radius: radius, ratios: Array(repeating: Double(step) / 4, count: 4)).stroke(TempoTheme.primary.opacity(0.10), lineWidth: 1)
                        }
                        ForEach(Array(balance.axes.enumerated()), id: \.element.id) { index, axis in
                            Path { path in path.move(to: center); path.addLine(to: point(center, radius: radius, index: index, ratio: 1)) }.stroke(TempoTheme.primary.opacity(0.10), lineWidth: 1)
                            Text(axis.axis.title).font(.caption2.weight(.medium)).foregroundStyle(TempoTheme.secondary)
                                .position(point(center, radius: radius + 27, index: index, ratio: 1))
                            if let value = axis.value {
                                Circle().fill(axis.axis.color).frame(width: 8, height: 8).position(point(center, radius: radius, index: index, ratio: Double(value) / 100))
                            }
                        }
                        if balance.hasCompleteAxes {
                            polygon(center: center, radius: radius, ratios: balance.axes.map { Double($0.value ?? 0) / 100 })
                                .fill(TempoTheme.blue.opacity(0.12))
                            polygon(center: center, radius: radius, ratios: balance.axes.map { Double($0.value ?? 0) / 100 })
                                .stroke(TempoTheme.blue, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                        }
                    }
                }.frame(height: 230).accessibilityHidden(true)
            }
            ForEach(balance.axes) { axis in
                HStack {
                    Label(axis.axis.title, systemImage: axis.axis.symbol).foregroundStyle(axis.axis.color)
                    Spacer(minLength: 8)
                    Text(axis.value.map { "\($0)%" } ?? "strain.notEnoughData".tempoLocalized).foregroundStyle(TempoTheme.primary)
                }.font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func point(_ center: CGPoint, radius: CGFloat, index: Int, ratio: Double) -> CGPoint {
        let angle = Double(index) * .pi / 2 - .pi / 2
        return CGPoint(x: center.x + radius * CGFloat(ratio * cos(angle)), y: center.y + radius * CGFloat(ratio * sin(angle)))
    }
    private func polygon(center: CGPoint, radius: CGFloat, ratios: [Double]) -> Path {
        Path { path in
            for (index, ratio) in ratios.enumerated() {
                let location = point(center, radius: radius, index: index, ratio: ratio)
                if index == 0 { path.move(to: location) } else { path.addLine(to: location) }
            }
            path.closeSubpath()
        }
    }
}

@MainActor
struct WorkoutStrainPreview: View {
    let record: ArchetypeWorkoutRecord
    let history: [ArchetypeWorkoutRecord]
    private var result: UniversalStrainScore? {
        guard let input = StrainInputAdapter.input(record) else { return nil }
        return UniversalStrainEngine().score(for: input, history: history.compactMap(StrainInputAdapter.input))
    }
    var body: some View {
        TempoCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("strain.workoutTitle".tempoLocalized, systemImage: "gauge.with.dots.needle.33percent").font(.headline)
                if let result {
                    Text("\(result.value)/100").font(.title.weight(.medium).monospacedDigit()).foregroundStyle(TempoTheme.blue)
                    Text("strain.workoutParts".tempoFormatted(result.cardioLoad.map({ String($0) }) ?? "—", result.muscleLoad.map({ String($0) }) ?? "—")).font(.subheadline).foregroundStyle(TempoTheme.secondary)
                    if result.hasLimitedEvidence { Text("strain.partial".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary) }
                    DisclosureGroup("strain.technical".tempoLocalized) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TRIMP: " + (result.cardioTRIMP.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—"))
                            Text("strain.zoneCoverage".tempoFormatted(Int((result.zoneCoverage * 100).rounded())))
                            Text("strain.rpeDose".tempoFormatted(result.sessionRPELoadAU.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—"))
                            if let reference = result.personalTonnageReferenceKg { Text("strain.personalVolume".tempoFormatted(reference.formatted(.number.precision(.fractionLength(0))))) }
                            Text(result.modelVersion)
                        }.font(.caption).foregroundStyle(TempoTheme.secondary).padding(.top, 10)
                    }.font(.subheadline)
                } else { Text("strain.noScoreHelp".tempoLocalized).font(.subheadline).foregroundStyle(TempoTheme.secondary) }
                Text("strain.muscleNote".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@MainActor
struct HeartRateZonesCard: View {
    let record: ArchetypeWorkoutRecord
    private var evidence: HeartRateZoneEvidence? {
        guard let automatic = record.automaticZones, record.payload?.heartRateZones?.seconds == automatic.map(Optional.some) else { return nil }
        return record.zoneEvidence
    }
    var body: some View {
        if let zones = record.payload?.heartRateZones, zones.isValid {
            TempoCard {
                VStack(alignment: .leading, spacing: 14) {
                    Label("zones.title".tempoLocalized, systemImage: "waveform.path.ecg").font(.headline)
                    ForEach(0..<5, id: \.self) { index in
                        HStack(spacing: 12) {
                            Text("Z\(index + 1)").font(.caption.weight(.semibold)).frame(width: 24)
                            ProgressView(value: min(1, (zones.seconds[index] ?? 0) / max(1, record.durationSeconds))).tint(index >= 3 ? TempoTheme.orange : TempoTheme.blue)
                            Text(TempoFormat.duration(zones.seconds[index] ?? 0)).font(.caption.monospacedDigit()).frame(minWidth: 48, alignment: .trailing)
                        }
                    }
                    if let evidence {
                        Text((evidence.reference == .fallback190 ? "zones.fallback" : "zones.recordedPeak").tempoFormatted(Int(evidence.maximumHeartRateBpm.rounded()))).font(.caption).foregroundStyle(TempoTheme.secondary)
                        Text("zones.coverage".tempoFormatted(Int(min(100, evidence.observedSeconds / max(1, record.durationSeconds) * 100)))).font(.caption).foregroundStyle(TempoTheme.secondary)
                        if evidence.belowZoneSeconds > 0 { Text("zones.below".tempoFormatted(TempoFormat.duration(evidence.belowZoneSeconds))).font(.caption).foregroundStyle(TempoTheme.secondary) }
                        if evidence.queryWasLimited { Text("zones.partial".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.orange) }
                        Text("zones.method".tempoLocalized).font(.caption2).foregroundStyle(TempoTheme.secondary)
                    } else { Text("zones.manual".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary) }
                }
            }
        }
    }
}

@MainActor
struct MuscleRecoveryCard: View {
    let summary: MuscleRecoverySummary
    var body: some View {
        TempoCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("recovery.title".tempoLocalized, systemImage: "figure.strengthtraining.traditional").font(.headline)
                Text("recovery.subtitle".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
                if summary.hasData {
                    TempoMetricGrid(columns: 2) {
                        ForEach(summary.entries.filter { $0.readinessPercent != nil }) { entry in
                            let value = entry.readinessPercent ?? 0
                            VStack(alignment: .leading, spacing: 9) {
                                Text(("archetype.muscle." + entry.muscle.rawValue).tempoLocalized).font(.subheadline.weight(.medium))
                                Text("\(value)%").font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(value >= 75 ? TempoTheme.green : TempoTheme.orange)
                                ProgressView(value: Double(value) / 100).tint(value >= 75 ? TempoTheme.green : TempoTheme.orange)
                                Text("recovery.sets".tempoFormatted(entry.recentSets, entry.recentHighEffortSets)).font(.caption2).foregroundStyle(TempoTheme.secondary)
                            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(TempoTheme.raised, in: RoundedRectangle(cornerRadius: 17))
                        }
                    }
                    let missing = summary.entries.filter { $0.readinessPercent == nil }.map { ("archetype.muscle." + $0.muscle.rawValue).tempoLocalized }
                    if !missing.isEmpty { Text("recovery.missing".tempoFormatted(missing.joined(separator: ", "))).font(.caption).foregroundStyle(TempoTheme.secondary) }
                } else { Text("recovery.noData".tempoLocalized).font(.subheadline).foregroundStyle(TempoTheme.secondary) }
                if summary.unclassifiedRecentSets > 0 { Text("recovery.unclassified".tempoFormatted(summary.unclassifiedRecentSets)).font(.caption).foregroundStyle(TempoTheme.secondary) }
                DisclosureGroup("recovery.how".tempoLocalized) { Text("recovery.explanation".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary).padding(.top, 8) }.font(.subheadline)
                Text("recovery.note".tempoLocalized).font(.caption2).foregroundStyle(TempoTheme.secondary)
            }
        }.accessibilityIdentifier("strain.muscleRecovery")
    }
}

@MainActor
struct AcuteChronicLoadCard: View {
    let summary: ACWRSummary
    var body: some View {
        TempoCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("acwr.title".tempoLocalized, systemImage: "chart.bar.xaxis").font(.headline)
                Text(summary.status == .insufficientHistory ? "—" : (summary.ratio.map { $0.formatted(.number.precision(.fractionLength(2))) + "×" } ?? "—")).font(.largeTitle.weight(.medium).monospacedDigit()).foregroundStyle(TempoTheme.blue)
                Text(("acwr.status." + summary.status.rawValue).tempoLocalized).font(.subheadline.weight(.semibold))
                Text("acwr.history".tempoFormatted(summary.historyDays, summary.scoredWorkouts, summary.unscoredWorkouts)).font(.caption).foregroundStyle(TempoTheme.secondary)
                if summary.limitedEvidence { Text("acwr.limited".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary) }
                DisclosureGroup("acwr.how".tempoLocalized) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("acwr.formula".tempoLocalized)
                        if summary.status == .insufficientHistory, let ratio = summary.ratio { Text("acwr.provisional".tempoFormatted(ratio.formatted(.number.precision(.fractionLength(2))))) }
                        Text("acwr.doses".tempoFormatted(summary.acuteDose.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "—", summary.chronicWeeklyAverageDose.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "—"))
                        Text("acwr.bands".tempoLocalized)
                    }.font(.caption).foregroundStyle(TempoTheme.secondary).padding(.top, 8)
                }.font(.subheadline)
                Text("acwr.note".tempoLocalized).font(.caption2).foregroundStyle(TempoTheme.secondary)
            }
        }.accessibilityIdentifier("strain.acwr")
    }
}
