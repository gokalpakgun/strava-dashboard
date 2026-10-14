import CoreLocation
import Foundation
import MapKit
import SwiftUI
import UIKit

struct SportsHubScreen: View {
    @EnvironmentObject private var account: TempoAccountStore
    @EnvironmentObject private var model: TempoAppModel

    private var selectedSports: [TempoSportChoice] {
        account.profile?.sports.compactMap(TempoSportChoice.init(rawValue:)) ?? []
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TempoTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("SANA ÖZEL").font(.caption.bold()).tracking(1.5).foregroundStyle(TempoTheme.green)
                            Text("Sporlarım").font(.system(size: 31, weight: .bold, design: .rounded))
                            Text("Seçtiğin sporlara göre aktivite geçmişin ve hızlı araçların.")
                                .font(.subheadline).foregroundStyle(TempoTheme.secondary)
                        }

                        if selectedSports.isEmpty {
                            Text("Profilinden ilgilendiğin sporları seçerek bu alanı kişiselleştirebilirsin.")
                                .padding(20).frame(maxWidth: .infinity)
                                .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        } else {
                            ForEach(selectedSports) { sport in
                                NavigationLink(destination: SportDetailScreen(sport: sport, activities: model.dashboard?.activities ?? [])) {
                                    SportSummaryCard(sport: sport, activities: model.dashboard?.activities ?? [])
                                }
                                .buttonStyle(.plain)
                                .simultaneousGesture(TapGesture().onEnded { TempoHaptics.selection() })
                            }
                        }

                        Text("HIZLI ARAÇLAR").font(.caption.bold()).tracking(1.5).foregroundStyle(TempoTheme.green).padding(.top, 4)
                        NavigationLink(destination: CoachScreen()) {
                            ToolCard(title: "Tempo Koç", subtitle: "Tüm spor verilerine göre kişisel değerlendirme", icon: "sparkles", color: TempoTheme.blue)
                        }
                        .buttonStyle(.plain)
                        NavigationLink(destination: RoutesScreen()) {
                            ToolCard(title: "Aktivite rotaları", subtitle: "Strava GPS rotalarını tek haritada incele", icon: "map.fill", color: TempoTheme.orange)
                        }
                        .buttonStyle(.plain)
                        NavigationLink(destination: NearbyFacilitiesScreen()) {
                            ToolCard(title: "Yakındaki spor alanları", subtitle: "Kort, saha, havuz ve spor salonlarını bul", icon: "location.fill", color: TempoTheme.green)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 34)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct SportSummaryCard: View {
    let sport: TempoSportChoice
    let activities: [TempoActivity]

    private var matching: [TempoActivity] { activities.filter { sport.matches(activityType: $0.type) } }
    private var distance: Double { matching.reduce(0) { $0 + $1.distanceKm } }
    private var seconds: Double { matching.reduce(0) { $0 + $1.movingSeconds } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: sport.symbol).font(.title2).foregroundStyle(.black)
                    .frame(width: 50, height: 50).background(TempoTheme.green, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(sport.title).font(.title3.bold())
                    Text("%d kayıtlı aktivite".tempoFormatted(matching.count)).font(.caption).foregroundStyle(TempoTheme.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(TempoTheme.secondary)
            }
            HStack(spacing: 8) {
                SportMetric(value: TempoFormat.distance(distance), label: "Mesafe")
                SportMetric(value: TempoFormat.duration(seconds), label: "Süre")
                SportMetric(value: "\(matching.filter { $0.date.map(Calendar.current.isDateInCurrentWeek) ?? false }.count)", label: "Bu hafta")
            }
        }
        .padding(18)
        .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
            Text(value).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.7)
            Text(label.tempoLocalized).font(.caption2).foregroundStyle(TempoTheme.secondary)
        }
        .padding(11).frame(maxWidth: .infinity, alignment: .leading)
        .background(TempoTheme.raised, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
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
    let sport: TempoSportChoice
    let activities: [TempoActivity]
    @State private var section: SportDetailSection = .overview
    @Namespace private var sectionAnimation

    private var matching: [TempoActivity] {
        activities.filter { sport.matches(activityType: $0.type) }
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
                            SportOverviewSection(sport: sport, activities: matching)
                        case .program:
                            SportProgramSection(sport: sport, guide: guide)
                        case .guide:
                            SportPreparationSection(sport: sport, guide: guide)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 42)
            }
        }
        .navigationTitle(sport.title)
        .navigationBarTitleDisplayMode(.inline)
        .tempoGlassBackButton()
    }

    private var sectionPicker: some View {
        HStack(spacing: 6) {
            ForEach(SportDetailSection.allCases) { item in
                Button {
                    TempoHaptics.selection()
                    withAnimation(.snappy(duration: 0.28)) { section = item }
                } label: {
                    Label(item.rawValue, systemImage: item.symbol)
                        .font(.caption.weight(.semibold))
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
    @State private var animates = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [sport.accentColor.opacity(0.22), TempoTheme.card, TempoTheme.blue.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .stroke(sport.accentColor.opacity(0.16), lineWidth: 1)
                .frame(width: 230, height: 230)
                .scaleEffect(animates ? 1.05 : 0.86)
            Circle()
                .stroke(TempoTheme.blue.opacity(0.14), lineWidth: 1)
                .frame(width: 160, height: 160)
                .scaleEffect(animates ? 0.90 : 1.08)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("ÇEVRİMDIŞI SPOR ALANI")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.45)
                        .foregroundStyle(sport.accentColor)
                    Text(sport.title)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text(sport.offlineGuide.headline)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.64))
                        .lineLimit(2)
                }
                Spacer(minLength: 12)
                Image(systemName: sport.symbol)
                    .font(.system(size: 57, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(colors: [sport.accentColor, TempoTheme.blue], startPoint: .top, endPoint: .bottom)
                    )
                    .symbolEffect(.pulse, options: .repeating, value: animates)
                    .frame(width: 95, height: 95)
            }
            .padding(23)
        }
        .frame(height: 190)
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.white.opacity(0.07)))
        .onAppear { animates = true }
    }
}

private struct SportOverviewSection: View {
    let sport: TempoSportChoice
    let activities: [TempoActivity]

    private var distance: Double { activities.reduce(0) { $0 + $1.distanceKm } }
    private var seconds: Double { activities.reduce(0) { $0 + $1.movingSeconds } }
    private var weekCount: Int {
        activities.filter { $0.date.map(Calendar.current.isDateInCurrentWeek) ?? false }.count
    }

    var body: some View {
        VStack(spacing: 15) {
            HStack(spacing: 8) {
                SportMetric(value: "\(activities.count)", label: "Aktivite")
                SportMetric(value: TempoFormat.duration(seconds), label: "Toplam süre")
                SportMetric(value: "\(weekCount)", label: "Bu hafta")
            }

            if activities.isEmpty {
                SportEmptyState(sport: sport)
            } else {
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("SON 7 GÜN").font(.caption.bold()).tracking(1.3).foregroundStyle(sport.accentColor)
                            Text("Hareket ritmin").font(.title3.bold())
                        }
                        Spacer()
                        Text(TempoFormat.distance(distance)).font(.subheadline.bold()).foregroundStyle(sport.accentColor)
                    }
                    WeeklySportChart(sport: sport, activities: activities)
                }
                .padding(18)
                .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.055)))

                VStack(alignment: .leading, spacing: 12) {
                    Text("SON AKTİVİTELER").font(.caption.bold()).tracking(1.3).foregroundStyle(sport.accentColor)
                    ForEach(Array(activities.prefix(4))) { activity in
                        HStack(spacing: 12) {
                            Image(systemName: sport.symbol)
                                .foregroundStyle(sport.accentColor)
                                .frame(width: 38, height: 38)
                                .background(sport.accentColor.opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(activity.name ?? sport.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(activity.date?.formatted(date: .abbreviated, time: .omitted) ?? "Tarih yok")
                                    .font(.caption2).foregroundStyle(TempoTheme.secondary)
                            }
                            Spacer()
                            Text(TempoFormat.duration(activity.movingSeconds)).font(.caption.bold()).foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
                .padding(18)
                .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
    }
}

private struct WeeklySportChart: View {
    let sport: TempoSportChoice
    let activities: [TempoActivity]

    private var days: [SportDayValue] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let value = activities
                .filter { $0.date.map { calendar.isDate($0, inSameDayAs: date) } ?? false }
                .reduce(0) { $0 + $1.movingSeconds / 60 }
            return SportDayValue(date: date, minutes: value)
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
            Text("İlk \(sport.title.lowercased()) kaydını bekliyoruz").font(.headline)
            Text("Strava’ya eklediğin aktivite burada grafik ve kişisel özet olarak görünecek.")
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
                Text(guide.summary).font(.subheadline).foregroundStyle(TempoTheme.secondary).lineSpacing(3)
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
                            Text(session.title).font(.headline).foregroundStyle(.white)
                            Text(session.subtitle).font(.caption).foregroundStyle(TempoTheme.secondary).lineLimit(2)
                            Text("\(session.minutes) dk · \(session.intensity)")
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
                        Label("\(session.minutes) dakika · \(session.intensity)", systemImage: sport.symbol)
                            .font(.caption.bold()).foregroundStyle(sport.accentColor)
                        Text(session.title).font(.system(size: 31, weight: .bold, design: .rounded))
                        Text(session.subtitle).font(.subheadline).foregroundStyle(TempoTheme.secondary)
                    }

                    ForEach(Array(session.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(index + 1)")
                                .font(.subheadline.bold()).foregroundStyle(.black)
                                .frame(width: 34, height: 34).background(sport.accentColor, in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.title).font(.headline)
                                Text(step.detail).font(.caption).foregroundStyle(TempoTheme.secondary).lineSpacing(3)
                            }
                            Spacer()
                            Text(step.duration).font(.caption2.bold()).foregroundStyle(sport.accentColor)
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
                .padding(16).padding(.bottom, 32)
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
                Text(showsWarmup ? "Vücudunu harekete hazırla" : "Nabzını sakin biçimde düşür")
                    .font(.title3.bold())
                Text(showsWarmup ? "Antrenmandan hemen önce sırayla uygula." : "Antrenman bittiğinde acele etmeden uygula.")
                    .font(.caption).foregroundStyle(TempoTheme.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(moves) { move in
                HStack(spacing: 14) {
                    Image(systemName: move.symbol)
                        .font(.title3).foregroundStyle(sport.accentColor)
                        .frame(width: 46, height: 46).background(sport.accentColor.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(move.title).font(.subheadline.weight(.semibold))
                        Text(move.detail).font(.caption).foregroundStyle(TempoTheme.secondary).lineLimit(2)
                    }
                    Spacer()
                    Text(move.duration).font(.caption2.bold()).foregroundStyle(sport.accentColor)
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
            Label(title, systemImage: icon)
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
        case .fitness, .football, .walking: return TempoTheme.green
        case .hiking, .padel: return TempoTheme.purple
        case .tennis, .volleyball: return Color(red: 0.84, green: 0.92, blue: 0.28)
        case .yoga: return .pink
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
        return "Bölüm \(index + 1)"
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
        .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
                            Text("YAKININDA").font(.caption.bold()).tracking(1.5).foregroundStyle(TempoTheme.green)
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
                            Text(message).font(.footnote).foregroundStyle(TempoTheme.secondary)
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
            searchModel.requestLocation()
        }
        .onChange(of: searchModel.region?.center.latitude) { _, _ in
            if let region = searchModel.region { camera = .region(region) }
            if let selectedSport {
                Task { await searchModel.search(for: selectedSport, radiusKm: searchRadiusKm) }
            }
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
final class FacilitySearchModel: NSObject, ObservableObject, CLLocationManagerDelegate {
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

        let applePlaces = await searchAppleMaps(for: sport, location: location, radiusMeters: radiusMeters)
        guard generation == searchGeneration else { return }
        places = Self.deduplicated(applePlaces)
        message = places.isEmpty ? "Açık harita kayıtları da taranıyor…" : "Apple Haritalar’dan \(places.count) alan bulundu; açık veriler taranıyor."

        let openPlaces = await searchOpenStreetMap(for: sport, location: location, radiusMeters: radiusMeters)
        guard generation == searchGeneration else { return }
        places = Self.deduplicated(applePlaces + openPlaces)
        isSearching = false
        message = places.isEmpty
            ? "\(sport.title) için \(radiusKm) km çevrede kayıtlı bir alan bulunamadı."
            : "\(places.count) alan bulundu · yakından uzağa sıralandı."
    }

    private func searchAppleMaps(for sport: TempoSportChoice, location: CLLocation, radiusMeters: Int) async -> [NearbyPlace] {
        let searchRegion = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: CLLocationDistance(radiusMeters * 2),
            longitudinalMeters: CLLocationDistance(radiusMeters * 2)
        )
        var results: [NearbyPlace] = []

        for query in sport.facilitySearchQueries {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = searchRegion
            request.resultTypes = .pointOfInterest
            do {
                let response = try await MKLocalSearch(request: request).start()
                results.append(contentsOf: response.mapItems.prefix(35).map { NearbyPlace($0, origin: location) })
                results = Self.deduplicated(results)
                if results.count >= 70 { break }
            } catch {
                continue
            }
        }
        return results
    }

    private func searchOpenStreetMap(for sport: TempoSportChoice, location: CLLocation, radiusMeters: Int) async -> [NearbyPlace] {
        guard !sport.openStreetMapSelectors.isEmpty else { return [] }
        let latitude = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), location.coordinate.latitude)
        let longitude = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), location.coordinate.longitude)
        let selectors = sport.openStreetMapSelectors
            .map { "nwr(around:\(radiusMeters),\(latitude),\(longitude))\($0);" }
            .joined()
        let query = "[out:json][timeout:18];(\(selectors));out center tags;"

        var components = URLComponents(string: "https://overpass-api.de/api/interpreter")
        components?.queryItems = [URLQueryItem(name: "data", value: query)]
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 22
        request.setValue("Tempo/1.0 (https://apitempo.com)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
            let decoded = try JSONDecoder().decode(OpenStreetMapResponse.self, from: data)
            return decoded.elements.prefix(160).compactMap {
                NearbyPlace(openStreetMapElement: $0, sportTitle: sport.title, origin: location)
            }
        } catch {
            return []
        }
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

struct NearbyPlace: Identifiable {
    enum Source: Equatable {
        case appleMaps
        case openStreetMap
    }

    let id: String
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let source: Source
    let distanceMeters: CLLocationDistance
    private let mapItem: MKMapItem?

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
        self.mapItem = mapItem
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
        name = tags["name:tr"] ?? tags["name"] ?? tags["operator"] ?? "\(sportTitle) alanı"

        let street = [tags["addr:street"], tags["addr:housenumber"]].compactMap { $0 }.joined(separator: " ")
        let area = [tags["addr:district"], tags["addr:suburb"], tags["addr:city"]].compactMap { $0 }.joined(separator: ", ")
        let parts = [street, area].filter { !$0.isEmpty }
        address = parts.isEmpty ? "Açık harita kaydı".tempoLocalized : parts.joined(separator: " · ")

        source = .openStreetMap
        mapItem = nil
        distanceMeters = origin.distance(from: CLLocation(latitude: latitude, longitude: longitude))
        id = "osm:\(element.type):\(element.id)"
    }

    func openDirections() {
        if let mapItem {
            mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
            return
        }
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
