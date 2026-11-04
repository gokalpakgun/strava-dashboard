import Foundation

var checks = 0
@MainActor func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { fatalError("DETECTION_FAIL: " + message) }
}
let now = Date(timeIntervalSince1970: 1_793_500_000)
let start = now.addingTimeInterval(-3600)
typealias Engine = WorkoutDetectionEngine
func motion(_ offset: Double, _ minutes: Double, _ kind: Engine.MotionKind, reliable: Bool = true) -> Engine.MotionSlice {
    Engine.MotionSlice(start: start.addingTimeInterval(offset * 60), end: start.addingTimeInterval((offset + minutes) * 60), kind: kind, reliable: reliable)
}
let walk = Engine.motionWindows([motion(0, 20, .walking)])
expect(walk.count == 1, "sustained walking creates a review window")
expect(Engine.phoneCandidate(walk[0], steps: 1800, distance: 1500) != nil, "measured sustained walking is eligible")
expect(Engine.phoneCandidate(walk[0], steps: 100, distance: nil) == nil, "motion label alone must not create exercise")
expect(Engine.phoneCandidate(walk[0], steps: 1800, distance: 20_000) == nil, "vehicle-like speed rejected")
expect(Engine.phoneCandidate(walk[0], steps: 9000, distance: nil) == nil, "implausible step cadence rejected")
expect(Engine.motionWindows([motion(0, 40, .vehicle)]).isEmpty, "driving never creates a movement window")
expect(Engine.motionWindows([motion(0, 30, .walking, reliable: false)]).isEmpty, "low confidence is not exercise")
expect(Engine.motionWindows([motion(0, 5, .walking)]).isEmpty, "short errands are not suggested")
expect(Engine.motionWindows([motion(0, 10, .walking), motion(10, 1, .vehicle), motion(11, 10, .walking)]).isEmpty, "car segment breaks walking continuity")
expect(Engine.motionWindows([motion(0, 8, .walking), motion(8, 1, .other), motion(9, 8, .walking)]).count == 1, "brief rest may remain in workout")
expect(Engine.motionWindows([motion(0, 8, .walking), motion(8, 4, .other), motion(12, 8, .walking)]).isEmpty, "long rests split unrelated movement")
let run = Engine.motionWindows([motion(0, 20, .running)])[0]
expect(Engine.phoneCandidate(run, steps: 3100, distance: 3000)?.suggestedSport == "run", "running classification needs cadence support")
expect(Engine.phoneCandidate(run, steps: 1500, distance: 1000)?.suggestedSport == "walking", "brief running classification does not force a run")

func bin(_ offset: Double, hr: Double? = 130, samples: Int = 4, energy: Double = 30, steps: Double = 0, exercise: Double = 0) -> Engine.HealthBin {
    Engine.HealthBin(start: start.addingTimeInterval(offset * 60), heartRate: hr, heartRateCount: samples, energyKcal: energy, steps: steps, exerciseSeconds: exercise)
}
let lifting = [bin(0), bin(5), bin(10), bin(15)]
let detected = Engine.healthCandidates(lifting, restingHeartRate: 65)
expect(detected.count == 1, "stationary lifting can be suggested with repeated HR and strong energy")
expect(detected[0].seconds == 1200, "observed time window retained")
expect(detected[0].averageHeartRate == 130, "only measured HR retained")
expect(Engine.healthCandidates([bin(0)], restingHeartRate: 60).isEmpty, "single HR spike not enough")
expect(Engine.healthCandidates([bin(0, energy: 0), bin(5, energy: 0), bin(10, energy: 0)], restingHeartRate: 60).isEmpty, "elevated HR without physical support rejected")
expect(Engine.healthCandidates([bin(0, samples: 1), bin(5, samples: 1), bin(10, samples: 1)], restingHeartRate: nil).isEmpty, "sparse HR is insufficient")
expect(Engine.healthCandidates([bin(0, hr: nil), bin(5, hr: nil), bin(10, hr: nil)], restingHeartRate: nil).isEmpty, "energy alone never invents HR")
expect(Engine.healthCandidates([bin(0, hr: 85), bin(5, hr: 85), bin(10, hr: 85)], restingHeartRate: 60).isEmpty, "ordinary resting physiology rejected")
expect(Engine.healthCandidates([bin(0), bin(25), bin(50)], restingHeartRate: 60).isEmpty, "large sample gaps are not bridged")
expect(Engine.healthCandidates([bin(0, steps: .infinity), bin(5, steps: .infinity), bin(10, steps: .infinity)], restingHeartRate: 60).isEmpty, "malformed telemetry cannot crash or create workouts")
expect(Engine.healthCandidates([bin(0, energy: .nan), bin(5, energy: .nan), bin(10, energy: .nan)], restingHeartRate: 60).isEmpty, "NaN energy is rejected")
let trailing = Engine.healthCandidates(lifting + [bin(20, hr: 75, energy: 50)], restingHeartRate: 65)
expect(trailing[0].activeEnergy == 120, "trailing recovery outside inferred window excluded from calories")
let phone = Engine.phoneCandidate(walk[0], steps: 1800, distance: 1500)!
let existing = DetectionInterval(start: start.addingTimeInterval(60), end: start.addingTimeInterval(1140))
expect(Engine.fresh([phone], existing: [existing], history: [], now: now).isEmpty, "existing workout suppresses duplicate suggestion")
var dismissed = phone; dismissed.decision = .dismissed
expect(Engine.fresh([phone], existing: [], history: [dismissed], now: now).isEmpty, "rejected window is not suggested repeatedly")
expect(Engine.fresh([phone] + detected, existing: [], history: [], now: now).count == 1, "phone and watch observations merge into one suggestion")
expect(Engine.fresh([phone], existing: [], history: [], now: start).isEmpty, "future/unfinished windows rejected")
let distant = DetectionInterval(start: start.addingTimeInterval(-3600), end: start.addingTimeInterval(-1800))
expect(!Engine.overlaps(phone.start, phone.end, distant), "separate sessions remain separate")

let healthRecord = TempoWorkoutLedger.Record(id: UUID(), sportID: "fitness", startedAt: start.addingTimeInterval(60), seconds: 1080, distanceKm: nil, source: "apple-health")
let inferredRecord = TempoWorkoutLedger.Record(id: phone.id, sportID: "walking", startedAt: phone.start, seconds: phone.seconds, distanceKm: 1.5, source: "detected-motion")
let merged = TempoWorkoutLedger.merge([inferredRecord, healthRecord], now: now)
expect(merged.count == 1 && merged[0].source == "apple-health", "later real workout replaces overlapping inferred totals even after sport correction")
expect(TempoWorkoutLedger.merge([inferredRecord], now: now).count == 1, "confirmed detection appears in activity/week/month totals")

// Pasif yük motoru gözlenmeyen süreyi veriyle doldurmaz.
let passiveStart = now.addingTimeInterval(-3_600)
let steadyRates = (0..<240).map { PassiveWorkoutEngine.HeartRate(date: passiveStart.addingTimeInterval(Double($0) * 15), bpm: 150) }
let steadyEstimate = PassiveWorkoutEngine.estimate(start: passiveStart, end: now, samples: steadyRates)
expect(steadyEstimate.pattern == .sustained && steadyEstimate.coverage == 1 && steadyEstimate.weightedMinutes == 180, "continuous heart-rate coverage and Edwards dose")
expect(steadyEstimate.strain == 7 && steadyEstimate.maximumHeartRateWasEstimated, "documented v1 strain normalization and default maximum")
let actualMaximum = PassiveWorkoutEngine.estimate(start: passiveStart, end: now, samples: steadyRates, maximumHeartRate: 180)
expect(!actualMaximum.maximumHeartRateWasEstimated && (1...10).contains(actualMaximum.strain ?? 0), "measured maximum is distinguished")
let intervalRates = (0..<240).map { PassiveWorkoutEngine.HeartRate(date: passiveStart.addingTimeInterval(Double($0) * 15), bpm: 125 + 30 * sin(Double($0) * .pi / 16)) }
expect(PassiveWorkoutEngine.estimate(start: passiveStart, end: now, samples: intervalRates).pattern == .intervals, "repeated peaks and recoveries are a pattern, not a confirmed sport")
let sparseRates = (0..<30).map { PassiveWorkoutEngine.HeartRate(date: passiveStart.addingTimeInterval(Double($0) * 120), bpm: 155) }
let sparseEstimate = PassiveWorkoutEngine.estimate(start: passiveStart, end: now, samples: sparseRates)
expect(sparseEstimate.strain == nil && sparseEstimate.coverage <= 0.25, "sparse watch samples do not become continuous exercise")
expect(PassiveWorkoutEngine.estimate(start: passiveStart, end: now, samples: []).strain == nil, "locker phone without watch has no invented strain")
let duplicateRates = Array(repeating: PassiveWorkoutEngine.HeartRate(date: passiveStart, bpm: 180), count: 240)
expect(PassiveWorkoutEngine.estimate(start: passiveStart, end: now, samples: duplicateRates).strain == nil, "duplicate timestamps do not manufacture coverage")
let invalidRates = (0..<240).map { PassiveWorkoutEngine.HeartRate(date: passiveStart.addingTimeInterval(Double($0) * 15), bpm: .nan) }
expect(PassiveWorkoutEngine.estimate(start: passiveStart, end: now, samples: invalidRates).strain == nil, "invalid rates rejected")
expect(PassiveWorkoutEngine.estimate(start: now, end: passiveStart, samples: steadyRates).strain == nil, "reversed window rejected")
expect(PassiveWorkoutEngine.estimate(start: now.addingTimeInterval(-600), end: now, samples: steadyRates).strain == nil, "brief fluctuations are not workouts")
expect(PassiveWorkoutEngine.estimate(start: passiveStart, end: now, samples: steadyRates, maximumHeartRate: .infinity).maximumHeartRateWasEstimated, "invalid maximum uses explicit fallback")
let restRates = (0..<240).map { PassiveWorkoutEngine.HeartRate(date: passiveStart.addingTimeInterval(Double($0) * 15), bpm: 70) }
expect(PassiveWorkoutEngine.estimate(start: passiveStart, end: now, samples: restRates).strain == nil, "resting data does not get minimum exercise strain")
for value in ["0", "11", "-1", "5.5", "seven", ""] { expect(PassiveWorkoutEngine.rpe(from: value) == nil, "invalid RPE rejected: \(value)") }
expect(PassiveWorkoutEngine.rpe(from: " 7 ") == 7 && PassiveWorkoutEngine.rpe(from: "10") == 10 && PassiveWorkoutEngine.rpe(from: "1") == 1, "RPE uses the user's explicit 1-10 scale")

// Geofence yalnız ziyaret önerisi verir, süre veya program tamamlandığını varsaymaz.
var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
let tuesday = utc.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 23, minute: 50))!
let gym = PassiveGymConfiguration(name: "Gym", latitude: 41, longitude: 29, routines: [3: "Push", 5: "Pull"])
expect(gym.isValid && gym.routine(at: tuesday, calendar: utc) == "Push", "weekday routine mapping")
var session = PassiveGymSession(); session.enter(at: tuesday); session.enter(at: tuesday.addingTimeInterval(60))
expect(session.enteredAt == tuesday, "duplicate region entry does not reset session")
let visit = session.exit(at: tuesday.addingTimeInterval(52 * 60), configuration: gym, calendar: utc)
expect(visit?.routine == "Push" && visit?.end.timeIntervalSince(visit!.start) == 52 * 60, "cross-midnight visit uses entry day's routine")
expect(session.exit(at: tuesday.addingTimeInterval(53 * 60), configuration: gym) == nil, "duplicate exit does not produce another suggestion")
var brief = PassiveGymSession(); brief.enter(at: tuesday)
expect(brief.exit(at: tuesday.addingTimeInterval(300), configuration: gym) == nil, "passing the gym briefly is ignored")
var stale = PassiveGymSession(); stale.enter(at: tuesday)
expect(stale.exit(at: tuesday.addingTimeInterval(5 * 3_600), configuration: gym) == nil, "missing exit cannot create all-day training")
var refreshedLong = PassiveGymSession(); refreshedLong.enter(at: tuesday)
refreshedLong.enter(at: tuesday.addingTimeInterval(4 * 3_600 + 60))
expect(refreshedLong.enteredAt == tuesday, "foreground inside-state refresh must preserve original gym arrival")
let restoredLong = try! JSONDecoder().decode(PassiveGymSession.self, from: JSONEncoder().encode(refreshedLong))
expect(restoredLong.enteredAt == tuesday, "refreshed arrival remains stable across restart")
expect(refreshedLong.exit(at: tuesday.addingTimeInterval(5 * 3_600), configuration: gym) == nil, "repeated inside events cannot turn an overlong visit into an invented short workout")
var order = PassiveGymSession(); order.enter(at: tuesday)
expect(order.exit(at: tuesday.addingTimeInterval(-30), configuration: gym) == nil && order.enteredAt == tuesday, "out-of-order events ignored without losing entry")
let savedSession = try! JSONDecoder().decode(PassiveGymSession.self, from: JSONEncoder().encode(order))
expect(savedSession.enteredAt == tuesday, "entry survives process restart")
let invalidGym = PassiveGymConfiguration(name: "", latitude: .nan, longitude: 300, routines: [9: "Invalid"])
expect(!invalidGym.isValid, "invalid gym definition rejected")
let venueRecord = TempoWorkoutLedger.Record(id: UUID(), sportID: "fitness", startedAt: start, seconds: 1200, distanceKm: nil, source: "detected-gym")
expect(TempoWorkoutLedger.merge([venueRecord], now: now).count == 1, "user-confirmed gym visit appears in local history")
expect(TempoWorkoutLedger.merge([venueRecord, healthRecord], now: now).count == 1, "real watch workout replaces gym visit in totals")
var badCandidate = phone; badCandidate.activeEnergy = .infinity
expect(!badCandidate.isValid && Engine.fresh([badCandidate], existing: [], history: [], now: now).isEmpty, "invalid candidate cannot reach confirmation or UI")
var legacyObject = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(phone)) as! [String: Any]
for key in ["loadEstimate", "healthWorkoutID", "primarySportIsKnown", "routineName"] { legacyObject.removeValue(forKey: key) }
let legacyCandidate = try! JSONDecoder().decode(DetectedWorkout.self, from: JSONSerialization.data(withJSONObject: legacyObject))
expect(legacyCandidate.id == phone.id && legacyCandidate.loadEstimate == nil, "old detection records remain readable")
expect(Engine.nativeReplacementID(start: phone.start, end: phone.end, history: [phone], queued: []) == phone.id, "native arrival retains the existing notification identity")
expect(Engine.nativeReplacementID(start: phone.start, end: phone.end, history: [phone], queued: [phone.id]) == nil, "queued user response is not replaced mid-commit")
expect(Engine.nativeReplacementID(start: phone.start, end: phone.end, history: [dismissed], queued: []) == nil, "dismissed proposal identity is not revived")
expect(Engine.nativeReplacementID(start: distant.start, end: distant.end, history: [phone], queued: []) == nil, "separate sessions cannot overwrite each other")
print("DETECTION_CORE_PASS checks=\(checks) swift6=true")
