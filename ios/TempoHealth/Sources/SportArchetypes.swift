import Foundation
#if canImport(HealthKit) && !STRAIN_CORE_TESTS
import HealthKit
#endif

enum SportArchetype: String, Codable, CaseIterable, Sendable, Identifiable {
    case strengthAndHypertrophy, endurance, teamAndCourt, combatAndMindBody
    var id: String { rawValue }
}

#if canImport(HealthKit) && !STRAIN_CORE_TESTS
protocol SportMappingProtocol: Sendable {
    func map(healthKit type: HKWorkoutActivityType) -> SportArchetype?
    func map(stravaType: String) -> SportArchetype?
}

struct SportMapper: SportMappingProtocol, Sendable {
    static func hasLowerBodyImpact(healthKitRawValue value: UInt?) -> Bool {
        guard let value else { return false }
        return [HKWorkoutActivityType.soccer, .basketball, .tennis, .volleyball, .badminton, .squash, .rugby, .handball, .pickleball].contains { $0.rawValue == value }
    }
    static func isMindBody(healthKitRawValue value: UInt?) -> Bool {
        guard let value else { return false }
        return [HKWorkoutActivityType.yoga, .pilates, .barre, .taiChi, .mindAndBody, .flexibility, .preparationAndRecovery, .cooldown, .danceInspiredTraining].contains { $0.rawValue == value }
    }
    func map(healthKit type: HKWorkoutActivityType) -> SportArchetype? {
        switch type {
        case .traditionalStrengthTraining, .functionalStrengthTraining, .crossTraining, .gymnastics, .coreTraining, .highIntensityIntervalTraining, .climbing:
            return .strengthAndHypertrophy
        case .americanFootball, .australianFootball, .badminton, .baseball, .basketball, .cricket, .curling, .golf, .handball, .hockey, .lacrosse, .racquetball, .rugby, .soccer, .softball, .squash, .tableTennis, .tennis, .volleyball, .waterPolo, .discSports, .pickleball, .archery, .bowling:
            return .teamAndCourt
        case .boxing, .fencing, .martialArts, .mindAndBody, .preparationAndRecovery, .wrestling, .yoga, .barre, .flexibility, .kickboxing, .pilates, .taiChi, .cooldown, .danceInspiredTraining:
            return .combatAndMindBody
        case .cycling, .running, .walking, .swimming, .rowing, .hiking, .elliptical, .paddleSports, .sailing, .skatingSports, .snowSports, .stairClimbing, .surfingSports, .waterFitness, .waterSports, .crossCountrySkiing, .downhillSkiing, .jumpRope, .snowboarding, .stairs, .stepTraining, .wheelchairWalkPace, .wheelchairRunPace, .handCycling, .mixedCardio, .mixedMetabolicCardioTraining, .dance, .cardioDance, .socialDance, .swimBikeRun, .underwaterDiving, .equestrianSports, .fishing, .hunting, .play, .fitnessGaming, .trackAndField:
            return .endurance
        default:
            // Tanınmayan/yeni branşlar yanlış bir fizyolojik gruba zorlanmaz.
            return nil
        }
    }

    func map(stravaType: String) -> SportArchetype? {
        let key = Self.normalized(stravaType)
        if ["fitness", "weighttraining", "powerlifting", "calisthenics", "kalistenik", "crossfit", "strengthtraining", "highintensityintervaltraining", "hiit", "rockclimbing"].contains(key) { return .strengthAndHypertrophy }
        if ["tennis", "tabletennis", "basketball", "football", "soccer", "volleyball", "padel", "badminton", "pickleball", "racquetball", "squash", "cricket", "golf", "baseball", "rugby", "hockey", "handball"].contains(key) { return .teamAndCourt }
        if ["boxing", "boks", "mma", "wrestling", "gures", "martialarts", "kickboxing", "yoga", "pilates", "taichi", "physicaltherapy", "mobility", "stretching"].contains(key) { return .combatAndMindBody }
        if ["run", "running", "trailrun", "virtualrun", "kosu", "cycling", "ride", "virtualride", "mountainbikeride", "gravelride", "ebikeride", "emountainbikeride", "swim", "swimming", "rowing", "virtualrow", "walk", "walking", "hike", "hiking", "canoeing", "kayaking", "standuppaddling", "surfing", "windsurf", "kitesurf", "sail", "alpineski", "backcountryski", "nordicski", "rollerski", "snowboard", "snowshoe", "iceskate", "inlineskate", "skateboard", "elliptical", "stairstepper", "velomobile", "handcycle", "wheelchair", "dance"].contains(key) { return .endurance }
        return nil
    }
    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
#endif

struct WorkoutLoadInputs: Codable, Sendable {
    var sessionRPE: Double?
    var zones: HeartRateZones?
    var explosiveSeconds: Double?
    var isValid: Bool { valid(sessionRPE, in: 1...10) && (zones?.isValid ?? true) && valid(explosiveSeconds, in: 0...604_800) }
    var isEmpty: Bool { sessionRPE == nil && zones == nil && explosiveSeconds == nil }
}

protocol WorkoutMetricsProtocol: Codable, Sendable {
    var archetype: SportArchetype { get }
    var isValid: Bool { get }
}

enum MuscleGroup: String, Codable, CaseIterable, Identifiable, Sendable {
    case unspecified, legs, chest, back, shoulders, arms, core, fullBody
    var id: String { rawValue }
}

struct StrengthSet: Codable, Sendable, Identifiable {
    var id = UUID()
    var muscle: MuscleGroup = .unspecified
    var repetitions: Int?
    var loadKg: Double?
    var rpe: Double?
    var rir: Double?
    var restSeconds: Double?
    var isValid: Bool {
        guard let repetitions else { return false }
        return (1...500).contains(repetitions) && valid(loadKg, in: 0...2_000) && valid(rpe, in: 1...10) && valid(rir, in: 0...20) && valid(restSeconds, in: 0...3_600)
    }
    var effectiveRepsEstimate: Double? {
        guard let repetitions, let remaining = rir ?? rpe.map({ max(0, 10 - $0) }) else { return nil }
        return min(Double(repetitions), max(0, 5 - remaining))
    }
}

struct MuscleWorkload: Sendable, Identifiable {
    let muscle: MuscleGroup
    let sets: Int
    let repetitions: Int
    let highEffortSets: Int
    var id: MuscleGroup { muscle }
}

struct StrengthMetrics: WorkoutMetricsProtocol {
    var loadInputs: WorkoutLoadInputs?
    var sets: [StrengthSet] = []
    var archetype: SportArchetype { .strengthAndHypertrophy }
    var isValid: Bool { sets.count <= 100 && sets.allSatisfy(\.isValid) && (loadInputs?.isValid ?? true) }
    var tonnageKg: Double? {
        guard !sets.isEmpty, sets.allSatisfy({ $0.loadKg != nil && $0.repetitions != nil }) else { return nil }
        return sets.reduce(0) { $0 + Double($1.repetitions ?? 0) * ($1.loadKg ?? 0) }
    }
    var effectiveRepsEstimate: Double? {
        guard !sets.isEmpty, sets.allSatisfy({ $0.effectiveRepsEstimate != nil }) else { return nil }
        return sets.reduce(0) { $0 + ($1.effectiveRepsEstimate ?? 0) }
    }
    var averageRPE: Double? { average(sets.compactMap(\.rpe)) }
    var averageRIR: Double? { average(sets.compactMap(\.rir)) }
    var averageRestSeconds: Double? { average(sets.compactMap(\.restSeconds)) }
    var regionalWorkload: [MuscleWorkload] {
        MuscleGroup.allCases.compactMap { muscle in
            let records = sets.filter { $0.muscle == muscle }
            guard !records.isEmpty else { return nil }
            return MuscleWorkload(muscle: muscle, sets: records.count, repetitions: records.reduce(0) { $0 + ($1.repetitions ?? 0) }, highEffortSets: records.filter { ($0.rpe ?? 0) >= 8 || ($0.rir.map { $0 <= 2 } ?? false) }.count)
        }
    }
}

struct HeartRateZones: Codable, Sendable {
    var seconds: [Double?]
    var isValid: Bool { seconds.count == 5 && seconds.allSatisfy { guard let value = $0 else { return false }; return value.isFinite && value >= 0 && value <= 604_800 } }
    var totalSeconds: Double { seconds.compactMap { $0 }.reduce(0, +) }
    var explosiveSharePercent: Double? { guard isValid, totalSeconds > 0, let high = seconds[4] else { return nil }; return high / totalSeconds * 100 }
}

struct SwimLap: Codable, Sendable, Identifiable {
    var id = UUID()
    var seconds: Double?
    var strokes: Int?
    var lengthMeters: Double?
    var isValid: Bool { guard let seconds, let strokes, let lengthMeters else { return false }; return seconds.isFinite && (1...3_600).contains(seconds) && (1...500).contains(strokes) && lengthMeters.isFinite && (1...1_000).contains(lengthMeters) }
    var swolf: Double? { guard let seconds, let strokes else { return nil }; return seconds + Double(strokes) }
}

enum EnduranceDiscipline: String, Codable, Sendable {
    case running, cycling, swimming, rowing, walking, other
    static func from(_ name: String) -> EnduranceDiscipline {
        let key = name.lowercased()
        if key.contains("run") { return .running }
        if key.contains("cycl") || key.contains("ride") { return .cycling }
        if key.contains("swim") { return .swimming }
        if key.contains("row") { return .rowing }
        if key.contains("walk") || key.contains("hik") { return .walking }
        return .other
    }
    #if canImport(HealthKit) && !STRAIN_CORE_TESTS
    static func from(healthKitRawValue value: UInt) -> EnduranceDiscipline {
        if [HKWorkoutActivityType.running, .wheelchairRunPace].contains(where: { $0.rawValue == value }) { return .running }
        if [HKWorkoutActivityType.cycling, .handCycling].contains(where: { $0.rawValue == value }) { return .cycling }
        if value == HKWorkoutActivityType.swimming.rawValue { return .swimming }
        if value == HKWorkoutActivityType.rowing.rawValue { return .rowing }
        if [HKWorkoutActivityType.walking, .hiking, .wheelchairWalkPace].contains(where: { $0.rawValue == value }) { return .walking }
        return .other
    }
    #endif
}

struct EnduranceMetrics: WorkoutMetricsProtocol {
    var loadInputs: WorkoutLoadInputs?
    var discipline: EnduranceDiscipline = .other
    var distanceMeters: Double?
    var movingSeconds: Double?
    var cadencePerMinute: Double?
    var averagePowerWatts: Double?
    var laps: [SwimLap] = []
    // GAP ve aerobik eşik ölçülmüş/sağlayıcıdan alınmış değerlerdir; ortalama nabızdan türetilmez.
    var gradeAdjustedPaceSecondsPerKm: Double?
    var aerobicThresholdBpm: Double?
    var archetype: SportArchetype { .endurance }
    var isValid: Bool {
        valid(distanceMeters, in: 0...2_000_000) && valid(movingSeconds, in: 1...604_800) && valid(cadencePerMinute, in: 0...400) && valid(averagePowerWatts, in: 0...5_000) && laps.count <= 100 && laps.allSatisfy(\.isValid) && valid(gradeAdjustedPaceSecondsPerKm, in: 30...7_200) && valid(aerobicThresholdBpm, in: 20...300) && (loadInputs?.isValid ?? true)
    }
    var paceSecondsPerKm: Double? {
        guard let distanceMeters, distanceMeters > 0, let movingSeconds, movingSeconds > 0 else { return nil }
        let pace = movingSeconds / (distanceMeters / 1_000)
        return pace.isFinite && pace <= Double(Int.max / 4) ? pace : nil
    }
    var speedKmh: Double? { guard let distanceMeters, let movingSeconds, movingSeconds > 0 else { return nil }; return distanceMeters / movingSeconds * 3.6 }
    var averageSWOLF: Double? { guard !laps.isEmpty, laps.allSatisfy(\.isValid), Set(laps.map(\.lengthMeters)).count == 1 else { return nil }; return laps.reduce(0) { $0 + ($1.swolf ?? 0) } / Double(laps.count) }
}

struct OneMinuteRecovery: Codable, Sendable {
    var startBpm: Double?
    var afterOneMinuteBpm: Double?
    var isValid: Bool { startBpm != nil && afterOneMinuteBpm != nil && valid(startBpm, in: 20...300) && valid(afterOneMinuteBpm, in: 20...300) }
    var dropBpm: Double? { guard let startBpm, let afterOneMinuteBpm else { return nil }; return startBpm - afterOneMinuteBpm }
    var relativeDropPercent: Double? { guard let dropBpm, let startBpm, startBpm > 0 else { return nil }; return dropBpm / startBpm * 100 }
}

struct TeamCourtMetrics: WorkoutMetricsProtocol {
    var loadInputs: WorkoutLoadInputs?
    var zones: HeartRateZones?
    var sprintCount: Int?
    var activeEnergyKcal: Double?
    var recovery: OneMinuteRecovery?
    var archetype: SportArchetype { .teamAndCourt }
    var isValid: Bool { (zones?.isValid ?? true) && (sprintCount.map { (0...10_000).contains($0) } ?? true) && valid(activeEnergyKcal, in: 0...100_000) && (recovery?.isValid ?? true) && (loadInputs?.isValid ?? true) }
}

struct CombatRound: Codable, Sendable, Identifiable {
    var id = UUID()
    var seconds: Double?
    var recovery: OneMinuteRecovery?
    var isValid: Bool { seconds != nil && valid(seconds, in: 1...7_200) && (recovery?.isValid ?? true) }
}

struct CombatMindBodyMetrics: WorkoutMetricsProtocol {
    var loadInputs: WorkoutLoadInputs?
    var rounds: [CombatRound] = []
    var hrvBeforeMs: Double?
    var hrvAfterMs: Double?
    var archetype: SportArchetype { .combatAndMindBody }
    var isValid: Bool { rounds.count <= 100 && rounds.allSatisfy(\.isValid) && valid(hrvBeforeMs, in: 1...1_000) && valid(hrvAfterMs, in: 1...1_000) && (loadInputs?.isValid ?? true) }
    var averageRecoveryBpm: Double? { let values = rounds.compactMap { $0.recovery?.dropBpm }; guard !values.isEmpty else { return nil }; return values.reduce(0, +) / Double(values.count) }
    var hrvChangeMs: Double? { guard let hrvBeforeMs, let hrvAfterMs else { return nil }; return hrvAfterMs - hrvBeforeMs }
}

enum WorkoutPayload: Codable, Sendable {
    case strength(StrengthMetrics), endurance(EnduranceMetrics), teamCourt(TeamCourtMetrics), combatMindBody(CombatMindBodyMetrics)
    var archetype: SportArchetype {
        switch self { case .strength: return .strengthAndHypertrophy; case .endurance: return .endurance; case .teamCourt: return .teamAndCourt; case .combatMindBody: return .combatAndMindBody }
    }
    var isValid: Bool {
        switch self { case .strength(let value): return value.isValid; case .endurance(let value): return value.isValid; case .teamCourt(let value): return value.isValid; case .combatMindBody(let value): return value.isValid }
    }
    static func empty(for archetype: SportArchetype) -> WorkoutPayload {
        switch archetype { case .strengthAndHypertrophy: return .strength(StrengthMetrics()); case .endurance: return .endurance(EnduranceMetrics()); case .teamAndCourt: return .teamCourt(TeamCourtMetrics()); case .combatAndMindBody: return .combatMindBody(CombatMindBodyMetrics()) }
    }
    var loadInputs: WorkoutLoadInputs {
        get {
            switch self { case .strength(let v): return v.loadInputs ?? WorkoutLoadInputs(); case .endurance(let v): return v.loadInputs ?? WorkoutLoadInputs(); case .teamCourt(let v): return v.loadInputs ?? WorkoutLoadInputs(); case .combatMindBody(let v): return v.loadInputs ?? WorkoutLoadInputs() }
        }
        set {
            let input: WorkoutLoadInputs? = newValue.isEmpty ? nil : newValue
            switch self { case .strength(var v): v.loadInputs = input; self = .strength(v); case .endurance(var v): v.loadInputs = input; self = .endurance(v); case .teamCourt(var v): v.loadInputs = input; self = .teamCourt(v); case .combatMindBody(var v): v.loadInputs = input; self = .combatMindBody(v) }
        }
    }
    var heartRateZones: HeartRateZones? {
        get { if case .teamCourt(let v) = self { return v.zones ?? v.loadInputs?.zones }; return loadInputs.zones }
        set {
            if case .teamCourt(var v) = self { v.zones = newValue; v.loadInputs?.zones = nil; self = .teamCourt(v) }
            else { var input = loadInputs; input.zones = newValue; loadInputs = input }
        }
    }
}

extension WorkoutPayload {
    func removingAutomaticMatches(from automatic: WorkoutPayload?) -> WorkoutPayload {
        guard let automatic, automatic.archetype == archetype else { return self }
        var result = self
        switch (result, automatic) {
        case (.endurance(var saved), .endurance(let source)):
            if saved.distanceMeters == source.distanceMeters { saved.distanceMeters = nil }
            if saved.movingSeconds == source.movingSeconds { saved.movingSeconds = nil }
            if saved.cadencePerMinute == source.cadencePerMinute { saved.cadencePerMinute = nil }
            if saved.averagePowerWatts == source.averagePowerWatts { saved.averagePowerWatts = nil }
            result = .endurance(saved)
        case (.teamCourt(var saved), .teamCourt(let source)):
            if saved.activeEnergyKcal == source.activeEnergyKcal { saved.activeEnergyKcal = nil }
            result = .teamCourt(saved)
        default: break
        }
        var input = result.loadInputs
        if input.sessionRPE == automatic.loadInputs.sessionRPE { input.sessionRPE = nil }
        result.loadInputs = input
        if result.heartRateZones?.seconds == automatic.heartRateZones?.seconds { result.heartRateZones = nil }
        return result
    }
    func fillingMissing(from automatic: WorkoutPayload?) -> WorkoutPayload {
        guard let automatic, automatic.archetype == archetype, automatic.isValid else { return self }
        var result = self
        switch (result, automatic) {
        case (.endurance(var saved), .endurance(let source)):
            saved.distanceMeters = saved.distanceMeters ?? source.distanceMeters
            saved.movingSeconds = saved.movingSeconds ?? source.movingSeconds
            saved.cadencePerMinute = saved.cadencePerMinute ?? source.cadencePerMinute
            saved.averagePowerWatts = saved.averagePowerWatts ?? source.averagePowerWatts
            result = .endurance(saved)
        case (.teamCourt(var saved), .teamCourt(let source)):
            saved.activeEnergyKcal = saved.activeEnergyKcal ?? source.activeEnergyKcal
            result = .teamCourt(saved)
        default: break
        }
        var input = result.loadInputs
        input.sessionRPE = input.sessionRPE ?? automatic.loadInputs.sessionRPE
        input.explosiveSeconds = input.explosiveSeconds ?? automatic.loadInputs.explosiveSeconds
        result.loadInputs = input
        if result.heartRateZones == nil { result.heartRateZones = automatic.heartRateZones }
        return result
    }
}

private func valid(_ value: Double?, in range: ClosedRange<Double>) -> Bool { value.map { $0.isFinite && range.contains($0) } ?? true }
private func average(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
