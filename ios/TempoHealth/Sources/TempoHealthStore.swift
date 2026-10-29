import Foundation
import HealthKit
import CoreMotion

final class TempoHealthStore {
    private let store = HKHealthStore()
    private let pedometer = CMPedometer()
    private var observerQueries: [HKObserverQuery] = []
    private let zoneCache = HeartRateZoneCache()

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
        var types: Set<HKObjectType> = [
            waterType, sleepType, stepType, energyType, exerciseTimeType, restingHeartRateType, hrvType,
            respiratoryRateType, oxygenSaturationType, vo2MaxType, walkingHeartRateType,
            heartRateRecoveryType, wristTemperatureType, bodyMassType, HKObjectType.workoutType(),
            heartRateType, HKQuantityType(.runningPower), HKQuantityType(.cyclingPower), HKQuantityType(.cyclingCadence),
        ]
        if #available(iOS 18.0, *) { types.formUnion([HKQuantityType(.workoutEffortScore), HKQuantityType(.estimatedWorkoutEffortScore)]) }
        return types
    }

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthStoreError.unavailable }
        try await store.requestAuthorization(toShare: [waterType], read: readTypes)
    }

    func readRecentWorkouts(dayCount: Int = 365) async throws -> [TempoManualWorkout] {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -min(max(dayCount, 1), 365), to: now) ?? now
        let snapshot: HealthWorkoutReadSnapshot = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate), limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let workouts = ((samples as? [HKWorkout]) ?? []).filter { $0.endDate <= now && $0.endDate > $0.startDate && $0.duration.isFinite && (1...604_800).contains($0.duration) }
                let records = workouts.map { workout in
                    let choice: TempoSportChoice?
                    switch workout.workoutActivityType {
                    case .running: choice = .run
                    case .cycling: choice = .cycling
                    case .walking: choice = .walking
                    case .hiking: choice = .hiking
                    case .swimming: choice = .swimming
                    case .tennis: choice = .tennis
                    case .basketball: choice = .basketball
                    case .soccer, .americanFootball: choice = .football
                    case .volleyball: choice = .volleyball
                    case .badminton: choice = .badminton
                    case .yoga: choice = .yoga
                    case .traditionalStrengthTraining, .functionalStrengthTraining, .highIntensityIntervalTraining, .crossTraining, .mixedCardio, .coreTraining: choice = .fitness
                    default: choice = nil
                    }
                    let title = choice?.title ?? "Diğer".tempoLocalized
                    var record = TempoManualWorkout(id: workout.uuid, sportId: choice?.rawValue ?? "other", sportTitle: title, title: title, startedAt: workout.startDate, durationMinutes: max(1, Int((workout.duration / 60).rounded())), notes: "", photoFilename: nil, healthSignal: nil, durationSeconds: Int(workout.duration.rounded()), distanceKm: workout.totalDistance.map { $0.doubleValue(for: .meter()) / 1000 }, routeCoordinates: nil, recordSource: "apple-health", perceivedEffort: nil, enjoyment: nil)
                    record.originalHealthActivityType = workout.workoutActivityType.rawValue
                    record.sourceEndedAt = workout.endDate
                    record.originalArchetype = SportMapper().map(healthKit: workout.workoutActivityType)?.rawValue
                    record.sourceEnergyKcal = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
                    let heart = workout.statistics(for: HKQuantityType(.heartRate))
                    let bpm = HKUnit.count().unitDivided(by: .minute())
                    record.sourceAverageHeartRateBpm = heart?.averageQuantity()?.doubleValue(for: bpm)
                    record.sourcePeakHeartRateBpm = heart?.maximumQuantity()?.doubleValue(for: bpm)
                    let powerType: HKQuantityTypeIdentifier? = workout.workoutActivityType == .running ? .runningPower : (workout.workoutActivityType == .cycling ? .cyclingPower : nil)
                    if let powerType { record.sourceAveragePowerWatts = workout.statistics(for: HKQuantityType(powerType))?.averageQuantity()?.doubleValue(for: .watt()) }
                    if workout.workoutActivityType == .cycling { record.sourceCadencePerMinute = workout.statistics(for: HKQuantityType(.cyclingCadence))?.averageQuantity()?.doubleValue(for: bpm) }
                    return record
                }
                let windows = workouts.map { workout in
                    HeartRateWorkoutWindow(id: workout.uuid, start: workout.startDate, end: workout.endDate, activeDurationSeconds: workout.duration, activeIntervals: Self.activeWorkoutIntervals(workout))
                }
                continuation.resume(returning: HealthWorkoutReadSnapshot(records: records, windows: windows))
            }
            store.execute(query)
        }
        guard !snapshot.records.isEmpty, !Task.isCancelled else { return snapshot.records }
        async let effortRead = availableWorkoutEfforts(ids: Set(snapshot.records.map(\.id)))
        // Açılışı hızlandırmak için yakın 90 gün topluca; eski kayıtlar ayrıntı açılınca okunur.
        async let zoneRead = readWorkoutHeartRateZones(windows: snapshot.windows, now: now, querySince: now.addingTimeInterval(-90 * 86_400))
        let (efforts, zones) = await (effortRead, zoneRead)
        return snapshot.records.map { original in
            var record = original
            if let effort = efforts[record.id] { record.sourceWorkoutEffort = effort.value; record.sourceEffortIsEstimated = effort.estimated }
            if let zones = zones[record.id] { record.sourceHeartRateZones = zones.seconds; record.sourceHeartRateZoneEvidence = zones.evidence }
            return record
        }
    }

    private func availableWorkoutEfforts(ids: Set<UUID>) async -> [UUID: HealthWorkoutEffort] {
        if #available(iOS 18.0, *) { return await readWorkoutEfforts(ids: ids) }
        return [:]
    }

    func readHeartRateZones(workoutID: UUID) async throws -> InferredHeartRateZones? {
        let workout: HKWorkout? = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: HKQuery.predicateForObject(with: workoutID), limit: 1, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: samples?.first as? HKWorkout)
            }
            store.execute(query)
        }
        guard let workout, workout.endDate <= Date(), workout.duration.isFinite, (1...604_800).contains(workout.duration), !Task.isCancelled else { return nil }
        let window = HeartRateWorkoutWindow(id: workout.uuid, start: workout.startDate, end: workout.endDate, activeDurationSeconds: workout.duration, activeIntervals: Self.activeWorkoutIntervals(workout))
        return await readWorkoutHeartRateZones(windows: [window], now: Date(), forceRefresh: true)[workoutID]
    }

    private static func activeWorkoutIntervals(_ workout: HKWorkout) -> [DateInterval] {
        var result: [DateInterval] = [], cursor = workout.startDate
        var paused = false
        for event in (workout.workoutEvents ?? []).sorted(by: { $0.dateInterval.start < $1.dateInterval.start }) {
            let at = min(workout.endDate, max(workout.startDate, event.dateInterval.start))
            switch event.type {
            case .pause, .motionPaused:
                if !paused { if at > cursor { result.append(DateInterval(start: cursor, end: at)) }; paused = true }
            case .resume, .motionResumed:
                if paused { cursor = at; paused = false }
            default: break
            }
        }
        if !paused, workout.endDate > cursor { result.append(DateInterval(start: cursor, end: workout.endDate)) }
        return result
    }

    private func readWorkoutHeartRateZones(windows: [HeartRateWorkoutWindow], now: Date, forceRefresh: Bool = false, querySince: Date? = nil) async -> [UUID: InferredHeartRateZones] {
        guard !windows.isEmpty, !Task.isCancelled else { return [:] }
        let peak = await recentMaximumHeartRate(now: now)
        let reference = peak.flatMap { $0.isFinite && (80...300).contains($0) ? $0 : nil } ?? 190
        let source: MaximumHeartRateReference = peak == nil ? .fallback190 : .recorded90DayPeak
        let cached = await zoneCache.lookup(windows, referenceBpm: reference, reference: source, now: now, force: forceRefresh || peak == nil)
        let pending = cached.pending.filter { $0.end > (querySince ?? .distantPast) }
        guard !pending.isEmpty else { return cached.values }
        let samples = await workoutHeartRateReadings(windows: pending)
        guard !Task.isCancelled else { return [:] }
        let computed = HeartRateZoneInference().infer(windows: pending, readings: samples.readings, recordedPeakBpm: peak, queryWasLimited: samples.limited)
        await zoneCache.save(computed, windows: pending, referenceBpm: reference, reference: source, now: now, generation: cached.generation)
        return cached.values.merging(computed) { _, current in current }
    }

    private func recentMaximumHeartRate(now: Date) async -> Double? {
        let healthStore = store, type = heartRateType, gate = HealthEffortReadGate()
        let unit = HKUnit.count().unitDivided(by: .minute())
        let period = HKQuery.predicateForSamples(withStart: now.addingTimeInterval(-90 * 86_400), end: now, options: .strictStartDate)
        let bounds = [HKQuery.predicateForQuantitySamples(with: .greaterThanOrEqualTo, quantity: HKQuantity(unit: unit, doubleValue: 80)), HKQuery.predicateForQuantitySamples(with: .lessThanOrEqualTo, quantity: HKQuantity(unit: unit, doubleValue: 300))]
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: NSCompoundPredicate(andPredicateWithSubpredicates: [period] + bounds), options: .discreteMax) { query, statistics, _ in
                guard gate.claimCompletion() else { return }
                healthStore.stop(query)
                continuation.resume(returning: statistics?.maximumQuantity()?.doubleValue(for: unit))
            }
            healthStore.execute(query)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 4) {
                guard gate.claimCompletion() else { return }; healthStore.stop(query); continuation.resume(returning: nil)
            }
        }
    }

    private func workoutHeartRateReadings(windows: [HeartRateWorkoutWindow]) async -> HeartRateQuerySnapshot {
        let healthStore = store, type = heartRateType
        let buffer = HeartRateQueryBuffer()
        let unit = HKUnit.count().unitDivided(by: .minute())
        let predicates = windows.map { HKQuery.predicateForSamples(withStart: $0.start, end: $0.end, options: []) }
        return await withCheckedContinuation { continuation in
            // Tek toplu sorgu, sıkıştırılmış örneklerdeki gerçek zaman noktalarını da açar.
            let query = HKQuantitySeriesSampleQuery(quantityType: type, predicate: NSCompoundPredicate(orPredicateWithSubpredicates: predicates)) { query, quantity, interval, _, done, error in
                if error != nil {
                    if buffer.finish(discard: true) != nil { healthStore.stop(query); continuation.resume(returning: HeartRateQuerySnapshot(readings: [], limited: true)) }
                    return
                }
                var reachedLimit = false
                if let quantity, let interval, quantity.is(compatibleWith: unit) {
                    reachedLimit = buffer.append(TimedHeartRateReading(start: interval.start, end: interval.end, bpm: quantity.doubleValue(for: unit)))
                }
                if done || reachedLimit, let snapshot = buffer.finish(limited: reachedLimit) { healthStore.stop(query); continuation.resume(returning: snapshot) }
            }
            healthStore.execute(query)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 8) {
                guard let snapshot = buffer.finish(limited: true) else { return }
                healthStore.stop(query); continuation.resume(returning: snapshot)
            }
        }
    }

    @available(iOS 18.0, *)
    private func readWorkoutEfforts(ids: Set<UUID>) async -> [UUID: HealthWorkoutEffort] {
        let healthStore = store
        let gate = HealthEffortReadGate()
        return await withCheckedContinuation { continuation in
            // İlişki sorgusu uzun ömürlüdür: ilk sonuçtan sonra durdurulur. Ana eşitleme bekletilmez.
            let query = HKWorkoutEffortRelationshipQuery(predicate: HKQuery.predicateForObjects(with: ids), anchor: nil, options: .mostRelevant) { query, relationships, _, _ in
                guard gate.claimCompletion() else { return }
                healthStore.stop(query)
                var result: [UUID: HealthWorkoutEffort] = [:]
                for relationship in relationships ?? [] where relationship.activity == nil && ids.contains(relationship.workout.uuid) {
                    let samples = (relationship.samples ?? []).compactMap { $0 as? HKQuantitySample }
                    let rated = samples.filter { $0.quantityType.identifier == HKQuantityTypeIdentifier.workoutEffortScore.rawValue }
                    let estimated = samples.filter { $0.quantityType.identifier == HKQuantityTypeIdentifier.estimatedWorkoutEffortScore.rawValue }
                    guard let sample = (rated.isEmpty ? estimated : rated).max(by: { $0.endDate < $1.endDate }), sample.quantity.is(compatibleWith: .appleEffortScore()) else { continue }
                    let value = sample.quantity.doubleValue(for: .appleEffortScore())
                    guard value.isFinite, (1...10).contains(value) else { continue }
                    result[relationship.workout.uuid] = HealthWorkoutEffort(value: value, estimated: rated.isEmpty)
                }
                continuation.resume(returning: result)
            }
            healthStore.execute(query)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 4) {
                guard gate.claimCompletion() else { return }
                healthStore.stop(query)
                continuation.resume(returning: [:])
            }
        }
    }

    func workoutHealthSignal(start: Date, durationMinutes: Int) async throws -> TempoWorkoutHealthSignal {
        guard isAvailable else { throw HealthStoreError.unavailable }
        let end = start.addingTimeInterval(Double(durationMinutes) * 60)
        guard durationMinutes > 0, durationMinutes <= 24 * 60,
              start.timeIntervalSince1970.isFinite, end <= Date() else { throw HealthStoreError.invalidWorkoutInterval }
        let baselineStart = start.addingTimeInterval(-20 * 60)
        // A missing Health stream must not discard other real measurements or phone steps.
        // Authorization failure still permits the independent Core Motion lookup.
        try? await store.requestAuthorization(toShare: [], read: [heartRateType, stepType, respiratoryRateType, energyType, exerciseTimeType, HKObjectType.workoutType()])
        try Task.checkCancellation()
        async let workoutHeartRates = try? heartRateSamples(from: start, to: end)
        async let baselineHeartRates = try? heartRateSamples(from: baselineStart, to: start)
        async let workoutRespiratoryRates = try? quantitySamples(type: respiratoryRateType, unit: .count().unitDivided(by: .minute()), from: start, to: end)
        async let baselineRespiratoryRates = try? quantitySamples(type: respiratoryRateType, unit: .count().unitDivided(by: .minute()), from: baselineStart, to: start)
        async let workoutSteps = try? stepCount(from: start, to: end)
        async let baselineSteps = try? stepCount(from: baselineStart, to: start)
        async let workoutEnergy = try? quantitySum(type: energyType, unit: .kilocalorie(), from: start, to: end)
        async let workoutExerciseMinutes = try? quantitySum(type: exerciseTimeType, unit: .minute(), from: start, to: end)
        async let matchingWorkoutMinutes = try? matchingHealthWorkoutMinutes(start: start, end: end)
        let values = await (
            workoutHeartRates, baselineHeartRates, workoutRespiratoryRates, baselineRespiratoryRates,
            workoutSteps, baselineSteps, workoutEnergy, workoutExerciseMinutes, matchingWorkoutMinutes
        )
        try Task.checkCancellation()

        let heartRates = values.0 ?? []
        let baselineRates = values.1 ?? []
        let average = heartRates.isEmpty ? nil : heartRates.reduce(0, +) / Double(heartRates.count)
        let baseline = baselineRates.isEmpty ? nil : baselineRates.reduce(0, +) / Double(baselineRates.count)
        let respiratoryRates = values.2 ?? []
        let baselineRespiratory = values.3 ?? []
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

    @discardableResult
    func saveWater(amountMl: Double) async throws -> UUID {
        guard isAvailable else { throw HealthStoreError.unavailable }
        guard amountMl.isFinite, amountMl > 0 else { throw HealthStoreError.invalidWaterAmount }
        let now = Date()
        let quantity = HKQuantity(unit: .literUnit(with: .milli), doubleValue: amountMl)
        let sample = HKQuantitySample(type: waterType, quantity: quantity, start: now, end: now, metadata: ["TempoWaterEntry": true])
        try await store.save(sample)
        return sample.uuid
    }

    func removeWater(id: UUID) async throws {
        guard isAvailable else { throw HealthStoreError.unavailable }
        guard store.authorizationStatus(for: waterType) == .sharingAuthorized else {
            throw NSError(domain: "TempoWater", code: 2, userInfo: [NSLocalizedDescriptionKey: "wellness.water.healthRequired".tempoLocalized])
        }
        let sample: HKQuantitySample? = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: waterType, predicate: HKQuery.predicateForObject(with: id), limit: 1, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples?.first as? HKQuantitySample) }
            }
            store.execute(query)
        }
        guard let sample else { return }
        guard sample.sourceRevision.source.bundleIdentifier == Bundle.main.bundleIdentifier,
              (sample.metadata?["TempoWaterEntry"] as? Bool) == true else {
            throw NSError(domain: "TempoWater", code: 1, userInfo: [NSLocalizedDescriptionKey: "wellness.water.notOwned".tempoLocalized])
        }
        try await store.delete(sample)
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
        let highFrequency = Set([HKQuantityTypeIdentifier.heartRate.rawValue, HKQuantityTypeIdentifier.runningPower.rawValue, HKQuantityTypeIdentifier.cyclingPower.rawValue, HKQuantityTypeIdentifier.cyclingCadence.rawValue])
        for type in readTypes.compactMap({ $0 as? HKSampleType }) where !highFrequency.contains(type.identifier) {
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
        let cache = zoneCache
        Task { await cache.removeAll() }
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
        let writeTypes: Set<HKSampleType> = [waterType, sleepType, stepType, HKObjectType.workoutType()]
        try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
        guard writeTypes.allSatisfy({ store.authorizationStatus(for: $0) == .sharingAuthorized }) else {
            throw simulatorCheckError("HealthKit test write permission was not granted for water, sleep, steps and workouts.")
        }

        let calendar = Calendar.autoupdatingCurrent
        let dayStart = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: Date()))!
        let key = Self.dayString(dayStart)
        let runID = UUID().uuidString
        let metadata: [String: Any] = ["TempoSimulatorIntegrationRun": runID]
        let at: (TimeInterval) -> Date = { dayStart.addingTimeInterval($0 * 60) }
        let workout = HKWorkout(activityType: .tennis, start: at(720), end: at(750), duration: 1_800, totalEnergyBurned: nil, totalDistance: HKQuantity(unit: .meter(), doubleValue: 1_200), metadata: metadata)
        let samples: [HKSample] = [
            workout,
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
                            Task {
                                do {
                                    for sample in samples {
                                        guard try await self.simulatorSampleCount(sample) == 0 else {
                                            throw self.simulatorCheckError("A test UUID was still readable after HealthKit cleanup.")
                                        }
                                    }
                                    continuation.resume(with: completed)
                                } catch {
                                    continuation.resume(throwing: error)
                                }
                            }
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
                    guard let imported = try await readRecentWorkouts(dayCount: 7).first(where: { $0.id == workout.uuid }),
                          imported.sportId == "tennis", imported.durationSeconds == 1_800,
                          abs((imported.distanceKm ?? 0) - 1.2) < 0.001, imported.recordSource == "apple-health" else {
                        throw simulatorCheckError("Production workout import did not return the tennis workout with its duration, distance and source.")
                    }
                    // Read permission cannot be inferred: HealthKit may expose an app's own
                    // samples even when access to samples from other apps is denied.
                    outcome = .success("HEALTHKIT_PASS own_samples=7 water_ml=321 steps=1234 sleep_min=180 stages=4 tennis_workouts=1 cleanup=7")
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

private struct HealthWorkoutReadSnapshot { let records: [TempoManualWorkout]; let windows: [HeartRateWorkoutWindow] }
private struct HeartRateQuerySnapshot: Sendable { let readings: [TimedHeartRateReading]; let limited: Bool }

private final class HeartRateQueryBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var readings: [TimedHeartRateReading] = []
    private var completed = false
    func append(_ reading: TimedHeartRateReading) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !completed else { return false }
        if readings.count < 200_000 { readings.append(reading) }
        return readings.count >= 200_000
    }
    func finish(limited: Bool = false, discard: Bool = false) -> HeartRateQuerySnapshot? {
        lock.lock(); defer { lock.unlock() }
        guard !completed else { return nil }
        completed = true
        let snapshot = HeartRateQuerySnapshot(readings: discard ? [] : readings, limited: limited)
        readings = []
        return snapshot
    }
}

private struct HealthWorkoutEffort: Sendable { let value: Double; let estimated: Bool }

// Yalnız kilit altında değişen bitiş bayrağı; zaman aşımı ve HealthKit aynı continuation'ı iki kez bitiremez.
private final class HealthEffortReadGate: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    func claimCompletion() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return false }
        finished = true
        return true
    }
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
