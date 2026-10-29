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
let zoneStart = now.addingTimeInterval(-50)
let zoneWindow = HeartRateWorkoutWindow(id: UUID(), start: zoneStart, end: now, activeDurationSeconds: 50, activeIntervals: [DateInterval(start: zoneStart, end: now)])
let heartReadings = [100.0, 120, 140, 160, 180].enumerated().map { index, value in TimedHeartRateReading(start: zoneStart.addingTimeInterval(Double(index * 10)), end: zoneStart.addingTimeInterval(Double(index * 10 + 10)), bpm: value) }
let inferred = HeartRateZoneInference().infer(windows: [zoneWindow], readings: heartReadings, recordedPeakBpm: 200)[zoneWindow.id]!
check(inferred.seconds == [10, 10, 10, 10, 10] && inferred.evidence.observedSeconds == 50, "Z1–Z5 alt sınırları ve gerçek örnek süreleri")
let fallbackZones = HeartRateZoneInference().infer(windows: [zoneWindow], readings: heartReadings, recordedPeakBpm: nil)[zoneWindow.id]!
check(fallbackZones.evidence.maximumHeartRateBpm == 190 && fallbackZones.evidence.reference == .fallback190, "190 varsayımı açık kaynak bilgisi taşır")
let duplicatedSignal = HeartRateZoneInference().infer(windows: [zoneWindow], readings: heartReadings + heartReadings, recordedPeakBpm: 200)[zoneWindow.id]!
check(duplicatedSignal.seconds == inferred.seconds, "Çift kaynak zamanları iki kez sayılmaz")
check(HeartRateZoneInference().infer(windows: [zoneWindow], readings: [], recordedPeakBpm: 200).isEmpty, "Nabız yoksa beş sahte sıfır üretilmez")
let pausedWindow = HeartRateWorkoutWindow(id: UUID(), start: zoneStart, end: now, activeDurationSeconds: 40, activeIntervals: [DateInterval(start: zoneStart, end: zoneStart.addingTimeInterval(20)), DateInterval(start: zoneStart.addingTimeInterval(30), end: now)])
let pausedZones = HeartRateZoneInference().infer(windows: [pausedWindow], readings: heartReadings, recordedPeakBpm: 200)[pausedWindow.id]!
check(pausedZones.seconds == [10, 10, 0, 10, 10] && pausedZones.evidence.observedSeconds == 40, "Duraklamanın nabız süreleri çıkarılır")
let gapStart = now.addingTimeInterval(-100)
let gapWindow = HeartRateWorkoutWindow(id: UUID(), start: gapStart, end: now, activeDurationSeconds: 100, activeIntervals: [DateInterval(start: gapStart, end: now)])
let gapReadings = [TimedHeartRateReading(start: gapStart, end: gapStart, bpm: 100), TimedHeartRateReading(start: gapStart.addingTimeInterval(90), end: now, bpm: 180)]
let gapZones = HeartRateZoneInference().infer(windows: [gapWindow], readings: gapReadings, recordedPeakBpm: 200)[gapWindow.id]!
check(gapZones.evidence.observedSeconds == 40, "90 saniyelik boşluk tam süre olarak doldurulmaz")
var gapPayload = WorkoutPayload.empty(for: .endurance); gapPayload.heartRateZones = HeartRateZones(seconds: gapZones.seconds.map(Optional.some))
let gapWorkout = StrainWorkout(id: "gap", startedAt: gapStart, durationSeconds: 100, payload: gapPayload, source: .health, heartRateZoneEvidence: gapZones.evidence)
check(engine.score(for: gapWorkout) == nil, "Yetersiz sinyal kapsaması TRIMP puanı üretmez")
let lowReadings = (0..<10).map { index in TimedHeartRateReading(start: gapStart.addingTimeInterval(Double(index * 10)), end: gapStart.addingTimeInterval(Double(index * 10 + 10)), bpm: 70) }
let lowZones = HeartRateZoneInference().infer(windows: [gapWindow], readings: lowReadings, recordedPeakBpm: 200)[gapWindow.id]!
check(lowZones.seconds == [0, 0, 0, 0, 0] && lowZones.evidence.belowZoneSeconds == 100, "Ölçülmüş düşük nabız eksik veri sayılmaz")
var lowPayload = WorkoutPayload.empty(for: .endurance); lowPayload.heartRateZones = HeartRateZones(seconds: lowZones.seconds.map(Optional.some))
let lowWorkout = StrainWorkout(id: "lowMeasured", startedAt: gapStart, durationSeconds: 100, payload: lowPayload, source: .health, heartRateZoneEvidence: lowZones.evidence)
check(engine.score(for: lowWorkout)?.cardioLoad == 0, "Yeterli ölçüm varsa Z1 altındaki TRIMP sıfır olabilir")
var pausedPayload = WorkoutPayload.empty(for: .endurance); pausedPayload.heartRateZones = HeartRateZones(seconds: pausedZones.seconds.map(Optional.some))
let pausedWorkout = StrainWorkout(id: "paused", startedAt: zoneStart, durationSeconds: 40, payload: pausedPayload, source: .health, heartRateZoneEvidence: pausedZones.evidence, sourceEndedAt: now)
check(pausedWorkout.isValid && pausedWorkout.endedAt == now, "Duraklamalı antrenmanın gerçek bitiş zamanı korunur")
var badEnd = pausedWorkout; badEnd.sourceEndedAt = zoneStart.addingTimeInterval(-1)
check(!badEnd.isValid, "Başlangıçtan önceki bitiş reddedilir")

let zoneCache = HeartRateZoneCache()
let emptyCache = await zoneCache.lookup([zoneWindow], referenceBpm: 200, reference: .recorded90DayPeak, now: now, force: false)
check(emptyCache.pending.count == 1, "İlk okumada sorgu gerekir")
await zoneCache.save([zoneWindow.id: inferred], windows: [zoneWindow], referenceBpm: 200, reference: .recorded90DayPeak, now: now, generation: emptyCache.generation)
let hit = await zoneCache.lookup([zoneWindow], referenceBpm: 200, reference: .recorded90DayPeak, now: now, force: false)
check(hit.pending.isEmpty && hit.values.count == 1, "Tekrarlanan eşitleme ham nabzı yeniden okumaz")
let changedReference = await zoneCache.lookup([zoneWindow], referenceBpm: 190, reference: .fallback190, now: now, force: false)
check(changedReference.pending.count == 1, "Nabız referansı değişirse yeniden hesaplanır")
await zoneCache.removeAll()
await zoneCache.save([zoneWindow.id: inferred], windows: [zoneWindow], referenceBpm: 200, reference: .recorded90DayPeak, now: now, generation: emptyCache.generation)
let afterDisconnect = await zoneCache.lookup([zoneWindow], referenceBpm: 200, reference: .recorded90DayPeak, now: now, force: false)
check(afterDisconnect.pending.count == 1, "Bağlantı kesildikten sonra eski sorgu önbelleği geri yazamaz")

@MainActor func legSession(_ id: String, hoursAgo: Double, source: StrainRecordSource = .tempo, muscle: MuscleGroup = .legs) -> StrainWorkout {
    let end = now.addingTimeInterval(-hoursAgo * 3_600)
    let sets = (0..<4).map { _ in StrengthSet(muscle: muscle, repetitions: 8, loadKg: 80, rpe: 8) }
    return StrainWorkout(id: id, startedAt: end.addingTimeInterval(-1_800), durationSeconds: 1_800, payload: .strength(StrengthMetrics(sets: sets)), source: source)
}
let muscleCalculator = MuscleRecoveryCalculator()
let freshMuscles = muscleCalculator.summary([legSession("fresh", hoursAgo: 0)], now: now)
check(freshMuscles.entries.first { $0.muscle == .legs }?.readinessPercent == 68, "4 zor set 32 puanlık model yükü taşır")
check(freshMuscles.entries.first { $0.muscle == .chest }?.readinessPercent == nil, "Göğüs verisi yoksa yüzde uydurulmaz")
check(muscleCalculator.summary([legSession("half", hoursAgo: 36)], now: now).entries.first { $0.muscle == .legs }?.readinessPercent == 84, "36 saatte model yükü yarıya iner")
check(muscleCalculator.summary([legSession("rested", hoursAgo: 72)], now: now).entries.first { $0.muscle == .legs }?.readinessPercent == 100, "72 saat sınırında model yükü sıfır")
check(!muscleCalculator.summary([], now: now).hasData, "Boş kayıtta tüm kaslar 100 gösterilmez")
check(!muscleCalculator.summary([legSession("futureMuscle", hoursAgo: -1), legSession("remoteMuscle", hoursAgo: 1, source: .strava)], now: now).hasData, "Gelecek ve Strava kas haritasına girmez")
let duplicateLeg = legSession("duplicateLeg", hoursAgo: 0)
check(muscleCalculator.summary([duplicateLeg, duplicateLeg], now: now).entries.first { $0.muscle == .legs }?.readinessPercent == 68, "Aynı set kaydı iki kez sayılmaz")
let fullBody = muscleCalculator.summary([legSession("fullBody", hoursAgo: 0, muscle: .fullBody)], now: now)
check(fullBody.entries.first { $0.muscle == .fullBody }?.readinessPercent == 68 && fullBody.entries.first { $0.muscle == .legs }?.readinessPercent == nil, "Tüm vücut setleri her kasa çoğaltılmaz")
let unknownMuscles = muscleCalculator.summary([legSession("unspecified", hoursAgo: 0, muscle: .unspecified)], now: now)
check(unknownMuscles.unclassifiedRecentSets == 4 && !unknownMuscles.hasData, "Belirsiz kas grubu ayrıca raporlanır")

let monthSessions = [2, 9, 16, 27].map { day in workout("month-\(day)", rpe: 7, end: now.addingTimeInterval(-Double(day) * 86_400)) }
let monthLoad = engine.acwrSummary(monthSessions, now: now)
check(abs((monthLoad.ratio ?? -1) - 1) < 0.00001 && monthLoad.status == .referenceRange, "Dört eşit haftalık seans 1,0 oranı verir")
check(monthLoad.historyDays == 28 && monthLoad.scoredWorkouts == 4, "28 günlük görünür geçmiş")
check(engine.acwrSummary([], now: now).ratio == nil, "Sıfır paydadan sonsuz oran üretilmez")
let newHistory = engine.acwrSummary([workout("newHistory", rpe: 7)], now: now)
check(newHistory.ratio == 4 && newHistory.status == .insufficientHistory, "Kısa geçmişin 4,0 oranı yüksek risk diye sınıflanmaz")
let heavierMonth = engine.acwrSummary(monthSessions + [workout("extra1", rpe: 7), workout("extra2", rpe: 7)], now: now)
check(heavierMonth.status == .highIncrease, "Belirgin artış bandı")
check(ACWRStatus.band(for: 0.799) == .lowLoad && ACWRStatus.band(for: 0.8) == .referenceRange, "ACWR 0,8 sınırı dahil")
check(ACWRStatus.band(for: 1.3) == .referenceRange && ACWRStatus.band(for: 1.301) == .increasedLoad, "ACWR 1,3 sınırı ve boşluk bandı")
check(ACWRStatus.band(for: 1.5) == .increasedLoad && ACWRStatus.band(for: 1.501) == .highIncrease, "ACWR 1,5 üst sınırı")
check(ACWRStatus.band(for: .nan) == .insufficientHistory, "Geçersiz oran sınıflanmaz")
check(engine.acwrSummary(monthSessions + [monthSessions[0]], now: now).scoredWorkouts == 4, "ACWR kopya kayıtları dışlar")
check(engine.acwrSummary([workout("stravaLoad", rpe: 8, source: .strava)], now: now).ratio == nil, "ACWR kaynak sınırını korur")
let personalContext = builder.build(active: lower, workouts: [CrossSportWorkout(workout: legSession("coachLegs", hoursAgo: 0))], includeTraining: true, includeHealth: false, now: now)
check(personalContext.muscleRecovery?.hasData == true && personalContext.acwr != nil, "Koç izinli toparlanma ve yük bağlamı alır")
check(noConsent.muscleRecovery == nil && noConsent.acwr == nil, "Paylaşım kapalıyken yeni yüzdeler de gönderilmez")
check(TempoTrainingGuidance.targetStrainRange(readiness: 85) == 65...85 && TempoTrainingGuidance.targetStrainRange(readiness: 84) == 45...65 && TempoTrainingGuidance.targetStrainRange(readiness: 70) == 45...65 && TempoTrainingGuidance.targetStrainRange(readiness: 69) == 25...45 && TempoTrainingGuidance.targetStrainRange(readiness: 55) == 25...45 && TempoTrainingGuidance.targetStrainRange(readiness: 54) == 10...25, "Hazırlık aralığı sınırları")
check(TempoTrainingGuidance.checkInMismatch(readiness: 75, energy: 2, mood: 3, tiredness: 2), "Düşük enerji uyarısı")
check(TempoTrainingGuidance.checkInMismatch(readiness: 75, energy: 3, mood: 3, tiredness: 4), "Yüksek yorgunluk uyarısı")
check(!TempoTrainingGuidance.checkInMismatch(readiness: nil, energy: 1, mood: 3, tiredness: 4) && !TempoTrainingGuidance.checkInMismatch(readiness: 74, energy: 1, mood: 3, tiredness: 4), "Eksik veya düşük hazırlıkta karşılaştırma yapılmaz")
check(TempoTrainingGuidance.isSensorVerified(source: "apple-health", score: nil) && TempoTrainingGuidance.isSensorVerified(source: "phone-gps", score: nil) && TempoTrainingGuidance.isSensorVerified(source: "manual", score: 4), "Sensör kaynağı ve sinyal eşiği")
check(!TempoTrainingGuidance.isSensorVerified(source: "manual", score: 3.99) && !TempoTrainingGuidance.isSensorVerified(source: "manual", score: .nan), "Yetersiz sinyal doğrulanmış sayılmaz")
check(TempoTrainingGuidance.intensityBonus(minutes: 60, distanceKm: nil, sourceEffort: 7, perceivedEffort: nil, supportingMeasurement: false) == 93, "Mesafesiz efor XP")
check(TempoTrainingGuidance.intensityBonus(minutes: 60, distanceKm: 5, sourceEffort: 7, perceivedEffort: nil, supportingMeasurement: true) == 0, "Mesafeye ek olarak efor bonusu verilmez")
check(TempoTrainingGuidance.intensityBonus(minutes: 1_000, distanceKm: nil, sourceEffort: 10, perceivedEffort: nil, supportingMeasurement: true) == 300, "Efor bonusu sınırlanır")
let originalSet = StrengthSet(muscle: .legs, repetitions: 8, loadKg: 80, rpe: 7)
let draftSet = StrengthProgression.draft(from: [originalSet])[0]
check(draftSet.id != originalSet.id && draftSet.loadKg == 80 && draftSet.repetitions == 8 && draftSet.rpe == nil && draftSet.rir == nil, "Şablon eski eforu yeni ölçüm gibi taşımaz")
check(StrengthProgression.suggestsIncrease(originalSet, current: draftSet), "Düşük efora isteğe bağlı ilerleme önerisi")
let hardSet = StrengthSet(muscle: .legs, repetitions: 8, loadKg: 80, rpe: 9)
check(!StrengthProgression.suggestsIncrease(hardSet, current: draftSet), "Yüksek eforda artış önerilmez")
let savedPreset = StrengthWorkoutPreset(sportID: "fitness", name: "Upper A", sets: [originalSet])
check(savedPreset.isValid && (try? JSONDecoder().decode(StrengthWorkoutPreset.self, from: JSONEncoder().encode(savedPreset)))?.name == "Upper A", "Şablon yerel kayıtta korunur")
print("STRAIN_CORE_PASS checks=\(checked) swift6=true phases3to5=true")
