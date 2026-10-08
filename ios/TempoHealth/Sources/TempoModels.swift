import CoreLocation
import Foundation

struct TempoDashboard: Decodable {
    let athlete: TempoAthlete
    let segments: [TempoSegment]
    let photos: [TempoPhoto]
    let achievement: TempoAchievement?
    let historyLimited: Bool
    let activities: [TempoActivity]
}

struct TempoAthlete: Decodable {
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

struct TempoGear: Decodable, Identifiable {
    let id: String
    let name: String?
    let distance: Double?
    let primary: Bool?
    let type: String?
}

struct TempoSegment: Decodable, Identifiable {
    let id: Int64
    let name: String?
    let distance: Double?
    let averageGrade: Double?
    let climbCategory: Int?
    let starCount: Int?
}

struct TempoPhoto: Decodable, Identifiable {
    let activityId: Int64
    let activityName: String?
    let image: String
    var id: Int64 { activityId }
}

struct TempoActivity: Decodable, Identifiable, Hashable {
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

enum TempoSport: Equatable {
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
        case .run: return "Koşu"
        case .ride: return "Bisiklet"
        case .walk: return "Yürüyüş"
        case .hike: return "Doğa yürüyüşü"
        case .swim: return "Yüzme"
        case .tennis: return "Tenis"
        case .basketball: return "Basketbol"
        case .football: return "Futbol"
        case .volleyball: return "Voleybol"
        case .padel: return "Padel"
        case .badminton: return "Badminton"
        case .yoga: return "Yoga"
        case .workout: return "Antrenman"
        case .other: return "Aktivite"
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


struct TempoAchievement: Decodable {
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

struct TempoBadge: Decodable, Identifiable {
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

struct TempoHealthMetrics: Codable, Equatable {
    var waterMl: Double?
    var sleepMinutes: Double?
    var steps: Double?
    var activeEnergyKcal: Double?
    var restingHeartRateBpm: Double?
    var hrvMs: Double?
    var bodyMassKg: Double?

    init(
        waterMl: Double? = nil,
        sleepMinutes: Double? = nil,
        steps: Double? = nil,
        activeEnergyKcal: Double? = nil,
        restingHeartRateBpm: Double? = nil,
        hrvMs: Double? = nil,
        bodyMassKg: Double? = nil
    ) {
        self.waterMl = waterMl
        self.sleepMinutes = sleepMinutes
        self.steps = steps
        self.activeEnergyKcal = activeEnergyKcal
        self.restingHeartRateBpm = restingHeartRateBpm
        self.hrvMs = hrvMs
        self.bodyMassKg = bodyMassKg
    }

    var hasData: Bool {
        [waterMl, sleepMinutes, steps, activeEnergyKcal, restingHeartRateBpm, hrvMs, bodyMassKg].contains { $0 != nil }
    }
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
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMM"
        return formatter
    }()
    static let longDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter
    }()
    static let month: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "MMM"
        return formatter
    }()
    static let monthLong: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "MMMM"
        return formatter
    }()

    static func distance(_ kilometers: Double) -> String {
        kilometers.formatted(.number.locale(Locale(identifier: "tr_TR")).precision(.fractionLength(1))) + " km"
    }
    static func duration(_ seconds: Double) -> String {
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours) sa \(minutes) dk" : "\(minutes) dk"
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
