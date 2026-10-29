import SwiftUI
import Combine

extension SportArchetype {
    var title: String { ("archetype." + rawValue).tempoLocalized }
    var symbol: String {
        switch self { case .strengthAndHypertrophy: return "dumbbell.fill"; case .endurance: return "figure.run"; case .teamAndCourt: return "sportscourt.fill"; case .combatAndMindBody: return "figure.mind.and.body" }
    }
    var color: Color {
        switch self { case .strengthAndHypertrophy: return TempoTheme.orange; case .endurance: return TempoTheme.blue; case .teamAndCourt: return TempoTheme.green; case .combatAndMindBody: return TempoTheme.purple }
    }
}

enum ArchetypeRecordSource: String, Sendable { case tempo, health, strava }

struct ArchetypeWorkoutRecord: Identifiable, Sendable {
    let id: String
    let title: String
    let date: Date
    let durationSeconds: Double
    let source: ArchetypeRecordSource
    let sourceLabel: String
    var payload: WorkoutPayload?
    var userEdited = false
    var isMindBody = false
    var sportID: String?
    var hasLowerBodyImpact = false
    var averageHeartRateBpm: Double?
    var peakHeartRateBpm: Double?
    var automaticEffort: Double?
    var effortIsEstimated = false
    var sourceTitle: String {
        sourceLabel
    }
}

@MainActor
enum WorkoutPayloadAdapter {
    static func record(_ workout: TempoManualWorkout) -> ArchetypeWorkoutRecord {
        let mapper = SportMapper()
        let archetype = workout.originalArchetype.flatMap(SportArchetype.init(rawValue:)) ?? mapper.map(stravaType: workout.sportId)
        let duration = Double(workout.durationSeconds ?? workout.durationMinutes * 60)
        var payload = archetype.map(WorkoutPayload.empty(for:))
        if archetype == .endurance {
            let discipline = workout.originalHealthActivityType.map { EnduranceDiscipline.from(healthKitRawValue: $0) } ?? .from(workout.sportId)
            payload = .endurance(EnduranceMetrics(discipline: discipline, distanceMeters: workout.distanceKm.map { $0 * 1_000 }, movingSeconds: duration, cadencePerMinute: workout.sourceCadencePerMinute.flatMap { $0.isFinite && (0...400).contains($0) ? $0 : nil }, averagePowerWatts: workout.sourceAveragePowerWatts.flatMap { $0.isFinite && (0...5_000).contains($0) ? $0 : nil }))
        }
        if archetype == .teamAndCourt { payload = .teamCourt(TeamCourtMetrics(activeEnergyKcal: workout.sourceEnergyKcal ?? workout.healthSignal?.activeEnergyKcal)) }
        if let effort = workout.sourceWorkoutEffort, effort.isFinite, (1...10).contains(effort), var value = payload {
            var input = value.loadInputs; input.sessionRPE = effort; value.loadInputs = input; payload = value
        }
        // Mevcut 1–5 zorluk notu, farklı bir ölçek olan RPE 1–10'a dönüştürülmez.
        return ArchetypeWorkoutRecord(id: "local-" + workout.id.uuidString, title: workout.title, date: workout.startedAt, durationSeconds: duration, source: workout.recordSource == "apple-health" ? .health : .tempo, sourceLabel: workout.sourceTitle, payload: payload, isMindBody: workout.sportId == "yoga" || SportMapper.isMindBody(healthKitRawValue: workout.originalHealthActivityType), sportID: workout.sportId, hasLowerBodyImpact: ["football", "basketball", "tennis", "volleyball", "padel", "badminton"].contains(workout.sportId) || SportMapper.hasLowerBodyImpact(healthKitRawValue: workout.originalHealthActivityType), averageHeartRateBpm: workout.sourceAverageHeartRateBpm, peakHeartRateBpm: workout.sourcePeakHeartRateBpm, automaticEffort: workout.sourceWorkoutEffort, effortIsEstimated: workout.sourceEffortIsEstimated == true)
    }
    static func record(_ activity: TempoActivity) -> ArchetypeWorkoutRecord? {
        guard let date = activity.date else { return nil }
        let archetype = SportMapper().map(stravaType: activity.type ?? "")
        var payload = archetype.map(WorkoutPayload.empty(for:))
        if archetype == .endurance { payload = .endurance(EnduranceMetrics(discipline: .from(activity.type ?? ""), distanceMeters: activity.distance, movingSeconds: activity.movingTime)) }
        return ArchetypeWorkoutRecord(id: "strava-\(activity.id)", title: activity.name ?? activity.sport.title, date: date, durationSeconds: activity.movingSeconds, source: .strava, sourceLabel: "Strava", payload: payload)
    }
}

@MainActor
protocol WorkoutMetricsRepository {
    func load(for owner: String) throws -> [String: WorkoutPayload]
    func save(_ entries: [String: WorkoutPayload], for owner: String) throws
    func remove(for owner: String)
}

@MainActor
struct UserDefaultsWorkoutMetricsRepository: WorkoutMetricsRepository {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private func key(_ owner: String) -> String { "tempo.archetype-details.v1." + owner }
    func load(for owner: String) throws -> [String: WorkoutPayload] {
        guard let data = defaults.data(forKey: key(owner)) else { return [:] }
        return try JSONDecoder().decode([String: WorkoutPayload].self, from: data)
    }
    func save(_ entries: [String: WorkoutPayload], for owner: String) throws {
        let encoded = try JSONEncoder().encode(entries)
        guard encoded.count <= 10_000_000 else { throw CocoaError(.fileWriteOutOfSpace) }
        defaults.set(encoded, forKey: key(owner))
    }
    func remove(for owner: String) { defaults.removeObject(forKey: key(owner)) }
}

@MainActor
final class SportMetricsStore: ObservableObject {
    @Published private var entries: [String: WorkoutPayload] = [:]
    @Published private(set) var owner: String?
    @Published private(set) var error: String?
    @Published private(set) var revision = 0
    private let repository: any WorkoutMetricsRepository
    init(repository: (any WorkoutMetricsRepository)? = nil) { self.repository = repository ?? UserDefaultsWorkoutMetricsRepository() }
    func bind(_ owner: String?) {
        guard self.owner != owner else { return }
        self.owner = owner; entries = [:]; error = nil
        reload()
    }
    func reload() {
        defer { revision += 1 }
        guard let owner else { return }
        do {
            let decoded = try repository.load(for: owner)
            guard decoded.values.allSatisfy(\.isValid) else { throw CocoaError(.coderReadCorrupt) }
            entries = decoded; error = nil
        } catch { self.error = "archetype.storageError".tempoLocalized }
    }
    static func removeData(for owner: String) { UserDefaultsWorkoutMetricsRepository().remove(for: owner) }
    func applying(to record: ArchetypeWorkoutRecord) -> ArchetypeWorkoutRecord {
        var result = record
        if record.source != .strava, let saved = entries[record.id], saved.archetype == record.payload?.archetype { result.payload = saved.fillingMissing(from: record.payload); result.userEdited = true }
        return result
    }
    func save(_ payload: WorkoutPayload, for record: ArchetypeWorkoutRecord, owner expectedOwner: String) throws {
        guard let owner, owner == expectedOwner, error == nil, record.source != .strava, record.durationSeconds.isFinite, record.durationSeconds > 0, payload.archetype == record.payload?.archetype, payload.isValid else {
            throw NSError(domain: "TempoMetrics", code: 1, userInfo: [NSLocalizedDescriptionKey: "archetype.invalid".tempoLocalized])
        }
        if let zones = payload.heartRateZones, zones.totalSeconds > record.durationSeconds + 1 {
            throw NSError(domain: "TempoMetrics", code: 2, userInfo: [NSLocalizedDescriptionKey: "archetype.zonesDuration".tempoLocalized])
        }
        if let seconds = payload.loadInputs.explosiveSeconds, seconds > record.durationSeconds {
            throw NSError(domain: "TempoMetrics", code: 6, userInfo: [NSLocalizedDescriptionKey: "strain.explosiveDurationError".tempoLocalized])
        }
        if case .combatMindBody(let value) = payload, value.rounds.compactMap(\.seconds).reduce(0, +) > record.durationSeconds + 1 {
            throw NSError(domain: "TempoMetrics", code: 3, userInfo: [NSLocalizedDescriptionKey: "archetype.roundsDuration".tempoLocalized])
        }
        if case .endurance(let value) = payload, let moving = value.movingSeconds, moving > record.durationSeconds + 1 {
            throw NSError(domain: "TempoMetrics", code: 4, userInfo: [NSLocalizedDescriptionKey: "archetype.movingDuration".tempoLocalized])
        }
        if case .endurance(let value) = payload, value.laps.compactMap(\.seconds).reduce(0, +) > record.durationSeconds + 1 {
            throw NSError(domain: "TempoMetrics", code: 5, userInfo: [NSLocalizedDescriptionKey: "archetype.lapsDuration".tempoLocalized])
        }
        var updated = entries; updated[record.id] = payload.removingAutomaticMatches(from: record.payload)
        try repository.save(updated, for: owner); entries = updated; revision += 1
    }
}

@MainActor
struct PolymorphicWorkoutCardView: View {
    let record: ArchetypeWorkoutRecord
    var showsDisclosure = false
    private func number(_ value: Double?, unit: String = "") -> String {
        guard let value, value.isFinite else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0...1))) + (unit.isEmpty ? "" : " " + unit)
    }
    var body: some View {
        TempoCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: record.payload?.archetype.symbol ?? "figure.mixed.cardio").font(.title2).foregroundStyle(record.payload?.archetype.color ?? TempoTheme.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.title).font(.headline).foregroundStyle(TempoTheme.primary).fixedSize(horizontal: false, vertical: true)
                        Text(record.payload?.archetype.title ?? "archetype.unmapped".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
                        Text(record.sourceTitle + " · " + record.date.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(TempoTheme.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if showsDisclosure { Image(systemName: "chevron.right").font(.caption).foregroundStyle(TempoTheme.secondary).accessibilityHidden(true) }
                }
                Label(record.durationSeconds.isFinite && (0...31_536_000).contains(record.durationSeconds) ? TempoFormat.duration(record.durationSeconds) : "—", systemImage: "clock").font(.subheadline.monospacedDigit())
                compactMetrics
                if !showsDisclosure {
                    DisclosureGroup("auto.additional".tempoLocalized) { metrics.padding(.top, 12) }.font(.subheadline)
                }
                if record.automaticEffort != nil, record.payload?.loadInputs.sessionRPE == record.automaticEffort {
                    Label((record.effortIsEstimated ? "auto.effortEstimated" : "auto.effortReported").tempoLocalized, systemImage: "heart.text.square").font(.caption).foregroundStyle(TempoTheme.secondary)
                }
                if record.userEdited { Label("archetype.userEntered".tempoLocalized, systemImage: "pencil").font(.caption).foregroundStyle(TempoTheme.orange) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    @ViewBuilder private var compactMetrics: some View {
        TempoMetricGrid(columns: 2) {
            if let effort = record.payload?.loadInputs.sessionRPE { metric("strain.sessionRPE", number(effort, unit: "/10")) }
            if let heart = record.averageHeartRateBpm { metric("auto.averageHeart", number(heart, unit: "bpm")) }
            if let peak = record.peakHeartRateBpm { metric("auto.peakHeart", number(peak, unit: "bpm")) }
            if case .endurance(let value) = record.payload {
                if let distance = value.distanceMeters { metric("Mesafe", value.discipline == .swimming ? number(distance, unit: "m") : number(distance / 1_000, unit: "km")) }
                if let power = value.averagePowerWatts { metric("archetype.power", number(power, unit: "W")) }
                if let cadence = value.cadencePerMinute { metric("archetype.cadence", number(cadence)) }
                if value.discipline == .running || value.discipline == .walking, let pace = value.paceSecondsPerKm { metric("archetype.pace", TempoFormat.duration(pace) + " /km") }
                if value.discipline == .cycling, let speed = value.speedKmh { metric("archetype.speed", number(speed, unit: "km/h")) }
            }
            if case .strength(let value) = record.payload, !value.sets.isEmpty {
                metric("archetype.setsReps", "\(value.sets.count) / \(value.sets.reduce(0) { $0 + ($1.repetitions ?? 0) })")
                if let tonnage = value.tonnageKg { metric("archetype.tonnage", number(tonnage, unit: "kg")) }
            }
            if case .teamCourt(let value) = record.payload, let energy = value.activeEnergyKcal { metric("Aktif enerji", number(energy, unit: "kcal")) }
        }
    }
    @ViewBuilder private var metrics: some View {
        switch record.payload {
        case .strength(let value):
            TempoMetricGrid(columns: 2) {
                metric("archetype.tonnage", number(value.tonnageKg, unit: "kg"))
                metric("archetype.setsReps", value.sets.isEmpty ? "—" : "\(value.sets.count) / \(value.sets.reduce(0) { $0 + ($1.repetitions ?? 0) })")
                metric("archetype.effective", number(value.effectiveRepsEstimate))
                metric("archetype.averageRPE", number(value.averageRPE))
                metric("archetype.averageRIR", number(value.averageRIR))
                metric("archetype.rest", value.averageRestSeconds.map(TempoFormat.duration) ?? "—")
            }
            ForEach(value.regionalWorkload) { group in
                Text("archetype.muscleSummary".tempoFormatted(("archetype.muscle." + group.muscle.rawValue).tempoLocalized, group.sets, group.repetitions, group.highEffortSets)).font(.caption).foregroundStyle(TempoTheme.secondary)
            }
            Text("archetype.strengthNote".tempoLocalized).font(.caption2).foregroundStyle(TempoTheme.secondary)
        case .endurance(let value):
            TempoMetricGrid(columns: 2) {
                metric("Mesafe", [.swimming, .rowing].contains(value.discipline) ? number(value.distanceMeters, unit: "m") : number(value.distanceMeters.map { $0 / 1_000 }, unit: "km"))
                if value.discipline == .swimming {
                    metric("archetype.pace", value.paceSecondsPerKm.map { TempoFormat.duration($0 / 10) + " /100m" } ?? "—")
                    metric("SWOLF", number(value.averageSWOLF))
                } else if value.discipline == .rowing {
                    metric("archetype.pace", value.paceSecondsPerKm.map { TempoFormat.duration($0 / 2) + " /500m" } ?? "—")
                } else if value.discipline != .cycling { metric("archetype.pace", value.paceSecondsPerKm.map { TempoFormat.duration($0) + " /km" } ?? "—") }
                if value.discipline != .swimming { metric("archetype.speed", number(value.speedKmh, unit: "km/h")) }
                metric("archetype.cadence", number(value.cadencePerMinute))
                if [.cycling, .rowing, .other].contains(value.discipline) { metric("archetype.power", number(value.averagePowerWatts, unit: "W")) }
                if value.discipline == .running { metric("GAP", value.gradeAdjustedPaceSecondsPerKm.map { TempoFormat.duration($0) + " /km" } ?? "—") }
                metric("archetype.threshold", number(value.aerobicThresholdBpm, unit: "bpm"))
            }
            Text("archetype.enduranceNote".tempoLocalized).font(.caption2).foregroundStyle(TempoTheme.secondary)
        case .teamCourt(let value):
            TempoMetricGrid(columns: 2) {
                metric("archetype.sprints", value.sprintCount.map { $0.formatted() } ?? "—")
                metric("Aktif enerji", number(value.activeEnergyKcal, unit: "kcal"))
                metric("archetype.explosive", number(value.zones?.explosiveSharePercent, unit: "%"))
                metric("archetype.recovery", number(value.recovery?.dropBpm, unit: "bpm"))
            }
            if let zones = value.zones, zones.isValid {
                ForEach(0..<5, id: \.self) { index in
                    HStack { Text("Z\(index + 1)"); ProgressView(value: zones.totalSeconds > 0 ? (zones.seconds[index] ?? 0) / zones.totalSeconds : 0).tint(TempoTheme.green); Text(TempoFormat.duration(zones.seconds[index] ?? 0)) }.font(.caption)
                }
            }
        case .combatMindBody(let value):
            TempoMetricGrid(columns: 2) {
                if !value.rounds.isEmpty {
                    metric("archetype.rounds", value.rounds.count.formatted())
                    metric("archetype.roundTime", TempoFormat.duration(value.rounds.reduce(0) { $0 + ($1.seconds ?? 0) }))
                }
                metric("archetype.recovery", number(value.averageRecoveryBpm, unit: "bpm"))
                metric("archetype.hrvChange", number(value.hrvChangeMs, unit: "ms"))
            }
            Text("archetype.recoveryNote".tempoLocalized).font(.caption2).foregroundStyle(TempoTheme.secondary)
        case nil:
            Text("archetype.unmappedNote".tempoLocalized).font(.subheadline).foregroundStyle(TempoTheme.secondary)
        }
    }
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit()).fixedSize(horizontal: false, vertical: true)
            Text(label.tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(TempoTheme.raised, in: RoundedRectangle(cornerRadius: 14))
    }
}

@MainActor
struct PolymorphicWorkoutLibraryScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    @EnvironmentObject private var account: TempoAccountStore
    @StateObject private var store = SportMetricsStore()
    @State private var selected: SportArchetype?
    private var local: [ArchetypeWorkoutRecord] { model.activityWorkouts.map { store.applying(to: WorkoutPayloadAdapter.record($0)) }.filter { selected == nil || $0.payload?.archetype == selected }.sorted { $0.date > $1.date } }
    private var strava: [ArchetypeWorkoutRecord] { (model.dashboard?.activities ?? []).compactMap { WorkoutPayloadAdapter.record($0) }.filter { selected == nil || $0.payload?.archetype == selected }.sorted { $0.date > $1.date } }
    var body: some View {
        TempoPage {
            PageTitle(title: "archetype.library", subtitle: "archetype.librarySubtitle")
            TempoCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("auto.title".tempoLocalized, systemImage: "heart.text.square").font(.headline)
                    Text("auto.explanation".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
                    if model.isHealthSyncing { ProgressView("auto.reading".tempoLocalized).font(.caption) }
                    DisclosureGroup("auto.permissions".tempoLocalized) {
                        Button { model.connectAppleHealth() } label: { Label("auto.healthAccess".tempoLocalized, systemImage: "heart.fill").frame(maxWidth: .infinity) }
                            .buttonStyle(TempoSecondaryButtonStyle()).disabled(model.isHealthSyncing).padding(.top, 10)
                        Text("auto.limits".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
                    }.font(.subheadline)
                }
            }
            Picker("archetype.group".tempoLocalized, selection: $selected) {
                Text("Tümü".tempoLocalized).tag(Optional<SportArchetype>.none)
                ForEach(SportArchetype.allCases) { Text($0.title).tag(Optional($0)) }
            }.pickerStyle(.menu).tint(TempoTheme.green)
            if let error = store.error { Text(error).font(.footnote).foregroundStyle(TempoTheme.orange) }
            if let error = model.healthWorkoutError ?? model.healthError { Text(error.tempoLocalized).font(.footnote).foregroundStyle(TempoTheme.orange) }
            Text("Tempo + Apple Sağlık".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
            if local.isEmpty { EmptyCard(icon: "figure.mixed.cardio", text: "archetype.empty") }
            ForEach(local.prefix(60)) { record in
                NavigationLink(destination: PolymorphicWorkoutDetailScreen(record: record, store: store)) { PolymorphicWorkoutCardView(record: record, showsDisclosure: true) }.buttonStyle(.plain)
            }
            if !strava.isEmpty {
                TempoDisclosureSection(title: "Strava", icon: "link") {
                    VStack(spacing: 12) {
                        ForEach(strava.prefix(60)) { record in PolymorphicWorkoutCardView(record: record) }
                        Text("archetype.stravaNote".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
                    }
                }
            }
            Text("archetype.libraryNote".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
        }.navigationTitle("archetype.library".tempoLocalized).navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
            .task(id: account.profile?.id) { store.bind(account.profile?.id); if model.healthSyncEnabled { await model.syncAppleHealth() } }
            .onAppear { store.reload() }
    }
}

@MainActor
struct SportArchetypeSection: View {
    let workout: TempoManualWorkout
    @EnvironmentObject private var account: TempoAccountStore
    @StateObject private var store = SportMetricsStore()
    private var record: ArchetypeWorkoutRecord { store.applying(to: WorkoutPayloadAdapter.record(workout)) }
    var body: some View {
        NavigationLink(destination: PolymorphicWorkoutDetailScreen(record: record, store: store)) { PolymorphicWorkoutCardView(record: record, showsDisclosure: true) }
            .buttonStyle(.plain).task(id: account.profile?.id) { store.bind(account.profile?.id) }
    }
}

@MainActor
struct PolymorphicWorkoutDetailScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    let record: ArchetypeWorkoutRecord
    @ObservedObject var store: SportMetricsStore
    @State private var editing = false
    private var current: ArchetypeWorkoutRecord { store.applying(to: record) }
    var body: some View {
        TempoPage {
            PolymorphicWorkoutCardView(record: current)
            if record.source != .strava {
                WorkoutStrainPreview(record: current, history: model.activityWorkouts.map { store.applying(to: WorkoutPayloadAdapter.record($0)) })
            }
            if record.payload != nil, record.source != .strava {
                Button { editing = true } label: { Label("archetype.edit".tempoLocalized, systemImage: "slider.horizontal.3").frame(maxWidth: .infinity) }
                    .buttonStyle(TempoPrimaryButtonStyle()).disabled(store.owner == nil || store.error != nil)
            }
            Text("archetype.editNote".tempoLocalized).font(.footnote).foregroundStyle(TempoTheme.secondary)
        }.navigationTitle("archetype.details".tempoLocalized).navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
            .sheet(isPresented: $editing) {
                if let payload = current.payload { WorkoutMetricsEditor(record: record, initial: payload, store: store) }
            }
    }
}

@MainActor
private final class MetricTextDraft: ObservableObject {
    @Published var values: [String: String] = [:]
}

@MainActor
private struct WorkoutMetricsEditor: View {
    @State private var showsAdditionalMetrics = false
    let record: ArchetypeWorkoutRecord
    @ObservedObject var store: SportMetricsStore
    @Environment(\.dismiss) private var dismiss
    @State private var payload: WorkoutPayload
    @State private var invalidFields: Set<String> = []
    @State private var error = ""
    @StateObject private var draft = MetricTextDraft()
    private let owner: String
    init(record: ArchetypeWorkoutRecord, initial: WorkoutPayload, store: SportMetricsStore) {
        self.record = record; self.store = store; _payload = State(initialValue: initial); owner = store.owner ?? ""
    }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("archetype.editNote".tempoLocalized).font(.footnote) }
                WorkoutLoadInputEditor(payload: $payload, invalid: $invalidFields)
                Section {
                    DisclosureGroup("auto.additional".tempoLocalized, isExpanded: $showsAdditionalMetrics) {
                        Text("auto.editHelp".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
                    }
                }
                if showsAdditionalMetrics { fields }
                if !error.isEmpty { Section { Text(error).foregroundStyle(TempoTheme.orange) } }
            }.environmentObject(draft).scrollContentBackground(.hidden).background(TempoTheme.background)
                .navigationTitle("archetype.edit".tempoLocalized).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Kaydet") {
                            do { try store.save(payload, for: record, owner: owner); dismiss() }
                            catch { self.error = error.localizedDescription.tempoLocalized }
                        }.disabled(!invalidFields.isEmpty || store.owner != owner)
                    }
                }
                .onChange(of: store.owner) { _, value in if value != owner { dismiss() } }
        }
    }
    @ViewBuilder private var fields: some View {
        switch payload {
        case .strength:
            StrengthMetricsEditor(value: Binding(get: { if case .strength(let v) = payload { return v }; return StrengthMetrics() }, set: { payload = .strength($0) }), invalid: $invalidFields)
        case .endurance:
            EnduranceMetricsEditor(value: Binding(get: { if case .endurance(let v) = payload { return v }; return EnduranceMetrics() }, set: { payload = .endurance($0) }), invalid: $invalidFields)
        case .teamCourt:
            TeamMetricsEditor(value: Binding(get: { if case .teamCourt(let v) = payload { return v }; return TeamCourtMetrics() }, set: { payload = .teamCourt($0) }), invalid: $invalidFields)
        case .combatMindBody:
            CombatMetricsEditor(value: Binding(get: { if case .combatMindBody(let v) = payload { return v }; return CombatMindBodyMetrics() }, set: { payload = .combatMindBody($0) }), invalid: $invalidFields)
        }
    }
}

@MainActor
private struct WorkoutLoadInputEditor: View {
    @Binding var payload: WorkoutPayload
    @Binding var invalid: Set<String>
    @EnvironmentObject private var draft: MetricTextDraft
    private var rpe: Binding<Double?> { Binding(get: { payload.loadInputs.sessionRPE }, set: { var input = payload.loadInputs; input.sessionRPE = $0; payload.loadInputs = input }) }
    private var explosive: Binding<Double?> { Binding(get: { payload.loadInputs.explosiveSeconds }, set: { var input = payload.loadInputs; input.explosiveSeconds = $0; payload.loadInputs = input }) }
    var body: some View {
        Section("strain.inputs".tempoLocalized) {
            MetricNumberField(title: "strain.sessionRPE", id: "sessionRPE", value: rpe, invalid: $invalid)
            Text("strain.rpeHelp".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
            MetricNumberField(title: "strain.explosiveSeconds", id: "explosiveSeconds", value: explosive, invalid: $invalid)
            Group {
                DisclosureGroup("archetype.zones".tempoLocalized) {
                    if payload.heartRateZones != nil {
                        ForEach(0..<5, id: \.self) { i in
                            MetricNumberField(title: "archetype.zoneSeconds".tempoFormatted(i + 1), id: "loadzone\(i)", value: Binding(get: { guard let zones = payload.heartRateZones, zones.seconds.indices.contains(i) else { return nil }; return zones.seconds[i] }, set: { var zones = payload.heartRateZones; if zones?.seconds.count == 5 { zones?.seconds[i] = $0 }; payload.heartRateZones = zones }), invalid: $invalid, required: true)
                        }
                        Button("archetype.clearZones".tempoLocalized) {
                            for i in 0..<5 { invalid.remove("loadzone\(i)"); draft.values.removeValue(forKey: "loadzone\(i)") }
                            payload.heartRateZones = nil
                        }
                    } else { Button("archetype.addZones".tempoLocalized) { payload.heartRateZones = HeartRateZones(seconds: [nil, nil, nil, nil, nil]) } }
                }
            }
            Text("strain.inputHelp".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
        }
    }
}

@MainActor
private struct MetricNumberField: View {
    let title: String
    let id: String
    @Binding var value: Double?
    @Binding var invalid: Set<String>
    var required = false
    @EnvironmentObject private var draft: MetricTextDraft
    private var text: Binding<String> {
        Binding(get: { draft.values[id] ?? value.map { String($0) } ?? "" }, set: { let input = String($0.prefix(48)); draft.values[id] = input; validate(input) })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
            TextField("—", text: text).keyboardType(.decimalPad)
                .accessibilityLabel(title.tempoLocalized)
            if invalid.contains(id) { Text("archetype.numberError".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.orange) }
        }.onAppear { validate(text.wrappedValue) }
    }
    private func validate(_ raw: String) {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        if input.isEmpty, !required { if value != nil { value = nil }; invalid.remove(id) }
        else if let parsed = Double(input), parsed.isFinite { if value != parsed { value = parsed }; invalid.remove(id) }
        else { invalid.insert(id) }
    }
}

@MainActor
private struct MetricIntegerField: View {
    let title: String
    let id: String
    @Binding var value: Int?
    @Binding var invalid: Set<String>
    let range: ClosedRange<Int>
    var required = false
    @EnvironmentObject private var draft: MetricTextDraft
    private var text: Binding<String> {
        Binding(get: { draft.values[id] ?? value.map { String($0) } ?? "" }, set: { let raw = String($0.prefix(24)); draft.values[id] = raw; validate(raw) })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
            TextField("—", text: text).keyboardType(.numberPad).accessibilityLabel(title.tempoLocalized)
            if invalid.contains(id) { Text("archetype.integerError".tempoFormatted(range.lowerBound, range.upperBound)).font(.caption).foregroundStyle(TempoTheme.orange) }
        }.onAppear { validate(text.wrappedValue) }
    }
    private func validate(_ raw: String) {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.isEmpty, !required { if value != nil { value = nil }; invalid.remove(id) }
        else if let parsed = Int(input), range.contains(parsed) { if value != parsed { value = parsed }; invalid.remove(id) }
        else { invalid.insert(id) }
    }
}

@MainActor
private struct StrengthMetricsEditor: View {
    @Binding var value: StrengthMetrics
    @Binding var invalid: Set<String>
    @State private var expanded: UUID?
    var body: some View {
        Section("archetype.sets".tempoLocalized) {
            ForEach($value.sets) { $set in
                DisclosureGroup("archetype.setTitle".tempoFormatted(("archetype.muscle." + set.muscle.rawValue).tempoLocalized, set.repetitions.map { $0.formatted() } ?? "—"), isExpanded: Binding(get: { expanded == set.id }, set: { expanded = $0 ? set.id : nil })) {
                    Picker("archetype.muscle".tempoLocalized, selection: $set.muscle) { ForEach(MuscleGroup.allCases) { Text(("archetype.muscle." + $0.rawValue).tempoLocalized).tag($0) } }
                    MetricIntegerField(title: "archetype.repetitions", id: set.id.uuidString + "reps", value: $set.repetitions, invalid: $invalid, range: 1...500, required: true)
                    MetricNumberField(title: "archetype.load", id: set.id.uuidString + "load", value: $set.loadKg, invalid: $invalid)
                    MetricNumberField(title: "archetype.rpe", id: set.id.uuidString + "rpe", value: $set.rpe, invalid: $invalid)
                    MetricNumberField(title: "archetype.rir", id: set.id.uuidString + "rir", value: $set.rir, invalid: $invalid)
                    MetricNumberField(title: "archetype.rest", id: set.id.uuidString + "rest", value: $set.restSeconds, invalid: $invalid)
                    Button("archetype.remove".tempoLocalized, role: .destructive) { let removedID = set.id; invalid = Set(invalid.filter { !$0.hasPrefix(removedID.uuidString) }); value.sets.removeAll { $0.id == removedID } }
                }
            }
            Button("archetype.addSet".tempoLocalized) { let set = StrengthSet(); value.sets.append(set); expanded = set.id }.disabled(value.sets.count >= 100)
        }
    }
}

@MainActor
private struct EnduranceMetricsEditor: View {
    @Binding var value: EnduranceMetrics
    @Binding var invalid: Set<String>
    @State private var expanded: UUID?
    var body: some View {
        Section("archetype.measurements".tempoLocalized) {
            MetricNumberField(title: "archetype.distanceMeters", id: "distance", value: $value.distanceMeters, invalid: $invalid)
            MetricNumberField(title: "archetype.seconds", id: "seconds", value: $value.movingSeconds, invalid: $invalid)
            MetricNumberField(title: "archetype.cadence", id: "cadence", value: $value.cadencePerMinute, invalid: $invalid)
            if [.cycling, .rowing, .other].contains(value.discipline) { MetricNumberField(title: "archetype.watts", id: "watts", value: $value.averagePowerWatts, invalid: $invalid) }
            if value.discipline == .running { MetricNumberField(title: "archetype.gapInput", id: "gap", value: $value.gradeAdjustedPaceSecondsPerKm, invalid: $invalid) }
            MetricNumberField(title: "archetype.threshold", id: "threshold", value: $value.aerobicThresholdBpm, invalid: $invalid)
        }
        if value.discipline == .swimming { Section("archetype.swimLaps".tempoLocalized) {
            ForEach($value.laps) { $lap in
                DisclosureGroup("archetype.lap".tempoLocalized, isExpanded: Binding(get: { expanded == lap.id }, set: { expanded = $0 ? lap.id : nil })) {
                    MetricNumberField(title: "archetype.seconds", id: lap.id.uuidString + "time", value: $lap.seconds, invalid: $invalid, required: true)
                    MetricNumberField(title: "archetype.poolLength", id: lap.id.uuidString + "length", value: $lap.lengthMeters, invalid: $invalid, required: true)
                    MetricIntegerField(title: "archetype.strokes", id: lap.id.uuidString + "strokes", value: $lap.strokes, invalid: $invalid, range: 1...500, required: true)
                    Button("archetype.remove".tempoLocalized, role: .destructive) { let removedID = lap.id; invalid = Set(invalid.filter { !$0.hasPrefix(removedID.uuidString) }); value.laps.removeAll { $0.id == removedID } }
                }
            }
            Button("archetype.addLap".tempoLocalized) { let lap = SwimLap(); value.laps.append(lap); expanded = lap.id }.disabled(value.laps.count >= 100)
            Text("archetype.swimNote".tempoLocalized).font(.caption)
        } }
    }
}

@MainActor
private struct TeamMetricsEditor: View {
    @Binding var value: TeamCourtMetrics
    @Binding var invalid: Set<String>
    @EnvironmentObject private var draft: MetricTextDraft
    var body: some View {
        Section("archetype.measurements".tempoLocalized) {
            MetricNumberField(title: "archetype.caloriesInput", id: "calories", value: $value.activeEnergyKcal, invalid: $invalid)
            MetricIntegerField(title: "archetype.sprints", id: "sprints", value: $value.sprintCount, invalid: $invalid, range: 0...10_000)
            if value.sprintCount != nil { Button("archetype.clearSprints".tempoLocalized) { draft.values.removeValue(forKey: "sprints"); invalid.remove("sprints"); value.sprintCount = nil } }
        }
        Section("archetype.recovery".tempoLocalized) {
            RecoveryMetricsEditor(value: $value.recovery, id: "team", invalid: $invalid)
        }
    }
}

@MainActor
private struct CombatMetricsEditor: View {
    @Binding var value: CombatMindBodyMetrics
    @Binding var invalid: Set<String>
    @State private var expanded: UUID?
    var body: some View {
        Section("archetype.hrv".tempoLocalized) {
            MetricNumberField(title: "archetype.hrvBefore", id: "hrvBefore", value: $value.hrvBeforeMs, invalid: $invalid)
            MetricNumberField(title: "archetype.hrvAfter", id: "hrvAfter", value: $value.hrvAfterMs, invalid: $invalid)
        }
        Section("archetype.rounds".tempoLocalized) {
            ForEach($value.rounds) { $round in
                DisclosureGroup("archetype.round".tempoLocalized, isExpanded: Binding(get: { expanded == round.id }, set: { expanded = $0 ? round.id : nil })) {
                    MetricNumberField(title: "archetype.seconds", id: round.id.uuidString + "duration", value: $round.seconds, invalid: $invalid, required: true)
                    RecoveryMetricsEditor(value: $round.recovery, id: round.id.uuidString, invalid: $invalid)
                    Button("archetype.remove".tempoLocalized, role: .destructive) { let removedID = round.id; invalid = Set(invalid.filter { !$0.hasPrefix(removedID.uuidString) }); value.rounds.removeAll { $0.id == removedID } }
                }
            }
            Button("archetype.addRound".tempoLocalized) { let round = CombatRound(); value.rounds.append(round); expanded = round.id }.disabled(value.rounds.count >= 100)
        }
    }
}

@MainActor
private struct RecoveryMetricsEditor: View {
    @Binding var value: OneMinuteRecovery?
    let id: String
    @Binding var invalid: Set<String>
    @EnvironmentObject private var draft: MetricTextDraft
    var body: some View {
        if value != nil {
            MetricNumberField(title: "archetype.hrStart", id: id + "start", value: Binding(get: { value?.startBpm }, set: { if let v = $0 { value?.startBpm = v } }), invalid: $invalid, required: true)
            MetricNumberField(title: "archetype.hrEnd", id: id + "end", value: Binding(get: { value?.afterOneMinuteBpm }, set: { if let v = $0 { value?.afterOneMinuteBpm = v } }), invalid: $invalid, required: true)
            Button("archetype.clearRecovery".tempoLocalized) { invalid.remove(id + "start"); invalid.remove(id + "end"); draft.values.removeValue(forKey: id + "start"); draft.values.removeValue(forKey: id + "end"); value = nil }
        } else { Button("archetype.addRecovery".tempoLocalized) { value = OneMinuteRecovery() } }
    }
}

