import Foundation

enum SportType: String, Codable, CaseIterable, Sendable {
    case running, cycling, lifting, swimming, generic

    init(sportID: String, archetype: SportArchetype? = nil) {
        let key = sportID.lowercased().filter(\.isLetter)
        if archetype == .teamAndCourt || archetype == .combatAndMindBody { self = .generic }
        else if archetype == .strengthAndHypertrophy { self = .lifting }
        else if ["swim", "swimming", "openwaterswimming"].contains(key) { self = .swimming }
        else if ["run", "running", "trailrun", "virtualrun", "walk", "walking", "hike", "hiking", "wheelchairrunpace", "wheelchairwalkpace"].contains(key) { self = .running }
        else if ["ride", "cycling", "virtualride", "mountainbikeride", "gravelride", "ebikeride", "emountainbikeride", "handcycle", "handcycling"].contains(key) { self = .cycling }
        else if ["fitness", "weighttraining", "strengthtraining", "powerlifting", "calisthenics", "crossfit", "lifting"].contains(key) { self = .lifting }
        else { self = .generic }
    }
    init(from decoder: Decoder) throws {
        self = SportType(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .generic
    }
}

/// Tüm kaynakların kart sınırında kullandığı tek model. Depolama/API kayıtları göç ettirilmez.
/// Birimler: süre saniye, mesafe metre, hacim kg, enerji kcal, nabız bpm.
struct Workout: Codable, Identifiable, Sendable {
    let id: String
    let sportType: SportType
    let date: Date?
    let duration: TimeInterval
    var activeCalories: Double? = nil
    var avgHeartRate: Double? = nil
    var distance: Double? = nil
    var laps: Int? = nil
    var totalVolume: Double? = nil
    var title = ""
    var sportName = ""
    var symbol = "figure.mixed.cardio"
    var archetype: SportArchetype? = nil
    // Nabızdan üretilmez; mevcut efor motorunun set/RPE verisine dayanan model tahminidir.
    var estimatedMuscleLoad: Int? = nil

    var validDuration: Double? { Self.positive(duration).flatMap { $0 <= 604_800 ? $0 : nil } }
    var validDistance: Double? { Self.nonnegative(distance) }
    var validCalories: Double? { Self.nonnegative(activeCalories) }
    var validVolume: Double? { Self.nonnegative(totalVolume) }
    var validHeartRate: Double? { avgHeartRate.flatMap { $0.isFinite && (20...300).contains($0) ? $0 : nil } }
    var validLaps: Int? { laps.flatMap { (0...100_000).contains($0) ? $0 : nil } }
    var validMuscleLoad: Int? { estimatedMuscleLoad.flatMap { (0...100).contains($0) ? $0 : nil } }
    var paceSecondsPerKm: Double? {
        guard let seconds = validDuration, let meters = validDistance, meters > 0 else { return nil }
        return Self.positive(seconds / meters * 1_000).flatMap { $0 <= Double(Int.max / 4) ? $0 : nil }
    }
    var speedKmh: Double? {
        guard let seconds = validDuration, let meters = validDistance else { return nil }
        return Self.nonnegative(meters / seconds * 3.6)
    }
    private static func positive(_ value: Double?) -> Double? { value.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } }
    private static func nonnegative(_ value: Double?) -> Double? { value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } }
}
