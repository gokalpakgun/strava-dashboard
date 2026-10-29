import Foundation

struct TimedHeartRateReading: Sendable {
    let start: Date
    let end: Date
    let bpm: Double
}

struct HeartRateWorkoutWindow: Sendable, Equatable {
    let id: UUID
    let start: Date
    let end: Date
    let activeDurationSeconds: Double
    let activeIntervals: [DateInterval]
}

enum MaximumHeartRateReference: String, Codable, Sendable { case recorded90DayPeak, fallback190 }

struct HeartRateZoneEvidence: Codable, Equatable, Sendable {
    let maximumHeartRateBpm: Double
    let reference: MaximumHeartRateReference
    let observedSeconds: Double
    let belowZoneSeconds: Double
    let queryWasLimited: Bool
    var isValid: Bool {
        maximumHeartRateBpm.isFinite && (80...300).contains(maximumHeartRateBpm) && observedSeconds.isFinite && (0...604_800).contains(observedSeconds) && belowZoneSeconds.isFinite && (0...observedSeconds).contains(belowZoneSeconds)
    }
}

struct InferredHeartRateZones: Sendable {
    let seconds: [Double]
    let evidence: HeartRateZoneEvidence
}

struct HeartRateZoneCacheLookup: Sendable {
    let values: [UUID: InferredHeartRateZones]
    let pending: [HeartRateWorkoutWindow]
    let generation: Int
}

actor HeartRateZoneCache {
    private struct Entry {
        let window: HeartRateWorkoutWindow
        let referenceBpm: Double
        let reference: MaximumHeartRateReference
        let result: InferredHeartRateZones?
        let expires: Date
    }
    private var entries: [UUID: Entry] = [:]
    private var generation = 0
    func lookup(_ windows: [HeartRateWorkoutWindow], referenceBpm: Double, reference: MaximumHeartRateReference, now: Date, force: Bool) -> HeartRateZoneCacheLookup {
        entries = entries.filter { $0.value.expires > now }
        var values: [UUID: InferredHeartRateZones] = [:], pending: [HeartRateWorkoutWindow] = []
        for window in windows {
            if !force, let entry = entries[window.id], entry.window == window, entry.referenceBpm == referenceBpm, entry.reference == reference {
                if let value = entry.result { values[window.id] = value }
            } else { pending.append(window) }
        }
        return HeartRateZoneCacheLookup(values: values, pending: pending, generation: generation)
    }
    func save(_ results: [UUID: InferredHeartRateZones], windows: [HeartRateWorkoutWindow], referenceBpm: Double, reference: MaximumHeartRateReference, now: Date, generation expected: Int) {
        guard expected == generation else { return }
        if entries.count + windows.count > 2_000 { entries = [:] }
        for window in windows {
            let result = results[window.id]
            let sufficient = result.map { !$0.evidence.queryWasLimited && $0.evidence.observedSeconds >= window.activeDurationSeconds * 0.8 } ?? false
            let ttl: Double = sufficient && now.timeIntervalSince(window.end) > 7_200 ? 3_600 : 60
            entries[window.id] = Entry(window: window, referenceBpm: referenceBpm, reference: reference, result: result, expires: now.addingTimeInterval(ttl))
        }
    }
    func removeAll() { generation += 1; entries = [:] }
}

struct HeartRateZoneInference: Sendable {
    // Nokta örnekleri en fazla 30 saniye ileri taşınır; uzun ölçüm boşlukları doldurulmaz.
    var maximumSampleHoldSeconds = 30.0

    func infer(windows: [HeartRateWorkoutWindow], readings: [TimedHeartRateReading], recordedPeakBpm: Double?, queryWasLimited: Bool = false) -> [UUID: InferredHeartRateZones] {
        guard maximumSampleHoldSeconds.isFinite, (1...60).contains(maximumSampleHoldSeconds) else { return [:] }
        let ordered = readings.filter {
            $0.start.timeIntervalSince1970.isFinite && $0.end.timeIntervalSince1970.isFinite && $0.end >= $0.start && $0.bpm.isFinite && (20...300).contains($0.bpm)
        }.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end < $1.end }
            return $0.bpm < $1.bpm
        }
        var samples: [TimedHeartRateReading] = []
        for reading in ordered where samples.last?.start != reading.start { samples.append(reading) }
        let peak = recordedPeakBpm.flatMap { $0.isFinite && (80...300).contains($0) ? $0 : nil }
        let maximum = peak ?? 190
        var result: [UUID: InferredHeartRateZones] = [:]
        for window in windows {
            guard window.start.timeIntervalSince1970.isFinite, window.end.timeIntervalSince1970.isFinite, window.end > window.start,
                  window.activeDurationSeconds.isFinite, (1...604_800).contains(window.activeDurationSeconds) else { continue }
            let active = mergedIntervals(window.activeIntervals, start: window.start, end: window.end)
            var zones = Array(repeating: 0.0, count: 5)
            var observed = 0.0, below = 0.0
            var index = lowerBound(samples, date: window.start.addingTimeInterval(-maximumSampleHoldSeconds))
            while index < samples.count && samples[index].start < window.end {
                let sample = samples[index]
                let next = index + 1 < samples.count ? samples[index + 1].start : sample.start
                let measuredEnd = sample.end > sample.start ? sample.end : next
                let end = min(measuredEnd, sample.start.addingTimeInterval(maximumSampleHoldSeconds), next > sample.start ? next : measuredEnd, window.end)
                let start = max(sample.start, window.start)
                if end > start {
                    let seconds = active.reduce(0.0) { total, interval in total + max(0, min(end, interval.end).timeIntervalSince(max(start, interval.start))) }
                    observed += seconds
                    let fraction = sample.bpm / maximum
                    if fraction < 0.5 { below += seconds }
                    else {
                        let zone: Int = fraction < 0.6 ? 0 : fraction < 0.7 ? 1 : fraction < 0.8 ? 2 : fraction < 0.9 ? 3 : 4
                        zones[zone] += seconds
                    }
                }
                index += 1
            }
            // Duraklama bilgisi süreyle uyuşmuyorsa bölgeler ölçeklenerek uydurulmaz.
            guard observed > 0, observed <= window.activeDurationSeconds + 1 else { continue }
            result[window.id] = InferredHeartRateZones(seconds: zones, evidence: HeartRateZoneEvidence(maximumHeartRateBpm: maximum, reference: peak == nil ? .fallback190 : .recorded90DayPeak, observedSeconds: min(observed, window.activeDurationSeconds), belowZoneSeconds: min(below, observed, window.activeDurationSeconds), queryWasLimited: queryWasLimited))
        }
        return result
    }

    private func lowerBound(_ samples: [TimedHeartRateReading], date: Date) -> Int {
        var low = 0, high = samples.count
        while low < high { let middle = (low + high) / 2; if samples[middle].start < date { low = middle + 1 } else { high = middle } }
        return low
    }
    private func mergedIntervals(_ intervals: [DateInterval], start: Date, end: Date) -> [DateInterval] {
        var merged: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            let left = max(start, interval.start), right = min(end, interval.end)
            guard right > left else { continue }
            if let last = merged.last, last.end >= left { merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, right)) }
            else { merged.append(DateInterval(start: left, end: right)) }
        }
        return merged
    }
}
