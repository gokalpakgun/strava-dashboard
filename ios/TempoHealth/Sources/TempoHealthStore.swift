import Foundation
import HealthKit
import CoreMotion

final class TempoHealthStore {
    private let store = HKHealthStore()
    private let pedometer = CMPedometer()
    private var observerQueries: [HKObserverQuery] = []

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var waterType: HKQuantityType { HKQuantityType(.dietaryWater) }
    private var sleepType: HKCategoryType { HKCategoryType(.sleepAnalysis) }
    private var stepType: HKQuantityType { HKQuantityType(.stepCount) }
    private var heartRateType: HKQuantityType { HKQuantityType(.heartRate) }
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

    func workoutHealthSignal(start: Date, durationMinutes: Int) async throws -> TempoWorkoutHealthSignal {
        guard isAvailable else { throw HealthStoreError.unavailable }
        let end = start.addingTimeInterval(Double(durationMinutes) * 60)
        guard durationMinutes > 0, durationMinutes <= 24 * 60,
              start.timeIntervalSince1970.isFinite, end <= Date() else { throw HealthStoreError.invalidWorkoutInterval }
        let baselineStart = start.addingTimeInterval(-20 * 60)
        try await store.requestAuthorization(toShare: [], read: [heartRateType, stepType, respiratoryRateType, energyType, exerciseTimeType, HKObjectType.workoutType()])

        async let workoutHeartRates = heartRateSamples(from: start, to: end)
        async let baselineHeartRates = heartRateSamples(from: baselineStart, to: start)
        async let workoutRespiratoryRates = quantitySamples(type: respiratoryRateType, unit: .count().unitDivided(by: .minute()), from: start, to: end)
        async let baselineRespiratoryRates = quantitySamples(type: respiratoryRateType, unit: .count().unitDivided(by: .minute()), from: baselineStart, to: start)
        async let workoutSteps = stepCount(from: start, to: end)
        async let baselineSteps = stepCount(from: baselineStart, to: start)
        async let workoutEnergy = quantitySum(type: energyType, unit: .kilocalorie(), from: start, to: end)
        async let workoutExerciseMinutes = quantitySum(type: exerciseTimeType, unit: .minute(), from: start, to: end)
        async let matchingWorkoutMinutes = matchingHealthWorkoutMinutes(start: start, end: end)
        let values = try await (
            workoutHeartRates, baselineHeartRates, workoutRespiratoryRates, baselineRespiratoryRates,
            workoutSteps, baselineSteps, workoutEnergy, workoutExerciseMinutes, matchingWorkoutMinutes
        )

        let heartRates = values.0
        let baselineRates = values.1
        let average = heartRates.isEmpty ? nil : heartRates.reduce(0, +) / Double(heartRates.count)
        let baseline = baselineRates.isEmpty ? nil : baselineRates.reduce(0, +) / Double(baselineRates.count)
        let respiratoryRates = values.2
        let baselineRespiratory = values.3
        let averageRespiratory = respiratoryRates.isEmpty ? nil : respiratoryRates.reduce(0, +) / Double(respiratoryRates.count)
        let averageBaselineRespiratory = baselineRespiratory.isEmpty ? nil : baselineRespiratory.reduce(0, +) / Double(baselineRespiratory.count)
        let duringSteps = values.4
        let beforeSteps = values.5
        let phoneStepsDuring = try? await phoneStepCount(from: start, to: end)
        let phoneStepsBefore = try? await phoneStepCount(from: baselineStart, to: start)
        let hasPhoneStepBaseline = phoneStepsDuring != nil && phoneStepsBefore != nil
        let movementSteps = hasPhoneStepBaseline ? phoneStepsDuring : duringSteps
        let baselineMovementSteps = hasPhoneStepBaseline ? phoneStepsBefore : beforeSteps
        let normalizedBeforeSteps = baselineMovementSteps.map { Double($0) * Double(durationMinutes) / 20 }
        let movementIncrease: Bool
        if let movementSteps, let normalizedBeforeSteps {
            movementIncrease = movementSteps >= 50 && Double(movementSteps) >= normalizedBeforeSteps * 1.5 + 30
        } else {
            movementIncrease = false
        }

        return TempoWorkoutHealthSignal(
            heartRateSampleCount: heartRates.count,
            averageHeartRateBpm: average.map { Self.round($0, digits: 0) },
            peakHeartRateBpm: heartRates.max().map { Self.round($0, digits: 0) },
            baselineHeartRateBpm: baseline.map { Self.round($0, digits: 0) },
            stepsDuringWorkout: duringSteps,
            stepsBeforeWorkout: beforeSteps,
            phoneStepsDuringWorkout: phoneStepsDuring,
            phoneStepsBeforeWorkout: phoneStepsBefore,
            movementIncreaseDetected: movementIncrease,
            averageRespiratoryRatePerMinute: averageRespiratory.map { Self.round($0, digits: 1) },
            baselineRespiratoryRatePerMinute: averageBaselineRespiratory.map { Self.round($0, digits: 1) },
            activeEnergyKcal: values.6.map { Self.round($0, digits: 1) },
            exerciseMinutes: values.7.map { Self.round($0, digits: 1) },
            matchedHealthWorkoutMinutes: values.8,
            checkedAt: Date()
        )
    }

    func saveWater(amountMl: Double) async throws {
        guard isAvailable else { throw HealthStoreError.unavailable }
        guard amountMl.isFinite, amountMl > 0 else { throw HealthStoreError.invalidWaterAmount }
        let now = Date()
        let quantity = HKQuantity(unit: .literUnit(with: .milli), doubleValue: amountMl)
        let sample = HKQuantitySample(type: waterType, quantity: quantity, start: now, end: now)
        try await store.save(sample)
    }

    func readRecentDays(dayCount: Int = 90) async throws -> [String: TempoHealthMetrics] {
        guard isAvailable else { throw HealthStoreError.unavailable }
        guard dayCount > 0, dayCount <= 366 else { throw HealthStoreError.invalidHistoryRange }
        let calendar = Calendar.autoupdatingCurrent
        let end = Date()
        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -(dayCount - 1), to: end) ?? end)

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
            return (day, TempoHealthMetrics(
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

    private func heartRateSamples(from start: Date, to end: Date) async throws -> [Double] {
        try await quantitySamples(type: heartRateType, unit: .count().unitDivided(by: .minute()), from: start, to: end)
    }

    private func quantitySamples(type: HKQuantityType, unit: HKUnit, from start: Date, to end: Date) async throws -> [Double] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let values = ((samples as? [HKQuantitySample]) ?? []).compactMap { sample -> Double? in
                    let value = sample.quantity.doubleValue(for: unit)
                    return value.isFinite && value > 0 ? value : nil
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }

    private func stepCount(from start: Date, to end: Date) async throws -> Int? {
        guard let value = try await quantitySum(type: stepType, unit: .count(), from: start, to: end) else { return nil }
        return Int(value.rounded())
    }

    private func phoneStepCount(from start: Date, to end: Date) async throws -> Int? {
        guard CMPedometer.isStepCountingAvailable(), end <= Date(), start >= Date().addingTimeInterval(-7 * 24 * 60 * 60) else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: end) { data, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: data?.numberOfSteps.intValue)
            }
        }
    }

    private func quantitySum(type: HKQuantityType, unit: HKUnit, from start: Date, to end: Date) async throws -> Double? {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                if let error { continuation.resume(throwing: error); return }
                guard let value = statistics?.sumQuantity()?.doubleValue(for: unit), value.isFinite, value >= 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func matchingHealthWorkoutMinutes(start: Date, end: Date) async throws -> Int? {
        try await withCheckedThrowingContinuation { continuation in
            let nearbyStart = start.addingTimeInterval(-5 * 60)
            let nearbyEnd = end.addingTimeInterval(5 * 60)
            let predicate = HKQuery.predicateForSamples(withStart: nearbyStart, end: nearbyEnd, options: .strictStartDate)
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let expectedDuration = end.timeIntervalSince(start)
                let candidates = ((samples as? [HKWorkout]) ?? []).filter { workout in
                    let startDifference = abs(workout.startDate.timeIntervalSince(start))
                    let durationDifference = abs(workout.duration - expectedDuration)
                    let allowedDurationDifference = min(20 * 60, max(10 * 60, expectedDuration * 0.3))
                    return startDifference <= 5 * 60 && durationDifference <= allowedDurationDifference
                }
                let closest = candidates.min { abs($0.startDate.timeIntervalSince(start)) < abs($1.startDate.timeIntervalSince(start)) }
                continuation.resume(returning: closest.map { Int(($0.duration / 60).rounded()) })
            }
            store.execute(query)
        }
    }

    private func sleepBreakdown(start: Date, end: Date) async throws -> [String: TempoSleepBreakdown] {
        try await withCheckedThrowingContinuation { continuation in
            // Include the preceding evening so the oldest wake date has a complete night.
            let previousDay = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -1, to: start) ?? start
            let predicate = HKQuery.predicateForSamples(withStart: previousDay, end: end, options: [])
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let intervals = ((samples as? [HKCategorySample]) ?? []).compactMap { sample -> TempoSleepInterval? in
                    let stage: TempoSleepStage
                    switch sample.value {
                    case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: stage = .unspecified
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue: stage = .core
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: stage = .deep
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue: stage = .rem
                    case HKCategoryValueSleepAnalysis.awake.rawValue: stage = .awake
                    default: return nil // In-bed time is not sleep time.
                    }
                    return TempoSleepInterval(
                        start: sample.startDate, end: sample.endDate, stage: stage,
                        source: sample.sourceRevision.source.bundleIdentifier + ":" + (sample.device?.localIdentifier ?? "")
                    )
                }
                continuation.resume(returning: TempoSleepAggregation.dailyBreakdown(intervals, from: start, to: end))
            }
            store.execute(query)
        }
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func round(_ value: Double, digits: Int) -> Double {
        let factor = pow(10, Double(digits))
        return (value * factor).rounded() / factor
    }

    #if DEBUG && targetEnvironment(simulator)
    /// Exercises the real simulator HealthKit store, including the system permission sheet.
    /// This method is absent from Release builds and every physical-device build.
    func runSimulatorIntegrationCheck() async throws -> String {
        guard isAvailable else { throw HealthStoreError.unavailable }
        let writeTypes: Set<HKSampleType> = [waterType, sleepType, stepType]
        try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
        guard writeTypes.allSatisfy({ store.authorizationStatus(for: $0) == .sharingAuthorized }) else {
            throw simulatorCheckError("HealthKit test write permission was not granted for water, sleep and steps.")
        }

        let calendar = Calendar.autoupdatingCurrent
        let dayStart = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: Date()))!
        let key = Self.dayString(dayStart)
        let runID = UUID().uuidString
        let metadata: [String: Any] = ["TempoSimulatorIntegrationRun": runID]
        let at: (TimeInterval) -> Date = { dayStart.addingTimeInterval($0 * 60) }
        let samples: [HKSample] = [
            HKQuantitySample(type: waterType, quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: 321), start: at(600), end: at(600), metadata: metadata),
            HKQuantitySample(type: stepType, quantity: HKQuantity(unit: .count(), doubleValue: 1234), start: at(600), end: at(610), metadata: metadata),
            HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: at(0), end: at(60), metadata: metadata),
            HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepDeep.rawValue, start: at(60), end: at(120), metadata: metadata),
            HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.awake.rawValue, start: at(120), end: at(130), metadata: metadata),
            HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepREM.rawValue, start: at(130), end: at(190), metadata: metadata),
        ]
        let before = try await readRecentDays(dayCount: 7)[key]

        // The callback continuation resumes only after deferred cleanup completes. The defer
        // also runs when an assertion or HealthKit query fails, deleting only this run's UUIDs.
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            Task {
                var outcome: Result<String, Error> = .failure(simulatorCheckError("HealthKit test did not complete."))
                defer {
                    let completed = outcome
                    store.delete(samples) { success, error in
                        if let error {
                            continuation.resume(throwing: self.simulatorCheckError("HealthKit test cleanup failed: \(error.localizedDescription)"))
                        } else if !success {
                            continuation.resume(throwing: self.simulatorCheckError("HealthKit did not confirm test sample cleanup."))
                        } else {
                            continuation.resume(with: completed)
                        }
                    }
                }
                do {
                    try await store.save(samples)
                    for sample in samples {
                        let count = try await simulatorSampleCount(sample)
                        guard count == 1 else { throw simulatorCheckError("HealthKit did not return the test sample \(sample.sampleType.identifier).") }
                    }
                    guard let after = try await readRecentDays(dayCount: 7)[key] else {
                        throw simulatorCheckError("Production Health history did not return the seeded day.")
                    }
                    guard abs((after.waterMl ?? 0) - (before?.waterMl ?? 0) - 321) < 0.2 else {
                        throw simulatorCheckError("Production daily water query did not include the 321 ml sample.")
                    }
                    guard abs((after.steps ?? 0) - (before?.steps ?? 0) - 1234) < 0.2 else {
                        throw simulatorCheckError("Production daily step query did not include the 1234 steps sample.")
                    }
                    // A clean simulator has no other sleep records. Existing overlapping sleep
                    // must not be mistaken for this test's expected stage totals.
                    guard before?.sleepMinutes == nil else {
                        throw simulatorCheckError("Choose a clean simulator: this test date already contains sleep data.")
                    }
                    guard after.sleepMinutes == 180, after.sleepCoreMinutes == 60,
                          after.sleepDeepMinutes == 60, after.sleepREMMinutes == 60,
                          after.sleepAwakeMinutes == 10 else {
                        throw simulatorCheckError("Production sleep aggregation did not return 180 minutes and the expected stage totals.")
                    }
                    // Read permission cannot be inferred: HealthKit may expose an app's own
                    // samples even when access to samples from other apps is denied.
                    outcome = .success("HEALTHKIT_PASS own_samples=6 water_ml=321 steps=1234 sleep_min=180 stages=4 cleanup=6")
                } catch {
                    outcome = .failure(error)
                }
            }
        }
    }

    private func simulatorSampleCount(_ sample: HKSample) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sample.sampleType, predicate: HKQuery.predicateForObject(with: sample.uuid),
                limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples?.count ?? 0) }
            }
            store.execute(query)
        }
    }

    private func simulatorCheckError(_ message: String) -> NSError {
        NSError(domain: "TempoSimulatorHealthIntegration", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    #endif
}

private enum HealthStoreError: LocalizedError {
    case unavailable
    case invalidWaterAmount
    case invalidWorkoutInterval
    case invalidHistoryRange

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Apple Sağlık bu cihazda kullanılamıyor.".tempoLocalized
        case .invalidWaterAmount: return NSLocalizedString("Water amount must be greater than zero.", comment: "Health validation")
        case .invalidWorkoutInterval: return NSLocalizedString("Choose a completed workout lasting between 1 minute and 24 hours.", comment: "Health validation")
        case .invalidHistoryRange: return NSLocalizedString("Health history must cover between 1 and 366 days.", comment: "Health validation")
        }
    }
}
