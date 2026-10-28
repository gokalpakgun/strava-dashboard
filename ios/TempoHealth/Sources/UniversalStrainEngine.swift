import Foundation

enum StrainRecordSource: String, Codable, Sendable { case tempo, health, strava }

struct StrainWorkout: Sendable, Identifiable {
    let id: String
    let startedAt: Date
    let durationSeconds: Double
    let payload: WorkoutPayload
    let source: StrainRecordSource
    var isMindBody = false
    var userEntered = false
    var endedAt: Date { startedAt.addingTimeInterval(durationSeconds) }
    var isValid: Bool {
        source != .strava && startedAt.timeIntervalSince1970.isFinite && durationSeconds.isFinite && (1...604_800).contains(durationSeconds) && payload.isValid && (payload.heartRateZones.map { $0.totalSeconds <= durationSeconds + 1 } ?? true) && (payload.loadInputs.explosiveSeconds.map { $0 <= durationSeconds } ?? true)
    }
}

struct UniversalStrainConfiguration: Sendable {
    // Tempo v1 ölçekleri: klinik eşik veya evrensel antrenman hedefi değildir.
    var modelVersion = "tempo-load-v1"
    var cardioReferenceTRIMP = 150.0
    var sessionReferenceAU = 300.0
    var hardSetReference = 8.0
    var explosiveReferenceSeconds = 180.0
    var minimumZoneCoverage = 0.8
    var minimumTonnageHistory = 3
    var isValid: Bool {
        [cardioReferenceTRIMP, sessionReferenceAU, hardSetReference, explosiveReferenceSeconds].allSatisfy { $0.isFinite && (1...1_000_000_000).contains($0) } && minimumZoneCoverage.isFinite && minimumZoneCoverage > 0 && minimumZoneCoverage <= 1 && (3...8).contains(minimumTonnageHistory)
    }
}

struct UniversalStrainScore: Sendable, Identifiable {
    let id: String
    let value: Int
    let cardioLoad: Int?
    let muscleLoad: Int?
    let cardioTRIMP: Double?
    let sessionRPELoadAU: Double?
    let recordedTonnageKg: Double?
    let personalTonnageReferenceKg: Double?
    let zoneCoverage: Double
    let setCoverage: Double?
    let cardioDose: Double?
    let muscleDose: Double?
    let combinedDose: Double
    let userEntered: Bool
    let modelVersion: String
    var hasLimitedEvidence: Bool { cardioLoad == nil || muscleLoad == nil || (cardioLoad != nil && zoneCoverage < 0.999) || (setCoverage.map { $0 < 0.999 } ?? false) }
}

struct StrainWindowSummary: Sendable {
    let value: Int?
    let cardioLoad: Int?
    let muscleLoad: Int?
    let workoutsWithScore: Int
    let workoutsWithoutScore: Int
    let hasLimitedEvidence: Bool
}

enum HybridAxis: String, CaseIterable, Codable, Identifiable, Sendable {
    case strength, aerobic, anaerobic, mobility
    var id: String { rawValue }
}

struct HybridAxisScore: Sendable, Identifiable {
    let axis: HybridAxis
    let value: Int?
    let minutes: Double?
    var id: HybridAxis { axis }
}

struct HybridAthleteBalance: Sendable {
    let axes: [HybridAxisScore]
    let workoutCount: Int
    let intensityCoverage: Double
    var hasCompleteAxes: Bool { axes.count == 4 && axes.allSatisfy { $0.value != nil } }
    var leastRepresentedAxes: [HybridAxis] {
        guard workoutCount >= 3, hasCompleteAxes, let lowest = axes.compactMap(\.value).min() else { return [] }
        return axes.filter { $0.value == lowest }.map(\.axis)
    }
    var weakestAxis: HybridAxis? {
        leastRepresentedAxes.count == 1 ? leastRepresentedAxes.first : nil
    }
}

protocol UniversalStrainCalculating: Sendable {
    func score(for workout: StrainWorkout, history: [StrainWorkout]) -> UniversalStrainScore?
}

struct UniversalStrainEngine: UniversalStrainCalculating, Sendable {
    let configuration: UniversalStrainConfiguration
    init(configuration: UniversalStrainConfiguration = UniversalStrainConfiguration()) { self.configuration = configuration }

    func score(for workout: StrainWorkout, history: [StrainWorkout] = []) -> UniversalStrainScore? {
        guard configuration.isValid, workout.isValid else { return nil }
        let zones = workout.payload.heartRateZones
        let coverage = zones.map { min(1, $0.totalSeconds / workout.durationSeconds) } ?? 0
        let trimp = zones.flatMap { values -> Double? in
            guard values.isValid, values.totalSeconds > 0 else { return nil }
            // Edwards tipi TRIMP: Z1–Z5'teki dakikalar × 1–5.
            return values.seconds.enumerated().reduce(0) { $0 + (($1.element ?? 0) / 60) * Double($1.offset + 1) }
        }
        let cardioDose = coverage >= configuration.minimumZoneCoverage ? trimp.map { $0 / configuration.cardioReferenceTRIMP } : nil
        let sessionAU = workout.payload.loadInputs.sessionRPE.map { workout.durationSeconds / 60 * $0 }
        var muscleProxies: [Double] = []
        if let sessionAU { muscleProxies.append(sessionAU / configuration.sessionReferenceAU) }
        if let seconds = workout.payload.loadInputs.explosiveSeconds, seconds > 0 { muscleProxies.append(seconds / configuration.explosiveReferenceSeconds) }
        var tonnage: Double?
        var tonnageReference: Double?
        var setCoverage: Double?
        if case .strength(let strength) = workout.payload {
            tonnage = strength.tonnageKg
            let rated = strength.sets.compactMap { set -> Double? in
                if let rpe = set.rpe { return rpe / 10 }
                if let rir = set.rir { return max(1, 10 - rir) / 10 }
                return nil
            }
            if !strength.sets.isEmpty { setCoverage = Double(rated.count) / Double(strength.sets.count) }
            if !rated.isEmpty { muscleProxies.append(rated.reduce(0, +) / configuration.hardSetReference) }
            let prior = uniqueValid(history).filter { previous in
                previous.id != workout.id && previous.isValid && previous.endedAt <= workout.startedAt && previous.startedAt >= workout.startedAt.addingTimeInterval(-28 * 86_400)
            }.sorted { $0.startedAt > $1.startedAt }.compactMap { previous -> Double? in
                guard case .strength(let value) = previous.payload, let volume = value.tonnageKg, volume > 0 else { return nil }
                return volume
            }.prefix(8).sorted()
            if prior.count >= configuration.minimumTonnageHistory {
                let middle = prior.count / 2
                let median = prior.count.isMultiple(of: 2) ? (prior[middle - 1] + prior[middle]) / 2 : prior[middle]
                tonnageReference = median
                if let tonnage, tonnage > 0 { muscleProxies.append(min(3, tonnage / median)) }
            }
        }
        // İlişkili RPE/tonaj/set ölçülerini toplayarak aynı yük iki kez sayılmaz.
        let muscleDose = muscleProxies.max()
        let weights = archetypeWeights(workout.payload.archetype, mindBody: workout.isMindBody)
        var weighted = 0.0
        var totalWeight = 0.0
        if let cardioDose { weighted += cardioDose * weights.cardio; totalWeight += weights.cardio }
        if let muscleDose { weighted += muscleDose * weights.muscle; totalWeight += weights.muscle }
        guard totalWeight > 0 else { return nil }
        let combined = weighted / totalWeight
        return UniversalStrainScore(id: workout.id, value: normalized(combined), cardioLoad: cardioDose.map(normalized), muscleLoad: muscleDose.map(normalized), cardioTRIMP: trimp, sessionRPELoadAU: sessionAU, recordedTonnageKg: tonnage, personalTonnageReferenceKg: tonnageReference, zoneCoverage: coverage, setCoverage: setCoverage, cardioDose: cardioDose, muscleDose: muscleDose, combinedDose: combined, userEntered: workout.userEntered, modelVersion: configuration.modelVersion)
    }

    func summary(_ workouts: [StrainWorkout], since start: Date, until end: Date) -> StrainWindowSummary {
        guard configuration.isValid, start < end else { return emptySummary() }
        let records = uniqueValid(workouts).filter { $0.endedAt <= end && $0.endedAt > start && $0.startedAt < end }
        var combined = 0.0, cardio = 0.0, muscle = 0.0
        var scores = 0, without = 0, hasCardio = false, hasMuscle = false, limited = false
        for workout in records {
            guard let result = score(for: workout, history: workouts) else { without += 1; continue }
            // Kayıt, bitiş zamanı pencere içindeyse tüm seans olarak değerlendirilir.
            combined += result.combinedDose; scores += 1; limited = limited || result.hasLimitedEvidence
            if let dose = result.cardioDose { cardio += dose; hasCardio = true }
            if let dose = result.muscleDose { muscle += dose; hasMuscle = true }
        }
        return StrainWindowSummary(value: scores > 0 ? normalized(combined) : nil, cardioLoad: hasCardio ? normalized(cardio) : nil, muscleLoad: hasMuscle ? normalized(muscle) : nil, workoutsWithScore: scores, workoutsWithoutScore: without, hasLimitedEvidence: limited || without > 0)
    }

    func hybridBalance(_ workouts: [StrainWorkout], now: Date, calendar: Calendar = .autoupdatingCurrent) -> HybridAthleteBalance {
        guard configuration.isValid else { return HybridAthleteBalance(axes: HybridAxis.allCases.map { HybridAxisScore(axis: $0, value: nil, minutes: nil) }, workoutCount: 0, intensityCoverage: 0) }
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let records = uniqueValid(workouts).filter { $0.endedAt <= now && $0.endedAt > start }
        var exposure = Dictionary(uniqueKeysWithValues: HybridAxis.allCases.map { ($0, 0.0) })
        var intensityEligible = 0.0, intensityKnown = 0.0
        for workout in records {
            let seconds = workout.durationSeconds
            if workout.isMindBody { exposure[.mobility, default: 0] += seconds / 60; continue }
            let explicit = workout.payload.loadInputs.explosiveSeconds
            let zones = workout.payload.heartRateZones
            let zoneCoverage = zones.map { $0.totalSeconds / workout.durationSeconds } ?? 0
            let high = zones.flatMap { $0.isValid ? (($0.seconds[3] ?? 0) + ($0.seconds[4] ?? 0)) : nil }
            let known = explicit != nil || zoneCoverage >= configuration.minimumZoneCoverage
            let explosive = min(workout.durationSeconds, max(explicit ?? 0, high ?? 0))
            intensityEligible += seconds
            if known { intensityKnown += seconds }
            exposure[.anaerobic, default: 0] += explosive / 60
            let main: HybridAxis = workout.payload.archetype == .strengthAndHypertrophy ? .strength : .aerobic
            exposure[main, default: 0] += max(0, seconds - explosive) / 60
        }
        let total = exposure.values.reduce(0, +)
        let coverage = intensityEligible > 0 ? intensityKnown / intensityEligible : 0
        let axes = HybridAxis.allCases.map { axis -> HybridAxisScore in
            let hasData = total > 0 && (axis != .anaerobic || coverage >= configuration.minimumZoneCoverage)
            let minutes = exposure[axis] ?? 0
            return HybridAxisScore(axis: axis, value: hasData ? Int((minutes / total * 100).rounded()) : nil, minutes: hasData ? minutes : nil)
        }
        return HybridAthleteBalance(axes: axes, workoutCount: records.count, intensityCoverage: coverage)
    }

    private func archetypeWeights(_ archetype: SportArchetype, mindBody: Bool) -> (cardio: Double, muscle: Double) {
        if mindBody { return (0.25, 0.75) }
        switch archetype { case .strengthAndHypertrophy: return (0.25, 0.75); case .endurance: return (0.8, 0.2); case .teamAndCourt: return (0.6, 0.4); case .combatAndMindBody: return (0.5, 0.5) }
    }
    private func normalized(_ dose: Double) -> Int {
        guard dose.isFinite, dose >= 0 else { return 0 }
        return min(100, max(0, Int((100 * (1 - exp(-min(dose, 40)))).rounded())))
    }
    private func uniqueValid(_ workouts: [StrainWorkout]) -> [StrainWorkout] {
        var seen = Set<String>()
        return workouts.filter { $0.isValid && seen.insert($0.id).inserted }
    }
    private func emptySummary() -> StrainWindowSummary {
        StrainWindowSummary(value: nil, cardioLoad: nil, muscleLoad: nil, workoutsWithScore: 0, workoutsWithoutScore: 0, hasLimitedEvidence: false)
    }
}
