import Foundation

// Compiles the production ledger itself, with no copy of its logic.
let formatter = ISO8601DateFormatter()
func date(_ s: String) -> Date { formatter.date(from: s)! }
let now = date("2026-10-24T12:00:00Z")
let start = date("2026-10-23T08:00:00Z")
var count = 0
func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    guard condition() else { fatalError("FAIL: \(name)") }
    count += 1; print("PASS: \(name)")
}
func record(_ n: Int, _ sport: String = "run", _ source: String = "manual", _ offset: Double = 0, _ seconds: Double = 1_200, _ km: Double? = 2) -> TempoWorkoutLedger.Record {
    TempoWorkoutLedger.Record(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!, sportID: sport, startedAt: start.addingTimeInterval(offset), seconds: seconds, distanceKm: km, source: source)
}
let phone = record(1, "run", "phone-gps")
let healthCopy = record(2, "run", "apple-health", 5)
let tennis = record(3, "tennis", "apple-health", 1_800, 1_800, 1.2)
let basketball = record(4, "basketball", "apple-health", 4_000, 2_400, nil)
let merged = TempoWorkoutLedger.merge([healthCopy, tennis, phone, basketball], now: now)
check("Health copy does not duplicate a phone workout", merged.count == 3 && merged.contains(phone) && !merged.contains(healthCopy))
check("exact seconds survive merging", merged.reduce(0) { $0 + $1.seconds } == 5_400)
check("missing distance does not discard court sports", abs(merged.reduce(0) { $0 + ($1.distanceKm ?? 0) } - 3.2) < 0.0001)
check("input order does not change the display ledger", TempoWorkoutLedger.merge([basketball, phone, tennis, healthCopy], now: now) == merged)
check("repeated UUID is not counted again", TempoWorkoutLedger.merge([phone, phone], now: now).count == 1)
check("separate local sets stay separate", TempoWorkoutLedger.merge([phone, record(5)], now: now).count == 2)
check("different sports at the same time stay separate", TempoWorkoutLedger.merge([phone, record(6, "tennis", "apple-health")], now: now).count == 2)
check("back-to-back workouts stay separate", TempoWorkoutLedger.merge([phone, record(7, "run", "apple-health", 1_200)], now: now).count == 2)
check("different lengths stay separate", TempoWorkoutLedger.merge([phone, record(8, "run", "apple-health", 0, 2_400)], now: now).count == 2)
check("different distances stay separate", TempoWorkoutLedger.merge([phone, record(9, "run", "apple-health", 0, 1_200, 8)], now: now).count == 2)
check("unknown distance can still match an imported copy", TempoWorkoutLedger.merge([phone, record(10, "run", "apple-health", 0, 1_200, nil)], now: now).count == 1)
check("Strava API data never enters local analytics", TempoWorkoutLedger.merge([record(11, "run", "strava")], now: now).isEmpty)
for (label, bad) in [("zero duration", record(12,"run","manual",0,0)), ("invalid duration", record(13,"run","manual",0,.nan)), ("negative distance", record(14,"run","manual",0,60,-1)), ("invalid distance",record(15,"run","manual",0,60,.infinity)), ("future workout",record(16,"run","manual",1_000_000))] {
    check("exclude " + label, TempoWorkoutLedger.merge([bad], now: now).isEmpty)
}
check("newest records display first", merged.map(\.id) == [basketball.id, tennis.id, phone.id])
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
calendar.firstWeekday = 2
let monday = date("2026-10-18T21:00:00Z")
let boundary = [
    TempoWorkoutLedger.Record(id: UUID(), sportID: "tennis", startedAt: monday, seconds: 60, distanceKm: nil, source: "manual"),
    TempoWorkoutLedger.Record(id: UUID(), sportID: "run", startedAt: monday.addingTimeInterval(-1), seconds: 60, distanceKm: nil, source: "manual"),
    TempoWorkoutLedger.Record(id: UUID(), sportID: "run", startedAt: now.addingTimeInterval(60), seconds: 60, distanceKm: nil, source: "manual")
]
check("week uses local timezone and includes its first instant", TempoWorkoutLedger.currentWeek(boundary, now: now, calendar: calendar).map(\.sportID) == ["tennis"])
calendar.timeZone = TimeZone(identifier: "America/New_York")!
let dstNow = date("2026-11-01T18:00:00Z")
calendar.firstWeekday = 1
let dstRecord = TempoWorkoutLedger.Record(id: UUID(), sportID: "walking", startedAt: date("2026-11-01T05:30:00Z"), seconds: 60, distanceKm: nil, source: "manual")
check("DST transition keeps same-week workouts", TempoWorkoutLedger.currentWeek([dstRecord], now: dstNow, calendar: calendar).count == 1)
print("WORKOUT_LEDGER_PASS assertions=\(count)")
