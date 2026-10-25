import CoreLocation
import Foundation
import MapKit
import SwiftUI
import UIKit

struct SportsHubScreen: View {
    @EnvironmentObject private var account: TempoAccountStore
    @EnvironmentObject private var model: TempoAppModel

    private var selectedSports: [TempoSportChoice] {
        let chosen = account.profile?.sports.compactMap(TempoSportChoice.init(rawValue:)) ?? []
        let performed = Set(model.activityWorkouts.map(\.sportId))
        let stravaSports = TempoSportChoice.allCases.filter { sport in (model.dashboard?.activities ?? []).contains { sport.matches(activityType: $0.type) } }
        return chosen + TempoSportChoice.allCases.filter { (performed.contains($0.rawValue) || stravaSports.contains($0)) && !chosen.contains($0) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TempoTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        sportsHeader

                        if selectedSports.isEmpty {
                            Text("Profilinden ilgilendiğin sporları seçerek bu alanı kişiselleştirebilirsin.")
                                .padding(20).frame(maxWidth: .infinity)
                                .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        } else {
                            ForEach(selectedSports) { sport in
                                NavigationLink(destination: SportDetailScreen(sport: sport)) {
                                    SportSummaryCard(sport: sport, manualWorkouts: model.activityWorkouts)
                                }
                                .buttonStyle(.plain)
                                .simultaneousGesture(TapGesture().onEnded { TempoHaptics.selection() })
                                .accessibilityIdentifier("sport.open.\(sport.id)")
                            }
                        }

                        TempoDisclosureSection(title: "Spor araçları", icon: "slider.horizontal.3") {
                            VStack(spacing: 10) {
                                NavigationLink(destination: NearbyFacilitiesScreen()) { ToolCard(title: "Yakındaki spor alanları", subtitle: "Kort, saha, havuz ve spor salonlarını bul", icon: "mappin.and.ellipse", color: TempoTheme.green) }
                                NavigationLink(destination: RoutesScreen()) { ToolCard(title: "Aktivite rotaları", subtitle: "Strava GPS rotalarını tek haritada incele", icon: "map", color: TempoTheme.blue) }
                                NavigationLink(destination: CoachScreen()) { ToolCard(title: "Tempo Koç", subtitle: "Spor ve sağlıklı yaşam için sohbet", icon: "sparkles", color: TempoTheme.purple) }
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, TempoTheme.scrollBottomClearance)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var sportsHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Sporlarım").font(.system(size: 28, weight: .bold, design: .rounded)).accessibilityIdentifier("screen.sports")
                Text("Her spora uygun, sade bir özet.").font(.subheadline).foregroundStyle(TempoTheme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            NavigationLink(destination: AccountSettingsScreen()) {
                Image(systemName: "slider.horizontal.3").font(.subheadline).frame(width: 42, height: 42).background(TempoTheme.card, in: Circle())
            }.tint(TempoTheme.green).accessibilityLabel("Sporlarını düzenle".tempoLocalized)
        }.padding(.vertical, 8)
    }

}

private struct SportSummaryCard: View {
    let sport: TempoSportChoice
    let manualWorkouts: [TempoManualWorkout]

    private var matchingManual: [TempoManualWorkout] { manualWorkouts.filter { $0.sportId == sport.rawValue } }
    private var distance: Double { matchingManual.reduce(0) { $0 + ($1.distanceKm ?? 0) } }
    private var seconds: Double { matchingManual.reduce(0) { $0 + Double($1.durationSeconds ?? $1.durationMinutes * 60) } }
    private var weekCount: Int {
        matchingManual.filter { Calendar.current.isDateInCurrentWeek($0.startedAt) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: sport.symbol).font(.title2).foregroundStyle(.black)
                    .frame(width: 50, height: 50).background(TempoTheme.green, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(sport.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text("%d antrenman · bu hafta %d".tempoFormatted(matchingManual.count, weekCount)).font(.caption).foregroundStyle(TempoTheme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(TempoTheme.secondary)
            }
            TempoMetricGrid(columns: 2) {
                SportMetric(value: TempoFormat.duration(seconds), label: "Toplam süre")
                if sport.supportsDistance {
                    SportMetric(value: sport.distanceText(distance), label: "Mesafe")
                } else {
                    SportMetric(value: "\(Set(matchingManual.map { Calendar.current.startOfDay(for: $0.startedAt) }).count)", label: "Hareketli gün")
                }
            }
        }
        .multilineTextAlignment(.leading)
        .padding(18)
        .background(
            LinearGradient(colors: [TempoTheme.green.opacity(0.09), TempoTheme.card, TempoTheme.blue.opacity(0.045)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.075), lineWidth: 1))
    }
}

private enum TempoHaptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func impact() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

private struct SportMetric: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.subheadline.monospacedDigit().weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            Text(label.tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .background(TempoTheme.raised, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private enum TempoMovementEnergy: String, CaseIterable, Identifiable {
    case low
    case steady
    case high

    var id: String { rawValue }
    var title: String {
        switch self {
        case .low: return "Düşük"
        case .steady: return "Normal"
        case .high: return "Enerjik"
        }
    }
    var symbol: String {
        switch self {
        case .low: return "moon.zzz.fill"
        case .steady: return "figure.walk"
        case .high: return "bolt.fill"
        }
    }
}

private struct TempoMovementRoutine: Identifiable {
    let id: String
    let sport: TempoSportChoice
    let title: String
    let subtitle: String
    let minutes: Int
    let intensity: String
    let steps: [String]
}

struct TempoMovementMenuScreen: View {
    @EnvironmentObject private var account: TempoAccountStore
    @EnvironmentObject private var model: TempoAppModel
    @State private var minutes = 15
    @State private var energy: TempoMovementEnergy = .steady
    @State private var hasEquipment = false
    @State private var selectedSportID = "walking"

    private var selectedSport: TempoSportChoice {
        TempoSportChoice(rawValue: selectedSportID) ?? .walking
    }

    private var adaptedSport: TempoSportChoice {
        let recentHardSession = model.manualWorkouts.sorted { $0.startedAt > $1.startedAt }.first?.perceivedEffort ?? 0
        if isReturningAfterBreak || energy == .low || (model.tempoBalance?.value ?? 100) < 55 || recentHardSession >= 4 {
            return profileSports.contains(.yoga) ? .yoga : .walking
        }
        let needsEquipment: Set<TempoSportChoice> = [.cycling, .swimming, .tennis, .basketball, .football, .volleyball, .padel, .badminton]
        if !hasEquipment && needsEquipment.contains(selectedSport) {
            return profileSports.contains(.fitness) ? .fitness : .walking
        }
        return selectedSport
    }

    private var profileSports: [TempoSportChoice] {
        let sports = account.profile?.sports.compactMap(TempoSportChoice.init(rawValue:)) ?? []
        return sports.isEmpty ? [.walking, .run, .fitness, .yoga] : sports
    }

    private var lastRecordedWorkoutDate: Date? {
        // Use the same combined movement history shown below so Health-only users
        // are not incorrectly put into return mode while their daily activity is current.
        movementDates.max()
    }
    private var daysSinceLastWorkout: Int? {
        guard let lastRecordedWorkoutDate else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: lastRecordedWorkoutDate), to: calendar.startOfDay(for: Date())).day
    }
    private var isReturningAfterBreak: Bool { (daysSinceLastWorkout ?? 0) >= 14 }

    private var currentRoutine: TempoMovementRoutine { makeRoutine(minutes: minutes, sport: adaptedSport) }
    private var planB: TempoMovementRoutine { makeRoutine(minutes: 5, sport: recoverySport) }
    private var recoverySport: TempoSportChoice { profileSports.contains(.yoga) ? .yoga : .walking }
    private var activeDaysThisWeek: Int { movementDates.filter { Calendar.current.isDate($0, equalTo: Date(), toGranularity: .weekOfYear) }.count }
    private var activeDaysPreviousWeek: Int {
        guard let previousWeek = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date()) else { return 0 }
        return movementDates.filter { Calendar.current.isDate($0, equalTo: previousWeek, toGranularity: .weekOfYear) }.count
    }
    private var movementDates: Set<Date> {
        let calendar = Calendar.current
        var dates = Set<Date>()
        for workout in model.manualWorkouts { dates.insert(calendar.startOfDay(for: workout.startedAt)) }
        for (day, values) in model.healthDays where (values.steps ?? 0) >= 3_000 || (values.exerciseMinutes ?? 0) >= 10 {
            if let date = TempoFormat.date(from: day) { dates.insert(calendar.startOfDay(for: date)) }
        }
        for offset in 0..<365 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let key = completionKey(for: day)
            if UserDefaults.standard.bool(forKey: key) { dates.insert(calendar.startOfDay(for: day)) }
        }
        return dates
    }
    private var movementStreak: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var cursor = movementDates.contains(today) ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        var count = 0
        while movementDates.contains(cursor), count < 365 {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
    private var adjustmentNote: String {
        if isReturningAfterBreak, let daysSinceLastWorkout {
            return "Son antrenman kaydının üzerinden %d gün geçti. Kısa ve kolay başlayıp ritmini yeniden kurabilirsin.".tempoFormatted(daysSinceLastWorkout)
        }
        if (model.tempoBalance?.value ?? 100) < 55 || energy == .low {
            return "Bugünkü seçimine göre toparlanma ve hafif hareket öne alındı."
        }
        if let effort = model.manualWorkouts.sorted(by: { $0.startedAt > $1.startedAt }).first?.perceivedEffort, effort >= 4 {
            return "Son antrenmanını zor olarak işaretlediğin için bugün daha kısa ve kontrollü seçenekler gösteriliyor."
        }
        return "Süre ve enerji seçimine göre önerildi; istemezsen sporunu veya şiddeti değiştirebilirsin."
    }

    var body: some View {
        TempoPage {
            PageTitle(title: "Günün hareket menüsü", subtitle: "Bugün sana uyan seçeneği bul")
            readinessCard
            activityChoices
            consistencyCard
            NavigationLink(destination: CoachScreen()) {
                Label("Tempo Koç’a danış", systemImage: "sparkles").frame(maxWidth: .infinity)
            }
            .buttonStyle(TempoSecondaryButtonStyle())
            Text("Bu öneriler tıbbi değerlendirme değildir. Eksik sensör verileri varmış gibi kullanılmaz.")
                .font(.caption2).foregroundStyle(TempoTheme.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Hareket menüsü")
        .navigationBarTitleDisplayMode(.inline)
        .tempoGlassBackButton()
        .onAppear {
            if !profileSports.contains(selectedSport) { selectedSportID = profileSports.first?.rawValue ?? "walking" }
        }
    }

    private var readinessCard: some View {
        TempoCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: model.tempoBalance == nil ? "slider.horizontal.3" : "heart.text.square.fill")
                        .foregroundStyle(TempoTheme.green).frame(width: 40, height: 40)
                        .background(TempoTheme.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text((model.tempoBalance == nil ? "Kendine göre ayarla" : "Bugünkü işaretler").tempoLocalized)
                            .font(.subheadline.weight(.semibold))
                        Text((model.tempoBalance.map { "Tempo Dengesi %d · %@".tempoFormatted($0.value, $0.confidence.tempoLocalized) } ?? "Sağlık ölçümü olmadan da zaman ve enerjine göre seçenek çıkarır.").tempoLocalized)
                            .font(.caption).foregroundStyle(TempoTheme.secondary)
                    }
                    Spacer(minLength: 0)
                }
                if isReturningAfterBreak {
                    Label("Spora dönüş modu", systemImage: "arrow.uturn.backward.circle.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(TempoTheme.blue)
                        .padding(.horizontal, 11).padding(.vertical, 8)
                        .background(TempoTheme.blue.opacity(0.11), in: Capsule())
                }
                HStack(spacing: 7) {
                    ForEach([5, 15, 30], id: \.self) { option in
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { minutes = option }
                        } label: {
                            Text("%d dk".tempoFormatted(option))
                                .font(.caption.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                                .foregroundStyle(minutes == option ? .black : TempoTheme.secondary)
                                .background(minutes == option ? TempoTheme.green : TempoTheme.raised, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text("Bugünkü enerjin nasıl?").font(.caption.weight(.semibold)).foregroundStyle(TempoTheme.secondary)
                    HStack(spacing: 7) {
                        ForEach(TempoMovementEnergy.allCases) { option in
                            Button {
                                withAnimation(.snappy(duration: 0.2)) { energy = option }
                            } label: {
                                Label(option.title.tempoLocalized, systemImage: option.symbol)
                                    .font(.caption.weight(.semibold)).labelStyle(.titleAndIcon)
                                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                                    .foregroundStyle(energy == option ? .black : TempoTheme.secondary)
                                    .background(energy == option ? TempoTheme.green : TempoTheme.raised, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack {
                    Label("Ekipmanım var", systemImage: hasEquipment ? "checkmark.circle.fill" : "circle")
                        .font(.caption.weight(.semibold)).foregroundStyle(hasEquipment ? TempoTheme.green : TempoTheme.secondary)
                    Spacer()
                    Toggle("Ekipmanım var", isOn: $hasEquipment).labelsHidden().tint(TempoTheme.green)
                }
                Text(adjustmentNote.tempoLocalized).font(.caption2).foregroundStyle(TempoTheme.secondary).lineSpacing(3)
            }
        }
    }

    private var activityChoices: some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionHeading(title: "Sana uygun seçenek", caption: "ÇEVRİMDIŞI HAZIR", padding: false)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(TempoSportChoice.allCases) { sport in
                        Button { selectedSportID = sport.rawValue } label: {
                            Text(sport.title).font(.caption.weight(.semibold))
                                .foregroundStyle(selectedSportID == sport.rawValue ? .black : TempoTheme.secondary)
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .background(selectedSportID == sport.rawValue ? TempoTheme.green : TempoTheme.card, in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
            MovementRoutineCard(routine: currentRoutine, label: "Bugünkü plan")
            MovementRoutineCard(routine: planB, label: "Plan B · vakit azalırsa")
        }
    }

    private var consistencyCard: some View {
        TempoCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Kişisel gelişim hikâyen").font(.subheadline.weight(.semibold))
                        Text("Bu hafta %d hareket günü".tempoFormatted(activeDaysThisWeek)).font(.title3.bold())
                    }
                    Spacer()
                    Image(systemName: "calendar.badge.clock").font(.title2).foregroundStyle(TempoTheme.green)
                }
                let difference = activeDaysThisWeek - activeDaysPreviousWeek
                Text((difference == 0 ? "Geçen haftayla aynı ritimdesin." : (difference > 0 ? "Geçen haftaya göre %d gün daha aktifsin.".tempoFormatted(difference) : "Geçen haftaya göre %d gün daha az hareket ettin; kısa bir yürüyüşle yeniden başlayabilirsin.".tempoFormatted(abs(difference)))).tempoLocalized)
                    .font(.caption).foregroundStyle(TempoTheme.secondary).lineSpacing(3)
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill").foregroundStyle(TempoTheme.orange)
                    Text("Bugün de geldin: %d gün".tempoFormatted(movementStreak)).font(.caption.weight(.semibold))
                    Spacer()
                }
                .padding(10).background(TempoTheme.raised, in: RoundedRectangle(cornerRadius: 13))
                Text("Bu ritim özeti Apple Sağlık hareket günlerini, Tempo GPS ve manuel kayıtlarını, ayrıca tamamlanan çevrimdışı planları kullanır. Strava verileri puana katılmaz.")
                    .font(.caption2).foregroundStyle(TempoTheme.secondary).lineSpacing(3)
            }
        }
    }

    private func makeRoutine(minutes: Int, sport: TempoSportChoice) -> TempoMovementRoutine {
        let low = energy == .low || (model.tempoBalance?.value ?? 100) < 55
        if low || sport == .yoga {
            let steps: [String]
            if minutes == 5 { steps = ["1 dk sakin nefes", "2 dk omuz ve kalça mobilitesi", "2 dk yavaş yürüyüş"] }
            else if minutes == 15 { steps = ["3 dk rahat başlangıç", "8 dk kolay yürüyüş veya yumuşak yoga akışı", "4 dk gevşeme ve nefes"] }
            else { steps = ["5 dk sakin başlangıç", "20 dk konuşma temposunda yürüyüş veya mobilite", "5 dk soğuma"] }
            return TempoMovementRoutine(id: "recovery-\(minutes)-\(sport.rawValue)", sport: sport, title: "Rahat toparlanma", subtitle: "Yüksek efor yerine kolay hareket", minutes: minutes, intensity: "Kolay", steps: steps)
        }

        switch sport {
        case .run, .walking, .hiking:
            let steps = minutes == 5
                ? ["2 dk rahat yürüyüş", "2 dk canlı adım", "1 dk yavaşla"]
                : (minutes == 15 ? ["3 dk rahat ısınma", "9 dk yürüyüş/koşu aralıkları: 1 dk canlı, 2 dk rahat", "3 dk yavaş yürüyüş"] : ["5 dk rahat ısınma", "20 dk konuşma temposunda hareket", "5 dk yavaş bitiriş"])
            return TempoMovementRoutine(id: "endurance-\(minutes)-\(sport.rawValue)", sport: sport, title: sport == .run ? "Rahat koşu ritmi" : "Canlı adımlar", subtitle: "Eforu konuşabilecek düzeyde tut", minutes: minutes, intensity: "Kolay · orta", steps: steps)
        case .cycling:
            let steps = minutes == 5 ? ["2 dk hafif pedal", "2 dk akıcı kadans", "1 dk çok hafif pedal"] : (minutes == 15 ? ["3 dk hafif pedal", "9 dk rahat, düzenli kadans", "3 dk çok hafif pedal"] : ["5 dk rahat başlangıç", "20 dk sabit ve kontrollü sürüş", "5 dk soğuma"])
            return TempoMovementRoutine(id: "ride-\(minutes)", sport: sport, title: "Dengeli sürüş", subtitle: "Kadansı zorlamadan sabitle", minutes: minutes, intensity: "Kolay · orta", steps: steps)
        case .tennis, .basketball, .football, .volleyball, .padel, .badminton:
            let steps = minutes == 5 ? ["1 dk hafif yerinde adım", "2 dk yumuşak yan adım", "1 dk kontrollü gölge hareket", "1 dk rahatlama"] : (minutes == 15 ? ["3 dk eklem ve ayak bileği ısınması", "8 dk kontrollü yön değiştirme ve teknik tekrar", "4 dk yavaşlama"] : ["5 dk dinamik ısınma", "20 dk teknik ve ayak işi blokları; aralarda dinlen", "5 dk soğuma"])
            return TempoMovementRoutine(id: "court-\(minutes)-\(sport.rawValue)", sport: sport, title: "Teknik ve ayak işi", subtitle: "Kısa bloklar, rahat dinlenme araları", minutes: minutes, intensity: "Kontrollü", steps: steps)
        case .fitness:
            let steps = minutes == 5 ? ["1 dk yerinde yürü", "1 dk sandalyeye squat", "1 dk duvar şınavı", "1 dk kalça köprüsü", "1 dk nefes ve gevşeme"] : (minutes == 15 ? ["3 dk ısınma", "3 tur: 8 squat, 6 duvar şınavı, 10 kalça köprüsü", "3 dk soğuma"] : ["5 dk eklem ısınması", "4 tur: 10 squat, 8 yükseltilmiş şınav, 12 kalça köprüsü, 20 sn plank", "5 dk soğuma"])
            return TempoMovementRoutine(id: "bodyweight-\(minutes)", sport: sport, title: "Ekipmansız kuvvet", subtitle: hasEquipment ? "İstersen hafif ekipman ekleyebilirsin" : "Evde veya parkta, vücut ağırlığıyla", minutes: minutes, intensity: "Kendi temponda", steps: steps)
        case .swimming:
            return TempoMovementRoutine(id: "swim-dry-\(minutes)", sport: sport, title: "Yüzme öncesi mobilite", subtitle: "Havuz dışında, ekipmansız hazırlık", minutes: minutes, intensity: "Kolay", steps: ["Omuz ve kürek kemiğini kontrollü çevir", "Gövde rotasyonu ve kol açma hareketleri", "Hafif adımla nabzını kademeli yükselt"])
        case .yoga:
            return TempoMovementRoutine(id: "yoga-\(minutes)", sport: sport, title: "Yumuşak akış", subtitle: "Nefes ve hareketi eşleştir", minutes: minutes, intensity: "Kolay", steps: ["Rahat nefes ve boyun gevşetme", "Kedi-inek ve kalça mobilitesi", "Yavaş bitiriş ve kısa dinlenme"])
        }
    }

    private func completionKey(for date: Date) -> String {
        let day = tempoMovementDayStamp(date)
        return "tempo.movement.completed.\(account.profile?.id ?? "guest").\(day)"
    }
}

private struct MovementRoutineCard: View {
    @EnvironmentObject private var account: TempoAccountStore
    let routine: TempoMovementRoutine
    let label: String

    var body: some View {
        NavigationLink(destination: TempoMovementRoutineScreen(routine: routine, accountId: account.profile?.id ?? "guest")) {
            HStack(spacing: 12) {
                Image(systemName: routine.sport.symbol)
                    .font(.title3.weight(.semibold)).foregroundStyle(routine.sport.accentColor)
                    .frame(width: 44, height: 44).background(routine.sport.accentColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(label.tempoLocalized.uppercased()).font(.caption2.weight(.bold)).tracking(0.7).foregroundStyle(routine.sport.accentColor)
                    Text(routine.title.tempoLocalized).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Text("%d dk · %@".tempoFormatted(routine.minutes, routine.intensity.tempoLocalized)).font(.caption).foregroundStyle(TempoTheme.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(TempoTheme.secondary)
            }
            .padding(14)
            .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}

private struct TempoMovementRoutineScreen: View {
    let routine: TempoMovementRoutine
    let accountId: String
    @State private var isCompleted = false

    private var key: String {
        "tempo.movement.completed.\(accountId).\(tempoMovementDayStamp(Date()))"
    }

    var body: some View {
        ZStack {
            TempoTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("%d dakika · %@".tempoFormatted(routine.minutes, routine.intensity.tempoLocalized), systemImage: routine.sport.symbol)
                            .font(.caption.weight(.bold)).foregroundStyle(routine.sport.accentColor)
                        Text(routine.title.tempoLocalized).font(.system(size: 30, weight: .bold, design: .rounded))
                        Text(routine.subtitle.tempoLocalized).font(.subheadline).foregroundStyle(TempoTheme.secondary)
                    }
                    ForEach(Array(routine.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("%02d".tempoFormatted(index + 1)).font(.caption.bold()).foregroundStyle(.black)
                                .frame(width: 34, height: 34).background(routine.sport.accentColor, in: Circle())
                            Text(step.tempoLocalized).font(.subheadline).foregroundStyle(.white.opacity(0.88)).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(15).background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    Button {
                        isCompleted = true
                        UserDefaults.standard.set(true, forKey: key)
                    } label: {
                        Label(isCompleted ? "Bugünkü hareket tamamlandı" : "Hareket ettim", systemImage: isCompleted ? "checkmark.circle.fill" : "figure.run")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TempoPrimaryButtonStyle())
                    Text("Bu kayıt cihazında tamamlandı olarak işaretlenir; Strava veya arkadaşlarla otomatik paylaşılmaz.")
                        .font(.caption2).foregroundStyle(TempoTheme.secondary)
                }
                .padding(16).padding(.bottom, TempoTheme.scrollBottomClearance)
            }
        }
        .navigationTitle("Antrenman planı")
        .navigationBarTitleDisplayMode(.inline)
        .tempoGlassBackButton()
        .onAppear { isCompleted = UserDefaults.standard.bool(forKey: key) }
    }
}

private func tempoMovementDayStamp(_ date: Date) -> String {
    let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
}

private enum SportDetailSection: String, CaseIterable, Identifiable {
    case overview = "Özet"
    case program = "Program"
    case guide = "Rehber"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: return "chart.xyaxis.line"
        case .program: return "list.clipboard.fill"
        case .guide: return "figure.cooldown"
        }
    }
}

private struct SportDetailScreen: View {
    @EnvironmentObject private var account: TempoAccountStore
    @EnvironmentObject private var model: TempoAppModel
    let sport: TempoSportChoice
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var section: SportDetailSection = .overview
    @State private var weeklyTarget = 3
    @Namespace private var sectionAnimation

    private var weeklyTargetKey: String { "tempo.sport.weekly-target.\(account.profile?.id ?? "guest").\(sport.rawValue)" }

    private var matchingManual: [TempoManualWorkout] {
        model.activityWorkouts.filter { $0.sportId == sport.rawValue }
    }

    private var guide: SportOfflineGuide { sport.offlineGuide }

    var body: some View {
        ZStack {
            TempoTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    SportMotionArtwork(sport: sport)
                    sectionPicker

                    Group {
                        switch section {
                        case .overview:
                            SportOverviewSection(sport: sport, manualWorkouts: matchingManual, weeklyTarget: $weeklyTarget)
                        case .program:
                            SportProgramSection(sport: sport, guide: guide)
                        case .guide:
                            SportPreparationSection(sport: sport, guide: guide)
                        }
                    }
                    .transition(.opacity)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, TempoTheme.scrollBottomClearance)
            }
        }
        .navigationTitle(sport.title)
        .navigationBarTitleDisplayMode(.inline)
        .tempoGlassBackButton()
        .onAppear {
            weeklyTarget = UserDefaults.standard.object(forKey: weeklyTargetKey) == nil
                ? 3
                : min(max(UserDefaults.standard.integer(forKey: weeklyTargetKey), 1), 14)
        }
        .onChange(of: weeklyTarget) { _, value in UserDefaults.standard.set(min(max(value, 1), 14), forKey: weeklyTargetKey) }
    }

    private var sectionPicker: some View {
        HStack(spacing: 6) {
            ForEach(SportDetailSection.allCases) { item in
                Button {
                    TempoHaptics.selection()
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { section = item }
                } label: {
                    Text(item.rawValue.tempoLocalized)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1).minimumScaleFactor(0.85)
                        .foregroundStyle(section == item ? .black : .white.opacity(0.72))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background {
                            if section == item {
                                Capsule()
                                    .fill(sport.accentColor)
                                    .matchedGeometryEffect(id: "sport-section", in: sectionAnimation)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.08)))
    }
}

private struct SportMotionArtwork: View {
    let sport: TempoSportChoice
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: sport.symbol).font(.system(size: 30, weight: .medium)).foregroundStyle(sport.accentColor)
                .frame(width: 58, height: 58).background(sport.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 6) {
                Text(sport.title).font(.title2.weight(.bold))
                Text(sport.offlineGuide.headline.tempoLocalized).font(.subheadline).foregroundStyle(TempoTheme.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 22))
            .multilineTextAlignment(.leading)
    }
}

private struct SportOverviewSection: View {
    let sport: TempoSportChoice
    let manualWorkouts: [TempoManualWorkout]
    @Binding var weeklyTarget: Int

    private var seconds: Double { manualWorkouts.reduce(0) { $0 + Double($1.durationSeconds ?? $1.durationMinutes * 60) } }
    private var weekCount: Int {
        manualWorkouts.filter { Calendar.current.isDateInCurrentWeek($0.startedAt) }.count
    }
    private var lastSevenDays: [TempoManualWorkout] {
        let today = Calendar.current.startOfDay(for: Date())
        let start = Calendar.current.date(byAdding: .day, value: -6, to: today) ?? today
        return manualWorkouts.filter { $0.startedAt >= start && $0.startedAt <= Date() }
    }
    private var recentMetric: String {
        if sport.supportsDistance { return sport.distanceText(lastSevenDays.reduce(0) { $0 + ($1.distanceKm ?? 0) }) }
        return TempoFormat.duration(lastSevenDays.reduce(0) { $0 + Double($1.durationSeconds ?? $1.durationMinutes * 60) })
    }
    private var recentEntries: [SportRecentEntry] {
        let local = manualWorkouts.map { workout in
            SportRecentEntry(
                id: "local-\(workout.id.uuidString)",
                title: workout.title,
                date: workout.startedAt,
                durationSeconds: Double(workout.durationSeconds ?? workout.durationMinutes * 60),
                source: workout.sourceTitle
            )
        }
        return local.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    @EnvironmentObject private var model: TempoAppModel
    private var stravaEntries: [TempoActivity] { (model.dashboard?.activities ?? []).filter { sport.matches(activityType: $0.type) } }
    var body: some View {
        VStack(spacing: 15) {
            TempoMetricGrid {
                SportMetric(value: "\(manualWorkouts.count)", label: "Antrenman")
                    .accessibilityElement(children: .ignore).accessibilityLabel("Antrenman".tempoLocalized).accessibilityValue("\(manualWorkouts.count)").accessibilityIdentifier("sport.total.workouts")
                SportMetric(value: TempoFormat.duration(seconds), label: "Toplam süre")
                SportMetric(value: "\(weekCount)", label: "Bu hafta")
            }

            Text("Tempo + Apple Sağlık".tempoLocalized).font(.caption2).foregroundStyle(TempoTheme.secondary)
            if !stravaEntries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Strava aktiviteleri".tempoLocalized).font(.subheadline.weight(.semibold))
                    ForEach(Array(stravaEntries.prefix(5))) { activity in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(activity.name ?? activity.sport.title).font(.subheadline)
                            Text("Strava · %@ · %@".tempoFormatted(activity.date?.formatted(date: .abbreviated, time: .omitted) ?? "—", TempoFormat.duration(activity.movingSeconds))).font(.caption).foregroundStyle(TempoTheme.secondary)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 20))
            }
            weeklyGoalCard

            if manualWorkouts.isEmpty {
                SportEmptyState(sport: sport)
            } else {
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("SON 7 GÜN".tempoSentenceCased).font(.caption.weight(.semibold)).foregroundStyle(TempoTheme.secondary)
                            Text("Hareket ritmin".tempoLocalized).font(.title3.bold())
                        }
                        Spacer()
                        Text(recentMetric).font(.subheadline.monospacedDigit().bold()).foregroundStyle(sport.accentColor).fixedSize()
                    }
                    WeeklySportChart(sport: sport, manualWorkouts: manualWorkouts)
                }
                .padding(18)
                .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.055)))

                VStack(alignment: .leading, spacing: 12) {
                    Text("SON AKTİVİTELER".tempoSentenceCased).font(.subheadline.weight(.semibold)).foregroundStyle(TempoTheme.secondary)
                    ForEach(Array(recentEntries.prefix(6))) { entry in
                        HStack(spacing: 12) {
                            Image(systemName: sport.symbol)
                                .foregroundStyle(sport.accentColor)
                                .frame(width: 38, height: 38)
                                .background(sport.accentColor.opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                HStack(spacing: 5) {
                                    Text(entry.source.tempoLocalized)
                                    Text("·")
                                    Text((entry.date?.formatted(date: .abbreviated, time: .omitted) ?? "Tarih yok").tempoLocalized)
                                }
                                .font(.caption2).foregroundStyle(TempoTheme.secondary)
                            }
                            Spacer()
                            Text(TempoFormat.duration(entry.durationSeconds)).font(.caption.bold()).foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
                .padding(18)
                .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
    }

    private var weeklyGoalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Haftalık kişisel hedef").font(.subheadline.weight(.semibold))
                    Text("%d / %d antrenman".tempoFormatted(min(weekCount, weeklyTarget), weeklyTarget))
                        .font(.caption).foregroundStyle(TempoTheme.secondary)
                }
                Spacer()
                Stepper("", value: $weeklyTarget, in: 1...14).labelsHidden()
                    .accessibilityLabel("Haftalık antrenman hedefi")
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    Capsule().fill(sport.accentColor).frame(width: geometry.size.width * min(CGFloat(weekCount) / CGFloat(max(weeklyTarget, 1)), 1))
                }
            }
            .frame(height: 7)
            Text("Hedef bu sporun Tempo ve Apple Sağlık kayıtlarını sayar; dilediğinde değiştirebilirsin.")
                .font(.caption2).foregroundStyle(TempoTheme.secondary)
        }
        .padding(15)
        .background(sport.accentColor.opacity(0.075), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct SportRecentEntry: Identifiable {
    let id: String
    let title: String
    let date: Date?
    let durationSeconds: Double
    let source: String
}

private struct WeeklySportChart: View {
    let sport: TempoSportChoice
    let manualWorkouts: [TempoManualWorkout]

    private var days: [SportDayValue] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let manualMinutes: Double = manualWorkouts.reduce(0) { total, workout in
                guard calendar.isDate(workout.startedAt, inSameDayAs: date) else { return total }
                return total + Double(workout.durationSeconds ?? workout.durationMinutes * 60) / 60
            }
            return SportDayValue(date: date, minutes: manualMinutes)
        }
    }

    private var maximum: Double { max(days.map(\.minutes).max() ?? 0, 20) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 9) {
            ForEach(days) { day in
                VStack(spacing: 7) {
                    Text(day.minutes > 0 ? "\(Int(day.minutes.rounded()))" : "")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(sport.accentColor)
                        .frame(height: 11)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: day.minutes > 0 ? [sport.accentColor, sport.accentColor.opacity(0.38)] : [.white.opacity(0.07), .white.opacity(0.025)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: max(10, 86 * day.minutes / maximum))
                    Text(day.date.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2).foregroundStyle(TempoTheme.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 125, alignment: .bottom)
        .animation(.snappy(duration: 0.45), value: days.map(\.minutes))
    }
}

private struct SportDayValue: Identifiable {
    let date: Date
    let minutes: Double
    var id: Date { date }
}

private struct SportEmptyState: View {
    let sport: TempoSportChoice
    @State private var moves = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(sport.accentColor.opacity(0.10)).frame(width: 112, height: 112)
                Circle().stroke(sport.accentColor.opacity(0.24), style: StrokeStyle(lineWidth: 2, dash: [6, 8]))
                    .frame(width: 88, height: 88)
                    .rotationEffect(.degrees(moves ? 360 : 0))
                Image(systemName: sport.symbol).font(.system(size: 38)).foregroundStyle(sport.accentColor)
            }
            Text("İlk %@ kaydını bekliyoruz".tempoFormatted(sport.title.lowercased())).font(.headline)
            Text("Tempo’da kaydettiğin veya elle eklediğin antrenmanlar burada görünür.".tempoLocalized)
                .font(.caption).foregroundStyle(TempoTheme.secondary).multilineTextAlignment(.center).lineSpacing(3)
        }
        .padding(25).frame(maxWidth: .infinity)
        .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onAppear {
            withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) { moves = true }
        }
    }
}

private struct SportProgramSection: View {
    let sport: TempoSportChoice
    let guide: SportOfflineGuide

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Label("Çevrimdışı kullanılabilir", systemImage: "arrow.down.circle.fill")
                    .font(.caption.bold()).foregroundStyle(sport.accentColor)
                Text(guide.summary.tempoLocalized).font(.subheadline).foregroundStyle(TempoTheme.secondary).lineSpacing(3)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(sport.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            ForEach(guide.sessions) { session in
                NavigationLink(destination: OfflineSessionScreen(sport: sport, session: session)) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(sport.accentColor.opacity(0.14))
                            Text("\(session.order)").font(.title3.bold()).foregroundStyle(sport.accentColor)
                        }
                        .frame(width: 50, height: 50)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.title.tempoLocalized).font(.headline).foregroundStyle(.white)
                            Text(session.subtitle.tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary).lineLimit(2)
                            Text("%d dk · %@".tempoFormatted(session.minutes, session.intensity.tempoLocalized))
                                .font(.caption2.bold()).foregroundStyle(sport.accentColor)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(TempoTheme.secondary)
                    }
                    .padding(17)
                    .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { TempoHaptics.impact() })
            }
        }
    }
}

private struct OfflineSessionScreen: View {
    let sport: TempoSportChoice
    let session: SportProgramSession
    @State private var completed = false

    private var completionKey: String { "tempo.offline.session.\(sport.rawValue).\(session.id)" }

    var body: some View {
        ZStack {
            TempoTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("%d dakika · %@".tempoFormatted(session.minutes, session.intensity.tempoLocalized), systemImage: sport.symbol)
                            .font(.caption.bold()).foregroundStyle(sport.accentColor)
                        Text(session.title.tempoLocalized).font(.system(size: 31, weight: .bold, design: .rounded))
                        Text(session.subtitle.tempoLocalized).font(.subheadline).foregroundStyle(TempoTheme.secondary)
                    }

                    ForEach(Array(session.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(index + 1)")
                                .font(.subheadline.bold()).foregroundStyle(.black)
                                .frame(width: 34, height: 34).background(sport.accentColor, in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.title.tempoLocalized).font(.headline)
                                Text(step.detail.tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary).lineSpacing(3)
                            }
                            Spacer()
                            Text(step.duration.tempoLocalized).font(.caption2.bold()).foregroundStyle(sport.accentColor)
                        }
                        .padding(17)
                        .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
                    }

                    Button {
                        completed.toggle()
                        UserDefaults.standard.set(completed, forKey: completionKey)
                        completed ? TempoHaptics.success() : TempoHaptics.selection()
                    } label: {
                        Label(completed ? "Tamamlandı" : "Antrenmanı tamamla", systemImage: completed ? "checkmark.circle.fill" : "circle")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                            .foregroundStyle(completed ? .black : .white)
                            .background(completed ? sport.accentColor : TempoTheme.raised, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Label("Bu program cihazında kayıtlıdır ve internet bağlantısı olmadan açılır.", systemImage: "iphone.and.arrow.forward")
                        .font(.caption).foregroundStyle(TempoTheme.secondary)
                }
                .padding(16).padding(.bottom, TempoTheme.scrollBottomClearance)
            }
        }
        .navigationTitle("Program")
        .navigationBarTitleDisplayMode(.inline)
        .tempoGlassBackButton()
        .onAppear { completed = UserDefaults.standard.bool(forKey: completionKey) }
    }
}

private struct SportPreparationSection: View {
    let sport: TempoSportChoice
    let guide: SportOfflineGuide
    @State private var showsWarmup = true

    private var moves: [SportGuideMove] { showsWarmup ? guide.warmup : guide.cooldown }

    var body: some View {
        VStack(spacing: 15) {
            HStack(spacing: 8) {
                preparationButton(title: "Isınma", icon: "flame.fill", selected: showsWarmup) {
                    TempoHaptics.selection(); withAnimation(.snappy) { showsWarmup = true }
                }
                preparationButton(title: "Soğuma", icon: "wind", selected: !showsWarmup) {
                    TempoHaptics.selection(); withAnimation(.snappy) { showsWarmup = false }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text((showsWarmup ? "Vücudunu harekete hazırla" : "Nabzını sakin biçimde düşür").tempoLocalized)
                    .font(.title3.bold())
                Text((showsWarmup ? "Antrenmandan hemen önce sırayla uygula." : "Antrenman bittiğinde acele etmeden uygula.").tempoLocalized)
                    .font(.caption).foregroundStyle(TempoTheme.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(moves) { move in
                HStack(spacing: 14) {
                    Image(systemName: move.symbol)
                        .font(.title3).foregroundStyle(sport.accentColor)
                        .frame(width: 46, height: 46).background(sport.accentColor.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(move.title.tempoLocalized).font(.subheadline.weight(.semibold))
                        Text(move.detail.tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary).lineLimit(2)
                    }
                    Spacer()
                    Text(move.duration.tempoLocalized).font(.caption2.bold()).foregroundStyle(sport.accentColor)
                }
                .padding(15)
                .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Label("Ağrı hissedersen hareketi durdur. Rehber genel egzersiz bilgilendirmesidir.", systemImage: "heart.text.square")
                .font(.caption).foregroundStyle(TempoTheme.secondary).lineSpacing(3)
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(TempoTheme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func preparationButton(title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title.tempoLocalized, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? .black : .white.opacity(0.75))
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(selected ? sport.accentColor : TempoTheme.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SportOfflineGuide {
    let headline: String
    let summary: String
    let sessions: [SportProgramSession]
    let warmup: [SportGuideMove]
    let cooldown: [SportGuideMove]
}

private struct SportProgramSession: Identifiable {
    let id: String
    let order: Int
    let title: String
    let subtitle: String
    let minutes: Int
    let intensity: String
    let steps: [SportSessionStep]
}

private struct SportSessionStep {
    let title: String
    let detail: String
    let duration: String
}

private struct SportGuideMove: Identifiable {
    let id: String
    let title: String
    let detail: String
    let duration: String
    let symbol: String
}

private extension TempoSportChoice {
    var accentColor: Color {
        switch self {
        case .run, .basketball: return TempoTheme.orange
        case .cycling, .swimming, .badminton: return TempoTheme.blue
        case .fitness, .football, .walking, .tennis, .volleyball: return TempoTheme.green
        case .hiking, .padel, .yoga: return TempoTheme.purple
        }
    }

    var offlineGuide: SportOfflineGuide {
        let content: SportGuideContent
        switch self {
        case .run:
            content = .init(headline: "Daha dengeli ve akıcı koş.", summary: "Üç koşuluk temel program; kolay tempo, ritim ve dayanıklılığı dengeler.", sessions: [
                ("easy", "Kolay ritim", "Konuşma temposunda kontrollü koşu", 28, "Kolay", ["5 dk tempolu yürüyüş", "18 dk rahat koşu", "5 dk yavaş yürüyüş"]),
                ("tempo", "Tempo dokunuşu", "Kısa hızlanmalarla ritim çalışması", 32, "Orta", ["8 dk kolay koşu", "4 × 3 dk canlı tempo / 90 sn kolay", "5 dk soğuma"]),
                ("long", "Dayanıklılık", "Kesintisiz, sakin ve uzun efor", 42, "Orta", ["7 dk kolay başlangıç", "30 dk sabit rahat tempo", "5 dk yürüyüş"])
            ], warmup: ["Tempolu yürüyüş", "Ayak bileği çevirme", "Diz çekme", "Kısa açma koşuları"], cooldown: ["Yavaş yürüyüş", "Baldır esnetme", "Ön bacak esnetme", "Sakin nefes"])
        case .cycling:
            content = .init(headline: "Kadansını bul, sürüşünü uzat.", summary: "Kontrol, kadans ve dayanıklılık için üç çevrimdışı sürüş planı.", sessions: [
                ("spin", "Rahat çevir", "Akıcı pedal ve hafif direnç", 35, "Kolay", ["8 dk hafif pedal", "22 dk 80–90 kadans", "5 dk çok hafif pedal"]),
                ("cadence", "Kadans blokları", "Bacak hızını kontrollü artır", 40, "Orta", ["10 dk ısınma", "6 × 2 dk hızlı pedal / 2 dk rahat", "6 dk soğuma"]),
                ("endurance", "Uzun sürüş", "Sabit eforla aerobik dayanıklılık", 60, "Orta", ["10 dk rahat başlangıç", "40 dk sabit efor", "10 dk hafif bitiriş"])
            ], warmup: ["Omuz çevirme", "Kalça mobilitesi", "Hafif pedal", "Kısa kadans artışı"], cooldown: ["Çok hafif pedal", "Kalça önü esnetme", "Arka bacak esnetme", "Omuz gevşetme"])
        case .walking:
            content = .init(headline: "Adımlarını düzenli bir alışkanlığa çevir.", summary: "Tempo değişimleriyle günlük yürüyüşünü daha işlevsel hale getir.", sessions: [
                ("reset", "Günlük yenilenme", "Rahat ve kesintisiz yürüyüş", 25, "Kolay", ["5 dk rahat tempo", "15 dk canlı yürüyüş", "5 dk gevşeme"]),
                ("brisk", "Canlı adımlar", "Kısa tempolu yürüyüş blokları", 32, "Orta", ["7 dk ısınma", "5 × 3 dk hızlı / 1 dk rahat", "5 dk soğuma"]),
                ("distance", "Uzun rota", "Dengeli tempoda mesafe biriktir", 50, "Orta", ["10 dk rahat", "30 dk sabit canlı tempo", "10 dk kolay"])
            ], warmup: ["Yerinde adım", "Ayak bileği açma", "Kalça çevirme", "Kısa canlı yürüyüş"], cooldown: ["Yavaş adımlar", "Baldır esnetme", "Arka bacak esnetme", "Derin nefes"])
        case .hiking:
            content = .init(headline: "Patikaya güçlü ve dengeli çık.", summary: "Yokuş dayanıklılığı, denge ve uzun yürüyüş kontrolü için üç plan.", sessions: [
                ("base", "Patika temeli", "Kolay arazide dengeli yürüyüş", 40, "Kolay", ["8 dk düz ısınma", "25 dk dalgalı rota", "7 dk rahat bitiriş"]),
                ("climb", "Yokuş gücü", "Kısa tırmanış tekrarları", 45, "Orta", ["10 dk ısınma", "6 × 3 dk yokuş / kontrollü dönüş", "8 dk soğuma"]),
                ("trail", "Uzun patika", "Beslenme ve tempo kontrollü rota", 75, "Orta", ["15 dk sakin başlangıç", "50 dk sabit patika temposu", "10 dk kolay"])
            ], warmup: ["Ayak bileği mobilitesi", "Kalça açma", "Gövde rotasyonu", "Kısa yokuş yürüyüşü"], cooldown: ["Düz zeminde yürüme", "Baldır gevşetme", "Kalça esnetme", "Bel rahatlatma"])
        case .swimming:
            content = .init(headline: "Tekniği koru, kulaçlarını akıcı tut.", summary: "Teknik, nefes ve dayanıklılığı birleştiren üç havuz programı.", sessions: [
                ("technique", "Teknik havuzu", "Rahat kulaç ve gövde pozisyonu", 30, "Kolay", ["200 m kolay yüzme", "6 × 50 m teknik", "200 m rahat bitiriş"]),
                ("interval", "Kulaç ritmi", "Kontrollü kısa aralıklar", 38, "Orta", ["300 m ısınma", "8 × 100 m orta / 30 sn dinlen", "200 m soğuma"]),
                ("endurance", "Kesintisiz yüzüş", "Uzun ve sakin aerobik set", 45, "Orta", ["300 m rahat", "3 × 500 m sabit tempo", "200 m çok kolay"])
            ], warmup: ["Omuz çevirme", "Kürek kemiği açma", "Gövde rotasyonu", "Kolay 200 metre"], cooldown: ["Çok kolay yüzme", "Göğüs esnetme", "Omuz arkası esnetme", "Sakin nefes"])
        case .fitness:
            content = .init(headline: "Gücü kontrollü ve düzenli artır.", summary: "Ekipmansız uygulanabilen temel kuvvet, merkez ve tam vücut planları.", sessions: [
                ("foundation", "Temel kuvvet", "Dengeli tam vücut çalışması", 32, "Orta", ["3 × 10 squat", "3 × 8 eğimli şınav", "3 × 12 kalça köprüsü", "3 × 30 sn plank"]),
                ("core", "Merkez kontrolü", "Gövde dayanıklılığı ve denge", 25, "Orta", ["3 × 8 dead bug", "3 × 10 bird dog", "3 × 25 sn yan plank", "3 × 12 ters mekik"]),
                ("circuit", "Tempo devresi", "Düşük ekipmanlı kondisyon devresi", 36, "Canlı", ["4 tur: 12 squat", "10 yükseltilmiş şınav", "12 geriye lunge", "40 sn yerinde hızlı adım"])
            ], warmup: ["Yerinde hafif adım", "Omuz ve kol çevirme", "Kalça menteşesi", "Vücut ağırlığı squat"], cooldown: ["Yavaş yürüyüş", "Göğüs açma", "Kalça esnetme", "Çocuk pozu"])
        case .tennis:
            content = .init(headline: "Ayaklarını hazırla, vuruş ritmini koru.", summary: "Kort hareketi, vuruş tutarlılığı ve maç dayanıklılığı için üç plan.", sessions: [
                ("footwork", "Kort ayakları", "Yön değiştirme ve hazır pozisyon", 28, "Orta", ["5 dk hafif koşu", "6 × gölge kort geçişi", "4 × 45 sn yan adım", "5 dk rahatlama"]),
                ("rally", "Ralli ritmi", "Kontrollü forehand ve backhand", 40, "Orta", ["10 dk mini tenis", "4 × 6 dk çapraz ralli", "10 dk servis ritmi"]),
                ("match", "Maç provası", "Puan düzeninde kontrollü oyun", 55, "Canlı", ["10 dk ısınma", "20 dk servis + ilk vuruş", "20 dk puan oyunu", "5 dk soğuma"])
            ], warmup: ["Hafif kort turu", "Yan adım", "Omuz çevirme", "Gölge vuruş"], cooldown: ["Yavaş yürüyüş", "Ön kol esnetme", "Omuz gevşetme", "Baldır esnetme"])
        case .basketball:
            content = .init(headline: "Kontrol, ayak işi ve şut ritmi.", summary: "Top hakimiyeti, bitiriş ve kondisyonu dengeli ilerleten üç saha planı.", sessions: [
                ("handle", "Top kontrolü", "İki elle dengeli dripling", 28, "Orta", ["5 dk ısınma", "6 × 45 sn sağ/sol el", "5 × yön değiştirme", "20 serbest atış"]),
                ("finish", "Pota çevresi", "İki taraftan kontrollü bitiriş", 38, "Orta", ["10 yakın şut", "3 × 8 sağ turnike", "3 × 8 sol turnike", "20 orta mesafe"]),
                ("court", "Saha temposu", "Şut ve koşuyu birleştir", 45, "Canlı", ["8 dk top sürme", "5 nokta × 5 şut", "6 tam saha kontrollü koşu", "20 serbest atış"])
            ], warmup: ["Hafif saha turu", "Ayak bileği açma", "Yan kayma", "Yakın mesafe şut"], cooldown: ["Yavaş yürüme", "Baldır esnetme", "Ön bacak esnetme", "Omuz gevşetme"])
        case .football:
            content = .init(headline: "Top kontrolünü ve saha temposunu geliştir.", summary: "Teknik, çeviklik ve maç kondisyonu için üç dengeli çalışma.", sessions: [
                ("touch", "İlk dokunuş", "Yakın top kontrolü ve pas", 32, "Orta", ["5 dk hafif koşu", "8 dk dar alanda dokunuş", "4 × 3 dk duvar pası", "5 dk top sürme"]),
                ("agility", "Çeviklik", "Kısa yön değişimleri", 35, "Canlı", ["8 dk ısınma", "6 × koni slalom", "6 × 15 m hızlanma", "8 dk top kontrolü"]),
                ("matchfit", "Maç ritmi", "Aralıklı saha kondisyonu", 45, "Canlı", ["10 dk teknik ısınma", "8 × 2 dk canlı / 1 dk rahat", "10 dk şut veya pas", "5 dk soğuma"])
            ], warmup: ["Hafif koşu", "Kalça açma", "Yan adım", "Topla kısa dokunuş"], cooldown: ["Yavaş yürüme", "Arka bacak esnetme", "Kalça önü esnetme", "Baldır gevşetme"])
        case .volleyball:
            content = .init(headline: "Sıçrama, denge ve top kontrolü.", summary: "Pas tekniği, file ayakları ve kontrollü sıçrama için üç plan.", sessions: [
                ("passing", "Pas kontrolü", "Manşet ve parmak pası ritmi", 30, "Orta", ["6 dk ısınma", "4 × 3 dk duvar manşeti", "4 × 3 dk parmak pas", "5 dk servis"]),
                ("net", "File ayakları", "Yaklaşma ve blok adımları", 35, "Orta", ["8 dk mobilite", "6 × yaklaşma adımı", "5 × blok yan geçişi", "10 kontrollü sıçrama"]),
                ("court", "Saha akışı", "Servis, pas ve hareket bağlantısı", 42, "Canlı", ["10 dk top kontrolü", "20 hedef servis", "5 × savunma geçişi", "8 dk rahat oyun"])
            ], warmup: ["Omuz çevirme", "Ayak bileği açma", "Yan geçiş", "Düşük sıçrama"], cooldown: ["Yavaş yürüme", "Omuz esnetme", "Ön bacak esnetme", "Bilek gevşetme"])
        case .padel:
            content = .init(headline: "Duvarı kullan, kortu birlikte yönet.", summary: "Ayak işi, vole ve puan düzeni için üç çevrimdışı padel planı.", sessions: [
                ("control", "Kort kontrolü", "Kısa adımlar ve dengeli temas", 30, "Orta", ["6 dk hareketli ısınma", "6 × gölge geçiş", "4 × 4 dk kontrollü ralli", "5 dk servis"]),
                ("net", "File oyunu", "Vole ve pozisyon geçişi", 38, "Orta", ["8 dk mini ralli", "5 × vole bloğu", "5 × lob sonrası geçiş", "10 dk puan oyunu"]),
                ("match", "Maç akışı", "Savunmadan hücuma geçiş", 50, "Canlı", ["10 dk ısınma", "15 dk çapraz ralli", "20 dk puan düzeni", "5 dk soğuma"])
            ], warmup: ["Kort turu", "Yan adım", "Omuz çevirme", "Gölge vole"], cooldown: ["Yavaş yürüyüş", "Ön kol esnetme", "Omuz rahatlatma", "Baldır esnetme"])
        case .badminton:
            content = .init(headline: "Hafif ayaklar, hızlı raket kontrolü.", summary: "Kort köşeleri, vuruş ritmi ve kısa oyun dayanıklılığı için üç plan.", sessions: [
                ("footwork", "Altı köşe", "Raketsiz kort ayak çalışması", 26, "Orta", ["6 dk ısınma", "6 × 45 sn altı köşe", "5 × split step", "5 dk rahatlama"]),
                ("racket", "Raket ritmi", "Clear, drop ve kısa servis", 35, "Orta", ["8 dk hafif vuruş", "4 × clear serisi", "4 × drop serisi", "20 kısa servis"]),
                ("rally", "Hızlı ralli", "Kısa yoğun bloklar", 40, "Canlı", ["10 dk ısınma", "8 × 90 sn hızlı ralli", "8 dk servis dönüşü", "5 dk soğuma"])
            ], warmup: ["Hafif kort turu", "Split step", "Bilek çevirme", "Gölge vuruş"], cooldown: ["Yavaş adım", "Ön kol esnetme", "Omuz gevşetme", "Baldır esnetme"])
        case .yoga:
            content = .init(headline: "Nefes, hareket ve dengeyi birleştir.", summary: "Mobilite, denge ve sakin akış için üç çevrimdışı yoga pratiği.", sessions: [
                ("mobility", "Sabah mobilitesi", "Yumuşak eklem ve omurga akışı", 18, "Kolay", ["3 dk sakin nefes", "5 dk kedi-inek", "6 dk düşük hamle akışı", "4 dk çocuk pozu"]),
                ("balance", "Denge akışı", "Tek ayak kontrolü ve merkez", 25, "Orta", ["5 dk güneşe selam", "3 × ağaç pozu", "3 × savaşçı III", "5 dk oturarak nefes"]),
                ("restore", "Yenilenme", "Yavaş esneme ve gevşeme", 32, "Kolay", ["6 dk kalça açma", "8 dk omurga rotasyonu", "8 dk öne katlanma", "10 dk dinlenme"])
            ], warmup: ["Sakin nefes", "Boyun gevşetme", "Kedi-inek", "Kalça çevirme"], cooldown: ["Oturarak öne katlanma", "Yatarak rotasyon", "Dizleri göğse çekme", "Savasana"])
        }
        return content.makeGuide(symbol: symbol)
    }
}

private struct SportGuideContent {
    let headline: String
    let summary: String
    let sessions: [(String, String, String, Int, String, [String])]
    let warmup: [String]
    let cooldown: [String]

    func makeGuide(symbol: String) -> SportOfflineGuide {
        let programSessions = sessions.enumerated().map { index, value in
            SportProgramSession(
                id: value.0,
                order: index + 1,
                title: value.1,
                subtitle: value.2,
                minutes: value.3,
                intensity: value.4,
                steps: value.5.enumerated().map { stepIndex, text in
                    SportSessionStep(title: text, detail: stepDetail(for: text), duration: stepDuration(for: text, index: stepIndex))
                }
            )
        }
        return SportOfflineGuide(
            headline: headline,
            summary: summary,
            sessions: programSessions,
            warmup: makeMoves(warmup, symbol: "figure.warmup"),
            cooldown: makeMoves(cooldown, symbol: "figure.cooldown")
        )
    }

    private func makeMoves(_ values: [String], symbol: String) -> [SportGuideMove] {
        values.enumerated().map { index, title in
            SportGuideMove(
                id: "\(symbol)-\(index)",
                title: title,
                detail: index.isMultiple(of: 2) ? "Kontrollü aralıkta, acele etmeden uygula." : "Duruşunu koru ve nefesini doğal tut.",
                duration: index == values.count - 1 ? "60 sn" : "40 sn",
                symbol: symbol
            )
        }
    }

    private func stepDetail(for title: String) -> String {
        if title.contains("/") { return "Çalışma ve dinlenme aralığını dengeli uygula; form bozulursa tempoyu azalt." }
        if title.lowercased().contains("ısınma") { return "İlk bölümde temponu kademeli artır ve hareket kalitesine odaklan." }
        if title.lowercased().contains("soğuma") || title.lowercased().contains("bitiriş") { return "Nabzını kademeli düşür; son bölümde rahat nefese dön." }
        return "Rahat ama kontrollü formu koru; gerektiğinde kısa ara ver."
    }

    private func stepDuration(for title: String, index: Int) -> String {
        if let first = title.split(separator: " ").first, first.allSatisfy(\.isNumber) { return String(first) }
        return "Bölüm %d".tempoFormatted(index + 1)
    }
}

private struct ToolCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon).font(.title2).foregroundStyle(color)
                .frame(width: 52, height: 52).background(color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title.tempoLocalized).font(.headline).foregroundStyle(.white)
                Text(subtitle.tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary).lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(TempoTheme.secondary)
        }
        .padding(17)
        .background(TempoTheme.card.opacity(0.88), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.07), lineWidth: 1))
    }
}

struct NearbyFacilitiesScreen: View {
    @EnvironmentObject private var account: TempoAccountStore
    @StateObject private var searchModel = FacilitySearchModel()
    @State private var selectedSport: TempoSportChoice?
    @State private var selectedPlaceID: String?
    @State private var searchRadiusKm = 25
    @State private var camera: MapCameraPosition = .automatic

    private var availableSports: [TempoSportChoice] {
        let preferred = account.profile?.sports
            .compactMap(TempoSportChoice.init(rawValue:))
            .filter { $0.facilitySearchQuery != nil } ?? []
        let remaining = TempoSportChoice.allCases.filter { sport in
            sport.facilitySearchQuery != nil && !preferred.contains(sport)
        }
        return preferred + remaining
    }

    private var selectedPlace: NearbyPlace? {
        selectedPlaceID.flatMap { id in searchModel.places.first { $0.id == id } }
    }

    var body: some View {
        ZStack {
            TempoTheme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("YAKININDA".tempoSentenceCased).font(.caption.weight(.semibold)).foregroundStyle(TempoTheme.secondary)
                            Text("Spor alanları").font(.system(size: 31, weight: .bold, design: .rounded))
                        }
                        Spacer()
                        Menu {
                            ForEach([10, 25, 50], id: \.self) { radius in
                                Button {
                                    searchRadiusKm = radius
                                    selectedPlaceID = nil
                                    if let selectedSport {
                                        Task { await searchModel.search(for: selectedSport, radiusKm: radius) }
                                    }
                                } label: {
                                    if searchRadiusKm == radius {
                                        Label("\(radius) km", systemImage: "checkmark")
                                    } else {
                                        Text("\(radius) km")
                                    }
                                }
                            }
                        } label: {
                            Label("\(searchRadiusKm) km", systemImage: "scope")
                                .font(.caption.bold())
                                .foregroundStyle(TempoTheme.green)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(TempoTheme.card, in: Capsule())
                        }
                    }
                    .padding(.horizontal, 16)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(availableSports) { sport in
                                Button {
                                    selectedSport = sport
                                    selectedPlaceID = nil
                                    Task { await searchModel.search(for: sport, radiusKm: searchRadiusKm) }
                                } label: {
                                    Label(sport.title, systemImage: sport.symbol)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(selectedSport == sport ? .black : .white)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(selectedSport == sport ? TempoTheme.green : TempoTheme.card, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    ZStack {
                        Map(position: $camera, selection: $selectedPlaceID) {
                            UserAnnotation()
                            ForEach(searchModel.places) { place in
                                Marker(place.name, coordinate: place.coordinate)
                                    .tint(place.source == .openStreetMap ? TempoTheme.green : TempoTheme.orange)
                                    .tag(place.id)
                            }
                        }
                        .mapStyle(.standard(elevation: .realistic))
                        .mapControls {
                            MapUserLocationButton()
                            MapCompass()
                            MapScaleView()
                        }

                        if searchModel.isSearching {
                            ProgressView(searchModel.places.isEmpty ? "Spor alanları aranıyor…" : "Daha fazla yer taranıyor…")
                                .padding(14)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if searchModel.hasOpenStreetMapPlaces {
                            Link(destination: URL(string: "https://www.openstreetmap.org/copyright")!) {
                                Text("© OpenStreetMap katkıda bulunanlar")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.78))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                            .padding(8)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                    .padding(.horizontal, 12)

                    if let place = selectedPlace {
                        PlaceCard(place: place)
                            .padding(.horizontal, 16)
                    } else if let message = searchModel.message {
                        HStack(spacing: 10) {
                            Image(systemName: "location.circle.fill").foregroundStyle(TempoTheme.green)
                            Text(message.tempoLocalized).font(.footnote).foregroundStyle(TempoTheme.secondary)
                            Spacer()
                            if searchModel.needsPermission {
                                Button("İzin ver") { searchModel.requestLocation() }
                                    .font(.caption.bold()).foregroundStyle(TempoTheme.green)
                            }
                        }
                        .padding(.horizontal, 18)
                    }
            }
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .navigationTitle("Spor alanları")
        .navigationBarTitleDisplayMode(.inline)
        .tempoGlassBackButton()
        .onAppear {
            if selectedSport == nil { selectedSport = availableSports.first }
            if let selectedSport {
                Task { await searchModel.search(for: selectedSport, radiusKm: searchRadiusKm) }
            } else {
                searchModel.requestLocation()
            }
        }
        .onChange(of: searchModel.region?.center.latitude) { _, _ in
            if let region = searchModel.region { camera = .region(region) }
        }
        .onChange(of: searchModel.region?.center.longitude) { _, _ in
            if let region = searchModel.region { camera = .region(region) }
        }
        .onChange(of: searchModel.region?.span.latitudeDelta) { _, _ in
            if let region = searchModel.region { camera = .region(region) }
        }
    }
}

private struct PlaceCard: View {
    let place: NearbyPlace

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: place.source == .openStreetMap ? "map.fill" : "mappin.and.ellipse")
                .font(.title2)
                .foregroundStyle(place.source == .openStreetMap ? TempoTheme.green : TempoTheme.orange)
                .frame(width: 48, height: 48)
                .background((place.source == .openStreetMap ? TempoTheme.green : TempoTheme.orange).opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(place.name).font(.headline).lineLimit(1)
                Text(place.address).font(.caption).foregroundStyle(TempoTheme.secondary).lineLimit(2)
                Text("\(place.distanceText) · \(place.sourceTitle)")
                    .font(.caption2.bold())
                    .foregroundStyle(place.source == .openStreetMap ? TempoTheme.green : TempoTheme.orange)
            }
            Spacer()
            Button { place.openDirections() } label: {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .foregroundStyle(.black)
                    .frame(width: 42, height: 42)
                    .background(TempoTheme.green, in: Circle())
            }
        }
        .padding(15)
        .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
    }
}

@MainActor
final class FacilitySearchModel: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var places: [NearbyPlace] = []
    @Published var isSearching = false
    @Published var message: String? = "Yakındaki spor alanlarını görmek için konum izni ver."
    @Published var region: MKCoordinateRegion?
    @Published var needsPermission = true

    var hasOpenStreetMapPlaces: Bool { places.contains { $0.source == .openStreetMap } }

    private let manager = CLLocationManager()
    private var location: CLLocation?
    private var pendingSport: TempoSportChoice?
    private var pendingRadiusKm = 25
    private var searchGeneration = 0
    private var resultCache: [String: CachedFacilitySearch] = [:]

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            needsPermission = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            needsPermission = false
            manager.requestLocation()
        case .denied, .restricted:
            needsPermission = true
            message = "Konum izni kapalı. iPhone Ayarlar’dan Tempo için konuma izin verebilirsin."
        @unknown default:
            needsPermission = true
        }
    }

    func search(for sport: TempoSportChoice, radiusKm: Int) async {
        guard let location else {
            pendingSport = sport
            pendingRadiusKm = radiusKm
            requestLocation()
            return
        }

        searchGeneration += 1
        let generation = searchGeneration
        isSearching = true
        message = nil
        let radiusMeters = max(5_000, min(radiusKm, 50) * 1_000)
        region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: CLLocationDistance(radiusMeters * 2),
            longitudinalMeters: CLLocationDistance(radiusMeters * 2)
        )

        let cacheKey = Self.cacheKey(for: sport, radiusKm: radiusKm, location: location)
        if let cached = resultCache[cacheKey], Date().timeIntervalSince(cached.createdAt) < 10 * 60 {
            places = cached.places
            isSearching = false
            message = cached.places.isEmpty
                ? "%@ için %d km çevrede kayıtlı bir alan bulunamadı.".tempoFormatted(sport.title, radiusKm)
                : "%d alan bulundu · kayıtlı sonuçlar anında gösterildi.".tempoFormatted(cached.places.count)
            return
        }

        // Show whichever provider returns first; a slow Apple Maps search
        // must not hide completed OpenStreetMap results (or the reverse).
        places = []
        await withTaskGroup(of: [NearbyPlace].self) { group in
            group.addTask { await self.searchAppleMaps(for: sport, location: location, radiusMeters: radiusMeters) }
            group.addTask { await self.searchOpenStreetMap(for: sport, location: location, radiusMeters: radiusMeters) }
            var results: [NearbyPlace] = []
            for await batch in group {
                guard generation == searchGeneration, !Task.isCancelled else { group.cancelAll(); return }
                results.append(contentsOf: batch.filter { $0.distanceMeters <= Double(radiusMeters) })
                places = Self.deduplicated(results)
                if !places.isEmpty { message = "%d alan bulundu; diğer harita kaynakları taranıyor…".tempoFormatted(places.count) }
            }
        }
        guard generation == searchGeneration else { return }
        isSearching = false
        guard !Task.isCancelled else { return }
        resultCache[cacheKey] = CachedFacilitySearch(createdAt: Date(), places: places)
        message = places.isEmpty
            ? "%@ için %d km çevrede kayıtlı bir alan bulunamadı.".tempoFormatted(sport.title, radiusKm)
            : "%d alan bulundu · yakından uzağa sıralandı.".tempoFormatted(places.count)
    }

    private func searchAppleMaps(for sport: TempoSportChoice, location: CLLocation, radiusMeters: Int) async -> [NearbyPlace] {
        let searchRegion = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: CLLocationDistance(radiusMeters * 2),
            longitudinalMeters: CLLocationDistance(radiusMeters * 2)
        )
        return await withTaskGroup(of: [NearbyPlace].self, returning: [NearbyPlace].self) { group in
            for query in sport.facilitySearchQueries {
                group.addTask {
                    let request = MKLocalSearch.Request()
                    request.naturalLanguageQuery = query
                    request.region = searchRegion
                    request.resultTypes = .pointOfInterest
                    guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
                    return response.mapItems.prefix(35).map { NearbyPlace($0, origin: location) }
                }
            }
            var results: [NearbyPlace] = []
            for await batch in group {
                results.append(contentsOf: batch)
            }
            return Self.deduplicated(results)
        }
    }

    private func searchOpenStreetMap(for sport: TempoSportChoice, location: CLLocation, radiusMeters: Int) async -> [NearbyPlace] {
        guard !sport.openStreetMapSelectors.isEmpty else { return [] }
        let latitude = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), location.coordinate.latitude)
        let longitude = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), location.coordinate.longitude)
        let selectors = sport.openStreetMapSelectors
            .map { "nwr(around:\(radiusMeters),\(latitude),\(longitude))\($0);" }
            .joined()
        let query = "[out:json][timeout:18];(\(selectors));out center tags;"

        let endpoints = [
            "https://overpass.kumi.systems/api/interpreter",
            "https://overpass-api.de/api/interpreter",
        ]
        for endpoint in endpoints {
            guard !Task.isCancelled else { return [] }
            guard let url = URL(string: endpoint) else { continue }
            var components = URLComponents()
            components.queryItems = [URLQueryItem(name: "data", value: query)]
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
            request.timeoutInterval = 12
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.setValue("Tempo/1.0 (https://apitempo.com)", forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { continue }
                let decoded = try JSONDecoder().decode(OpenStreetMapResponse.self, from: data)
                return decoded.elements.prefix(160).compactMap {
                    NearbyPlace(openStreetMapElement: $0, sportTitle: sport.title, origin: location)
                }
            } catch {
                continue
            }
        }
        return []
    }

    private static func deduplicated(_ input: [NearbyPlace]) -> [NearbyPlace] {
        let sorted = input.sorted { $0.distanceMeters < $1.distanceMeters }
        var result: [NearbyPlace] = []
        for place in sorted {
            let duplicate = result.contains { existing in
                let distance = CLLocation(latitude: existing.coordinate.latitude, longitude: existing.coordinate.longitude)
                    .distance(from: CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude))
                let sameName = existing.normalizedName == place.normalizedName
                return distance < 70 || (sameName && distance < 700)
            }
            if !duplicate { result.append(place) }
            if result.count >= 100 { break }
        }
        return result
    }

    private static func cacheKey(for sport: TempoSportChoice, radiusKm: Int, location: CLLocation) -> String {
        let latitude = (location.coordinate.latitude * 100).rounded() / 100
        let longitude = (location.coordinate.longitude * 100).rounded() / 100
        return "\(sport.rawValue):\(radiusKm):\(latitude):\(longitude)"
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            needsPermission = false
            manager.requestLocation()
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            needsPermission = true
            message = "Konum izni kapalı. iPhone Ayarlar’dan Tempo için konuma izin verebilirsin."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let value = locations.last else { return }
        location = value
        region = MKCoordinateRegion(center: value.coordinate, latitudinalMeters: 16_000, longitudinalMeters: 16_000)
        if let pendingSport {
            let radius = pendingRadiusKm
            self.pendingSport = nil
            Task { await search(for: pendingSport, radiusKm: radius) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isSearching = false
        message = "Konum alınamadı. Konum servislerini kontrol edip yeniden deneyebilirsin."
    }
}

private struct CachedFacilitySearch {
    let createdAt: Date
    let places: [NearbyPlace]
}

struct OpenStreetMapResponse: Decodable {
    let elements: [OpenStreetMapElement]
}

struct OpenStreetMapElement: Decodable {
    struct Center: Decodable {
        let lat: Double
        let lon: Double
    }

    let type: String
    let id: Int64
    let lat: Double?
    let lon: Double?
    let center: Center?
    let tags: [String: String]?
}

struct NearbyPlace: Identifiable, @unchecked Sendable {
    enum Source: Equatable, Sendable {
        case appleMaps
        case openStreetMap
    }

    let id: String
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let source: Source
    let distanceMeters: CLLocationDistance

    var sourceTitle: String {
        source == .openStreetMap ? "OpenStreetMap" : "Apple Haritalar".tempoLocalized
    }

    var normalizedName: String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: " ", with: "")
    }

    var distanceText: String {
        if distanceMeters < 1_000 { return "\(max(1, Int(distanceMeters.rounded()))) m" }
        return String(format: "%.1f km", distanceMeters / 1_000)
    }

    init(_ mapItem: MKMapItem, origin: CLLocation) {
        name = mapItem.name ?? "Spor alanı".tempoLocalized
        coordinate = mapItem.placemark.coordinate
        address = mapItem.placemark.title ?? "Adres bilgisi yok".tempoLocalized
        source = .appleMaps
        distanceMeters = origin.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        id = String(format: "apple:%.6f,%.6f,%@", coordinate.latitude, coordinate.longitude, name)
    }

    init?(openStreetMapElement element: OpenStreetMapElement, sportTitle: String, origin: CLLocation) {
        guard let latitude = element.lat ?? element.center?.lat,
              let longitude = element.lon ?? element.center?.lon else { return nil }

        let tags = element.tags ?? [:]
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let prefersEnglish = Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true
        name = (prefersEnglish ? tags["name:en"] : tags["name:tr"])
            ?? tags["name"]
            ?? tags["operator"]
            ?? "%@ alanı".tempoFormatted(sportTitle)

        let street = [tags["addr:street"], tags["addr:housenumber"]].compactMap { $0 }.joined(separator: " ")
        let area = [tags["addr:district"], tags["addr:suburb"], tags["addr:city"]].compactMap { $0 }.joined(separator: ", ")
        let parts = [street, area].filter { !$0.isEmpty }
        address = parts.isEmpty ? "Açık harita kaydı".tempoLocalized : parts.joined(separator: " · ")

        source = .openStreetMap
        distanceMeters = origin.distance(from: CLLocation(latitude: latitude, longitude: longitude))
        id = "osm:\(element.type):\(element.id)"
    }

    func openDirections() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

private extension Calendar {
    func isDateInCurrentWeek(_ date: Date) -> Bool {
        isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
    }
}
