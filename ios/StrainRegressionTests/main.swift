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
let lower = ActiveSportContext(sportID: "fitness", archetype: .strengthAndHypertrophy, strengthFocus: .lowerBody)
let upper = ActiveSportContext(sportID: "fitness", archetype: .strengthAndHypertrophy, strengthFocus: .upperBody)
let undecided = ActiveSportContext(sportID: "fitness", archetype: .strengthAndHypertrophy)
let analyzer = InterferenceAnalyzer()
let court = CrossSportWorkout(workout: workout("court", archetype: .teamAndCourt, minutes: 45, end: now.addingTimeInterval(-12 * 3_600)), hasLowerBodyImpact: true)
check(analyzer.warning(for: lower, workouts: [court], now: now)?.suggestedVolumeReductionPercent == 30, "Yakın saha kaydı için koşullu planlama")
check(analyzer.warning(for: lower, workouts: [court], now: now)?.limitedEvidence == true, "Yoğunluğu bilinmeyen saha kaydı ölçülmüş yorgunluk sayılmaz")
check(analyzer.warning(for: upper, workouts: [court], now: now) == nil, "Üst vücuda alt vücut uyarısı taşınmaz")
check(analyzer.warning(for: undecided, workouts: [court], now: now) == nil, "Fitness ekranı otomatik bacak sayılmaz")
check(analyzer.warning(for: lower, workouts: [CrossSportWorkout(workout: court.workout)], now: now) == nil, "Golf gibi belirsiz kort grubu bacak yükü sayılmaz")
for (id, hours, source) in [("oldCourt", 48.0, StrainRecordSource.tempo), ("futureCourt", -1.0, .tempo), ("stravaCourt", 5.0, .strava)] {
    let item = CrossSportWorkout(workout: workout(id, archetype: .teamAndCourt, end: now.addingTimeInterval(-hours * 3_600), source: source), hasLowerBodyImpact: true)
    check(analyzer.warning(for: lower, workouts: [item], now: now) == nil, "48 saat sınırı, gelecek ve kaynak filtresi")
}
let olderCourt = CrossSportWorkout(workout: workout("olderCourt", archetype: .teamAndCourt, minutes: 40, end: now.addingTimeInterval(-36 * 3_600)), hasLowerBodyImpact: true)
check(analyzer.warning(for: lower, workouts: [olderCourt], now: now)?.suggestedVolumeReductionPercent == 20, "24–48 saat seçeneği")
var hardRun = workout("hardRun", minutes: 30, zones: [540, 0, 0, 1_260, 0])
if case .endurance(var metrics) = hardRun.payload { metrics.discipline = .running; hardRun = StrainWorkout(id: hardRun.id, startedAt: hardRun.startedAt, durationSeconds: hardRun.durationSeconds, payload: .endurance(metrics), source: .tempo) }
check(analyzer.warning(for: lower, workouts: [CrossSportWorkout(workout: hardRun)], now: now)?.reason == .intenseEndurance, "Ölçülmüş Z4–5 yirmi dakikayı geçerse uyarı")
let legSets = (0..<4).map { _ in StrengthSet(muscle: .legs, repetitions: 8, loadKg: 80, rpe: 8) }
let legs = StrainWorkout(id: "legs", startedAt: now.addingTimeInterval(-7_200), durationSeconds: 1_800, payload: .strength(StrengthMetrics(sets: legSets)), source: .tempo)
check(analyzer.warning(for: lower, workouts: [CrossSportWorkout(workout: legs)], now: now)?.reason == .legStrength, "Kas grubu belli zor setler")

let builder = AIContextBuilder()
let noConsent = builder.build(active: lower, workouts: [court], includeTraining: false, includeHealth: true, now: now)
check(noConsent.load24h == nil && noConsent.interference == nil && noConsent.balance7d == nil && noConsent.latestMetrics == nil, "Kişisel bağlam için ayrı onay")
let healthOnly = CrossSportWorkout(workout: workout("health-rpe", archetype: .strengthAndHypertrophy, minutes: 30, rpe: 7, source: .health))
let healthOff = builder.build(active: lower, workouts: [healthOnly], includeTraining: true, includeHealth: false, now: now)
check(healthOff.load24h?.scoredWorkouts == 0 && healthOff.latestMetrics == nil, "Sağlık izni kapalıyken sağlık antrenmanı çıkarılır")
let healthOn = builder.build(active: lower, workouts: [healthOnly], includeTraining: true, includeHealth: true, now: now)
check(healthOn.load24h?.scoredWorkouts == 1 && healthOn.latestMetrics?.sessionRPE == 7, "İzinli gerçek RPE bağlama girer")
check(healthOn.load48h?.hours == 48 && healthOn.load24h?.hours == 24, "Pencereler ayrı etiketlenir")
let remoteContext = builder.build(active: lower, workouts: [CrossSportWorkout(workout: workout("remote", rpe: 7, source: .strava))], includeTraining: true, includeHealth: true, now: now)
check(remoteContext.load24h?.scoredWorkouts == 0 && remoteContext.latestMetrics == nil, "AI bağlamında Strava yok")
check(builder.focusMetrics(for: ActiveSportContext(sportID: "tennis", archetype: .teamAndCourt)).contains(.shoulderElbowControl), "Tenis odak noktası")
check(builder.focusMetrics(for: ActiveSportContext(sportID: "cycling", archetype: .endurance)).contains(.cadence), "Bisiklet odak noktası")
let encodedContext = try JSONEncoder().encode(healthOn)
let decodedContext = try JSONDecoder().decode(AthleticAIContext.self, from: encodedContext)
check(decodedContext.activeSport == lower && decodedContext.schemaVersion == 1, "Tip güvenli JSON gidiş dönüşü")

let guardrail = AthleticGuardrailValidator()
for question in ["JavaScript kod yaz", "Basketbol ve bitcoin", "SİYASET konuşalım", "merhaba!"] { check(guardrail.validate(question) == .refuse, "Spor dışı soru modelden önce durdurulur") }
for question in ["Can you shorten that?", "Tenis tekniği", "HRV toparlanmamı nasıl etkiler?", "Protein ne kadar?"] { check(guardrail.validate(question) == .allow, "Spor ve kısa takip soruları korunur") }
for question in ["Göğsüm ağrıyor", "Koşarken bayıldım", "I have chest pain"] { check(guardrail.validate(question) == .urgentSafety, "Acil belirtiler sessizce reddedilmez") }

var automatic = WorkoutPayload.endurance(EnduranceMetrics(discipline: .cycling, distanceMeters: 15_000, movingSeconds: 1_800, cadencePerMinute: 85, averagePowerWatts: 180))
automatic.loadInputs = WorkoutLoadInputs(sessionRPE: 7)
let annotations = automatic.removingAutomaticMatches(from: automatic)
check(annotations.loadInputs.sessionRPE == nil, "Otomatik efor notu düzenleme kaydında dondurulmaz")
if case .endurance(let values) = annotations { check(values.averagePowerWatts == nil && values.distanceMeters == nil, "Otomatik güç ve mesafe güncellenebilir kalır") }
var refreshed = automatic; if case .endurance(var metrics) = refreshed { metrics.averagePowerWatts = 200; refreshed = .endurance(metrics) }
let merged = annotations.fillingMissing(from: refreshed)
if case .endurance(let metrics) = merged { check(metrics.averagePowerWatts == 200 && metrics.cadencePerMinute == 85, "Yeni kaynak değerleri boş alanları tamamlar") }
var edited = automatic; var effort = edited.loadInputs; effort.sessionRPE = 9; edited.loadInputs = effort
check(edited.removingAutomaticMatches(from: automatic).fillingMissing(from: refreshed).loadInputs.sessionRPE == 9, "Kullanıcının ayrı efor notu korunur")
var estimatedWorkout = workout("estimated", rpe: 7); estimatedWorkout.effortIsEstimated = true
check(engine.score(for: estimatedWorkout)?.hasLimitedEvidence == true, "Apple efor tahmini doğrudan ölçüm sayılmaz")
print("STRAIN_CORE_PASS checks=\(checked) swift6=true module3=true")
