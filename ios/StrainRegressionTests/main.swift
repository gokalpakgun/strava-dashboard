import Foundation

let now = Date(timeIntervalSince1970: 1_800_000_000)
var checked = 0
@MainActor func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    precondition(condition(), label); checked += 1
}
@MainActor func workout(_ id: String, archetype: SportArchetype = .endurance, minutes: Double = 30, rpe: Double? = nil, zones: [Double?]? = nil, burst: Double? = nil, end: Date = now.addingTimeInterval(-60), source: StrainRecordSource = .tempo, mindBody: Bool = false) -> StrainWorkout {
    var payload = WorkoutPayload.empty(for: archetype)
    payload.loadInputs = WorkoutLoadInputs(sessionRPE: rpe, zones: zones.map { HeartRateZones(seconds: $0) }, explosiveSeconds: burst)
    return StrainWorkout(id: id, startedAt: end.addingTimeInterval(-minutes * 60), durationSeconds: minutes * 60, payload: payload, source: source, isMindBody: mindBody)
}
let engine = UniversalStrainEngine()

let zone3 = workout("zone3", zones: [0, 0, 1_800, 0, 0])
let trimp = engine.score(for: zone3)!
check(trimp.cardioTRIMP == 90, "30 dakika Z3 = 90 TRIMP")
check(trimp.cardioLoad == 45 && trimp.value == 45, "V1 normalizasyonu")
check(trimp.muscleLoad == nil, "Eksik kas yükü sıfır sayılmaz")
check(engine.score(for: workout("missing")) == nil, "Veri yoksa puan yok")
check(engine.score(for: workout("partial", zones: [0, 0, 900, 0, 0])) == nil, "Yetersiz nabız kapsaması puanlanmaz")
check(engine.score(for: workout("incomplete", zones: [0, nil, 1_800, 0, 0])) == nil, "Eksik bölge süresi reddedilir")
check(engine.score(for: workout("tooManyZones", zones: [0, 0, 1_900, 0, 0])) == nil, "Bölge süresi antrenmanı aşamaz")
check(engine.score(for: workout("rpe11", rpe: 11)) == nil, "RPE aralığı")
check(engine.score(for: workout("nan", rpe: .nan)) == nil, "NaN reddedilir")
check(engine.score(for: workout("burst", burst: 1_801)) == nil, "Patlayıcı süre antrenmanı aşamaz")
check(engine.score(for: workout("strava", rpe: 8, source: .strava)) == nil, "Strava puana katılmaz")

let easyHeart = workout("heartOnly", archetype: .strengthAndHypertrophy, minutes: 60, zones: [3_600, 0, 0, 0, 0])
let heavy = workout("heavy", archetype: .strengthAndHypertrophy, minutes: 60, rpe: 9, zones: [3_600, 0, 0, 0, 0])
check(engine.score(for: heavy)!.value > engine.score(for: easyHeart)!.value, "Düşük nabız ağır kuvvet yükünü silmez")
check(engine.score(for: heavy)!.sessionRPELoadAU == 540, "Seans zorluğu × dakika")
check(engine.score(for: workout("muscleOnly", archetype: .strengthAndHypertrophy, minutes: 60, rpe: 9))!.value == 83, "Yalnız RPE verisi açıkça puanlanır")
let bodyweight = StrainWorkout(id: "bodyweight", startedAt: now.addingTimeInterval(-1_860), durationSeconds: 1_800, payload: .strength(StrengthMetrics(sets: [StrengthSet(repetitions: 10, loadKg: 0, rpe: 9)])), source: .tempo)
check((engine.score(for: bodyweight)?.value ?? 0) > 0, "Sıfır dış ağırlık, sıfır efor demek değildir")

@MainActor func volume(_ id: String, sets: Int, end: Date, source: StrainRecordSource = .tempo) -> StrainWorkout {
    let records = (0..<sets).map { _ in StrengthSet(repetitions: 10, loadKg: 50) }
    return StrainWorkout(id: id, startedAt: end.addingTimeInterval(-1_800), durationSeconds: 1_800, payload: .strength(StrengthMetrics(sets: records)), source: source)
}
let current = volume("current", sets: 2, end: now.addingTimeInterval(-60))
let history = (1...3).map { volume("prior\($0)", sets: 1, end: now.addingTimeInterval(-Double($0) * 86_400)) }
check(engine.score(for: current, history: history)!.personalTonnageReferenceKg == 500, "Kişisel medyan referansı")
check(engine.score(for: current, history: history)!.value == 86, "İki kat tonajın göreli yükü")
check(engine.score(for: current) == nil, "Referans olmadan yalnız tonaj puanlanmaz")
check(engine.score(for: current, history: [history[0], history[0], history[0]]) == nil, "Kopya kayıtlar referansı çoğaltmaz")
check(engine.score(for: current, history: (1...3).map { volume("future\($0)", sets: 1, end: now.addingTimeInterval(Double($0) * 86_400)) }) == nil, "Gelecekten referans alınmaz")
check(engine.score(for: current, history: (1...3).map { volume("remote\($0)", sets: 1, end: now.addingTimeInterval(-Double($0) * 86_400), source: .strava) }) == nil, "Referansta da Strava kullanılmaz")

let second = workout("zone3b", zones: [0, 0, 1_800, 0, 0])
let daily = engine.summary([zone3, second], since: now.addingTimeInterval(-86_400), until: now)
check(daily.value == 70 && daily.workoutsWithScore == 2, "Günlük yük puan ortalaması değildir")
check(engine.summary([zone3, zone3], since: now.addingTimeInterval(-86_400), until: now).workoutsWithScore == 1, "Günlük kopyalar tek sayılır")
check(engine.summary([workout("future", rpe: 8, end: now.addingTimeInterval(60))], since: now.addingTimeInterval(-86_400), until: now).value == nil, "Bitmemiş seans puanlanmaz")
check(engine.summary([workout("old", rpe: 8, end: now.addingTimeInterval(-86_401))], since: now.addingTimeInterval(-86_400), until: now).value == nil, "Pencere dışı seans hariçtir")
check(engine.summary([], since: now, until: now).value == nil, "Boş pencere")

let strength = workout("s", archetype: .strengthAndHypertrophy, minutes: 20, rpe: 7, burst: 0)
let running = workout("r", minutes: 30, zones: [0, 0, 900, 900, 0])
let yoga = workout("y", archetype: .combatAndMindBody, minutes: 10, rpe: 2, mindBody: true)
var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
let balance = engine.hybridBalance([strength, running, yoga], now: now, calendar: calendar)
check(balance.hasCompleteAxes && balance.workoutCount == 3, "Dört eksen için açık veri")
check(balance.axes.map(\.value) == [33, 25, 25, 17], "Sürelerin dört eksene ayrılması")
check(balance.weakestAxis == .mobility, "En az kaydedilen tek alan")
let incomplete = engine.hybridBalance([workout("unratedRun")], now: now, calendar: calendar)
check(incomplete.axes.first { $0.axis == .anaerobic }?.value == nil, "Eksik yoğunluk sıfır sayılmaz")
check(incomplete.weakestAxis == nil, "Eksik veriden fiziksel zayıflık seçilmez")
check(engine.hybridBalance([], now: now).axes.allSatisfy { $0.value == nil }, "Boş radar veri uydurmaz")
check(engine.hybridBalance([workout("remote", rpe: 7, source: .strava)], now: now).workoutCount == 0, "Radar da kaynak kuralına uyar")

for archetype in SportArchetype.allCases {
    var previous = -1
    for rating in 1...10 {
        let score = engine.score(for: workout("rpe-\(rating)", archetype: archetype, rpe: Double(rating), zones: [0, 0, 1_800, 0, 0]))!
        check((0...100).contains(score.value) && score.value >= previous, "RPE ile puan monoton ve sınırlı")
        previous = score.value
    }
    let old = WorkoutPayload.empty(for: archetype)
    let encoded = try JSONEncoder().encode(old)
    let decoded = try JSONDecoder().decode(WorkoutPayload.self, from: encoded)
    check(decoded.isValid && decoded.loadInputs.isEmpty, "Eski metrik kaydı yeni alan olmadan açılır")
}
var invalid = UniversalStrainConfiguration(); invalid.cardioReferenceTRIMP = 0
check(UniversalStrainEngine(configuration: invalid).score(for: zone3) == nil, "Geçersiz model ayarı puan üretmez")
print("STRAIN_CORE_PASS checks=\(checked) swift6=true")
