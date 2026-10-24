import Foundation

/// HealthKit adapters supply values here so the exact aggregation can also run without a device.
enum TempoSleepStage: Int {
    case unspecified, core, deep, rem, awake

    var isAsleep: Bool { self != .awake }
    var isDetailed: Bool { self == .core || self == .deep || self == .rem }
}

struct TempoSleepInterval {
    let start: Date
    let end: Date
    let stage: TempoSleepStage
    let source: String
}

struct TempoSleepBreakdown: Equatable {
    let totalMinutes: Double
    let coreMinutes: Double?
    let deepMinutes: Double?
    let remMinutes: Double?
    let awakeMinutes: Double?
}

enum TempoSleepAggregation {
    /// A night belongs to its wake date. Samples on either side of midnight stay in one session.
    /// Three hours without any sleep/awake sample starts a new session, including daytime naps.
    static func dailyBreakdown(
        _ samples: [TempoSleepInterval], from start: Date, to end: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [String: TempoSleepBreakdown] {
        guard start < end else { return [:] }
        let valid = samples.compactMap { sample -> TempoSleepInterval? in
            let clippedEnd = min(sample.end, end)
            guard sample.start < clippedEnd else { return nil }
            return TempoSleepInterval(start: sample.start, end: clippedEnd, stage: sample.stage, source: sample.source)
        }.sorted { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }

        var sessions: [[TempoSleepInterval]] = []
        var sessionEnd: Date?
        for sample in valid {
            if let previousEnd = sessionEnd, sample.start.timeIntervalSince(previousEnd) <= 3 * 60 * 60 {
                sessions[sessions.count - 1].append(sample)
                sessionEnd = max(previousEnd, sample.end)
            } else {
                sessions.append([sample])
                sessionEnd = sample.end
            }
        }

        var totals: [String: [TempoSleepStage: Double]] = [:]
        for session in sessions {
            // Leading/trailing awake samples cannot move a night's wake date to another day.
            guard let wake = session.filter({ $0.stage.isAsleep }).map(\.end).max(), wake >= start else { continue }
            let day = dayString(wake, calendar: calendar)
            // Detailed coverage gives a stable preference when sources disagree. Overlapping
            // records still contribute at most one stage at every instant.
            let coverage = Dictionary(grouping: session, by: \.source).mapValues { sourceSamples in
                mergedDuration(sourceSamples.filter { $0.stage.isDetailed })
            }
            let boundaries = Array(Set(session.flatMap { [$0.start, $0.end] })).sorted()
            guard boundaries.count > 1 else { continue }
            for index in 0..<(boundaries.count - 1) {
                let left = boundaries[index]
                let right = boundaries[index + 1]
                let candidates = session.filter { $0.start <= left && $0.end >= right }
                let selected = candidates.sorted { a, b in
                    // Generic asleep records are often an envelope for detailed stages.
                    if (a.stage == .unspecified) != (b.stage == .unspecified) { return a.stage != .unspecified }
                    let aCoverage = coverage[a.source] ?? 0
                    let bCoverage = coverage[b.source] ?? 0
                    if aCoverage != bCoverage { return aCoverage > bCoverage }
                    if a.source != b.source { return a.source < b.source }
                    if a.start != b.start { return a.start > b.start }
                    if (a.stage == .awake) != (b.stage == .awake) { return a.stage == .awake }
                    return a.stage.rawValue < b.stage.rawValue
                }.first
                guard let selected else { continue }
                totals[day, default: [:]][selected.stage, default: 0] += right.timeIntervalSince(left) / 60
            }
        }

        return totals.compactMapValues { stages in
            let total = stages.filter { $0.key.isAsleep }.values.reduce(0, +)
            guard total > 0 else { return nil }
            return TempoSleepBreakdown(
                totalMinutes: rounded(total), coreMinutes: stages[.core].map(rounded),
                deepMinutes: stages[.deep].map(rounded), remMinutes: stages[.rem].map(rounded),
                awakeMinutes: stages[.awake].map(rounded)
            )
        }
    }

    private static func dayString(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func rounded(_ value: Double) -> Double { (value * 10).rounded() / 10 }

    private static func mergedDuration(_ samples: [TempoSleepInterval]) -> TimeInterval {
        let sorted = samples.sorted { $0.start < $1.start }
        var seconds: TimeInterval = 0
        var active: DateInterval?
        for sample in sorted {
            if let interval = active, sample.start <= interval.end {
                active = DateInterval(start: interval.start, end: max(interval.end, sample.end))
            } else {
                seconds += active?.duration ?? 0
                active = DateInterval(start: sample.start, end: sample.end)
            }
        }
        return seconds + (active?.duration ?? 0)
    }
}
