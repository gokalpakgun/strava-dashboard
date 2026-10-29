import Foundation

struct MuscleRecoveryEntry: Codable, Sendable, Identifiable {
    let muscle: MuscleGroup
    let readinessPercent: Int?
    let recentSets: Int
    let recentHighEffortSets: Int
    let hoursSinceLastRecordedSet: Double?
    var id: MuscleGroup { muscle }
}

struct MuscleRecoverySummary: Codable, Sendable {
    let entries: [MuscleRecoveryEntry]
    let unclassifiedRecentSets: Int
    let modelVersion: String
    var hasData: Bool { entries.contains { $0.readinessPercent != nil } }
    var lowerReadinessGroups: [MuscleGroup] { entries.filter { ($0.readinessPercent ?? 100) < 50 }.map(\.muscle) }
}

struct MuscleRecoveryCalculator: Sendable {
    func summary(_ workouts: [StrainWorkout], now: Date = Date()) -> MuscleRecoverySummary {
        var seen = Set<String>()
        let records = workouts.filter { $0.isValid && $0.endedAt <= now && seen.insert($0.id).inserted }
        var loads: [MuscleGroup: Double] = [:], lastHours: [MuscleGroup: Double] = [:]
        var counts: [MuscleGroup: Int] = [:], hardCounts: [MuscleGroup: Int] = [:]
        var unclassified = 0
        for workout in records {
            guard case .strength(let strength) = workout.payload else { continue }
            let hours = now.timeIntervalSince(workout.endedAt) / 3_600
            guard hours.isFinite, hours >= 0 else { continue }
            for region in strength.regionalWorkload {
                if region.muscle == .unspecified { if hours < 72 { unclassified += region.sets }; continue }
                lastHours[region.muscle] = min(lastHours[region.muscle] ?? hours, hours)
                guard hours < 72 else { continue }
                // 4 puan/set + 4 ek puan/yüksek eforlu set, 72 saatte doğrusal olarak sıfıra iner.
                let residual = Double(region.sets * 4 + region.highEffortSets * 4) * max(0, 1 - hours / 72)
                loads[region.muscle, default: 0] += residual
                counts[region.muscle, default: 0] += region.sets
                hardCounts[region.muscle, default: 0] += region.highEffortSets
            }
        }
        let entries = MuscleGroup.allCases.filter { $0 != .unspecified }.map { group in
            MuscleRecoveryEntry(muscle: group, readinessPercent: lastHours[group] == nil ? nil : max(0, min(100, Int((100 - min(100, loads[group] ?? 0)).rounded()))), recentSets: counts[group] ?? 0, recentHighEffortSets: hardCounts[group] ?? 0, hoursSinceLastRecordedSet: lastHours[group])
        }
        return MuscleRecoverySummary(entries: entries, unclassifiedRecentSets: unclassified, modelVersion: "tempo-regional-v1")
    }
}

enum ACWRStatus: String, Codable, Sendable {
    case insufficientHistory, lowLoad, referenceRange, increasedLoad, highIncrease
    static func band(for ratio: Double) -> ACWRStatus {
        guard ratio.isFinite, ratio >= 0 else { return .insufficientHistory }
        let value = (ratio * 1_000_000_000).rounded() / 1_000_000_000
        return value < 0.8 ? .lowLoad : value <= 1.3 ? .referenceRange : value <= 1.5 ? .increasedLoad : .highIncrease
    }
}

struct ACWRSummary: Codable, Sendable {
    let ratio: Double?
    let acuteDose: Double?
    let chronicWeeklyAverageDose: Double?
    let status: ACWRStatus
    let historyDays: Int
    let scoredWorkouts: Int
    let unscoredWorkouts: Int
    let limitedEvidence: Bool
}

struct AcuteChronicLoadCalculator: Sendable {
    let engine: UniversalStrainEngine
    func summary(_ workouts: [StrainWorkout], now: Date) -> ACWRSummary {
        let start = now.addingTimeInterval(-28 * 86_400), acuteStart = now.addingTimeInterval(-7 * 86_400)
        var seen = Set<String>()
        let valid = workouts.filter { $0.isValid && $0.endedAt <= now && $0.endedAt > start && seen.insert($0.id).inserted }
        var acute = 0.0, chronic = 0.0, scored = 0, missing = 0, limited = false
        var earliest: Date?
        for workout in valid {
            guard let score = engine.score(for: workout, history: workouts) else { missing += 1; continue }
            scored += 1; chronic += score.combinedDose
            if workout.endedAt > acuteStart { acute += score.combinedDose }
            earliest = min(earliest ?? workout.endedAt, workout.endedAt)
            limited = limited || score.hasLimitedEvidence
        }
        let historyDays = earliest.map { min(28, max(1, Int(now.timeIntervalSince($0) / 86_400) + 1)) } ?? 0
        let average = chronic / 4
        let ratio = average > 0 && average.isFinite && acute.isFinite ? acute / average : nil
        let enoughHistory = historyDays >= 28 && scored >= 4
        let status: ACWRStatus
        if let ratio, ratio.isFinite, enoughHistory {
            status = .band(for: ratio)
        } else { status = .insufficientHistory }
        return ACWRSummary(ratio: ratio.flatMap { $0.isFinite ? $0 : nil }, acuteDose: scored > 0 ? acute : nil, chronicWeeklyAverageDose: scored > 0 ? average : nil, status: status, historyDays: historyDays, scoredWorkouts: scored, unscoredWorkouts: missing, limitedEvidence: limited || missing > 0 || !enoughHistory)
    }
}
