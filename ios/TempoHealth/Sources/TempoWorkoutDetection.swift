import BackgroundTasks
import Combine
import CoreMotion
import CryptoKit
import Foundation
import HealthKit
import UserNotifications

@MainActor
final class TempoWorkoutDetection: ObservableObject {
    static let shared = TempoWorkoutDetection()
    private var schedulingNotification = false
    static let backgroundID = "com.apitempo.tempohealth.detect-workouts"
    @Published private(set) var enabled = false
    @Published private(set) var candidates: [DetectedWorkout] = []
    @Published private(set) var scanning = false
    @Published private(set) var message = ""
    @Published private(set) var lastScan: Date?
    @Published private(set) var motionAuthorized = false
    @Published private(set) var responseRevision = 0
    var queuedResponses: [PassiveWorkoutResponse] { state.responses ?? [] }
    private(set) var owner: String?
    private let motion = CMMotionActivityManager()
    private let pedometer = CMPedometer()
    private let health = HKHealthStore()
    private var observers: [HKObserverQuery] = []
    private var generation = UUID()
    private var scanTask: Task<Void, Never>?
    private var liveRecordingStart: Date?
    private var state = State()
    private var storageReady = true
    private let center = UNUserNotificationCenter.current()
    private var bootstrapped = false
    var pending: [DetectedWorkout] { candidates.filter { $0.decision == .pending }.sorted { $0.start > $1.start } }
    var healthEnabled: Bool { state.healthEnabled }

    private struct State: Codable {
        var enabled = false
        var healthEnabled = false
        var activatedAt = Date()
        var lastScan: Date?
        var lastNotification: Date?
        var records: [DetectedWorkout] = []
        var known: [DetectionInterval] = []
        var responses: [PassiveWorkoutResponse]? = nil
    }

    /// iOS çağırma zamanını kendisi belirler; sürekli arka plan yürütmesi istenmez.
    func bootstrap() {
        guard !bootstrapped else { return }; bootstrapped = true
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundID, using: nil) { task in
            Task { @MainActor in
                guard let refresh = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
                let work = Task { @MainActor in
                    await self.scan(force: true)
                    self.scheduleBackground()
                    refresh.setTaskCompleted(success: !Task.isCancelled)
                }
                refresh.expirationHandler = { work.cancel() }
            }
        }
        if let savedOwner = UserDefaults.standard.string(forKey: "tempo.detection.activeOwner") {
            load(owner: savedOwner)
            if enabled { startObservers(); scheduleBackground() }
        }
    }

    func bind(owner next: String?, healthEnabled: Bool, known: [DetectionInterval]) {
        if owner != next {
            stopRuntime()
            liveRecordingStart = nil
            owner = nil; state = State(); storageReady = true; candidates = []; enabled = false; message = ""; lastScan = nil
            if let next { load(owner: next) }
        }
        if let next, owner == next, !storageReady { load(owner: next) }
        guard let next else {
            UserDefaults.standard.removeObject(forKey: "tempo.detection.activeOwner")
            return
        }
        UserDefaults.standard.set(next, forKey: "tempo.detection.activeOwner")
        let healthChanged = state.healthEnabled != healthEnabled
        state.healthEnabled = healthEnabled
        state.known = Array(known.filter { $0.end > Date().addingTimeInterval(-3 * 86400) }.prefix(500))
        removeCoveredCandidates()
        persist()
        motionAuthorized = CMMotionActivityManager.authorizationStatus() == .authorized
        if enabled {
            if healthChanged || observers.isEmpty { startObservers() }
            scheduleBackground()
        }
    }

    func enable() async {
        guard owner != nil, storageReady else { return }
        let token = generation
        message = ""
        // Sistem izin ekranı yalnız kullanıcının etkinleştir düğmesinden sonra açılır.
        if CMMotionActivityManager.isActivityAvailable(), CMMotionActivityManager.authorizationStatus() == .notDetermined {
            _ = try? await motionHistory(from: Date().addingTimeInterval(-60), to: Date())
        }
        guard generation == token else { return }
        motionAuthorized = CMMotionActivityManager.authorizationStatus() == .authorized
        guard motionAuthorized || state.healthEnabled else { message = "detection.permissionNeeded".tempoLocalized; return }
        state.enabled = true; state.activatedAt = Date().addingTimeInterval(-24 * 3600)
        enabled = true; persist(); startObservers(); scheduleBackground()
        await scan(force: true)
    }

    func disable() {
        state.enabled = false; enabled = false
        state.responses = []; responseRevision += 1
        stopRuntime(); persist()
        TempoPassiveGym.shared.pauseForDetectionDisable()
    }
    @discardableResult func enableVenueDetection() -> Bool {
        guard owner != nil, storageReady else { return false }
        let previous = state
        state.enabled = true; enabled = true; state.activatedAt = Date().addingTimeInterval(-24 * 3600)
        guard persist() else { state = previous; enabled = previous.enabled; return false }
        startObservers(); scheduleBackground()
        return true
    }
    @discardableResult func addGymVisit(_ visit: PassiveGymVisit, owner expected: String) async -> Bool {
        guard owner == expected, enabled, storageReady else { return false }
        var candidate = DetectedWorkout(id: visit.id, start: visit.start, end: visit.end, origin: .gym, suggestedSport: "fitness")
        candidate.routineName = visit.routine
        guard candidate.isValid else { return false }
        let fresh = WorkoutDetectionEngine.fresh([candidate], existing: state.known, history: state.records, now: Date())
        let previous = state.records
        state.records += fresh
        guard persist() else { state.records = previous; candidates = previous; return false }
        await notifyIfNeeded(generation: generation)
        return true
    }
    func queueResponse(id: UUID, owner expected: String, rpe: Int?) {
        guard owner == expected, enabled, pending.contains(where: { $0.id == id }), rpe.map({ (1...10).contains($0) }) ?? true else { return }
        var responses = state.responses ?? []; responses.removeAll { $0.id == id }
        responses.append(PassiveWorkoutResponse(id: id, rpe: rpe, createdAt: Date()))
        state.responses = Array(responses.suffix(30)); persist(); clearNotifications([id]); responseRevision += 1
    }
    func finishResponse(_ id: UUID) {
        state.responses?.removeAll { $0.id == id }; persist(); responseRevision += 1
    }
    func reportResponseError() { message = "passive.action.failed".tempoLocalized }
    func setLiveRecording(start: Date?) { liveRecordingStart = start }

    func removeAccount(_ accountID: String) {
        TempoPassiveGym.shared.removeAccount(accountID)
        if owner == accountID { disable(); owner = nil; candidates = []; state = State(); UserDefaults.standard.removeObject(forKey: "tempo.detection.activeOwner") }
        try? FileManager.default.removeItem(at: fileURL(owner: accountID))
    }

    func decide(_ candidate: DetectedWorkout, accepted: Bool) {
        guard let index = state.records.firstIndex(where: { $0.id == candidate.id }) else { return }
        state.records[index].decision = accepted ? .accepted : .dismissed
        if !accepted { state.responses?.removeAll { $0.id == candidate.id }; responseRevision += 1 }
        clearNotifications([candidate.id]); persist()
    }

    func requestNotifications() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        await TempoNotifications.shared.reconnect()
        await notifyIfNeeded(generation: generation)
        let settings = await center.notificationSettings()
        message = (settings.authorizationStatus == .denied ? "detection.notificationDenied" : "detection.notificationsReady").tempoLocalized
    }

    func scan(force: Bool = false) async {
        guard enabled, owner != nil, !scanning else { return }
        if !force, let lastScan, Date().timeIntervalSince(lastScan) < 180 { return }
        let token = generation
        scanning = true
        defer { if generation == token { scanning = false } }
        let now = Date()
        let start = max(state.activatedAt, now.addingTimeInterval(-24 * 3600))
        var found: [DetectedWorkout] = []
        var failed = false
        motionAuthorized = CMMotionActivityManager.authorizationStatus() == .authorized
        if motionAuthorized, CMMotionActivityManager.isActivityAvailable(), CMPedometer.isStepCountingAvailable() {
            do {
                let slices = try await motionHistory(from: start, to: now)
                let windows = WorkoutDetectionEngine.motionWindows(slices)
                for window in windows.filter({ $0.end <= now.addingTimeInterval(-120) }).suffix(12) {
                    guard generation == token, !Task.isCancelled else { return }
                    let data = try await steps(from: window.start, to: window.end)
                    if let candidate = WorkoutDetectionEngine.phoneCandidate(window, steps: data.0, distance: data.1) { found.append(candidate) }
                }
            } catch { failed = true }
        }
        guard generation == token, !Task.isCancelled else { return }
        var known = state.known
        if state.healthEnabled, HKHealthStore.isHealthDataAvailable() {
            do {
                let workouts = try await samples(type: HKObjectType.workoutType(), from: start, to: now)
                let nativeIDs = Set(workouts.compactMap { ($0 as? HKWorkout)?.uuid })
                let removed = pending.filter { $0.start >= start && $0.healthWorkoutID.map { !nativeIDs.contains($0) } == true }
                for candidate in removed { decide(candidate, accepted: false) }
                known += workouts.map { DetectionInterval(start: $0.startDate, end: $0.endDate) }
                async let rates = quantities(.heartRate, from: start, to: now, unit: HKUnit.count().unitDivided(by: .minute()))
                async let energy = quantities(.activeEnergyBurned, from: start, to: now, unit: .kilocalorie())
                async let count = quantities(.stepCount, from: start, to: now, unit: .count())
                async let exercise = quantities(.appleExerciseTime, from: start, to: now, unit: .second())
                let values = try await (rates, energy, count, exercise)
                let resting = try await quantities(.restingHeartRate, from: now.addingTimeInterval(-7 * 86400), to: now, unit: HKUnit.count().unitDivided(by: .minute()))
                let bins = Self.bins(start: start, end: now, rates: values.0, energy: values.1, steps: values.2, exercise: values.3)
                var inferred = WorkoutDetectionEngine.healthCandidates(bins, restingHeartRate: resting.last?.value).filter { $0.end <= now.addingTimeInterval(-300) }
                for index in inferred.indices {
                    inferred[index].loadEstimate = PassiveWorkoutEngine.estimate(start: inferred[index].start, end: inferred[index].end, samples: values.0.map { .init(date: $0.start, bpm: $0.value) })
                }
                found += inferred
                for workout in workouts.compactMap({ $0 as? HKWorkout }).suffix(12) where workout.endDate <= now && workout.startDate >= start && (900...14_400).contains(workout.duration) && (workout.metadata?[HKMetadataKeyWasUserEntered] as? Bool) != true {
                    guard generation == token, !Task.isCancelled else { return }
                    let estimate = PassiveWorkoutEngine.estimate(start: workout.startDate, end: workout.endDate, samples: values.0.map { .init(date: $0.start, bpm: $0.value) })
                    if let index = state.records.firstIndex(where: { $0.healthWorkoutID == workout.uuid }) {
                        // Saatin nabız örnekleri antrenman kaydından sonra eşitlenebilir.
                        if state.records[index].decision == .pending { state.records[index].loadEstimate = estimate }
                        continue
                    }
                    let overlapping = state.records.filter { WorkoutDetectionEngine.overlaps(workout.startDate, workout.endDate, DetectionInterval(start: $0.start, end: $0.end)) }
                    let replacementID = WorkoutDetectionEngine.nativeReplacementID(start: workout.startDate, end: workout.endDate, history: overlapping, queued: Set(queuedResponses.map(\.id)))
                    var candidate = DetectedWorkout(id: replacementID ?? workout.uuid, start: workout.startDate, end: workout.endDate, origin: .health, suggestedSport: Self.sportID(workout.workoutActivityType) ?? "fitness")
                    candidate.primarySportIsKnown = Self.sportID(workout.workoutActivityType) != nil
                    candidate.healthWorkoutID = workout.uuid; candidate.loadEstimate = estimate
                    let rates = values.0.filter { $0.start >= workout.startDate && $0.start < workout.endDate }
                    candidate.averageHeartRate = rates.isEmpty ? nil : rates.reduce(0) { $0 + $1.value } / Double(rates.count)
                    candidate.activeEnergy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
                    candidate.notified = overlapping.contains { $0.notified || $0.decision != .pending }
                    if let decision = overlapping.first(where: { $0.decision != .pending })?.decision { candidate.decision = decision }
                    guard candidate.isValid else { continue }
                    for prior in overlapping where prior.id != candidate.id && prior.decision == .pending && !queuedResponses.contains(where: { $0.id == prior.id }) { decide(prior, accepted: false) }
                    if let index = state.records.firstIndex(where: { $0.id == candidate.id }) { state.records[index] = candidate }
                    else { state.records.append(candidate) }
                }
            } catch { failed = true }
        }
        guard generation == token, !Task.isCancelled else { return }
        // Yeni Sağlık kaydı sonradan geldiyse bekleyen öneri sessizce kaldırılır.
        state.known = Array(Set(known.filter { $0.end > now.addingTimeInterval(-3 * 86400) }).sorted { $0.start > $1.start }.prefix(500))
        removeCoveredCandidates()
        let live = liveRecordingStart.map { [DetectionInterval(start: $0, end: now)] } ?? []
        let fresh = WorkoutDetectionEngine.fresh(found, existing: known + live, history: state.records, now: now)
        state.records += fresh
        state.records = Array(state.records.filter { $0.end > now.addingTimeInterval(-7 * 86400) }.sorted { $0.start > $1.start }.prefix(100))
        state.lastScan = now; lastScan = now
        message = (failed ? "detection.partial" : "").tempoLocalized
        persist()
        await notifyIfNeeded(generation: token)
    }

    private func startObservers() {
        motion.stopActivityUpdates()
        observers.forEach { health.stop($0) }; observers = []
        guard enabled else { return }
        if CMMotionActivityManager.authorizationStatus() == .authorized {
            motion.startActivityUpdates(to: .main) { [weak self] _ in
                Task { @MainActor in self?.queueScan() }
            }
        }
        if state.healthEnabled, HKHealthStore.isHealthDataAvailable() {
            let types: [HKSampleType] = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.appleExerciseTime), HKQuantityType(.heartRate)]
            for type in types {
                let isWorkout = type == HKObjectType.workoutType()
                let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, complete, error in
                    guard error == nil else { complete(); return }
                    Task { @MainActor in
                        defer { complete() }
                        await self?.scan(force: isWorkout)
                    }
                }
                observers.append(query); health.execute(query)
                health.enableBackgroundDelivery(for: type, frequency: type == HKObjectType.workoutType() ? .immediate : .hourly) { _, _ in }
            }
        }
    }
    private func queueScan() {
        guard scanTask == nil else { return }
        scanTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            guard let self else { return }
            self.scanTask = nil
            await self.scan()
        }
    }
    private func stopRuntime() {
        generation = UUID(); scanTask?.cancel(); scanTask = nil; scanning = false
        motion.stopActivityUpdates(); observers.forEach { health.stop($0) }; observers = []
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundID)
        clearNotifications(state.records.map(\.id))
    }
    private func scheduleBackground() {
        guard enabled, bootstrapped else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundID)
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundID)
        request.earliestBeginDate = Date().addingTimeInterval(30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
    private func removeCoveredCandidates() {
        let covered = state.records.filter { candidate in candidate.decision == .pending && candidate.healthWorkoutID == nil && !queuedResponses.contains(where: { $0.id == candidate.id }) && state.known.contains { WorkoutDetectionEngine.overlaps(candidate.start, candidate.end, $0) } }
        for item in covered {
            if let index = state.records.firstIndex(where: { $0.id == item.id }) { state.records[index].decision = .dismissed }
        }
        clearNotifications(covered.map(\.id))
    }
    private func notifyIfNeeded(generation token: UUID) async {
        guard !schedulingNotification, enabled, let owner, state.lastNotification.map({ Date().timeIntervalSince($0) >= 10 * 60 }) ?? true,
              let candidate = pending.first(where: { candidate in
                  guard !candidate.notified, candidate.end > Date().addingTimeInterval(-6 * 3600) else { return false }
                  if let liveRecordingStart { return !WorkoutDetectionEngine.overlaps(candidate.start, candidate.end, DetectionInterval(start: liveRecordingStart, end: Date())) }
                  return true
              }) else { return }
        schedulingNotification = true
        defer { schedulingNotification = false }
        let settings = await center.notificationSettings()
        guard pending.contains(where: { $0.id == candidate.id && !$0.notified }), generation == token, enabled, [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }
        let content = UNMutableNotificationContent()
        content.title = "detection.notificationTitle".tempoLocalized
        content.body = PassiveWorkoutNotifications.body(for: candidate)
        content.categoryIdentifier = candidate.origin == .gym ? PassiveWorkoutNotifications.gymCategory : PassiveWorkoutNotifications.workoutCategory
        content.sound = .default
        content.userInfo = ["tempo": ["destination": "detection", "owner": owner, "candidate": candidate.id.uuidString]]
        do {
            try await center.add(UNNotificationRequest(identifier: "tempo-detected-" + candidate.id.uuidString, content: content, trigger: nil))
            guard generation == token, enabled, pending.contains(where: { $0.id == candidate.id }) else { clearNotifications([candidate.id]); return }
            if let index = state.records.firstIndex(where: { $0.id == candidate.id }) { state.records[index].notified = true }
            state.lastNotification = Date(); persist()
        } catch { /* Öneri uygulama içinde görünmeye devam eder. */ }
    }
    private func clearNotifications(_ ids: [UUID]) {
        let identifiers = ids.map { "tempo-detected-" + $0.uuidString }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
    private func fileURL(owner: String) -> URL {
        let name = SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WorkoutDetection", isDirectory: true).appendingPathComponent(name + ".json")
    }
    private static func sportID(_ type: HKWorkoutActivityType) -> String? {
        switch type {
        case .running: "run"
        case .walking: "walking"
        case .cycling: "cycling"
        case .swimming: "swimming"
        case .hiking: "hiking"
        case .tennis, .tableTennis: "tennis"
        case .basketball: "basketball"
        case .soccer, .americanFootball: "football"
        case .volleyball: "volleyball"
        case .badminton: "badminton"
        case .yoga, .pilates, .taiChi, .mindAndBody: "yoga"
        case .traditionalStrengthTraining, .functionalStrengthTraining, .crossTraining, .highIntensityIntervalTraining: "fitness"
        default: nil
        }
    }
    private func load(owner: String) {
        self.owner = owner
        let url = fileURL(owner: owner)
        if FileManager.default.fileExists(atPath: url.path) {
            guard let data = try? Data(contentsOf: url), data.count <= 2_000_000, let saved = try? JSONDecoder().decode(State.self, from: data) else {
                storageReady = false; enabled = false; message = "detection.storageError".tempoLocalized; return
            }
            state = saved
        }
        storageReady = true
        state.records.removeAll { $0.end < Date().addingTimeInterval(-7 * 86400) }
        state.records.removeAll { !$0.isValid }
        enabled = state.enabled; candidates = state.records; lastScan = state.lastScan
        motionAuthorized = CMMotionActivityManager.authorizationStatus() == .authorized
    }
    @discardableResult private func persist() -> Bool {
        candidates = state.records
        guard let owner, storageReady else { return false }
        do {
            let url = fileURL(owner: owner)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            var file = url; try? file.setResourceValues(values)
            return true
        } catch { message = "detection.storageError".tempoLocalized; return false }
    }

    private func motionHistory(from start: Date, to end: Date) async throws -> [WorkoutDetectionEngine.MotionSlice] {
        try await query { gate in
            gate.arm { }
            motion.queryActivityStarting(from: start, to: end, to: .main) { values, error in
                Task { @MainActor in
                    if let error { gate.finish(.failure(error)); return }
                    let sorted = (values ?? []).sorted { $0.startDate < $1.startDate }
                    let slices = sorted.enumerated().map { index, item in
                        WorkoutDetectionEngine.MotionSlice(start: max(start, item.startDate), end: min(end, index + 1 < sorted.count ? sorted[index + 1].startDate : end), kind: item.automotive ? .vehicle : (item.running ? .running : (item.walking ? .walking : .other)), reliable: item.confidence != .low)
                    }
                    gate.finish(.success(slices))
                }
            }
        }
    }
    private func steps(from start: Date, to end: Date) async throws -> (Int, Double?) {
        try await query { gate in
            gate.arm { }
            pedometer.queryPedometerData(from: start, to: end) { data, error in
                Task { @MainActor in
                    if let error { gate.finish(.failure(error)) }
                    else if let data { gate.finish(.success((data.numberOfSteps.intValue, data.distance?.doubleValue))) }
                    else { gate.finish(.failure(DetectionError.noData)) }
                }
            }
        }
    }
    private func samples(type: HKSampleType, from start: Date, to end: Date) async throws -> [HKSample] {
        try await query { gate in
            let query = HKSampleQuery(sampleType: type, predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: []), limit: 20_000, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, values, error in
                Task { @MainActor in
                    if let error { gate.finish(.failure(error)) }
                    else { gate.finish(.success((values ?? []).filter { $0 is HKWorkout || ($0.metadata?[HKMetadataKeyWasUserEntered] as? Bool) != true })) }
                }
            }
            gate.arm { self.health.stop(query) }; health.execute(query)
        }
    }
    private func query<Value>(_ start: (DetectionQueryGate<Value>) -> Void) async throws -> Value {
        let gate = DetectionQueryGate<Value>()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                if gate.install(continuation) { start(gate) }
            }
        } onCancel: {
            Task { @MainActor in gate.cancel() }
        }
    }
    private struct Quantity {
        let start: Date; let end: Date; let value: Double; let source: String
    }
    private func quantities(_ type: HKQuantityTypeIdentifier, from start: Date, to end: Date, unit: HKUnit) async throws -> [Quantity] {
        try await samples(type: HKQuantityType(type), from: start, to: end).compactMap { sample in
            guard let value = sample as? HKQuantitySample else { return nil }
            let number = value.quantity.doubleValue(for: unit)
            guard number.isFinite, number >= 0 else { return nil }
            let source = sample.sourceRevision.source.bundleIdentifier + "|" + (sample.sourceRevision.productType ?? sample.device?.model ?? "") + "|" + (sample.device?.localIdentifier ?? "")
            return Quantity(start: sample.startDate, end: sample.endDate, value: number, source: source)
        }
    }
    private static func bins(start: Date, end: Date, rates: [Quantity], energy: [Quantity], steps: [Quantity], exercise: [Quantity]) -> [WorkoutDetectionEngine.HealthBin] {
        let anchor = floor(start.timeIntervalSince1970 / 300) * 300
        let count = min(289, max(0, Int((end.timeIntervalSince1970 - anchor) / 300)))
        var heartRates = Array(repeating: [Double](), count: count)
        var rateTimes = Set<Int>()
        for sample in rates {
            let index = Int((sample.start.timeIntervalSince1970 - anchor) / 300)
            let timeKey = Int(sample.start.timeIntervalSince1970 / 30)
            if (0..<count).contains(index), (30...220).contains(sample.value), rateTimes.insert(timeKey).inserted { heartRates[index].append(sample.value) }
        }
        func totals(_ samples: [Quantity]) -> [Double] {
            var result = Array(repeating: [String: Double](), count: count)
            for sample in samples {
                let duration = sample.end.timeIntervalSince(sample.start)
                // Uzun günlük toplamlar yapay şekilde kısa efor pencerelerine dağıtılmaz.
                guard duration > 0, duration <= 600 else { continue }
                let low = max(0, Int(floor((sample.start.timeIntervalSince1970 - anchor) / 300)))
                let high = min(count - 1, Int(floor((sample.end.timeIntervalSince1970 - anchor) / 300)))
                guard low <= high else { continue }
                for index in low...high {
                    let a = Date(timeIntervalSince1970: anchor + Double(index) * 300)
                    let overlap = max(0, min(sample.end, a.addingTimeInterval(300)).timeIntervalSince(max(sample.start, a)))
                    result[index][sample.source, default: 0] += sample.value * overlap / duration
                }
            }
            // Telefon+saat aynı kaloriyi/adımı iki kez saymasın.
            return result.map { $0.values.max() ?? 0 }
        }
        let calories = totals(energy), stepCounts = totals(steps), exerciseTime = totals(exercise)
        return (0..<count).map { index in
            let values = heartRates[index]
            return WorkoutDetectionEngine.HealthBin(start: Date(timeIntervalSince1970: anchor + Double(index) * 300), heartRate: values.isEmpty ? nil : values.reduce(0, +) / Double(values.count), heartRateCount: values.count, energyKcal: calories[index], steps: stepCounts[index], exerciseSeconds: exerciseTime[index])
        }
    }
}

private enum DetectionError: Error { case timeout, noData }

/// Geç gelen callback ve zaman aşımı aynı continuation'ı iki kez tamamlayamaz.
@MainActor
private final class DetectionQueryGate<Value> {
    private var continuation: CheckedContinuation<Value, Error>?
    private var timeout: Task<Void, Never>?
    private var finished = false
    private var cancellation: (() -> Void)?
    func install(_ continuation: CheckedContinuation<Value, Error>) -> Bool {
        guard !finished else { continuation.resume(throwing: CancellationError()); return false }
        self.continuation = continuation
        return true
    }
    func cancel() {
        cancellation?()
        finish(.failure(CancellationError()))
    }
    func arm(cancel: @escaping () -> Void) {
        cancellation = cancel
        timeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
            cancel(); self?.finish(.failure(DetectionError.timeout))
        }
    }
    func finish(_ result: Result<Value, Error>) {
        guard !finished else { return }; finished = true
        let continuation = self.continuation
        self.continuation = nil; timeout?.cancel(); timeout = nil; cancellation = nil
        continuation?.resume(with: result)
    }
}
