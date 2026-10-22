import CoreLocation
import Foundation

extension String {
    /// Resolves app owned copy through Localizable.strings while preserving
    /// server and user supplied text when a translation key does not exist.
    var tempoLocalized: String {
        Bundle.main.localizedString(forKey: self, value: self, table: nil)
    }

    var tempoSentenceCased: String {
        let localized = tempoLocalized.lowercased(with: .autoupdatingCurrent)
        guard let first = localized.first else { return localized }
        return String(first).uppercased(with: .autoupdatingCurrent) + String(localized.dropFirst())
    }

    func tempoFormatted(_ arguments: CVarArg...) -> String {
        String(format: tempoLocalized, locale: .autoupdatingCurrent, arguments: arguments)
    }
}

struct TempoDashboard: Codable {
    let athlete: TempoAthlete
    let segments: [TempoSegment]
    let photos: [TempoPhoto]
    let achievement: TempoAchievement?
    let historyLimited: Bool
    let activities: [TempoActivity]
}

struct TempoAthlete: Codable {
    let id: Int64
    let firstname: String?
    let lastname: String?
    let profile: String?
    let city: String?
    let state: String?
    let country: String?
    let sex: String?
    let weight: Double?
    let followerCount: Int?
    let friendCount: Int?
    let bikes: [TempoGear]
    let shoes: [TempoGear]

    var fullName: String {
        [firstname, lastname].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    var location: String {
        [city, state, country].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

struct TempoGear: Codable, Identifiable {
    let id: String
    let name: String?
    let distance: Double?
    let primary: Bool?
    let type: String?

    var localizedType: String {
        switch type {
        case .some("Bisiklet"), .some("Bike"): return "Bisiklet".tempoLocalized
        case .some("Ayakkabı"), .some("Shoe"): return "Ayakkabı".tempoLocalized
        case .some(let value): return value
        case .none: return "Ekipman".tempoLocalized
        }
    }
}

struct TempoSegment: Codable, Identifiable {
    let id: Int64
    let name: String?
    let distance: Double?
    let averageGrade: Double?
    let climbCategory: Int?
    let starCount: Int?
}

struct TempoPhoto: Codable, Identifiable {
    let activityId: Int64
    let activityName: String?
    let image: String
    var id: Int64 { activityId }
}

struct TempoActivity: Codable, Identifiable, Hashable {
    let id: Int64
    let name: String?
    let type: String?
    let startDateLocal: String?
    let distance: Double?
    let movingTime: Double?
    let totalElevationGain: Double?
    let averageSpeed: Double?
    let gearId: String?
    let totalPhotoCount: Int?
    let polyline: String?

    var date: Date? { TempoFormat.date(from: startDateLocal) }
    var distanceKm: Double { max(0, distance ?? 0) / 1_000 }
    var movingSeconds: Double { max(0, movingTime ?? 0) }
    var elevationMeters: Double { max(0, totalElevationGain ?? 0) }
    var speedKmh: Double { max(0, averageSpeed ?? 0) * 3.6 }
    var route: [CLLocationCoordinate2D] { PolylineDecoder.decode(polyline ?? "") }
    var sport: TempoSport { TempoSport(rawValue: type ?? "") }
}

struct TempoWorkoutHealthSignal: Codable, Equatable {
    let heartRateSampleCount: Int
    let averageHeartRateBpm: Double?
    let peakHeartRateBpm: Double?
    let baselineHeartRateBpm: Double?
    let stepsDuringWorkout: Int?
    let stepsBeforeWorkout: Int?
    let phoneStepsDuringWorkout: Int?
    let phoneStepsBeforeWorkout: Int?
    let movementIncreaseDetected: Bool
    let averageRespiratoryRatePerMinute: Double?
    let baselineRespiratoryRatePerMinute: Double?
    let activeEnergyKcal: Double?
    let exerciseMinutes: Double?
    let matchedHealthWorkoutMinutes: Int?
    let checkedAt: Date

    var heartRateRiseBpm: Double? {
        guard let averageHeartRateBpm, let baselineHeartRateBpm else { return nil }
        return averageHeartRateBpm - baselineHeartRateBpm
    }

    func stepDifferenceAdjustedForWorkout(durationMinutes: Int) -> Int? {
        let currentSteps: Int
        let priorSteps: Int
        if let phoneStepsDuringWorkout, let phoneStepsBeforeWorkout {
            currentSteps = phoneStepsDuringWorkout
            priorSteps = phoneStepsBeforeWorkout
        } else if let stepsDuringWorkout, let stepsBeforeWorkout {
            currentSteps = stepsDuringWorkout
            priorSteps = stepsBeforeWorkout
        } else {
            return nil
        }
        let expectedSteps = Double(priorSteps) * Double(max(durationMinutes, 1)) / 20
        return currentSteps - Int(expectedSteps.rounded())
    }

    var supportingSignalScore: Double {
        let measuredSteps = max(stepsDuringWorkout ?? 0, phoneStepsDuringWorkout ?? 0)
        var score = 0.0
        if matchedHealthWorkoutMinutes != nil { score += 3 }
        if movementIncreaseDetected { score += 2 }
        else if measuredSteps >= 120 { score += 1.5 }
        if heartRateSampleCount >= 2 && ((heartRateRiseBpm ?? 0) >= 8 || (averageHeartRateBpm ?? 0) >= 105) {
            score += 2
        }
        if (respiratoryRateRisePerMinute ?? 0) >= 2 { score += 1.5 }
        if (activeEnergyKcal ?? 0) >= 20 { score += 1 }
        if (exerciseMinutes ?? 0) >= 5 { score += 1 }
        return score
    }

    var hasSupportingMeasurement: Bool {
        supportingSignalScore >= 2
    }

    var respiratoryRateRisePerMinute: Double? {
        guard let averageRespiratoryRatePerMinute, let baselineRespiratoryRatePerMinute else { return nil }
        return averageRespiratoryRatePerMinute - baselineRespiratoryRatePerMinute
    }
}

struct TempoManualWorkout: Codable, Identifiable, Equatable {
    let id: UUID
    let sportId: String
    let sportTitle: String
    let title: String
    let startedAt: Date
    let durationMinutes: Int
    let notes: String
    let photoFilename: String?
    let healthSignal: TempoWorkoutHealthSignal?
    let durationSeconds: Int?
    let distanceKm: Double?
    let routeCoordinates: [TempoCoordinate]?
    let recordSource: String?
    let perceivedEffort: Int?
    let enjoyment: Int?

    var endedAt: Date { startedAt.addingTimeInterval(Double(durationSeconds ?? durationMinutes * 60)) }
}

struct TempoCoordinate: Codable, Equatable {
    let latitude: Double
    let longitude: Double
}

enum TempoSport: Hashable {
    case run, ride, walk, hike, swim, tennis, basketball, football, volleyball, padel, badminton, yoga, workout, other

    init(rawValue: String) {
        let value = rawValue.lowercased()
        if value.contains("run") { self = .run }
        else if value.contains("ride") || value.contains("cycl") || value.contains("bike") { self = .ride }
        else if value.contains("walk") { self = .walk }
        else if value.contains("hike") { self = .hike }
        else if value.contains("swim") { self = .swim }
        else if value.contains("tennis") { self = .tennis }
        else if value.contains("basketball") { self = .basketball }
        else if value.contains("soccer") || value.contains("football") { self = .football }
        else if value.contains("volleyball") { self = .volleyball }
        else if value.contains("padel") { self = .padel }
        else if value.contains("badminton") { self = .badminton }
        else if value.contains("yoga") { self = .yoga }
        else if value.contains("workout") || value.contains("weight") || value.contains("crossfit") { self = .workout }
        else { self = .other }
    }

    var title: String {
        switch self {
        case .run: return "Koşu".tempoLocalized
        case .ride: return "Bisiklet".tempoLocalized
        case .walk: return "Yürüyüş".tempoLocalized
        case .hike: return "Doğa yürüyüşü".tempoLocalized
        case .swim: return "Yüzme".tempoLocalized
        case .tennis: return "Tenis".tempoLocalized
        case .basketball: return "Basketbol".tempoLocalized
        case .football: return "Futbol".tempoLocalized
        case .volleyball: return "Voleybol".tempoLocalized
        case .padel: return "Padel".tempoLocalized
        case .badminton: return "Badminton".tempoLocalized
        case .yoga: return "Yoga".tempoLocalized
        case .workout: return "Antrenman".tempoLocalized
        case .other: return "Aktivite".tempoLocalized
        }
    }

    var symbol: String {
        switch self {
        case .run: return "figure.run"
        case .ride: return "bicycle"
        case .walk: return "figure.walk"
        case .hike: return "figure.hiking"
        case .swim: return "figure.pool.swim"
        case .tennis: return "tennis.racket"
        case .basketball: return "basketball.fill"
        case .football: return "soccerball"
        case .volleyball: return "volleyball.fill"
        case .padel: return "figure.racquetball"
        case .badminton: return "figure.badminton"
        case .yoga: return "figure.yoga"
        case .workout: return "dumbbell.fill"
        case .other: return "figure.mixed.cardio"
        }
    }
}


struct TempoAchievement: Codable {
    let level: Int
    let title: String
    let totalXp: Int
    let currentLevelXp: Int
    let nextLevelXp: Int
    let progress: Double
    let unlockedBadgeCount: Int
    let totalBadgeCount: Int
    let badges: [TempoBadge]

    static let empty = TempoAchievement(
        level: 1,
        title: "Başlangıç",
        totalXp: 0,
        currentLevelXp: 0,
        nextLevelXp: 200,
        progress: 0,
        unlockedBadgeCount: 0,
        totalBadgeCount: 0,
        badges: []
    )

    var safeProgress: Double { min(max(progress, 0), 1) }
    var unlockedBadges: [TempoBadge] { badges.filter(\.unlocked) }
}

struct TempoBadge: Codable, Identifiable {
    let id: String
    let title: String
    let description: String
    let symbol: String
    let tint: String
    let unlocked: Bool
    let progress: Double
    let current: Double
    let target: Double
    let unit: String

    var safeProgress: Double { min(max(progress, 0), 1) }
}

struct TempoMonthStat: Identifiable {
    let date: Date
    var distanceKm: Double
    var count: Int
    var seconds: Double
    var id: Date { date }
}

struct TempoCoachResponse: Decodable {
    let answer: String?
    let period: String?
    let detailedActivityCount: Int?
    let periodActivityCount: Int?
    let error: String?
}

struct TempoCoachMessage: Identifiable, Equatable {
    let id: UUID
    let role: String
    let content: String

    init(role: String, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
    }
}

struct TempoSocialProfile: Decodable, Identifiable, Equatable {
    let id: String
    let username: String
    let displayName: String
    let avatarBase64: String?
}

struct TempoSocialRequest: Decodable, Identifiable {
    let id: String
    let createdAt: String
    let user: TempoSocialProfile
}

struct TempoSocialParticipant: Decodable, Identifiable {
    let userId: String
    let status: String
    let shareHealth: Bool
    let user: TempoSocialProfile
    let score: Int?
    var id: String { userId }
}

struct TempoSocialChallenge: Decodable, Identifiable {
    let id: String
    let myUserId: String
    let title: String
    let metric: String
    let startsAt: String
    let endsAt: String
    let myStatus: String
    let myShareHealth: Bool
    let participants: [TempoSocialParticipant]
}

struct TempoSocialSnapshot: Decodable {
    let profile: TempoSocialProfile?
    let friends: [TempoSocialProfile]
    let incoming: [TempoSocialRequest]
    let outgoing: [TempoSocialRequest]
    let challenges: [TempoSocialChallenge]
    let blocked: [TempoSocialProfile]

    private enum CodingKeys: String, CodingKey { case profile, friends, incoming, outgoing, challenges, blocked }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        profile = try values.decodeIfPresent(TempoSocialProfile.self, forKey: .profile)
        friends = try values.decodeIfPresent([TempoSocialProfile].self, forKey: .friends) ?? []
        incoming = try values.decodeIfPresent([TempoSocialRequest].self, forKey: .incoming) ?? []
        outgoing = try values.decodeIfPresent([TempoSocialRequest].self, forKey: .outgoing) ?? []
        challenges = try values.decodeIfPresent([TempoSocialChallenge].self, forKey: .challenges) ?? []
        blocked = try values.decodeIfPresent([TempoSocialProfile].self, forKey: .blocked) ?? []
    }
}

enum TempoSocialMetric: String, CaseIterable, Identifiable {
    case steps
    case exerciseMinutes
    case movementDays
    var id: String { rawValue }
    var title: String {
        switch self {
        case .steps: return "Adımlar".tempoLocalized
        case .exerciseMinutes: return "Egzersiz dakikası".tempoLocalized
        case .movementDays: return "Hareket edilen gün".tempoLocalized
        }
    }
    var symbol: String {
        switch self {
        case .steps: return "figure.walk"
        case .exerciseMinutes: return "figure.run"
        case .movementDays: return "calendar.badge.checkmark"
        }
    }
    var unit: String {
        switch self {
        case .steps: return "adım".tempoLocalized
        case .exerciseMinutes: return "dk"
        case .movementDays: return "gün".tempoLocalized
        }
    }
}

struct TempoHealthMetrics: Codable, Equatable {
    var waterMl: Double?
    var sleepMinutes: Double?
    var sleepCoreMinutes: Double?
    var sleepDeepMinutes: Double?
    var sleepREMMinutes: Double?
    var sleepAwakeMinutes: Double?
    var steps: Double?
    var activeEnergyKcal: Double?
    var exerciseMinutes: Double?
    var restingHeartRateBpm: Double?
    var hrvMs: Double?
    var respiratoryRate: Double?
    var oxygenSaturationPct: Double?
    var vo2Max: Double?
    var walkingHeartRateBpm: Double?
    var heartRateRecoveryBpm: Double?
    var wristTemperatureC: Double?
    var bodyMassKg: Double?

    init(
        waterMl: Double? = nil,
        sleepMinutes: Double? = nil,
        sleepCoreMinutes: Double? = nil,
        sleepDeepMinutes: Double? = nil,
        sleepREMMinutes: Double? = nil,
        sleepAwakeMinutes: Double? = nil,
        steps: Double? = nil,
        activeEnergyKcal: Double? = nil,
        exerciseMinutes: Double? = nil,
        restingHeartRateBpm: Double? = nil,
        hrvMs: Double? = nil,
        respiratoryRate: Double? = nil,
        oxygenSaturationPct: Double? = nil,
        vo2Max: Double? = nil,
        walkingHeartRateBpm: Double? = nil,
        heartRateRecoveryBpm: Double? = nil,
        wristTemperatureC: Double? = nil,
        bodyMassKg: Double? = nil
    ) {
        self.waterMl = waterMl
        self.sleepMinutes = sleepMinutes
        self.sleepCoreMinutes = sleepCoreMinutes
        self.sleepDeepMinutes = sleepDeepMinutes
        self.sleepREMMinutes = sleepREMMinutes
        self.sleepAwakeMinutes = sleepAwakeMinutes
        self.steps = steps
        self.activeEnergyKcal = activeEnergyKcal
        self.exerciseMinutes = exerciseMinutes
        self.restingHeartRateBpm = restingHeartRateBpm
        self.hrvMs = hrvMs
        self.respiratoryRate = respiratoryRate
        self.oxygenSaturationPct = oxygenSaturationPct
        self.vo2Max = vo2Max
        self.walkingHeartRateBpm = walkingHeartRateBpm
        self.heartRateRecoveryBpm = heartRateRecoveryBpm
        self.wristTemperatureC = wristTemperatureC
        self.bodyMassKg = bodyMassKg
    }

    var hasData: Bool {
        [
            waterMl, sleepMinutes, sleepCoreMinutes, sleepDeepMinutes, sleepREMMinutes, sleepAwakeMinutes,
            steps, activeEnergyKcal, exerciseMinutes, restingHeartRateBpm, hrvMs, respiratoryRate,
            oxygenSaturationPct, vo2Max, walkingHeartRateBpm, heartRateRecoveryBpm, wristTemperatureC,
            bodyMassKg,
        ].contains { $0 != nil }
    }
}

struct TempoSleepFactor: Identifiable, Equatable {
    let id: String
    let title: String
    let value: String
    let score: Int
    let symbol: String
}

struct TempoSleepAssessment: Equatable {
    let value: Int
    let state: String
    let summary: String
    let confidence: String
    let factors: [TempoSleepFactor]

    static func evaluate(_ metrics: TempoHealthMetrics) -> TempoSleepAssessment? {
        guard let totalMinutes = metrics.sleepMinutes, totalMinutes > 0 else { return nil }
        var weighted: [(TempoSleepFactor, Double)] = []

        let durationScore = scoreDuration(totalMinutes)
        weighted.append((
            TempoSleepFactor(
                id: "duration",
                title: "Toplam uyku",
                value: TempoFormat.duration(totalMinutes * 60),
                score: durationScore,
                symbol: "clock.fill"
            ),
            0.50
        ))

        if let deep = metrics.sleepDeepMinutes, deep >= 0 {
            let ratio = deep / totalMinutes
            weighted.append((
                TempoSleepFactor(
                    id: "deep",
                    title: "Derin uyku",
                    value: stageValue(deep, total: totalMinutes),
                    score: ratioScore(ratio, ideal: 0.13...0.23, hard: 0.03...0.38),
                    symbol: "moon.stars.fill"
                ),
                0.14
            ))
        }

        if let rem = metrics.sleepREMMinutes, rem >= 0 {
            let ratio = rem / totalMinutes
            weighted.append((
                TempoSleepFactor(
                    id: "rem",
                    title: "REM uykusu",
                    value: stageValue(rem, total: totalMinutes),
                    score: ratioScore(ratio, ideal: 0.20...0.30, hard: 0.07...0.45),
                    symbol: "brain.head.profile"
                ),
                0.14
            ))
        }

        let restorativeMinutes = (metrics.sleepDeepMinutes ?? 0) + (metrics.sleepREMMinutes ?? 0)
        if metrics.sleepDeepMinutes != nil || metrics.sleepREMMinutes != nil {
            let ratio = restorativeMinutes / totalMinutes
            weighted.append((
                TempoSleepFactor(
                    id: "restorative",
                    title: "Onarıcı uyku",
                    value: stageValue(restorativeMinutes, total: totalMinutes),
                    score: ratioScore(ratio, ideal: 0.33...0.53, hard: 0.15...0.70),
                    symbol: "sparkles"
                ),
                0.12
            ))
        }

        if let awake = metrics.sleepAwakeMinutes, awake >= 0 {
            let timeInBed = totalMinutes + awake
            let efficiency = timeInBed > 0 ? totalMinutes / timeInBed : 0
            weighted.append((
                TempoSleepFactor(
                    id: "continuity",
                    title: "Uyku devamlılığı",
                    value: "\(Int((efficiency * 100).rounded()))%",
                    score: continuityScore(efficiency),
                    symbol: "waveform.path.ecg"
                ),
                0.10
            ))
        }

        let totalWeight = weighted.reduce(0) { $0 + $1.1 }
        let score = bounded(weighted.reduce(0) { $0 + Double($1.0.score) * $1.1 } / totalWeight)
        let state: String
        let summary: String
        switch score {
        case 88...:
            state = "Çok iyi uyku"
            summary = "Süre ve uyku evrelerin güçlü bir geceye işaret ediyor."
        case 75..<88:
            state = "İyi uyku"
            summary = "Genel uyku düzenin dengeli; küçük iyileştirmelerle daha da güçlenebilir."
        case 60..<75:
            state = "Orta düzey uyku"
            summary = "Toparlanma var ancak süre veya uyku evrelerinden biri hedefin altında."
        case 45..<60:
            state = "Düşük uyku"
            summary = "Bugün antrenman yoğunluğunu seçerken uykunun sınırlı olduğunu hesaba kat."
        default:
            state = "Zayıf uyku"
            summary = "Uyku süreni ve gece devamlılığını geliştirmeye öncelik verebilirsin."
        }

        let stageCount = [metrics.sleepCoreMinutes, metrics.sleepDeepMinutes, metrics.sleepREMMinutes, metrics.sleepAwakeMinutes]
            .compactMap { $0 }.count
        let confidence = stageCount >= 4 ? "Tüm evrelerle hesaplandı" : (stageCount >= 2 ? "Kısmi evre verisi" : "Yalnızca süre verisi")
        return TempoSleepAssessment(value: score, state: state, summary: summary, confidence: confidence, factors: weighted.map { $0.0 })
    }

    private static func scoreDuration(_ minutes: Double) -> Int {
        let hours = minutes / 60
        switch hours {
        case ..<4.5: return bounded(18 + hours * 6)
        case 4.5..<6: return bounded(45 + (hours - 4.5) * 18)
        case 6..<7: return bounded(72 + (hours - 6) * 23)
        case 7...9: return 100
        case 9..<10: return bounded(100 - (hours - 9) * 12)
        default: return bounded(88 - (hours - 10) * 12)
        }
    }

    private static func ratioScore(_ value: Double, ideal: ClosedRange<Double>, hard: ClosedRange<Double>) -> Int {
        if ideal.contains(value) { return 100 }
        if value < ideal.lowerBound {
            guard value > hard.lowerBound else { return 25 }
            let progress = (value - hard.lowerBound) / (ideal.lowerBound - hard.lowerBound)
            return bounded(25 + progress * 75)
        }
        guard value < hard.upperBound else { return 35 }
        let progress = (hard.upperBound - value) / (hard.upperBound - ideal.upperBound)
        return bounded(35 + progress * 65)
    }

    private static func continuityScore(_ efficiency: Double) -> Int {
        switch efficiency {
        case 0.90...: return 100
        case 0.82..<0.90: return bounded(72 + (efficiency - 0.82) / 0.08 * 28)
        case 0.70..<0.82: return bounded(42 + (efficiency - 0.70) / 0.12 * 30)
        default: return bounded(15 + efficiency / 0.70 * 27)
        }
    }

    private static func stageValue(_ minutes: Double, total: Double) -> String {
        let percentage = total > 0 ? Int((minutes / total * 100).rounded()) : 0
        return "\(TempoFormat.duration(minutes * 60)) · \(percentage)%"
    }

    private static func bounded(_ value: Double) -> Int {
        Int(min(max(value, 0), 100).rounded())
    }
}

struct TempoBalanceFactor: Identifiable, Equatable {
    let id: String
    let title: String
    let value: String
    let score: Int
    let symbol: String
    let tint: String
}

struct TempoBalanceScore: Equatable {
    let value: Int
    let state: String
    let recommendation: String
    let confidence: String
    let factors: [TempoBalanceFactor]
}

struct TempoHealthSyncPayload: Encodable {
    let days: [String: TempoHealthMetrics]
}

enum TempoFormat {
    private static let isoWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let iso = ISO8601DateFormatter()

    static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        return isoWithFractional.date(from: value) ?? iso.date(from: value) ?? dayFormatter.date(from: String(value.prefix(10)))
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "d MMM"
        return formatter
    }()
    static let longDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "d MMMM yyyy"
        return formatter
    }()
    static let month: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "MMM"
        return formatter
    }()
    static let monthLong: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "MMMM"
        return formatter
    }()

    static func distance(_ kilometers: Double) -> String {
        kilometers.formatted(.number.locale(.autoupdatingCurrent).precision(.fractionLength(1))) + " km"
    }
    static func duration(_ seconds: Double) -> String {
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0
            ? "%d sa %d dk".tempoFormatted(hours, minutes)
            : "%d dk".tempoFormatted(minutes)
    }
}

enum PolylineDecoder {
    static func decode(_ encoded: String) -> [CLLocationCoordinate2D] {
        guard !encoded.isEmpty else { return [] }
        let bytes = Array(encoded.utf8)
        var coordinates: [CLLocationCoordinate2D] = []
        var index = 0
        var latitude = 0
        var longitude = 0
        while index < bytes.count {
            guard let latChange = readValue(bytes, index: &index), let lonChange = readValue(bytes, index: &index) else { break }
            latitude += latChange
            longitude += lonChange
            coordinates.append(CLLocationCoordinate2D(latitude: Double(latitude) / 100_000, longitude: Double(longitude) / 100_000))
        }
        return coordinates
    }

    private static func readValue(_ bytes: [UInt8], index: inout Int) -> Int? {
        var result = 0
        var shift = 0
        var byte: Int
        repeat {
            guard index < bytes.count else { return nil }
            byte = Int(bytes[index]) - 63
            index += 1
            result |= (byte & 0x1f) << shift
            shift += 5
        } while byte >= 0x20
        return (result & 1) == 1 ? ~(result >> 1) : (result >> 1)
    }
}
