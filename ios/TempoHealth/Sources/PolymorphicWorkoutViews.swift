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
    var automaticZones: [Double]?
    var zoneEvidence: HeartRateZoneEvidence?
    var sourceEndedAt: Date?
    var endedAt: Date { sourceEndedAt ?? date.addingTimeInterval(durationSeconds) }
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
        if let seconds = workout.sourceHeartRateZones, HeartRateZones(seconds: seconds.map(Optional.some)).isValid, var value = payload {
            value.heartRateZones = HeartRateZones(seconds: seconds.map(Optional.some)); payload = value
        }
        // Mevcut 1–5 zorluk notu, farklı bir ölçek olan RPE 1–10'a dönüştürülmez.
        return ArchetypeWorkoutRecord(id: "local-" + workout.id.uuidString, title: workout.title, date: workout.startedAt, durationSeconds: duration, source: workout.recordSource == "apple-health" ? .health : .tempo, sourceLabel: workout.sourceTitle, payload: payload, isMindBody: workout.sportId == "yoga" || SportMapper.isMindBody(healthKitRawValue: workout.originalHealthActivityType), sportID: workout.sportId, hasLowerBodyImpact: ["football", "basketball", "tennis", "volleyball", "padel", "badminton"].contains(workout.sportId) || SportMapper.hasLowerBodyImpact(healthKitRawValue: workout.originalHealthActivityType), averageHeartRateBpm: workout.sourceAverageHeartRateBpm, peakHeartRateBpm: workout.sourcePeakHeartRateBpm, automaticEffort: workout.sourceWorkoutEffort, effortIsEstimated: workout.sourceEffortIsEstimated == true, automaticZones: workout.sourceHeartRateZones, zoneEvidence: workout.sourceHeartRateZoneEvidence, sourceEndedAt: workout.sourceEndedAt)
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
    static let didChange = Notification.Name("TempoWorkoutMetricsDidChange")
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
    static func removeData(for owner: String) { UserDefaultsWorkoutMetricsRepository().remove(for: owner); StrengthPresetStore.removeData(for: owner) }
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
        NotificationCenter.default.post(name: Self.didChange, object: owner)
    }
}

@MainActor
final class StrengthPresetStore: ObservableObject {
    @Published private(set) var presets: [StrengthWorkoutPreset] = []
    @Published private(set) var error: String?
    private var owner: String?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private static func key(_ owner: String) -> String { "tempo.strength-presets.v1." + owner }
    func bind(_ owner: String?) {
        self.owner = owner; presets = []; error = nil
        guard let owner, !owner.isEmpty, let data = defaults.data(forKey: Self.key(owner)) else { return }
        do {
            guard data.count <= 2_000_000 else { throw CocoaError(.coderReadCorrupt) }
            let decoded = try JSONDecoder().decode([StrengthWorkoutPreset].self, from: data)
            guard decoded.count <= 50, decoded.allSatisfy(\.isValid), Set(decoded.map(\.id)).count == decoded.count else { throw CocoaError(.coderReadCorrupt) }
            presets = decoded
        } catch { self.error = "preset.storageError".tempoLocalized }
    }
    func save(name: String, sportID: String, sets: [StrengthSet], owner expected: String) throws -> UUID {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = StrengthWorkoutPreset(sportID: sportID, name: name, sets: sets)
        guard owner == expected, !expected.isEmpty, error == nil, preset.isValid, presets.count < 50 else { throw NSError(domain: "TempoPreset", code: 2, userInfo: [NSLocalizedDescriptionKey: "preset.saveError".tempoLocalized]) }
        guard !presets.contains(where: { $0.sportID == sportID && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else {
            throw NSError(domain: "TempoPreset", code: 1, userInfo: [NSLocalizedDescriptionKey: "preset.duplicate".tempoLocalized])
        }
        var next = presets; next.append(preset); try persist(next, owner: expected); return preset.id
    }
    func remove(_ id: UUID, owner expected: String) throws {
        guard owner == expected, !expected.isEmpty, error == nil else { throw CocoaError(.fileWriteNoPermission) }
        try persist(presets.filter { $0.id != id }, owner: expected)
    }
    private func persist(_ next: [StrengthWorkoutPreset], owner: String) throws {
        let data = try JSONEncoder().encode(next)
        guard data.count <= 2_000_000 else { throw CocoaError(.fileWriteOutOfSpace) }
        defaults.set(data, forKey: Self.key(owner)); presets = next
    }
    static func removeData(for owner: String) { UserDefaults.standard.removeObject(forKey: key(owner)) }
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
                NavigationLink(destination: PolymorphicWorkoutDetailScreen(record: record, store: store)) { PolymorphicWorkoutCardView(record: record, showsDisclosure: true) }.buttonStyle(TempoSoftPressStyle())
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
    var compact = false
    @EnvironmentObject private var account: TempoAccountStore
    @StateObject private var store = SportMetricsStore()
    private var record: ArchetypeWorkoutRecord { store.applying(to: WorkoutPayloadAdapter.record(workout)) }
    var body: some View {
        NavigationLink(destination: PolymorphicWorkoutDetailScreen(record: record, store: store)
            .task(id: account.profile?.id) { store.bind(account.profile?.id) }
            .onAppear { store.reload() }) {
            if compact {
                Label("archetype.details".tempoLocalized, systemImage: "chart.bar.xaxis")
                    .font(.caption.weight(.semibold)).foregroundStyle(TempoTheme.blue)
                    .frame(minHeight: 44).fixedSize(horizontal: false, vertical: true)
            } else { PolymorphicWorkoutCardView(record: record, showsDisclosure: true) }
        }
            .buttonStyle(TempoSoftPressStyle()).task(id: account.profile?.id) { if !compact { store.bind(account.profile?.id) } }
            .onAppear { if !compact { store.reload() } }
    }
}

@MainActor
struct PolymorphicWorkoutDetailScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    let record: ArchetypeWorkoutRecord
    @ObservedObject var store: SportMetricsStore
    private var sourceRecord: ArchetypeWorkoutRecord {
        guard record.source != .strava, let live = model.activityWorkouts.first(where: { "local-" + $0.id.uuidString == record.id }) else { return record }
        return WorkoutPayloadAdapter.record(live)
    }
    private var current: ArchetypeWorkoutRecord { store.applying(to: sourceRecord) }
    var body: some View {
        TempoPage {
            PolymorphicWorkoutCardView(record: current)
            if record.source != .strava {
                WorkoutStrainPreview(record: current, history: model.activityWorkouts.map { store.applying(to: WorkoutPayloadAdapter.record($0)) })
                if current.payload?.heartRateZones != nil { HeartRateZonesCard(record: current) }
            }
            Text("detection.automaticMetrics".tempoLocalized).font(.footnote).foregroundStyle(TempoTheme.secondary)
        }.navigationTitle("archetype.details".tempoLocalized).navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
            .task(id: record.id) {
                if record.source == .health, let id = UUID(uuidString: String(record.id.dropFirst(6))) { await model.ensureWorkoutHeartRateZones(workoutID: id) }
            }
    }
}

