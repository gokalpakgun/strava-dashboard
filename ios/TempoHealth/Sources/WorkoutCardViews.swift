import SwiftUI

@MainActor
enum WorkoutCardAdapter {
    static func make(_ source: TempoManualWorkout, record: ArchetypeWorkoutRecord) -> Workout {
        var value = Workout(id: record.id, sportType: SportType(sportID: source.sportId, archetype: record.payload?.archetype), date: source.startedAt, duration: record.durationSeconds,
                            activeCalories: source.sourceEnergyKcal ?? source.healthSignal?.activeEnergyKcal,
                            avgHeartRate: source.sourceAverageHeartRateBpm ?? source.healthSignal?.averageHeartRateBpm,
                            distance: source.distanceKm.map { $0 * 1_000 }, title: source.title, sportName: source.sportTitle,
                            symbol: TempoSportChoice(rawValue: source.sportId)?.symbol ?? TempoSport(rawValue: source.sportId).symbol,
                            archetype: record.payload?.archetype)
        if case .strength(let strength) = record.payload, strength.isValid { value.totalVolume = strength.totalTonnageKg }
        if case .endurance(let endurance) = record.payload, endurance.isValid {
            value.distance = endurance.distanceMeters ?? value.distance
            value.laps = endurance.laps.isEmpty ? nil : endurance.laps.count
        }
        if let payload = record.payload, record.source != .strava {
            let input = StrainWorkout(id: record.id, startedAt: record.date, durationSeconds: record.durationSeconds, payload: payload,
                                      source: record.source == .health ? .health : .tempo, isMindBody: record.isMindBody,
                                      userEntered: record.userEdited, effortIsEstimated: record.effortIsEstimated,
                                      heartRateZoneEvidence: record.zoneEvidence, sourceEndedAt: record.sourceEndedAt)
            value.estimatedMuscleLoad = UniversalStrainEngine().score(for: input)?.muscleLoad
        }
        return value
    }
    static func make(_ source: TempoActivity) -> Workout {
        let archetype = SportMapper().map(stravaType: source.type ?? "")
        return Workout(id: "strava-\(source.id)", sportType: SportType(sportID: source.type ?? "", archetype: archetype), date: source.date,
                       duration: source.movingTime ?? 0, distance: source.distance, title: source.name ?? source.sport.title,
                       sportName: source.sport.title, symbol: source.sport.symbol, archetype: archetype)
    }
}

struct WorkoutCardView: View {
    let workout: Workout
    var embedded = false
    @ViewBuilder private var sportContent: some View {
        switch workout.sportType {
        case .running, .cycling: CardioCardView(workout: workout)
        case .lifting: LiftingCardView(workout: workout)
        case .swimming: SwimCardView(workout: workout)
        case .generic: GenericWorkoutCardView(workout: workout)
        }
    }
    var body: some View {
        Group {
            if embedded { sportContent }
            else {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 14) {
                        TempoIconBadge(symbol: workout.symbol, color: accent)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(workout.title.isEmpty ? workout.sportName : workout.title).font(.headline)
                                .foregroundStyle(TempoTheme.primary).fixedSize(horizontal: false, vertical: true)
                            Text(workout.date?.formatted(date: .abbreviated, time: .shortened) ?? "feed.dateMissing".tempoLocalized)
                                .font(.caption).foregroundStyle(TempoTheme.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    sportContent
                }.padding(20).modifier(WorkoutCardSurface())
            }
        }
        .multilineTextAlignment(.leading)
        .modifier(WorkoutCardEntrance(enabled: !embedded))
    }
    private var accent: Color {
        switch workout.sportType { case .running: TempoTheme.green; case .cycling: TempoTheme.blue; case .lifting: TempoTheme.orange; case .swimming: TempoTheme.blue; case .generic: TempoTheme.purple }
    }
}

struct CardioCardView: View {
    let workout: Workout
    var body: some View {
        TempoMetricGrid {
            WorkoutCardMetric(value: WorkoutCardFormat.distance(workout), label: "Mesafe", symbol: "point.topleft.down.to.point.bottomright.curvepath", color: TempoTheme.green)
            if workout.sportType == .cycling {
                WorkoutCardMetric(value: WorkoutCardFormat.speed(workout), label: "Hız", symbol: "speedometer", color: TempoTheme.blue)
            } else {
                WorkoutCardMetric(value: WorkoutCardFormat.pace(workout), label: "Tempo", symbol: "figure.run", color: TempoTheme.blue)
            }
            WorkoutCardMetric(value: WorkoutCardFormat.duration(workout), label: "Süre", symbol: "clock", color: TempoTheme.green)
        }
    }
}

struct LiftingCardView: View {
    let workout: Workout
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TempoMetricGrid {
                WorkoutCardMetric(value: workout.validVolume.map { $0.formatted(.number.precision(.fractionLength(0...1))) + " kg" } ?? "—", label: "feed.volume", symbol: "dumbbell.fill", color: TempoTheme.orange)
                WorkoutCardMetric(value: WorkoutCardFormat.duration(workout), label: "Süre", symbol: "clock", color: TempoTheme.blue)
                WorkoutCardMetric(value: workout.validMuscleLoad.map { "\($0)/100" } ?? "—", label: "feed.muscleLoad", symbol: "bolt.fill", color: TempoTheme.purple, pulses: workout.validMuscleLoad != nil)
            }
            if let heartRate = workout.validHeartRate {
                HStack(spacing: 8) {
                    WorkoutHeartbeatIcon()
                    Text("feed.averageHR".tempoFormatted(heartRate.formatted(.number.precision(.fractionLength(0)))))
                        .font(.footnote).foregroundStyle(TempoTheme.secondary)
                }.accessibilityElement(children: .combine)
            }
            Text((workout.validMuscleLoad == nil ? "feed.loadMissing" : "feed.loadExplanation").tempoLocalized)
                .font(.caption).foregroundStyle(TempoTheme.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SwimCardView: View {
    let workout: Workout
    var body: some View {
        TempoMetricGrid {
            WorkoutCardMetric(value: workout.validLaps.map { $0.formatted() } ?? "—", label: "feed.laps", symbol: "figure.pool.swim", color: TempoTheme.blue)
            WorkoutCardMetric(value: WorkoutCardFormat.duration(workout), label: "Süre", symbol: "clock", color: TempoTheme.green)
            WorkoutCardMetric(value: WorkoutCardFormat.calories(workout), label: "Aktif enerji", symbol: "flame.fill", color: TempoTheme.orange)
        }
    }
}

private struct GenericWorkoutCardView: View {
    let workout: Workout
    var body: some View {
        TempoMetricGrid {
            WorkoutCardMetric(value: WorkoutCardFormat.duration(workout), label: "Süre", symbol: "clock", color: TempoTheme.blue)
            if workout.archetype == .endurance, workout.validDistance != nil {
                WorkoutCardMetric(value: WorkoutCardFormat.distance(workout), label: "Mesafe", symbol: "point.topleft.down.to.point.bottomright.curvepath", color: TempoTheme.green)
            } else {
                WorkoutCardMetric(value: workout.validHeartRate.map { $0.formatted(.number.precision(.fractionLength(0))) + " bpm" } ?? "—", label: "feed.heartRate", symbol: "heart.fill", color: TempoTheme.purple)
            }
            WorkoutCardMetric(value: WorkoutCardFormat.calories(workout), label: "Aktif enerji", symbol: "flame.fill", color: TempoTheme.orange)
        }
    }
}

private struct WorkoutCardMetric: View {
    let value: String
    let label: String
    let symbol: String
    let color: Color
    var pulses = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if pulses { WorkoutHeartbeatIcon(symbol: symbol, color: color) }
            else { Image(systemName: symbol).font(.body).foregroundStyle(color).accessibilityHidden(true) }
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(TempoTheme.primary).fixedSize(horizontal: false, vertical: true)
            Text(label.tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(12).frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .background(TempoTheme.raised.opacity(0.45), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityElement(children: .ignore).accessibilityLabel(label.tempoLocalized)
            .accessibilityValue(value == "—" ? "veri yok".tempoLocalized : value)
    }
}

private enum WorkoutCardFormat {
    static func duration(_ value: Workout) -> String { value.validDuration.map(TempoFormat.duration) ?? "—" }
    static func distance(_ value: Workout) -> String { value.validDistance.map { TempoFormat.distance($0 / 1_000) } ?? "—" }
    static func calories(_ value: Workout) -> String { value.validCalories.map { $0.formatted(.number.precision(.fractionLength(0))) + " kcal" } ?? "—" }
    static func speed(_ value: Workout) -> String { value.speedKmh.map { $0.formatted(.number.precision(.fractionLength(1))) + " km/h" } ?? "—" }
    static func pace(_ value: Workout) -> String {
        guard let pace = value.paceSecondsPerKm else { return "—" }
        let seconds = Int(pace.rounded())
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60)) /km"
    }
}

struct WorkoutCardSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.background {
            let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
            if reduceTransparency || contrast == .increased { shape.fill(TempoTheme.card) }
            else { shape.fill(.regularMaterial).background(shape.fill(TempoTheme.card)) }
        }.overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(TempoTheme.primary.opacity(contrast == .increased ? 0.28 : 0.08)))
            .shadow(color: .black.opacity(0.035), radius: 14, y: 5)
    }
}

/// Görünürlük ve uygulama durumu animasyon ömrünü sınırlar; listeden çıkınca durur.
private struct WorkoutHeartbeatIcon: View {
    var symbol = "heart.fill"
    var color = TempoTheme.orange
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @State private var visible = false
    @State private var pulse = false
    private var enabled: Bool { visible && !reduceMotion && phase == .active }
    var body: some View {
        Image(systemName: symbol).font(.footnote).foregroundStyle(color)
            .scaleEffect(pulse ? 1.08 : 1)
            .animation(enabled ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true) : nil, value: pulse)
            .onAppear { visible = true; pulse = enabled }
            .onDisappear { visible = false; pulse = false }
            .onChange(of: phase) { _, _ in pulse = enabled }
            .onChange(of: reduceMotion) { _, _ in pulse = enabled }
            .accessibilityHidden(true)
    }
}

struct WorkoutCardEntrance: ViewModifier {
    var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    func body(content: Content) -> some View {
        content.opacity(!enabled || appeared || reduceMotion ? 1 : 0).offset(y: !enabled || appeared || reduceMotion ? 0 : 10)
            .onAppear {
                guard enabled, !appeared else { return }
                withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.86)) { appeared = true }
            }
    }
}
