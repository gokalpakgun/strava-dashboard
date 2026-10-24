import Foundation

/// Merges only on-device Tempo and Apple Health records. Strava API data is
/// displayed independently and never enters these totals or this matching.
enum TempoWorkoutLedger {
    struct Record: Equatable {
        let id: UUID
        let sportID: String
        let startedAt: Date
        let seconds: Double
        let distanceKm: Double?
        let source: String
    }
    static func merge(_ records: [Record], now: Date = Date()) -> [Record] {
        let valid = records.filter { $0.seconds.isFinite && $0.seconds > 0 && ["manual", "phone-gps", "health-supported-manual", "apple-health"].contains($0.source) && $0.startedAt.timeIntervalSince1970.isFinite && $0.startedAt <= now && ($0.distanceKm == nil || ($0.distanceKm!.isFinite && $0.distanceKm! >= 0)) }
        let preferred = valid.sorted {
            let a = $0.source == "apple-health" ? 1 : 0
            let b = $1.source == "apple-health" ? 1 : 0
            if a != b { return a < b }
            if $0.startedAt != $1.startedAt { return $0.startedAt > $1.startedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        var result: [Record] = []
        var seen: Set<UUID> = []
        for record in preferred {
            guard seen.insert(record.id).inserted else { continue }
            let duplicate = result.contains { previous in
                // Keep separate local sets; match external copies conservatively.
                guard record.source == "apple-health" || previous.source == "apple-health",
                      previous.sportID == record.sportID,
                      abs(previous.startedAt.timeIntervalSince(record.startedAt)) <= 60,
                      abs(previous.seconds - record.seconds) <= max(60, min(180, max(previous.seconds, record.seconds) * 0.05)) else { return false }
                if let a = previous.distanceKm, let b = record.distanceKm, a > 0, b > 0 {
                    return abs(a - b) <= max(0.1, max(a, b) * 0.05)
                }
                return true
            }
            if !duplicate { result.append(record) }
        }
        return result.sorted { $0.startedAt == $1.startedAt ? $0.id.uuidString < $1.id.uuidString : $0.startedAt > $1.startedAt }
    }
    static func currentWeek(_ records: [Record], now: Date = Date(), calendar: Calendar = .current) -> [Record] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
        return records.filter { $0.startedAt >= week.start && $0.startedAt < week.end && $0.startedAt <= now }
    }
}
