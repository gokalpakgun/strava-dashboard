import Foundation

// Compile with the production aggregator; no test copy of its logic is used.
// swiftc ios/TempoHealth/Sources/TempoSleepAggregation.swift ios/HealthRegressionTests/main.swift -o /tmp/tempo-health-tests
let parser = ISO8601DateFormatter()
func date(_ value: String) -> Date { parser.date(from: value)! }
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(secondsFromGMT: 0)!
let from = date("2026-10-01T00:00:00Z")
let to = date("2026-10-04T23:59:59Z")

func sample(_ start: String, _ end: String, _ stage: TempoSleepStage, _ source: String = "watch") -> TempoSleepInterval {
    TempoSleepInterval(start: date(start), end: date(end), stage: stage, source: source)
}
func aggregate(_ samples: [TempoSleepInterval], start: Date = from, end: Date = to) -> [String: TempoSleepBreakdown] {
    TempoSleepAggregation.dailyBreakdown(samples, from: start, to: end, calendar: calendar)
}
var passed = 0
func check(_ label: String, _ condition: @autoclosure () -> Bool) {
    guard condition() else { fatalError("FAIL: \(label)") }
    passed += 1
    print("PASS: \(label)")
}

let overnight = [
    sample("2026-10-01T23:00:00Z", "2026-10-01T23:30:00Z", .core),
    sample("2026-10-01T23:30:00Z", "2026-10-02T01:00:00Z", .deep),
    sample("2026-10-02T01:00:00Z", "2026-10-02T06:00:00Z", .core),
    sample("2026-10-02T06:00:00Z", "2026-10-02T07:00:00Z", .rem),
]
let night = aggregate(overnight)
check("midnight stages stay on the wake date", night.count == 1 && night["2026-10-02"]?.totalMinutes == 480)
check("night preserves complete stages", night["2026-10-02"]?.coreMinutes == 330 && night["2026-10-02"]?.deepMinutes == 90 && night["2026-10-02"]?.remMinutes == 60)

let durationOnly = aggregate([sample("2026-10-01T23:00:00Z", "2026-10-02T07:00:00Z", .unspecified)])
check("duration-only records keep missing stages unknown", durationOnly["2026-10-02"]?.deepMinutes == nil && durationOnly["2026-10-02"]?.coreMinutes == nil && durationOnly["2026-10-02"]?.remMinutes == nil && durationOnly["2026-10-02"]?.awakeMinutes == nil)
check("duration-only sleep keeps all eight hours", durationOnly["2026-10-02"]?.totalMinutes == 480)

let duplicated = overnight + overnight + [sample("2026-10-01T23:00:00Z", "2026-10-02T07:00:00Z", .unspecified, "phone")]
check("duplicates and generic envelopes cannot double count", aggregate(duplicated) == night)

let overlap = aggregate([
    sample("2026-10-01T23:00:00Z", "2026-10-02T07:00:00Z", .core, "a-watch"),
    sample("2026-10-01T23:00:00Z", "2026-10-02T07:00:00Z", .deep, "b-watch"),
])
check("conflicting devices never add stage durations twice", overlap["2026-10-02"]?.totalMinutes == 480 && overlap["2026-10-02"]?.coreMinutes == 480 && overlap["2026-10-02"]?.deepMinutes == nil)
check("input order cannot change conflicting device selection", aggregate([
    sample("2026-10-01T23:00:00Z", "2026-10-02T07:00:00Z", .deep, "b-watch"),
    sample("2026-10-01T23:00:00Z", "2026-10-02T07:00:00Z", .core, "a-watch"),
]) == overlap)

let interrupted = aggregate([
    sample("2026-10-01T23:00:00Z", "2026-10-02T07:00:00Z", .unspecified, "phone"),
    sample("2026-10-02T02:00:00Z", "2026-10-02T02:30:00Z", .awake),
])
check("awake intervals subtract from a generic sleep envelope", interrupted["2026-10-02"]?.totalMinutes == 450 && interrupted["2026-10-02"]?.awakeMinutes == 30)

let naps = aggregate(overnight + [sample("2026-10-02T15:00:00Z", "2026-10-02T15:30:00Z", .unspecified)])
check("afternoon nap stays on its own calendar date", naps.count == 1 && naps["2026-10-02"]?.totalMinutes == 510)

let boundaryNight = aggregate(overnight, start: date("2026-10-02T00:00:00Z"))
check("oldest requested date retains the preceding evening", boundaryNight == night)
check("night waking before requested range is excluded", aggregate(overnight, start: date("2026-10-03T00:00:00Z")).isEmpty)
check("future sample end is clipped to query time", aggregate([sample("2026-10-02T01:00:00Z", "2026-10-02T09:00:00Z", .core)], end: date("2026-10-02T07:00:00Z"))["2026-10-02"]?.totalMinutes == 360)
check("awake-only records cannot create a sleep score", aggregate([sample("2026-10-02T01:00:00Z", "2026-10-02T02:00:00Z", .awake)]).isEmpty)
check("empty and reversed ranges remain empty", aggregate([]).isEmpty && aggregate(overnight, start: to, end: from).isEmpty)
check("invalid and zero-length intervals are ignored", aggregate([
    sample("2026-10-02T09:00:00Z", "2026-10-02T08:00:00Z", .core),
    sample("2026-10-02T09:00:00Z", "2026-10-02T09:00:00Z", .core),
]).isEmpty)

var newYork = Calendar(identifier: .gregorian)
newYork.timeZone = TimeZone(identifier: "America/New_York")!
let dst = TempoSleepAggregation.dailyBreakdown([
    sample("2026-11-01T00:00:00-04:00", "2026-11-01T08:00:00-05:00", .unspecified),
], from: date("2026-10-31T00:00:00Z"), to: date("2026-11-02T00:00:00Z"), calendar: newYork)
check("DST clock fallback uses elapsed nine hours", dst["2026-11-01"]?.totalMinutes == 540)

var buddhist = Calendar(identifier: .buddhist)
buddhist.timeZone = calendar.timeZone
check("health storage date keys stay Gregorian for other phone calendars", TempoSleepAggregation.dailyBreakdown(overnight, from: from, to: to, calendar: buddhist)["2026-10-02"]?.totalMinutes == 480)
print("\(passed) Health sleep regression checks passed.")
