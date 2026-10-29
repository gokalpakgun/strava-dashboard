import Foundation

enum StrengthSessionFocus: String, Codable, CaseIterable, Sendable, Identifiable {
    case unspecified, lowerBody, upperBody, fullBody
    var id: String { rawValue }
}

struct ActiveSportContext: Codable, Sendable, Equatable {
    let sportID: String
    let archetype: SportArchetype
    var strengthFocus: StrengthSessionFocus = .unspecified
    var isMindBody: Bool = false
}

struct CrossSportWorkout: Sendable {
    let workout: StrainWorkout
    var hasLowerBodyImpact = false
}

enum InterferenceReason: String, Codable, Sendable { case recentCourt, intenseEndurance, legStrength }
enum InterferenceLevel: String, Codable, Sendable { case notice, caution }

struct InterferenceWarning: Codable, Sendable {
    let reason: InterferenceReason
    let level: InterferenceLevel
    let hoursSinceWorkout: Int
    let suggestedVolumeReductionPercent: Int
    let suggestedRPECap: Int
    let limitedEvidence: Bool
}

protocol InterferenceAnalyzing: Sendable {
    func warning(for active: ActiveSportContext, workouts: [CrossSportWorkout], now: Date) -> InterferenceWarning?
}

struct InterferenceAnalyzer: InterferenceAnalyzing, Sendable {
    func warning(for active: ActiveSportContext, workouts: [CrossSportWorkout], now: Date = Date()) -> InterferenceWarning? {
        // Branş tek başına bacak antrenmanı sayılmaz; bugünkü hedef açıkça seçilmelidir.
        guard active.archetype == .strengthAndHypertrophy,
              [.lowerBody, .fullBody].contains(active.strengthFocus), now.timeIntervalSince1970.isFinite else { return nil }
        var seen = Set<String>()
        let ordered = workouts.filter {
            let age = now.timeIntervalSince($0.workout.endedAt)
            return $0.workout.isValid && age >= 0 && age < 48 * 3_600 && seen.insert($0.workout.id).inserted
        }.sorted { $0.workout.endedAt > $1.workout.endedAt }
        for item in ordered {
            let workout = item.workout
            let hours = Int(now.timeIntervalSince(workout.endedAt) / 3_600)
            let zones = workout.payload.heartRateZones
            let completeZones = (workout.heartRateZoneEvidence?.observedSeconds ?? zones?.totalSeconds ?? 0) >= workout.durationSeconds * 0.8
            let intenseSeconds = completeZones ? (zones?.seconds.suffix(2).compactMap { $0 }.reduce(0, +) ?? 0) : 0
            var reason: InterferenceReason?
            var limited = false
            switch workout.payload {
            case .teamCourt where item.hasLowerBodyImpact && workout.durationSeconds >= 1_200:
                reason = .recentCourt
                limited = workout.effortIsEstimated || workout.heartRateZoneEvidence != nil || (workout.payload.loadInputs.sessionRPE == nil && !completeZones)
            case .endurance(let metrics) where [.running, .cycling, .walking, .rowing].contains(metrics.discipline) && intenseSeconds > 1_200:
                reason = .intenseEndurance
                limited = workout.heartRateZoneEvidence != nil
            case .strength(let metrics):
                let legSets = metrics.sets.filter { [.legs, .fullBody].contains($0.muscle) }
                let hardSets = legSets.filter { ($0.rpe ?? 0) >= 8 || ($0.rir.map { $0 <= 2 } ?? false) }.count
                if hardSets >= 4 || (!legSets.isEmpty && (metrics.loadInputs?.sessionRPE ?? 0) >= 8) { reason = .legStrength }
            default: break
            }
            if let reason {
                // 20–30% bir Tempo planlama seçeneğidir; ölçülmüş CNS yorgunluğu/teşhis değildir.
                return InterferenceWarning(reason: reason, level: hours < 24 ? .caution : .notice,
                    hoursSinceWorkout: hours, suggestedVolumeReductionPercent: hours < 24 ? 30 : 20,
                    suggestedRPECap: 6, limitedEvidence: limited)
            }
        }
        return nil
    }
}

struct AthleticLoadContext: Codable, Sendable {
    let hours: Int
    let score: Int?
    let cardioLoad: Int?
    let estimatedMuscleLoad: Int?
    let scoredWorkouts: Int
    let unscoredWorkouts: Int
    let limitedEvidence: Bool
    init(hours: Int, summary: StrainWindowSummary) {
        self.hours = hours; score = summary.value; cardioLoad = summary.cardioLoad
        estimatedMuscleLoad = summary.muscleLoad; scoredWorkouts = summary.workoutsWithScore
        unscoredWorkouts = summary.workoutsWithoutScore; limitedEvidence = summary.hasLimitedEvidence
    }
}

struct AthleticBalanceContext: Codable, Sendable {
    let strength: Int?
    let aerobic: Int?
    let anaerobic: Int?
    let mobility: Int?
    let leastRepresentedAxes: [HybridAxis]
    let workoutCount: Int
    init(_ balance: HybridAthleteBalance) {
        strength = balance.axes.first { $0.axis == .strength }?.value
        aerobic = balance.axes.first { $0.axis == .aerobic }?.value
        anaerobic = balance.axes.first { $0.axis == .anaerobic }?.value
        mobility = balance.axes.first { $0.axis == .mobility }?.value
        leastRepresentedAxes = balance.leastRepresentedAxes; workoutCount = balance.workoutCount
    }
}

struct AthleticObservedMetrics: Codable, Sendable {
    let hoursSinceWorkout: Int
    var sessionRPE: Double?
    var tonnageKg: Double?
    var highZoneMinutes: Double?
    var cadencePerMinute: Double?
    var averagePowerWatts: Double?
    var heartRateRecoveryBpm: Double?
    var userEntered: Bool
    var effortIsEstimated = false
    var zoneReferenceMaxBpm: Double?
    var zoneReferenceSource: MaximumHeartRateReference?
}

enum AthleticFocusMetric: String, Codable, Sendable {
    case shoulderElbowControl, agility, heartRateZones, heartRateRecovery
    case sessionRPE, tonnage, setRepetitions, muscleRecovery, cadence, power, glycogenRecovery
    case pace, swolf, aerobicThreshold, explosiveEffort, mobility, breathingComfort, perceivedEffort
    case roundDuration, hrvChange
}

struct AthleticAIContext: Codable, Sendable {
    let schemaVersion: Int
    let activeSport: ActiveSportContext
    let focusMetrics: [AthleticFocusMetric]
    let load24h: AthleticLoadContext?
    let load48h: AthleticLoadContext?
    let interference: InterferenceWarning?
    let balance7d: AthleticBalanceContext?
    let latestMetrics: AthleticObservedMetrics?
    let includesHealthWorkouts: Bool
    let modelVersion: String
    var muscleRecovery: MuscleRecoverySummary?
    var acwr: ACWRSummary?
}

protocol AIContextBuilding: Sendable {
    func build(active: ActiveSportContext, workouts: [CrossSportWorkout], includeTraining: Bool, includeHealth: Bool, now: Date) -> AthleticAIContext
}

struct AIContextBuilder: AIContextBuilding, Sendable {
    func build(active: ActiveSportContext, workouts: [CrossSportWorkout], includeTraining: Bool, includeHealth: Bool, now: Date = Date()) -> AthleticAIContext {
        // Sağlık kayıtları ayrıca izin gerektirir. Strava hiçbir bağlam hesabına katılmaz.
        var seen = Set<String>()
        let allowed = includeTraining ? workouts.filter {
            $0.workout.isValid && $0.workout.endedAt <= now &&
            ($0.workout.source != .health || includeHealth) && seen.insert($0.workout.id).inserted
        } : []
        let inputs = allowed.map(\.workout)
        let engine = UniversalStrainEngine()
        let latest = inputs.filter { $0.payload.archetype == active.archetype && $0.endedAt > now.addingTimeInterval(-48 * 3_600) }
            .max { $0.endedAt < $1.endedAt }
        return AthleticAIContext(schemaVersion: 1, activeSport: active, focusMetrics: focusMetrics(for: active),
            load24h: includeTraining ? AthleticLoadContext(hours: 24, summary: engine.summary(inputs, since: now.addingTimeInterval(-24 * 3_600), until: now)) : nil,
            load48h: includeTraining ? AthleticLoadContext(hours: 48, summary: engine.summary(inputs, since: now.addingTimeInterval(-48 * 3_600), until: now)) : nil,
            interference: includeTraining ? InterferenceAnalyzer().warning(for: active, workouts: allowed, now: now) : nil,
            balance7d: includeTraining ? AthleticBalanceContext(engine.hybridBalance(inputs, now: now)) : nil,
            latestMetrics: latest.map { observedMetrics($0, now: now) }, includesHealthWorkouts: includeTraining && includeHealth,
            modelVersion: engine.configuration.modelVersion,
            muscleRecovery: includeTraining ? MuscleRecoveryCalculator().summary(inputs, now: now) : nil,
            acwr: includeTraining ? engine.acwrSummary(inputs, now: now) : nil)
    }

    func focusMetrics(for active: ActiveSportContext) -> [AthleticFocusMetric] {
        if ["tennis", "padel", "badminton", "squash", "pickleball"].contains(active.sportID) { return [.shoulderElbowControl, .agility, .heartRateZones, .heartRateRecovery] }
        switch active.archetype {
        case .strengthAndHypertrophy: return [.sessionRPE, .tonnage, .setRepetitions, .muscleRecovery]
        case .endurance:
            if active.sportID == "cycling" { return [.cadence, .power, .heartRateZones, .glycogenRecovery] }
            if active.sportID == "swimming" { return [.pace, .swolf, .heartRateZones] }
            return [.pace, .cadence, .heartRateZones, .aerobicThreshold]
        case .teamAndCourt: return [.heartRateZones, .agility, .explosiveEffort, .heartRateRecovery]
        case .combatAndMindBody: return active.isMindBody ? [.mobility, .breathingComfort, .perceivedEffort] : [.roundDuration, .heartRateRecovery, .hrvChange]
        }
    }

    private func observedMetrics(_ workout: StrainWorkout, now: Date) -> AthleticObservedMetrics {
        var result = AthleticObservedMetrics(hoursSinceWorkout: max(0, Int(now.timeIntervalSince(workout.endedAt) / 3_600)), sessionRPE: workout.payload.loadInputs.sessionRPE, userEntered: workout.userEntered, effortIsEstimated: workout.effortIsEstimated)
        result.zoneReferenceMaxBpm = workout.heartRateZoneEvidence?.maximumHeartRateBpm
        result.zoneReferenceSource = workout.heartRateZoneEvidence?.reference
        if let zones = workout.payload.heartRateZones, (workout.heartRateZoneEvidence?.observedSeconds ?? zones.totalSeconds) >= workout.durationSeconds * 0.8 {
            result.highZoneMinutes = zones.seconds.suffix(2).compactMap { $0 }.reduce(0, +) / 60
        }
        switch workout.payload {
        case .strength(let metrics): result.tonnageKg = metrics.tonnageKg
        case .endurance(let metrics): result.cadencePerMinute = metrics.cadencePerMinute; result.averagePowerWatts = metrics.averagePowerWatts
        case .teamCourt(let metrics): result.heartRateRecoveryBpm = metrics.recovery?.dropBpm
        case .combatMindBody: break
        }
        return result
    }
}

enum AthleticGuardrailDecision: Sendable, Equatable { case allow, refuse, urgentSafety }

struct AthleticGuardrailValidator: Sendable {
    func validate(_ question: String) -> AthleticGuardrailDecision {
        let text = question.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased().replacingOccurrences(of: "ı", with: "i").trimmingCharacters(in: .whitespacesAndNewlines)
        if matches(text, "gog(us|sum|su|sunde).*agr|chest pain|bayil|fainting|coughing blood|kan tukur|severe shortness of breath|nefes alam|ciddi nefes darl") { return .urgentSafety }
        if matches(text, "\\b(bitcoin|crypto|kripto|forex|borsa|stock market|stock price|election|secim|siyaset|politic\\w*|cumhurbaskani|president|basbakan|prime minister|javascript|python code|sql query|write code|kod yaz|programlama|hacking|siber guvenlik|hava durumu|weather forecast)\\b") { return .refuse }
        if matches(text, "^(hello|hi|hey|merhaba|selam|nasilsin|how are you|tell me a joke|fikra anlat)[!?., ]*$") { return .refuse }
        // Kısa takip sorularını kelime listesiyle kesmeyiz; belirsiz kapsamı sistem politikası denetler.
        return .allow
    }
    private func matches(_ text: String, _ pattern: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }
}

struct CrossSportAIService: Sendable {
    let analyzer = InterferenceAnalyzer()
    let contextBuilder = AIContextBuilder()
    let guardrail = AthleticGuardrailValidator()
    func context(active: ActiveSportContext, workouts: [CrossSportWorkout], includeTraining: Bool, includeHealth: Bool, now: Date = Date()) -> AthleticAIContext {
        contextBuilder.build(active: active, workouts: workouts, includeTraining: includeTraining, includeHealth: includeHealth, now: now)
    }
}
