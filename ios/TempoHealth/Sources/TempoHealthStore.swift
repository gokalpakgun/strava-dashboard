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
    private var exerciseTimeType: HKQuantityType { HKQuantityType(.appleExerciseTime) }
    private var restingHeartRateType: HKQuantityType { HKQuantityType(.restingHeartRate) }
    private var hrvType: HKQuantityType { HKQuantityType(.heartRateVariabilitySDNN) }
    private var respiratoryRateType: HKQuantityType { HKQuantityType(.respiratoryRate) }
    private var oxygenSaturationType: HKQuantityType { HKQuantityType(.oxygenSaturation) }
    private var vo2MaxType: HKQuantityType { HKQuantityType(.vo2Max) }
    private var walkingHeartRateType: HKQuantityType { HKQuantityType(.walkingHeartRateAverage) }
    private var heartRateRecoveryType: HKQuantityType { HKQuantityType(.heartRateRecoveryOneMinute) }
    private var wristTemperatureType: HKQuantityType { HKQuantityType(.appleSleepingWristTemperature) }
    private var bodyMassType: HKQuantityType { HKQuantityType(.bodyMass) }

    private var readTypes: Set<HKObjectType> {
        [
            waterType, sleepType, stepType, energyType, exerciseTimeType, restingHeartRateType, hrvType,
            respiratoryRateType, oxygenSaturationType, vo2MaxType, walkingHeartRateType,
            heartRateRecoveryType, wristTemperatureType, bodyMassType,
        ]
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
        async let exercise = dailyStatistics(type: exerciseTimeType, unit: .minute(), option: .cumulativeSum, start: start, end: end)
        async let restingHeartRate = dailyStatistics(type: restingHeartRateType, unit: .count().unitDivided(by: .minute()), option: .discreteAverage, start: start, end: end)
        async let hrv = dailyStatistics(type: hrvType, unit: .secondUnit(with: .milli), option: .discreteAverage, start: start, end: end)
        async let respiratoryRate = dailyStatistics(type: respiratoryRateType, unit: .count().unitDivided(by: .minute()), option: .discreteAverage, start: start, end: end)
        async let oxygen = dailyStatistics(type: oxygenSaturationType, unit: .percent(), option: .discreteAverage, start: start, end: end, multiplier: 100)
        async let vo2Max = dailyStatistics(type: vo2MaxType, unit: HKUnit(from: "ml/kg*min"), option: .discreteAverage, start: start, end: end)
        async let walkingHeartRate = dailyStatistics(type: walkingHeartRateType, unit: .count().unitDivided(by: .minute()), option: .discreteAverage, start: start, end: end)
        async let heartRateRecovery = dailyStatistics(type: heartRateRecoveryType, unit: .count().unitDivided(by: .minute()), option: .discreteAverage, start: start, end: end)
        async let wristTemperature = dailyStatistics(type: wristTemperatureType, unit: .degreeCelsius(), option: .discreteAverage, start: start, end: end)
        async let bodyMass = dailyStatistics(type: bodyMassType, unit: .gramUnit(with: .kilo), option: .discreteAverage, start: start, end: end)
        async let sleep = sleepBreakdown(start: start, end: end)

        let values = try await (
            water, steps, energy, exercise, restingHeartRate, hrv, respiratoryRate, oxygen,
            vo2Max, walkingHeartRate, heartRateRecovery, wristTemperature, bodyMass, sleep
        )
        let keys = [
            Set(values.0.keys), Set(values.1.keys), Set(values.2.keys), Set(values.3.keys),
            Set(values.4.keys), Set(values.5.keys), Set(values.6.keys), Set(values.7.keys),
            Set(values.8.keys), Set(values.9.keys), Set(values.10.keys), Set(values.11.keys),
            Set(values.12.keys), Set(values.13.keys),
        ].reduce(into: Set<String>()) { $0.formUnion($1) }

        return Dictionary(uniqueKeysWithValues: keys.map { day in
            let sleep = values.13[day]
            (day, TempoHealthMetrics(
                waterMl: values.0[day],
                sleepMinutes: sleep?.totalMinutes,
                sleepCoreMinutes: sleep?.coreMinutes,
                sleepDeepMinutes: sleep?.deepMinutes,
                sleepREMMinutes: sleep?.remMinutes,
                sleepAwakeMinutes: sleep?.awakeMinutes,
                steps: values.1[day],
                activeEnergyKcal: values.2[day],
                exerciseMinutes: values.3[day],
                restingHeartRateBpm: values.4[day],
                hrvMs: values.5[day],
                respiratoryRate: values.6[day],
                oxygenSaturationPct: values.7[day],
                vo2Max: values.8[day],
                walkingHeartRateBpm: values.9[day],
                heartRateRecoveryBpm: values.10[day],
                wristTemperatureC: values.11[day],
                bodyMassKg: values.12[day]
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
        end: Date,
        multiplier: Double = 1
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
                    output[Self.dayString(statistics.startDate)] = Self.round(value * multiplier, digits: 1)
                }
                continuation.resume(returning: output)
            }
            store.execute(query)
        }
    }

    private func sleepBreakdown(start: Date, end: Date) async throws -> [String: SleepBreakdown] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                var intervalsByNight: [String: [Int: [DateInterval]]] = [:]
                for sample in (samples as? [HKCategorySample]) ?? [] {
                    guard Self.isAsleep(sample.value) || sample.value == HKCategoryValueSleepAnalysis.awake.rawValue else { continue }
                    let night = Self.dayString(sample.endDate.addingTimeInterval(12 * 60 * 60))
                    intervalsByNight[night, default: [:]][sample.value, default: []]
                        .append(DateInterval(start: sample.startDate, end: sample.endDate))
                }
                let result = intervalsByNight.mapValues { stages in
                    let asleep = stages
                        .filter { Self.isAsleep($0.key) }
                        .flatMap(\.value)
                    return SleepBreakdown(
                        totalMinutes: Self.minutes(asleep),
                        coreMinutes: Self.minutes(stages[HKCategoryValueSleepAnalysis.asleepCore.rawValue] ?? []),
                        deepMinutes: Self.minutes(stages[HKCategoryValueSleepAnalysis.asleepDeep.rawValue] ?? []),
                        remMinutes: Self.minutes(stages[HKCategoryValueSleepAnalysis.asleepREM.rawValue] ?? []),
                        awakeMinutes: Self.minutes(stages[HKCategoryValueSleepAnalysis.awake.rawValue] ?? [])
                    )
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    private static func minutes(_ intervals: [DateInterval]) -> Double {
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []
        for interval in sorted {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return round(merged.reduce(0) { $0 + $1.duration / 60 }, digits: 0)
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

private struct SleepBreakdown {
    let totalMinutes: Double
    let coreMinutes: Double
    let deepMinutes: Double
    let remMinutes: Double
    let awakeMinutes: Double
}

private enum HealthStoreError: LocalizedError {
    case unavailable
    var errorDescription: String? { "Apple Sağlık bu cihazda kullanılamıyor." }
}
