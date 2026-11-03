import Foundation

enum PassiveActivityPattern: String, Codable, Sendable {
    case intervals, sustained, mixed, insufficient
}

struct PassiveLoadEstimate: Codable, Equatable, Sendable {
    let pattern: PassiveActivityPattern
    let strain: Int?
    let coverage: Double
    let weightedMinutes: Double
    let maximumHeartRateWasEstimated: Bool
}

enum PassiveWorkoutEngine {
    struct HeartRate: Sendable { let date: Date; let bpm: Double }

    /// Edwards tipi bölge ağırlığı, yalnız gözlenen aralıklarda birikir.
    /// Tempo v1 normalizasyonu klinik eşik veya doğrudan CNS ölçümü değildir.
    static func estimate(start: Date, end: Date, samples: [HeartRate], maximumHeartRate: Double? = nil) -> PassiveLoadEstimate {
        let duration = end.timeIntervalSince(start)
        let measuredMaximum = maximumHeartRate.flatMap { $0.isFinite && (120...230).contains($0) ? $0 : nil }
        let maximum = measuredMaximum ?? 190
        let empty = PassiveLoadEstimate(pattern: .insufficient, strain: nil, coverage: 0, weightedMinutes: 0, maximumHeartRateWasEstimated: measuredMaximum == nil)
        guard duration.isFinite, (900...14_400).contains(duration) else { return empty }
        var seen = Set<Date>()
        let rates = samples.filter { $0.date >= start && $0.date < end && $0.bpm.isFinite && (30...230).contains($0.bpm) && seen.insert($0.date).inserted }.sorted { $0.date < $1.date }
        guard rates.count >= 18 else { return empty }
        var covered = 0.0, weighted = 0.0
        for index in rates.indices {
            let next = index + 1 < rates.count ? rates[index + 1].date : min(end, rates[index].date.addingTimeInterval(15))
            let seconds = max(0, min(30, next.timeIntervalSince(rates[index].date)))
            let ratio = rates[index].bpm / maximum
            let weight = ratio >= 0.9 ? 5.0 : ratio >= 0.8 ? 4 : ratio >= 0.7 ? 3 : ratio >= 0.6 ? 2 : ratio >= 0.5 ? 1 : 0
            covered += seconds; weighted += seconds / 60 * weight
        }
        let coverage = min(1, covered / duration)
        guard coverage >= 0.7 else { return PassiveLoadEstimate(pattern: .insufficient, strain: nil, coverage: coverage, weightedMinutes: weighted, maximumHeartRateWasEstimated: measuredMaximum == nil) }
        // En az üç anlamlı yükseliş-dinlenme döngüsü gerekir; HIIT de aynı şekli üretebilir.
        var cycles = 0, peak = rates[0].bpm, valley = rates[0].bpm, rising = false
        var previousDate = rates[0].date
        for point in rates.dropFirst() {
            if point.date.timeIntervalSince(previousDate) > 90 { rising = false; valley = point.bpm; peak = point.bpm; previousDate = point.date; continue }
            previousDate = point.date
            if rising {
                peak = max(peak, point.bpm)
                if peak - point.bpm >= 18 { cycles += 1; rising = false; valley = point.bpm }
            } else {
                valley = min(valley, point.bpm)
                if point.bpm - valley >= 18 { rising = true; peak = point.bpm }
            }
        }
        let average = rates.reduce(0) { $0 + $1.bpm } / Double(rates.count)
        let deviation = sqrt(rates.reduce(0) { $0 + pow($1.bpm - average, 2) } / Double(rates.count))
        let sustained = rates.filter { $0.bpm >= maximum * 0.65 }.count >= Int(Double(rates.count) * 0.75) && deviation / average < 0.12
        let pattern: PassiveActivityPattern = cycles >= 3 ? .intervals : sustained ? .sustained : .mixed
        let strain = weighted > 0 ? min(10, max(1, Int(ceil(10 * (1 - exp(-weighted / 150)))))) : nil
        return PassiveLoadEstimate(pattern: pattern, strain: strain, coverage: coverage, weightedMinutes: weighted, maximumHeartRateWasEstimated: measuredMaximum == nil)
    }
    static func rpe(from text: String) -> Int? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Int(value), (1...10).contains(number) else { return nil }
        return number
    }
}

struct PassiveGymConfiguration: Codable, Equatable, Sendable {
    var name: String
    var latitude: Double
    var longitude: Double
    var routines: [Int: String]
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 64 && latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) && routines.count <= 7 && routines.allSatisfy { (1...7).contains($0.key) && $0.value.count <= 64 }
    }
    func routine(at date: Date, calendar: Calendar = .current) -> String? {
        guard let name = routines[calendar.component(.weekday, from: date)]?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return name
    }
}

struct PassiveGymVisit: Codable, Equatable, Sendable {
    let id: UUID
    let start: Date
    let end: Date
    let routine: String?
}

struct PassiveGymSession: Codable, Sendable {
    private(set) var enteredAt: Date?
    private(set) var lastEvent: Date?
    mutating func enter(at date: Date) {
        guard date.timeIntervalSince1970.isFinite, lastEvent.map({ date >= $0 }) ?? true else { return }
        lastEvent = date
        if let enteredAt { if date.timeIntervalSince(enteredAt) > 4 * 3600 { self.enteredAt = date } }
        else { enteredAt = date }
    }
    mutating func exit(at date: Date, configuration: PassiveGymConfiguration, calendar: Calendar = .current) -> PassiveGymVisit? {
        guard date.timeIntervalSince1970.isFinite, lastEvent.map({ date >= $0 }) ?? true else { return nil }
        lastEvent = date
        defer { enteredAt = nil }
        guard configuration.isValid, let start = enteredAt, (900...14_400).contains(date.timeIntervalSince(start)) else { return nil }
        return PassiveGymVisit(id: UUID(), start: start, end: date, routine: configuration.routine(at: start, calendar: calendar))
    }
}

struct PassiveWorkoutResponse: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let rpe: Int?
    let createdAt: Date
}
