import Foundation

/// Sinyal tabanlı bir öneridir; sporun yapıldığına dair doğrulama veya tıbbi değerlendirme değildir.
struct DetectedWorkout: Codable, Identifiable, Equatable, Sendable {
    enum Origin: String, Codable, Sendable { case phone, health }
    enum Decision: String, Codable, Sendable { case pending, accepted, dismissed }
    let id: UUID
    let start: Date
    let end: Date
    let origin: Origin
    let suggestedSport: String
    var steps: Int?
    var distanceMeters: Double?
    var averageHeartRate: Double?
    var activeEnergy: Double?
    var decision: Decision = .pending
    var notified = false
    var seconds: Double { end.timeIntervalSince(start) }
}

struct DetectionInterval: Codable, Hashable, Sendable {
    let start: Date
    let end: Date
}

enum WorkoutDetectionEngine {
    enum MotionKind: Sendable { case walking, running, vehicle, other }
    struct MotionSlice: Sendable {
        let start: Date
        let end: Date
        let kind: MotionKind
        let reliable: Bool
    }
    struct MotionWindow: Sendable {
        let start: Date
        let end: Date
        let running: Bool
        let activeSeconds: Double
    }
    struct HealthBin: Sendable {
        let start: Date
        let heartRate: Double?
        let heartRateCount: Int
        let energyKcal: Double
        let steps: Double
        let exerciseSeconds: Double
    }

    /// Kısa duraklamalar korunur; araç ve güvenilmez sınıflandırmalar pencereyi böler.
    static func motionWindows(_ slices: [MotionSlice]) -> [MotionWindow] {
        var output: [MotionWindow] = []
        var current: MotionWindow?
        func flush() { if let value = current { output.append(value) }; current = nil }
        for slice in slices.sorted(by: { $0.start < $1.start }) {
            guard slice.start.timeIntervalSince1970.isFinite, slice.end.timeIntervalSince1970.isFinite, slice.end > slice.start else { continue }
            let active = slice.reliable && (slice.kind == .walking || slice.kind == .running)
            if !active {
                if slice.kind == .vehicle || !slice.reliable || slice.end.timeIntervalSince(slice.start) > 120 { flush() }
                continue
            }
            if let value = current, slice.start.timeIntervalSince(value.end) <= 120, slice.start >= value.end {
                current = MotionWindow(start: value.start, end: slice.end, running: value.running || slice.kind == .running, activeSeconds: value.activeSeconds + slice.end.timeIntervalSince(slice.start))
            } else {
                flush()
                current = MotionWindow(start: slice.start, end: slice.end, running: slice.kind == .running, activeSeconds: slice.end.timeIntervalSince(slice.start))
            }
        }
        flush()
        return output.filter { window in
            let duration = window.end.timeIntervalSince(window.start)
            return duration >= 15 * 60 && duration <= 4 * 3600 && window.activeSeconds / duration >= 0.8
        }
    }

    static func phoneCandidate(_ window: MotionWindow, steps: Int, distance: Double?) -> DetectedWorkout? {
        let duration = window.end.timeIntervalSince(window.start)
        guard duration.isFinite, duration >= 900, duration <= 4 * 3600 else { return nil }
        let cadence = Double(steps) / (duration / 60)
        // Koşu sınıfına kısa geçiş, tüm yürüyüşü koşuya çevirmesin.
        let running = window.running && cadence >= 110
        guard cadence >= 70, cadence <= 230, window.activeSeconds / duration >= 0.8 else { return nil }
        if let distance {
            guard distance.isFinite, distance >= 0, distance / duration <= (running ? 7 : 3.5) else { return nil }
        }
        return DetectedWorkout(id: UUID(), start: window.start, end: window.end, origin: .phone, suggestedSport: running ? "run" : "walking", steps: steps, distanceMeters: distance)
    }

    /// Tek bir yüksek nabız örneği yeterli değildir: en az 15 dakika, çoklu nabız örneği ve enerji/hareket desteği gerekir.
    static func healthCandidates(_ bins: [HealthBin], restingHeartRate: Double?) -> [DetectedWorkout] {
        let baseline = restingHeartRate.flatMap { $0.isFinite && (35...100).contains($0) ? $0 : nil } ?? 70
        let threshold = max(105, baseline + 35)
        var result: [DetectedWorkout] = []
        var session: [HealthBin] = []
        func qualifies(_ bin: HealthBin) -> Bool {
            guard let hr = bin.heartRate, hr.isFinite, hr >= threshold, hr <= 220, bin.heartRateCount >= 2 else { return false }
            return bin.energyKcal >= 15 && (bin.steps >= 150 || bin.exerciseSeconds >= 120 || bin.energyKcal >= 25)
        }
        func flush() {
            defer { session = [] }
            let active = session.filter(qualifies)
            guard let first = active.first, let last = active.last else { return }
            let end = last.start.addingTimeInterval(300)
            let duration = end.timeIntervalSince(first.start)
            guard active.count >= 3, duration >= 900, duration <= 3 * 3600, Double(active.count) * 300 / duration >= 0.75 else { return }
            let measured = session.filter { $0.start >= first.start && $0.start < end }
            let rateCount = active.reduce(0) { $0 + $1.heartRateCount }
            let average = active.reduce(0.0) { $0 + ($1.heartRate ?? 0) * Double($1.heartRateCount) } / Double(rateCount)
            result.append(DetectedWorkout(id: UUID(), start: first.start, end: end, origin: .health, suggestedSport: "fitness", steps: Int(measured.reduce(0) { $0 + $1.steps }), averageHeartRate: average, activeEnergy: measured.reduce(0) { $0 + $1.energyKcal }))
        }
        for bin in bins.sorted(by: { $0.start < $1.start }) {
            guard bin.start.timeIntervalSince1970.isFinite, bin.energyKcal.isFinite, (0...250).contains(bin.energyKcal),
                  bin.steps.isFinite, (0...2000).contains(bin.steps), bin.exerciseSeconds.isFinite, (0...300).contains(bin.exerciseSeconds),
                  bin.heartRateCount >= 0, bin.heartRate.map({ $0.isFinite }) ?? true else { flush(); continue }
            if let last = session.last, bin.start.timeIntervalSince(last.start) > 301 { flush() }
            if qualifies(bin) { session.append(bin) }
            else if !session.isEmpty, session.last.map(qualifies) == true { session.append(bin) }
            else { flush() }
        }
        flush()
        return result
    }

    static func overlaps(_ start: Date, _ end: Date, _ other: DetectionInterval) -> Bool {
        let overlap = min(end, other.end).timeIntervalSince(max(start, other.start))
        let shorter = min(end.timeIntervalSince(start), other.end.timeIntervalSince(other.start))
        return shorter > 0 && overlap > 0 && (overlap / shorter >= 0.5 || overlap >= 10 * 60)
    }

    static func fresh(_ candidates: [DetectedWorkout], existing: [DetectionInterval], history: [DetectedWorkout], now: Date) -> [DetectedWorkout] {
        var accepted: [DetectedWorkout] = []
        for candidate in candidates.sorted(by: { $0.origin == .phone && $1.origin == .health }) {
            guard candidate.start >= now.addingTimeInterval(-48 * 3600), candidate.end <= now,
                  !existing.contains(where: { overlaps(candidate.start, candidate.end, $0) }),
                  !(history + accepted).contains(where: { overlaps(candidate.start, candidate.end, DetectionInterval(start: $0.start, end: $0.end)) }) else { continue }
            accepted.append(candidate)
        }
        return accepted
    }
}
