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

    var isLocalRecord: Bool { recordSource != "apple-health" }
    var sourceTitle: String {
        switch recordSource {
        case "apple-health": return "Apple Sağlık".tempoLocalized
        case "phone-gps": return "iPhone GPS kaydı".tempoLocalized
        case "phone-timer": return "Telefonla süre kaydı · rota yok".tempoLocalized
        case "manual": return "Elle eklendi · doğrulanmadı".tempoLocalized
        default: return healthSignal == nil ? "Elle eklendi".tempoLocalized : "Elle eklendi · Sağlık sinyali".tempoLocalized
        }
    }
    var endedAt: Date { startedAt.addingTimeInterval(Double(durationSeconds ?? durationMinutes * 60)) }
}

struct TempoCoordinate: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    // Optional for compatibility with routes already stored on the device.
    let startsNewSegment: Bool?

    init(latitude: Double, longitude: Double, startsNewSegment: Bool? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.startsNewSegment = startsNewSegment
    }

    static func segments(_ route: [TempoCoordinate]) -> [[TempoCoordinate]] {
        var result: [[TempoCoordinate]] = []
        for point in route {
            if result.isEmpty || point.startsNewSegment == true { result.append([]) }
            result[result.count - 1].append(point)
        }
        return result.filter { $0.count >= 2 }
    }
}

enum TempoSport: Hashable {
    case run, ride, walk, hike, swim, tennis, basketball, football, volleyball, padel, badminton, yoga, workout, other

    init(rawValue: String) {
        let value = rawValue.lowercased()
        if value.contains("run") { self = .run }
        else if value.contains("ride") || value.contains("cycl") || value.contains("bike") { self = .ride }
        else if value.contains("walk") { self = .walk }
        else if value.contains("hik") { self = .hike }
        else if value.contains("swim") { self = .swim }
        else if value.contains("tennis") { self = .tennis }
        else if value.contains("basketball") { self = .basketball }
        else if value.contains("soccer") || value.contains("football") { self = .football }
        else if value.contains("volleyball") { self = .volleyball }
        else if value.contains("padel") { self = .padel }
        else if value.contains("badminton") { self = .badminton }
        else if value.contains("yoga") { self = .yoga }
        else if value.contains("workout") || value.contains("weight") || value.contains("crossfit") || value.contains("fitness") { self = .workout }
        else { self = .other }
    }

    var supportsDistance: Bool {
        switch self { case .run, .ride, .walk, .hike, .swim: return true; default: return false }
    }
    var supportsElevation: Bool {
        switch self { case .run, .ride, .walk, .hike: return true; default: return false }
    }
    func distanceText(_ kilometres: Double) -> String {
        if self == .swim {
            return "\((max(0, kilometres.isFinite ? kilometres : 0) * 1_000).formatted(.number.precision(.fractionLength(0)))) m"
        }
        return TempoFormat.distance(kilometres)
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

enum TempoAchievementFactory {
    private struct SportDefinition {
        let id: String
        let title: String
        let symbol: String
        let tint: String
        let distanceTargets: [Double]
        let longestTargets: [Double]
        let sessionTargets: [Double]
    }

    static func make(workouts: [TempoManualWorkout], healthDays: [String: TempoHealthMetrics]) -> TempoAchievement {
        let valid = workouts.filter { $0.durationMinutes > 0 }
        let calendar = Calendar.current
        var activeDays = Set(valid.map { calendar.startOfDay(for: $0.startedAt) })
        for (day, metrics) in healthDays where (metrics.steps ?? 0) >= 3_000 || (metrics.exerciseMinutes ?? 0) >= 10 {
            if let date = TempoFormat.date(from: day) { activeDays.insert(calendar.startOfDay(for: date)) }
        }
        let manualStreak = longestStreak(activeDays)
        let totalMinutes = valid.reduce(0.0) { $0 + Double($1.durationSeconds ?? $1.durationMinutes * 60) / 60 }
        let totalDistance = valid.reduce(0.0) { $0 + ($1.distanceKm ?? 0) }
        let earlyBirds = valid.filter { (4..<8).contains(calendar.component(.hour, from: $0.startedAt)) }.count
        let playedSports = Set(valid.map(\.sportId))
        let activeDaysCount = activeDays.count

        func badge(_ id: String, _ title: String, _ description: String, _ symbol: String, _ tint: String, _ current: Double, _ target: Double, _ unit: String) -> TempoBadge {
            TempoBadge(
                id: id, title: title, description: description, symbol: symbol, tint: tint,
                unlocked: current >= target,
                progress: target > 0 ? min(max(current / target, 0), 1) : 0,
                current: (current * 10).rounded() / 10,
                target: target,
                unit: unit
            )
        }

        var badges = [
            badge("first_activity", "İlk Tempo Antrenmanı", "Tempo’da ilk antrenmanını tamamla.", "flag.checkered", "green", Double(valid.count), 1, "aktivite"),
            badge("activity_10", "Ritim Yakala", "Tempo’da 10 antrenman kaydet.", "10.circle.fill", "blue", Double(valid.count), 10, "aktivite"),
            badge("activity_25", "İstikrar", "Tempo’da 25 antrenman kaydet.", "25.circle.fill", "green", Double(valid.count), 25, "aktivite"),
            badge("activity_50", "Aktif 50", "Tempo’da 50 antrenman kaydet.", "50.circle.fill", "purple", Double(valid.count), 50, "aktivite"),
            badge("activity_100", "Yüzler Kulübü", "Tempo’da 100 antrenman kaydet.", "trophy.fill", "orange", Double(valid.count), 100, "aktivite"),
            badge("active_10_hours", "10 Saat Hareket", "Tempo kayıtlarında 10 saat hareket et.", "clock.fill", "purple", totalMinutes / 60, 10, "saat"),
            badge("active_50_hours", "50 Saat Hareket", "Tempo kayıtlarında 50 saat hareket et.", "clock.badge.checkmark.fill", "blue", totalMinutes / 60, 50, "saat"),
            badge("active_100_hours", "Yüz Saat", "Tempo kayıtlarında 100 saat hareket et.", "hourglass.tophalf.filled", "green", totalMinutes / 60, 100, "saat"),
            badge("streak_3", "Üç Gün Seri", "Üç farklı günde hareket kaydet.", "flame.fill", "orange", Double(manualStreak), 3, "gün"),
            badge("streak_7", "Yedi Gün Seri", "Yedi farklı günde hareket kaydet.", "calendar.badge.checkmark", "green", Double(manualStreak), 7, "gün"),
            badge("movement_days_10", "10 Hareket Günü", "Apple Sağlık veya Tempo kaydında 10 hareket günü biriktir.", "figure.walk", "blue", Double(activeDaysCount), 10, "gün"),
            badge("multi_sport_3", "Çok Yönlü", "Üç farklı spor dalında Tempo antrenmanı kaydet.", "square.grid.2x2.fill", "pink", Double(playedSports.count), 3, "spor"),
            badge("early_bird", "Erken Kuş", "Saat 08.00’den önce beş Tempo antrenmanına başla.", "sunrise.fill", "orange", Double(earlyBirds), 5, "aktivite"),
            badge("century", "Uzun Rota", "Tempo GPS kaydında toplam 100 km tamamla.", "medal.fill", "green", totalDistance, 100, "km"),
        ]

        let definitions: [SportDefinition] = [
            .init(id: "run", title: "Koşu", symbol: "figure.run", tint: "orange", distanceTargets: [25, 50, 100, 250], longestTargets: [5, 10, 21.1], sessionTargets: []),
            .init(id: "ride", title: "Bisiklet", symbol: "bicycle", tint: "blue", distanceTargets: [100, 250, 500, 1000], longestTargets: [25, 50, 100], sessionTargets: []),
            .init(id: "walk", title: "Yürüyüş", symbol: "figure.walk", tint: "green", distanceTargets: [25, 100, 250, 500], longestTargets: [5, 10, 20], sessionTargets: []),
            .init(id: "hike", title: "Doğa Yürüyüşü", symbol: "figure.hiking", tint: "purple", distanceTargets: [25, 50, 100, 250], longestTargets: [5, 10, 20], sessionTargets: []),
            .init(id: "swim", title: "Yüzme", symbol: "figure.pool.swim", tint: "blue", distanceTargets: [5, 10, 25, 50], longestTargets: [1, 2, 5], sessionTargets: []),
            .init(id: "fitness", title: "Fitness", symbol: "dumbbell.fill", tint: "orange", distanceTargets: [], longestTargets: [], sessionTargets: [20, 45, 75, 120]),
            .init(id: "tennis", title: "Tenis", symbol: "tennis.racket", tint: "green", distanceTargets: [], longestTargets: [], sessionTargets: [20, 45, 75, 120]),
            .init(id: "basketball", title: "Basketbol", symbol: "basketball.fill", tint: "orange", distanceTargets: [], longestTargets: [], sessionTargets: [20, 45, 75, 120]),
            .init(id: "football", title: "Futbol", symbol: "soccerball", tint: "green", distanceTargets: [], longestTargets: [], sessionTargets: [20, 45, 75, 120]),
            .init(id: "volleyball", title: "Voleybol", symbol: "volleyball.fill", tint: "blue", distanceTargets: [], longestTargets: [], sessionTargets: [20, 45, 75, 120]),
            .init(id: "padel", title: "Padel", symbol: "figure.racquetball", tint: "purple", distanceTargets: [], longestTargets: [], sessionTargets: [20, 45, 75, 120]),
            .init(id: "badminton", title: "Badminton", symbol: "figure.badminton", tint: "blue", distanceTargets: [], longestTargets: [], sessionTargets: [20, 45, 75, 120]),
            .init(id: "yoga", title: "Yoga", symbol: "figure.yoga", tint: "pink", distanceTargets: [], longestTargets: [], sessionTargets: [15, 30, 45, 60]),
        ]

        for sport in definitions {
            let entries = valid.filter { achievementSportID($0.sportId) == sport.id }
            let hours = entries.reduce(0.0) { $0 + Double($1.durationSeconds ?? $1.durationMinutes * 60) / 3_600 }
            let distance = entries.reduce(0.0) { $0 + ($1.distanceKm ?? 0) }
            let longest = entries.map { $0.distanceKm ?? 0 }.max() ?? 0
            let maxMinutes = entries.map { Double($0.durationSeconds ?? $0.durationMinutes * 60) / 60 }.max() ?? 0
            let sportDays = Set(entries.map { calendar.startOfDay(for: $0.startedAt) })
            let streak = longestStreak(sportDays)
            let countTargets = [1, 5, 10, 25, 50]
            let hourTargets = [5, 15, 30, 50]
            let streakTargets = [3, 7, 14]
            for target in countTargets {
                badges.append(badge("\(sport.id)_count_\(target)", target == 1 ? "İlk \(sport.title)" : "\(sport.title) · \(target) Aktivite", "\(target) Tempo \(sport.title.lowercased()) kaydı tamamla.", sport.symbol, sport.tint, Double(entries.count), Double(target), "aktivite"))
            }
            for target in hourTargets {
                badges.append(badge("\(sport.id)_hours_\(target)", "\(sport.title) · \(target) Saat", "Tempo’da toplam \(target) saat \(sport.title.lowercased()) kaydet.", "clock.fill", sport.tint, hours, Double(target), "saat"))
            }
            for target in streakTargets {
                badges.append(badge("\(sport.id)_streak_\(target)", "\(sport.title) · \(target) Gün Seri", "\(target) ayrı günde \(sport.title.lowercased()) kaydet.", "flame.fill", sport.tint, Double(streak), Double(target), "gün"))
            }
            if sport.distanceTargets.isEmpty {
                for target in sport.sessionTargets {
                    badges.append(badge("\(sport.id)_single_\(Int(target))", "\(sport.title) · \(Int(target)) dk", "Tek bir Tempo kaydında \(Int(target)) dakika tamamla.", "stopwatch.fill", sport.tint, maxMinutes, target, "dk"))
                }
            } else {
                for target in sport.distanceTargets {
                    let token = String(target).replacingOccurrences(of: ".", with: "_")
                    badges.append(badge("\(sport.id)_distance_\(token)", "\(sport.title) · \(target) km", "Tempo GPS kayıtlarında toplam \(target) km \(sport.title.lowercased()).", sport.symbol, sport.tint, distance, target, "km"))
                }
                for target in sport.longestTargets {
                    let token = String(target).replacingOccurrences(of: ".", with: "_")
                    badges.append(badge("\(sport.id)_longest_\(token)", "\(sport.title) · Tek Seferde \(target) km", "Tek bir Tempo GPS kaydında \(target) km tamamla.", "medal.fill", sport.tint, longest, target, "km"))
                }
            }
        }

        let xp = valid.reduce(0) { total, workout in
            let minutes = Double(workout.durationSeconds ?? workout.durationMinutes * 60) / 60
            let distance = workout.distanceKm ?? 0
            return total + 25 + min(Int(minutes) * 2, 360) + min(Int(distance * 8), 300)
        }
        let level = (1...50).last { xp >= 100 * $0 * ($0 - 1) } ?? 1
        let levelStart = 100 * level * (level - 1)
        let nextThreshold = level < 50 ? 100 * (level + 1) * level : levelStart
        let levelSpan = max(nextThreshold - levelStart, 0)
        let progress = levelSpan > 0 ? min(Double(xp - levelStart) / Double(levelSpan), 1) : 1
        return TempoAchievement(
            level: level,
            title: achievementLevelTitle(level),
            totalXp: xp,
            currentLevelXp: max(xp - levelStart, 0),
            nextLevelXp: levelSpan,
            progress: progress,
            unlockedBadgeCount: badges.filter(\.unlocked).count,
            totalBadgeCount: badges.count,
            badges: badges
        )
    }

    private static func achievementSportID(_ value: String) -> String {
        switch value {
        case "cycling": return "ride"
        case "walking": return "walk"
        case "hiking": return "hike"
        case "swimming": return "swim"
        default: return value
        }
    }

    private static func longestStreak(_ dates: Set<Date>) -> Int {
        let sorted = dates.sorted()
        guard !sorted.isEmpty else { return 0 }
        var longest = 1
        var current = 1
        for pair in zip(sorted, sorted.dropFirst()) {
            if Calendar.current.dateComponents([.day], from: pair.0, to: pair.1).day == 1 {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        return longest
    }

    private static func achievementLevelTitle(_ level: Int) -> String {
        if level >= 40 { return "Efsane" }
        if level >= 25 { return "Zirve" }
        if level >= 15 { return "Dayanıklılık" }
        if level >= 8 { return "Atılım" }
        if level >= 3 { return "Ritim" }
        return "Başlangıç"
    }
}

typealias TempoMonthStat = TempoWorkoutLedger.MonthSummary

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
        if metrics.sleepDeepMinutes != nil && metrics.sleepREMMinutes != nil {
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
        var summary: String
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
        if stageCount == 0 {
            summary = "Bu değerlendirme yalnızca uyku sürene dayanıyor; uyku evreleri ölçülmemiş."
        }
        let confidence = stageCount >= 4 ? "Tüm evrelerle hesaplandı" : (stageCount >= 1 ? "Kısmi evre verisi" : "Yalnızca süre verisi")
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
        guard seconds.isFinite else { return "—" }
        let safeSeconds = min(max(seconds, 0), 365 * 24 * 60 * 60)
        if safeSeconds > 0 && safeSeconds < 60 { return "%d sn".tempoFormatted(max(1, Int(safeSeconds))) }
        let totalMinutes = Int(safeSeconds / 60)
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
