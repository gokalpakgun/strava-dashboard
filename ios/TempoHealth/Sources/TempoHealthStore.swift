import Foundation
import HealthKit

final class TempoHealthStore {
    private let store = HKHealthStore()
    private var observerQueries: [HKObserverQuery] = []

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var waterType: HKQuantityType { HKQuantityType(.dietaryWater) }
    private var sleepType: HKCategoryType { HKCategoryType(.sleepAnalysis) }
    private var stepType: HKQuantityType { HKQuantityType(.stepCount) }
    private var energyType: HKQuantityType { HKQuantityType(.activeEnergyBurned) }
    private var restingHeartRateType: HKQuantityType { HKQuantityType(.restingHeartRate) }
    private var hrvType: HKQuantityType { HKQuantityType(.heartRateVariabilitySDNN) }
    private var bodyMassType: HKQuantityType { HKQuantityType(.bodyMass) }

    private var readTypes: Set<HKObjectType> {
        [waterType, sleepType, stepType, energyType, restingHeartRateType, hrvType, bodyMassType]
    }

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthStoreError.unavailable }
        try await store.requestAuthorization(toShare: [waterType], read: readTypes)
    }

    func saveWater(amountMl: Double) async throws {
        let quantity = HKQuantity(unit: .literUnit(with: .milli), doubleValue: amountMl)
        let sample = HKQuantitySample(type: waterType, quantity: quantity, start: Date(), end: Date())
        try await store.save(sample)
    }

    func readRecentDays(dayCount: Int = 90) async throws -> [String: TempoHealthMetrics] {
        let calendar = Calendar.autoupdatingCurrent
        let end = Date()
        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -dayCount, to: end) ?? end)

        async let water = dailyStatistics(type: waterType, unit: .literUnit(with: .milli), option: .cumulativeSum, start: start, end: end)
        async let steps = dailyStatistics(type: stepType, unit: .count(), option: .cumulativeSum, start: start, end: end)
        async let energy = dailyStatistics(type: energyType, unit: .kilocalorie(), option: .cumulativeSum, start: start, end: end)
        async let restingHeartRate = dailyStatistics(type: restingHeartRateType, unit: .count().unitDivided(by: .minute()), option: .discreteAverage, start: start, end: end)
        async let hrv = dailyStatistics(type: hrvType, unit: .secondUnit(with: .milli), option: .discreteAverage, start: start, end: end)
        async let bodyMass = dailyStatistics(type: bodyMassType, unit: .gramUnit(with: .kilo), option: .discreteAverage, start: start, end: end)
        async let sleep = sleepDurations(start: start, end: end)

        let values = try await (water, steps, energy, restingHeartRate, hrv, bodyMass, sleep)
        let keys = Set(values.0.keys)
            .union(values.1.keys)
            .union(values.2.keys)
            .union(values.3.keys)
            .union(values.4.keys)
            .union(values.5.keys)
            .union(values.6.keys)

        return Dictionary(uniqueKeysWithValues: keys.map { day in
            (day, TempoHealthMetrics(
                waterMl: values.0[day],
                sleepMinutes: values.6[day],
                steps: values.1[day],
                activeEnergyKcal: values.2[day],
                restingHeartRateBpm: values.3[day],
                hrvMs: values.4[day],
                bodyMassKg: values.5[day]
            ))
        }.filter { $0.1.hasData })
    }

    func startBackgroundDelivery(onChange: @escaping () async -> Void) {
        stopObservers()
        for type in readTypes.compactMap({ $0 as? HKSampleType }) {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                guard error == nil else { completion(); return }
                Task {
                    await onChange()
                    completion()
                }
            }
            observerQueries.append(query)
            store.execute(query)
            store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
        }
    }

    func stopObservers() {
        observerQueries.forEach { store.stop($0) }
        observerQueries.removeAll()
    }

    func disableBackgroundDelivery() {
        stopObservers()
        store.disableAllBackgroundDelivery { _, _ in }
    }

    private func dailyStatistics(
        type: HKQuantityType,
        unit: HKUnit,
        option: HKStatisticsOptions,
        start: Date,
        end: Date
    ) async throws -> [String: Double] {
        try await withCheckedThrowingContinuation { continuation in
            let calendar = Calendar.autoupdatingCurrent
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: option,
                anchorDate: calendar.startOfDay(for: start),
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, results, error in
                if let error { continuation.resume(throwing: error); return }
                guard let results else { continuation.resume(returning: [:]); return }
                var output: [String: Double] = [:]
                results.enumerateStatistics(from: start, to: end) { statistics, _ in
                    let quantity = option.contains(.cumulativeSum) ? statistics.sumQuantity() : statistics.averageQuantity()
                    guard let value = quantity?.doubleValue(for: unit), value.isFinite, value >= 0 else { return }
                    output[Self.dayString(statistics.startDate)] = Self.round(value, digits: 1)
                }
                continuation.resume(returning: output)
            }
            store.execute(query)
        }
    }

    private func sleepDurations(start: Date, end: Date) async throws -> [String: Double] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                var intervalsByNight: [String: [DateInterval]] = [:]
                for sample in (samples as? [HKCategorySample]) ?? [] where Self.isAsleep(sample.value) {
                    let night = Self.dayString(sample.endDate.addingTimeInterval(12 * 60 * 60))
                    intervalsByNight[night, default: []].append(DateInterval(start: sample.startDate, end: sample.endDate))
                }
                let result = intervalsByNight.mapValues { intervals in
                    let sorted = intervals.sorted { $0.start < $1.start }
                    var merged: [DateInterval] = []
                    for interval in sorted {
                        if let last = merged.last, interval.start <= last.end {
                            merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
                        } else {
                            merged.append(interval)
                        }
                    }
                    return Self.round(merged.reduce(0) { $0 + $1.duration / 60 }, digits: 0)
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    private static func isAsleep(_ value: Int) -> Bool {
        value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue ||
        value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
        value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
        value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func round(_ value: Double, digits: Int) -> Double {
        let factor = pow(10, Double(digits))
        return (value * factor).rounded() / factor
    }
}

private enum HealthStoreError: LocalizedError {
    case unavailable
    var errorDescription: String? { "Apple Sağlık bu cihazda kullanılamıyor." }
}
