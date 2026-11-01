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
print("DETECTION_CORE_PASS checks=\(checks) swift6=true")
