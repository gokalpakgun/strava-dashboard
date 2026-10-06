import Charts
import MapKit
import SwiftUI

enum TempoTheme {
    static let background = Color(red: 0.025, green: 0.035, blue: 0.03)
    static let card = Color(red: 0.065, green: 0.085, blue: 0.073)
    static let raised = Color(red: 0.095, green: 0.12, blue: 0.104)
    static let green = Color(red: 0.37, green: 0.94, blue: 0.56)
    static let orange = Color(red: 1.0, green: 0.39, blue: 0.20)
    static let blue = Color(red: 0.32, green: 0.65, blue: 1.0)
    static let purple = Color(red: 0.71, green: 0.52, blue: 1.0)
    static let secondary = Color.white.opacity(0.55)
}

struct ContentView: View {
    @EnvironmentObject private var model: TempoAppModel
    @State private var selectedTab = 0

    var body: some View {
        Group {
            if model.isConnected {
                TabView(selection: $selectedTab) {
                    HomeScreen().tag(0).tabItem { Label("Özet", systemImage: "square.grid.2x2.fill") }
                    ActivitiesScreen().tag(1).tabItem { Label("Aktiviteler", systemImage: "figure.run") }
                    RoutesScreen().tag(2).tabItem { Label("Rotalar", systemImage: "map.fill") }
                    CoachScreen().tag(3).tabItem { Label("Koç", systemImage: "sparkles") }
                    MoreScreen().tag(4).tabItem { Label("Profil", systemImage: "person.crop.circle.fill") }
                }
                .tint(TempoTheme.green)
                .toolbarBackground(TempoTheme.card, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
            } else {
                WelcomeScreen()
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct WelcomeScreen: View {
    @EnvironmentObject private var model: TempoAppModel

    var body: some View {
        ZStack {
            TempoTheme.background.ignoresSafeArea()
            Circle()
                .fill(TempoTheme.green.opacity(0.15))
                .frame(width: 360, height: 360)
                .blur(radius: 70)
                .offset(x: 150, y: -330)

            VStack(alignment: .leading, spacing: 28) {
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(LinearGradient(colors: [TempoTheme.green, TempoTheme.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.black)
                }
                .frame(width: 88, height: 88)

                VStack(alignment: .leading, spacing: 12) {
                    Text("TEMPO")
                        .font(.caption.bold())
                        .tracking(4)
                        .foregroundStyle(TempoTheme.green)
                    Text("Spor verilerin,\ntek bir yerde.")
                        .font(.system(size: 43, weight: .bold, design: .rounded))
                        .tracking(-1.2)
                    Text("Aktivitelerini incele, rotalarını haritada gör, gelişimini takip et ve kişisel antrenman koçundan değerlendirme al.")
                        .font(.body)
                        .foregroundStyle(TempoTheme.secondary)
                        .lineSpacing(4)
                }

                VStack(spacing: 11) {
                    FeatureLine(icon: "chart.xyaxis.line", text: "Gerçek Strava istatistikleri")
                    FeatureLine(icon: "map.fill", text: "Native rota ve ısı haritası")
                    FeatureLine(icon: "sparkles", text: "Verilerine özel yapay zekâ koçu")
                }

                Button(action: model.connectStrava) {
                    HStack {
                        Image(systemName: "figure.run")
                        Text(model.isBusy ? "Bağlanıyor…" : "Strava ile devam et")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20)
                    .frame(height: 58)
                    .background(TempoTheme.green, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(model.isBusy)

                Text(model.status)
                    .font(.footnote)
                    .foregroundStyle(TempoTheme.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer().frame(height: 16)
            }
            .padding(.horizontal, 24)
        }
    }
}

private struct FeatureLine: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(TempoTheme.green).frame(width: 24)
            Text(text).font(.subheadline.weight(.medium))
        }
    }
}

private struct HomeScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    @AppStorage("tempoWeeklyGoalKm") private var weeklyGoalKm = 40.0

    private var activities: [TempoActivity] { model.dashboard?.activities ?? [] }
    private var weekActivities: [TempoActivity] { activities.filter { $0.date.map(Calendar.current.isDateInCurrentWeek) ?? false } }
    private var weekDistance: Double { weekActivities.reduce(0) { $0 + $1.distanceKm } }
    private var weekSeconds: Double { weekActivities.reduce(0) { $0 + $1.movingSeconds } }
    private var weekElevation: Double { weekActivities.reduce(0) { $0 + $1.elevationMeters } }

    var body: some View {
        NavigationStack {
            TempoPage {
                HomeHeader()
                if let dashboard = model.dashboard {
                    hero(dashboard.athlete)
                    weeklyMetrics
                    challengeCard
                    hydrationCompact
                    SectionHeading(title: "Son aktiviteler", caption: "STRAVA")
                    ForEach(Array(dashboard.activities.prefix(4))) { ActivityRow(activity: $0) }
                    if dashboard.activities.isEmpty { EmptyCard(icon: "figure.run", text: "Henüz aktivite bulunamadı.") }
                } else {
                    LoadingDashboardCard()
                }
            }
            .refreshable { await model.reloadAll() }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func hero(_ athlete: TempoAthlete) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MERHABA, \((athlete.firstname ?? "SPORCU").uppercased())")
                        .font(.caption.bold()).tracking(1.8).foregroundStyle(.black.opacity(0.55))
                    Text("Bu hafta ritmini\nkorumaya devam et.")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                }
                Spacer()
                Image(systemName: "bolt.heart.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.black)
            }
            HStack {
                Label("\(weekActivities.count) aktivite", systemImage: "checkmark.circle.fill")
                Spacer()
                Text(TempoFormat.distance(weekDistance)).fontWeight(.bold)
            }
            .font(.subheadline)
            .foregroundStyle(.black.opacity(0.7))
        }
        .padding(22)
        .background(LinearGradient(colors: [TempoTheme.green, Color(red: 0.62, green: 1, blue: 0.67)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var weeklyMetrics: some View {
        HStack(spacing: 10) {
            MetricCard(value: TempoFormat.distance(weekDistance), label: "Mesafe", icon: "point.topleft.down.to.point.bottomright.curvepath", color: TempoTheme.orange)
            MetricCard(value: TempoFormat.duration(weekSeconds), label: "Süre", icon: "clock.fill", color: TempoTheme.blue)
            MetricCard(value: "\(Int(weekElevation)) m", label: "Tırmanış", icon: "mountain.2.fill", color: TempoTheme.purple)
        }
    }

    private var challengeCard: some View {
        let progress = min(weekDistance / max(weeklyGoalKm, 1), 1)
        return TempoCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(title: "Haftalık hedef", caption: "MEYDAN OKUMA", padding: false)
                HStack(spacing: 18) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.08), lineWidth: 9)
                        Circle().trim(from: 0, to: CGFloat(progress)).stroke(TempoTheme.orange, style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
                        Text("%\(Int(progress * 100))").font(.headline.bold())
                    }
                    .frame(width: 82, height: 82)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("\(TempoFormat.distance(weekDistance)) / \(Int(weeklyGoalKm)) km").font(.headline)
                        Text(progress >= 1 ? "Haftalık hedef tamamlandı." : "Hedefe \(TempoFormat.distance(max(weeklyGoalKm - weekDistance, 0))) kaldı.")
                            .font(.subheadline).foregroundStyle(TempoTheme.secondary)
                    }
                }
            }
        }
    }

    private var hydrationCompact: some View {
        NavigationLink(destination: HealthScreen()) {
            HStack(spacing: 16) {
                Image(systemName: "heart.text.square.fill").font(.title2).foregroundStyle(.pink)
                    .frame(width: 48, height: 48).background(Color.pink.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("Apple Sağlık").font(.headline)
                    Text(model.healthSyncEnabled ? "\(model.todayWaterMl) ml su · sağlık verileri bağlı" : "Uyku, adım, kalori, nabız ve daha fazlası")
                        .font(.subheadline).foregroundStyle(TempoTheme.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(TempoTheme.secondary)
            }
            .padding(18)
            .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ActivitiesScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    @State private var search = ""
    @State private var selectedSport = "Tümü"
    private let filters = ["Tümü", "Koşu", "Bisiklet", "Yürüyüş", "Diğer"]

    private var filtered: [TempoActivity] {
        (model.dashboard?.activities ?? []).filter { activity in
            let matchesSearch = search.isEmpty || (activity.name ?? "").localizedCaseInsensitiveContains(search)
            let sport = activity.sport.title
            let matchesSport = selectedSport == "Tümü" || sport == selectedSport || (selectedSport == "Diğer" && !["Koşu", "Bisiklet", "Yürüyüş"].contains(sport))
            return matchesSearch && matchesSport
        }
    }

    var body: some View {
        NavigationStack {
            TempoPage {
                PageTitle(title: "Aktiviteler", subtitle: "Tüm antrenman geçmişin")
                SearchField(text: $search, placeholder: "Aktivite ara")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filters, id: \.self) { filter in
                            Button(filter) { selectedSport = filter }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(selectedSport == filter ? .black : .white)
                                .padding(.horizontal, 15).padding(.vertical, 9)
                                .background(selectedSport == filter ? TempoTheme.green : TempoTheme.raised, in: Capsule())
                        }
                    }
                }
                Text("\(filtered.count) aktivite").font(.caption.bold()).tracking(1.2).foregroundStyle(TempoTheme.secondary)
                LazyVStack(spacing: 10) {
                    ForEach(filtered) { activity in
                        NavigationLink(destination: ActivityDetailScreen(activity: activity)) { ActivityRow(activity: activity) }
                            .buttonStyle(.plain)
                    }
                }
                if filtered.isEmpty { EmptyCard(icon: "magnifyingglass", text: "Bu filtreye uygun aktivite yok.") }
            }
            .refreshable { await model.refreshDashboard() }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct ActivityDetailScreen: View {
    let activity: TempoActivity
    var body: some View {
        TempoPage {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: activity.sport.symbol).font(.system(size: 30)).foregroundStyle(TempoTheme.orange)
                Text(activity.name ?? activity.sport.title).font(.largeTitle.bold())
                if let date = activity.date { Text(TempoFormat.longDate.string(from: date)).foregroundStyle(TempoTheme.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                MetricCard(value: TempoFormat.distance(activity.distanceKm), label: "Mesafe", icon: "arrow.left.and.right", color: TempoTheme.orange)
                MetricCard(value: TempoFormat.duration(activity.movingSeconds), label: "Süre", icon: "clock.fill", color: TempoTheme.blue)
                MetricCard(value: "\(Int(activity.elevationMeters)) m", label: "Yükseklik", icon: "mountain.2.fill", color: TempoTheme.purple)
            }
            if activity.route.count > 1 {
                RouteMap(routes: [activity], selectedActivity: activity)
                    .frame(height: 330).clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            TempoCard {
                DetailLine(label: "Spor", value: activity.sport.title)
                Divider().overlay(.white.opacity(0.08))
                DetailLine(label: "Ortalama hız", value: String(format: "%.1f km/sa", activity.speedKmh))
                Divider().overlay(.white.opacity(0.08))
                DetailLine(label: "Strava aktivitesi", value: "#\(activity.id)")
            }
            Link(destination: URL(string: "https://www.strava.com/activities/\(activity.id)")!) {
                Label("Strava’da aç", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity)
            }
            .buttonStyle(TempoPrimaryButtonStyle())
        }
        .navigationTitle("Aktivite")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RoutesScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    @State private var selectedId: Int64?

    private var routes: [TempoActivity] { (model.dashboard?.activities ?? []).filter { $0.route.count > 1 }.prefix(300).map { $0 } }
    private var selected: TempoActivity? { selectedId.flatMap { id in routes.first { $0.id == id } } }

    var body: some View {
        NavigationStack {
            TempoPage {
                PageTitle(title: "Rotalar", subtitle: "GPS aktivite haritan")
                TempoCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("HARİTADA GÖSTER").font(.caption2.bold()).tracking(1.4).foregroundStyle(TempoTheme.green)
                            Text(selected?.name ?? "Tüm rotalar").font(.headline).lineLimit(1)
                        }
                        Spacer()
                        Menu {
                            Button("Tüm rotalar") { selectedId = nil }
                            ForEach(routes) { activity in
                                Button("\(activity.date.map { TempoFormat.shortDate.string(from: $0) } ?? "") · \(activity.name ?? activity.sport.title)") { selectedId = activity.id }
                            }
                        } label: {
                            Image(systemName: "slider.horizontal.3").font(.title3).foregroundStyle(TempoTheme.green)
                                .frame(width: 44, height: 44).background(TempoTheme.green.opacity(0.1), in: Circle())
                        }
                    }
                }
                if routes.isEmpty {
                    EmptyCard(icon: "map", text: "Konum bilgisi olan Strava rotası bulunamadı.")
                } else {
                    RouteMap(routes: routes, selectedActivity: selected)
                        .frame(height: 470)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    Text(selected == nil ? "\(routes.count) GPS rotası gösteriliyor." : "Seçili rotayı yakınlaştırıp inceleyebilirsin.")
                        .font(.footnote).foregroundStyle(TempoTheme.secondary)
                }
            }
            .refreshable { await model.refreshDashboard() }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct RouteMap: View {
    let routes: [TempoActivity]
    let selectedActivity: TempoActivity?
    @State private var camera: MapCameraPosition = .automatic

    private var visible: [TempoActivity] { selectedActivity.map { [$0] } ?? routes }

    var body: some View {
        Map(position: $camera) {
            ForEach(visible) { activity in
                MapPolyline(coordinates: activity.route)
                    .stroke(selectedActivity == nil ? TempoTheme.orange.opacity(0.6) : TempoTheme.green, style: StrokeStyle(lineWidth: selectedActivity == nil ? 3 : 5, lineCap: .round, lineJoin: .round))
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .onAppear { fitCamera() }
        .onChange(of: selectedActivity?.id) { _, _ in fitCamera() }
    }

    private func fitCamera() {
        let points = visible.flatMap(\.route)
        guard let first = points.first else { return }
        var rect = MKMapRect(origin: MKMapPoint(first), size: MKMapSize(width: 1, height: 1))
        for point in points.dropFirst() { rect = rect.union(MKMapRect(origin: MKMapPoint(point), size: MKMapSize(width: 1, height: 1))) }
        camera = .rect(rect.insetBy(dx: -max(rect.width * 0.12, 1_500), dy: -max(rect.height * 0.12, 1_500)))
    }
}

private struct CoachScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    @State private var period = "90"
    @State private var question = ""
    private let periods = [("30", "30 gün"), ("90", "90 gün"), ("180", "6 ay"), ("365", "1 yıl"), ("all", "Tümü")]
    private let suggestions = ["Gelişimimi değerlendir", "Koşu tempomu yorumla", "Antrenman düzenim nasıl?", "Bir sonraki hedefim ne olmalı?"]

    var body: some View {
        NavigationStack {
            TempoPage {
                PageTitle(title: "Tempo Koç", subtitle: "Verilerini anlayan spor asistanın")
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "sparkles").font(.title).foregroundStyle(.black)
                        Spacer()
                        Text("YAPAY ZEKÂ").font(.caption.bold()).tracking(1.4).foregroundStyle(.black.opacity(0.55))
                    }
                    Text("Antrenman geçmişine göre net ve kişisel değerlendirmeler al.")
                        .font(.title2.bold()).foregroundStyle(.black)
                }
                .padding(22)
                .background(LinearGradient(colors: [TempoTheme.green, TempoTheme.blue], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                TempoCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("DEĞERLENDİRME DÖNEMİ").font(.caption.bold()).tracking(1.2).foregroundStyle(TempoTheme.secondary)
                        Picker("Dönem", selection: $period) {
                            ForEach(periods.indices, id: \.self) { index in Text(periods[index].1).tag(periods[index].0) }
                        }
                        .pickerStyle(.segmented)
                        TextEditor(text: $question)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 110)
                            .padding(12)
                            .background(TempoTheme.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(alignment: .topLeading) {
                                if question.isEmpty { Text("Koçuna ne sormak istiyorsun?").foregroundStyle(TempoTheme.secondary).padding(.horizontal, 17).padding(.vertical, 21).allowsHitTesting(false) }
                            }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(suggestions, id: \.self) { suggestion in
                                    Button(suggestion) { question = suggestion }
                                        .font(.caption.weight(.semibold)).foregroundStyle(.white)
                                        .padding(.horizontal, 12).padding(.vertical, 9).background(TempoTheme.raised, in: Capsule())
                                }
                            }
                        }
                        Button { model.askCoach(period: period, question: question) } label: {
                            HStack {
                                if model.isCoachLoading { ProgressView().tint(.black) } else { Image(systemName: "sparkles") }
                                Text(model.isCoachLoading ? "Veriler değerlendiriliyor…" : "Koça sor")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(TempoPrimaryButtonStyle())
                        .disabled(model.isCoachLoading)
                    }
                }
                if !model.coachAnswer.isEmpty {
                    TempoCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Koçun değerlendirmesi", systemImage: "bubble.left.and.text.bubble.right.fill").font(.headline)
                                Spacer()
                                Text(model.coachPeriodDescription).font(.caption).foregroundStyle(TempoTheme.green)
                            }
                            Divider().overlay(.white.opacity(0.08))
                            Text(model.coachAnswer).font(.body).lineSpacing(5).textSelection(.enabled)
                        }
                    }
                }
                Text(model.healthSyncEnabled ? "Koç, seçtiğin dönemdeki Strava ve özetlenmiş Apple Sağlık ölçülerini kullanır. Sağlık teşhisi vermez." : "Koç yalnızca seçtiğin dönemdeki Strava aktivite ölçülerini kullanır. Sağlık teşhisi vermez.")
                    .font(.caption).foregroundStyle(TempoTheme.secondary).lineSpacing(3)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct MoreScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            TempoPage {
                if let athlete = model.dashboard?.athlete { ProfileHeader(athlete: athlete) }
                else { PageTitle(title: "Profil", subtitle: "Tempo hesabın") }
                LazyVGrid(columns: columns, spacing: 12) {
                    MoreLink(title: "Apple Sağlık", subtitle: "Uyku, su ve hareket", icon: "heart.text.square.fill", color: .pink, destination: AnyView(HealthScreen()))
                    MoreLink(title: "Aylık", subtitle: "Son 6 ay", icon: "chart.bar.fill", color: TempoTheme.green, destination: AnyView(MonthlyStatsScreen()))
                    MoreLink(title: "Ekipman", subtitle: "Bisiklet ve ayakkabı", icon: "bicycle", color: TempoTheme.orange, destination: AnyView(GearScreen()))
                    MoreLink(title: "Segmentler", subtitle: "Favorilerin", icon: "flag.checkered", color: TempoTheme.purple, destination: AnyView(SegmentsScreen()))
                    MoreLink(title: "Eddington", subtitle: "Koşu sayın", icon: "number", color: TempoTheme.blue, destination: AnyView(EddingtonScreen()))
                    MoreLink(title: "Yıl Özeti", subtitle: "Bu yılın", icon: "arrow.counterclockwise", color: TempoTheme.green, destination: AnyView(YearSummaryScreen()))
                    MoreLink(title: "Fotoğraflar", subtitle: "Aktivitelerden", icon: "photo.stack.fill", color: TempoTheme.orange, destination: AnyView(PhotosScreen()))
                }
                TempoCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("BAĞLANTI DURUMU").font(.caption.bold()).tracking(1.3).foregroundStyle(TempoTheme.green)
                        Text(model.status).font(.subheadline).foregroundStyle(TempoTheme.secondary)
                    }
                }
                Button(role: .destructive, action: model.disconnect) {
                    Label("Strava bağlantısını kes", systemImage: "rectangle.portrait.and.arrow.right").frame(maxWidth: .infinity)
                }
                .buttonStyle(TempoSecondaryButtonStyle())
                .disabled(model.isBusy)
                Link("Gizlilik bilgisi", destination: URL(string: "https://apitempo.com/privacy")!)
                    .font(.footnote).foregroundStyle(TempoTheme.secondary).frame(maxWidth: .infinity)
            }
            .refreshable { await model.reloadAll() }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct HealthScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    private var progress: Double { min(Double(model.todayWaterMl) / Double(model.dailyGoalMl), 1) }

    var body: some View {
        TempoPage {
            PageTitle(title: "Apple Sağlık", subtitle: "Günlük sağlık ve toparlanma görünümün")
            if !model.healthAvailable {
                TempoCard {
                    Label("Apple Sağlık bu cihazda kullanılamıyor.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(TempoTheme.orange)
                }
            } else if !model.healthSyncEnabled {
                connectCard
            } else {
                healthOverview
                SectionHeading(title: "Bugünkü ölçüler", caption: "APPLE SAĞLIK", padding: false)
                LazyVGrid(columns: columns, spacing: 12) {
                    HealthMetricTile(title: "Adım", value: whole(model.todayHealth.steps), unit: "adım", icon: "figure.walk", color: TempoTheme.green)
                    HealthMetricTile(title: "Aktif enerji", value: whole(model.todayHealth.activeEnergyKcal), unit: "kcal", icon: "flame.fill", color: TempoTheme.orange)
                    HealthMetricTile(title: "Dinlenik nabız", value: decimal(model.todayHealth.restingHeartRateBpm), unit: "atım/dk", icon: "heart.fill", color: .pink)
                    HealthMetricTile(title: "HRV", value: decimal(model.todayHealth.hrvMs), unit: "ms", icon: "waveform.path.ecg", color: TempoTheme.purple)
                    HealthMetricTile(title: "Son uyku", value: sleepText, unit: model.latestSleep == nil ? "veri yok" : "", icon: "moon.zzz.fill", color: TempoTheme.blue)
                    HealthMetricTile(title: "Kilo", value: decimal(model.latestWeightKg), unit: "kg", icon: "scalemass.fill", color: TempoTheme.green)
                }
            }
            if let error = model.healthError {
                Text(error).font(.footnote).foregroundStyle(TempoTheme.orange).frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(model.status).font(.footnote).foregroundStyle(TempoTheme.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            if model.healthSyncEnabled {
                HStack(spacing: 10) {
                    Button { Task { await model.syncAppleHealth() } } label: {
                        Label(model.isHealthSyncing ? "Eşitleniyor…" : "Şimdi eşitle", systemImage: "arrow.triangle.2.circlepath").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TempoSecondaryButtonStyle())
                    .disabled(model.isHealthSyncing)
                    Button(role: .destructive, action: model.disconnectAppleHealth) {
                        Image(systemName: "link.badge.minus").frame(width: 26)
                    }
                    .buttonStyle(TempoSecondaryButtonStyle())
                }
                Text("Tempo yalnızca verdiğin Apple Sağlık izinlerindeki ölçüleri okur. Apple, reddedilen okuma izinlerini uygulamaya açıklamaz; eksik ölçüler boş görünür.")
                    .font(.caption).foregroundStyle(TempoTheme.secondary).lineSpacing(3)
            }
        }
        .navigationTitle("Sağlık")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var connectCard: some View {
        TempoCard {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "heart.text.square.fill").font(.system(size: 42)).foregroundStyle(.pink)
                Text("Sağlık verilerini Tempo’ya bağla").font(.title3.bold())
                Text("Son 90 gündeki su, uyku, adım, aktif kalori, dinlenik nabız, HRV ve kilo ölçülerini tek ekranda gör. Hızlı su ekleme de Apple Sağlık’a kaydedilir.")
                    .font(.subheadline).foregroundStyle(TempoTheme.secondary).lineSpacing(3)
                Button(action: model.connectAppleHealth) {
                    Label(model.isHealthSyncing ? "Bağlanıyor…" : "Apple Sağlık’a bağlan", systemImage: "heart.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(TempoPrimaryButtonStyle())
                .disabled(model.isHealthSyncing)
            }
        }
    }

    private var healthOverview: some View {
        TempoCard {
            VStack(spacing: 24) {
                HStack {
                    Label("Apple Sağlık bağlı", systemImage: "checkmark.circle.fill").font(.subheadline.bold()).foregroundStyle(TempoTheme.green)
                    Spacer()
                    if let date = model.healthLastSync {
                        Text(date.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(TempoTheme.secondary)
                    }
                }
                ZStack {
                    Circle().stroke(.white.opacity(0.08), lineWidth: 15)
                    Circle().trim(from: 0, to: CGFloat(progress)).stroke(TempoTheme.blue, style: StrokeStyle(lineWidth: 15, lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Image(systemName: "drop.fill").foregroundStyle(TempoTheme.blue)
                        Text("\(model.todayWaterMl)").font(.system(size: 38, weight: .bold, design: .rounded))
                        Text("/ \(model.dailyGoalMl) ml").font(.caption).foregroundStyle(TempoTheme.secondary)
                    }
                }.frame(width: 190, height: 190)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Hızlı su ekle").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 10) {
                        ForEach([200, 250, 500], id: \.self) { amount in
                            Button { model.addWater(amount) } label: {
                                VStack(spacing: 7) {
                                    Image(systemName: amount == 500 ? "waterbottle.fill" : "cup.and.saucer.fill").font(.title3)
                                    Text("+\(amount) ml").font(.subheadline.bold())
                                }.frame(maxWidth: .infinity).padding(.vertical, 14).background(TempoTheme.raised, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                            }.buttonStyle(.plain).foregroundStyle(TempoTheme.blue).disabled(model.isBusy)
                        }
                    }
                }
            }.frame(maxWidth: .infinity)
        }
    }

    private var sleepText: String {
        guard let minutes = model.latestSleep?.minutes else { return "—" }
        return TempoFormat.duration(minutes * 60)
    }

    private func whole(_ value: Double?) -> String {
        guard let value else { return "—" }
        return Int(value.rounded()).formatted(.number.locale(Locale(identifier: "tr_TR")))
    }

    private func decimal(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.locale(Locale(identifier: "tr_TR")).precision(.fractionLength(1)))
    }
}

private struct HealthMetricTile: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
                .frame(width: 38, height: 38).background(color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(TempoTheme.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value).font(.title3.bold())
                    if !unit.isEmpty { Text(unit).font(.caption2).foregroundStyle(TempoTheme.secondary) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct MonthlyStatsScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    var stats: [TempoMonthStat] { makeMonthStats(model.dashboard?.activities ?? []) }
    var body: some View {
        TempoPage {
            PageTitle(title: "Aylık İstatistikler", subtitle: "Son altı ay")
            TempoCard {
                Chart(stats) { item in
                    BarMark(x: .value("Ay", TempoFormat.month.string(from: item.date)), y: .value("Kilometre", item.distanceKm))
                        .foregroundStyle(TempoTheme.green.gradient).cornerRadius(5)
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 250)
            }
            ForEach(stats.reversed()) { item in
                TempoCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(TempoFormat.monthLong.string(from: item.date).capitalized).font(.headline)
                            Text("\(item.count) aktivite · \(TempoFormat.duration(item.seconds))").font(.caption).foregroundStyle(TempoTheme.secondary)
                        }
                        Spacer(); Text(TempoFormat.distance(item.distanceKm)).font(.headline).foregroundStyle(TempoTheme.green)
                    }
                }
            }
        }.navigationTitle("Aylık").navigationBarTitleDisplayMode(.inline)
    }
}

private struct GearScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    var gear: [TempoGear] { (model.dashboard?.athlete.bikes ?? []) + (model.dashboard?.athlete.shoes ?? []) }
    var body: some View {
        TempoPage {
            PageTitle(title: "Ekipman", subtitle: "Strava’daki kayıtların")
            ForEach(gear) { item in
                TempoCard {
                    HStack(spacing: 15) {
                        Image(systemName: item.type == "Bisiklet" ? "bicycle" : "shoe.2.fill").font(.title2).foregroundStyle(TempoTheme.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name ?? item.type ?? "Ekipman").font(.headline)
                            Text("\(item.type ?? "") · \(TempoFormat.distance((item.distance ?? 0) / 1000))").font(.caption).foregroundStyle(TempoTheme.secondary)
                        }
                        Spacer(); if item.primary == true { Image(systemName: "star.fill").foregroundStyle(TempoTheme.green) }
                    }
                }
            }
            if gear.isEmpty { EmptyCard(icon: "bicycle", text: "Strava profilinde ekipman bulunamadı.") }
        }.navigationTitle("Ekipman").navigationBarTitleDisplayMode(.inline)
    }
}

private struct SegmentsScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    var body: some View {
        TempoPage {
            PageTitle(title: "Segmentler", subtitle: "Favori Strava segmentlerin")
            ForEach(model.dashboard?.segments ?? []) { segment in
                Link(destination: URL(string: "https://www.strava.com/segments/\(segment.id)")!) {
                    TempoCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(segment.name ?? "İsimsiz segment").font(.headline).foregroundStyle(.white)
                                Text("\(TempoFormat.distance((segment.distance ?? 0) / 1000)) · %\(String(format: "%.1f", segment.averageGrade ?? 0)) eğim").font(.caption).foregroundStyle(TempoTheme.secondary)
                            }
                            Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(TempoTheme.green)
                        }
                    }
                }.buttonStyle(.plain)
            }
            if model.dashboard?.segments.isEmpty != false { EmptyCard(icon: "flag.checkered", text: "Favori segment bulunamadı.") }
        }.navigationTitle("Segmentler").navigationBarTitleDisplayMode(.inline)
    }
}

private struct EddingtonScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    private var number: Int { eddingtonNumber(model.dashboard?.activities ?? []) }
    var body: some View {
        TempoPage {
            PageTitle(title: "Eddington Sayısı", subtitle: "Koşu istikrarın")
            TempoCard {
                VStack(spacing: 16) {
                    Text("\(number)").font(.system(size: 92, weight: .bold, design: .rounded)).foregroundStyle(TempoTheme.green)
                    Text("\(number) farklı günde en az \(number) km koştun.").font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                    Text("Bu sayı düzenli ve uzun mesafeli koşular yaptıkça yükselir.").font(.subheadline).foregroundStyle(TempoTheme.secondary).multilineTextAlignment(.center)
                }.padding(.vertical, 28).frame(maxWidth: .infinity)
            }
        }.navigationTitle("Eddington").navigationBarTitleDisplayMode(.inline)
    }
}

private struct YearSummaryScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    private var activities: [TempoActivity] {
        (model.dashboard?.activities ?? []).filter { activity in
            guard let date = activity.date else { return false }
            return Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        }
    }
    var body: some View {
        TempoPage {
            PageTitle(title: "\(Calendar.current.component(.year, from: Date())) Özeti", subtitle: "Yıl içindeki hareketin")
            VStack(spacing: 10) {
                SummaryLine(icon: "figure.run", title: "Aktivite", value: "\(activities.count)", color: TempoTheme.orange)
                SummaryLine(icon: "arrow.left.and.right", title: "Toplam mesafe", value: TempoFormat.distance(activities.reduce(0) { $0 + $1.distanceKm }), color: TempoTheme.green)
                SummaryLine(icon: "clock.fill", title: "Hareket süresi", value: TempoFormat.duration(activities.reduce(0) { $0 + $1.movingSeconds }), color: TempoTheme.blue)
                SummaryLine(icon: "mountain.2.fill", title: "Yükseklik", value: "\(Int(activities.reduce(0) { $0 + $1.elevationMeters })) m", color: TempoTheme.purple)
                SummaryLine(icon: "trophy.fill", title: "En uzun", value: TempoFormat.distance(activities.map(\.distanceKm).max() ?? 0), color: TempoTheme.orange)
            }
        }.navigationTitle("Yıl Özeti").navigationBarTitleDisplayMode(.inline)
    }
}

private struct PhotosScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    var body: some View {
        TempoPage {
            PageTitle(title: "Fotoğraflar", subtitle: "Son aktivitelerinden")
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(model.dashboard?.photos ?? []) { photo in
                    Link(destination: URL(string: "https://www.strava.com/activities/\(photo.activityId)")!) {
                        VStack(alignment: .leading, spacing: 8) {
                            AsyncImage(url: URL(string: photo.image)) { phase in
                                if let image = phase.image { image.resizable().scaledToFill() }
                                else { ZStack { TempoTheme.raised; ProgressView() } }
                            }
                            .frame(height: 160).clipped().clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                            Text(photo.activityName ?? "Aktivite").font(.caption.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                        }
                    }.buttonStyle(.plain)
                }
            }
            if model.dashboard?.photos.isEmpty != false { EmptyCard(icon: "photo", text: "Gösterilecek aktivite fotoğrafı bulunamadı.") }
        }.navigationTitle("Fotoğraflar").navigationBarTitleDisplayMode(.inline)
    }
}

private struct TempoPage<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ZStack {
            TempoTheme.background.ignoresSafeArea()
            ScrollView { VStack(spacing: 16) { content }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 34) }
        }
    }
}

private struct HomeHeader: View {
    @EnvironmentObject private var model: TempoAppModel
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("TEMPO").font(.caption.bold()).tracking(3).foregroundStyle(TempoTheme.green)
                Text("Kontrol Paneli").font(.title2.bold())
            }
            Spacer()
            Button { Task { await model.reloadAll() } } label: {
                Group { if model.isLoadingDashboard { ProgressView() } else { Image(systemName: "arrow.clockwise") } }
                    .foregroundStyle(TempoTheme.green).frame(width: 44, height: 44).background(TempoTheme.card, in: Circle())
            }.disabled(model.isLoadingDashboard)
        }
    }
}

private struct PageTitle: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(subtitle.uppercased()).font(.caption.bold()).tracking(1.5).foregroundStyle(TempoTheme.green)
            Text(title).font(.system(size: 31, weight: .bold, design: .rounded))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
    }
}

private struct ProfileHeader: View {
    let athlete: TempoAthlete
    var body: some View {
        TempoCard {
            HStack(spacing: 16) {
                AsyncImage(url: athlete.profile.flatMap(URL.init(string:))) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { Image(systemName: "person.fill").font(.title).foregroundStyle(TempoTheme.green) }
                }
                .frame(width: 72, height: 72).background(TempoTheme.raised).clipShape(Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text(athlete.fullName.isEmpty ? "Tempo Sporcusu" : athlete.fullName).font(.title2.bold())
                    if !athlete.location.isEmpty { Label(athlete.location, systemImage: "location.fill").font(.caption).foregroundStyle(TempoTheme.secondary) }
                    HStack(spacing: 12) {
                        if let followers = athlete.followerCount { Text("\(followers) takipçi") }
                        if let weight = athlete.weight, weight > 0 { Text("\(weight, specifier: "%.1f") kg") }
                    }.font(.caption).foregroundStyle(TempoTheme.green)
                }
            }
        }
    }
}

private struct TempoCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.055)))
    }
}

private struct MetricCard: View {
    let value: String; let label: String; let icon: String; let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(color)
            Text(value).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(TempoTheme.secondary)
        }.padding(13).frame(maxWidth: .infinity, alignment: .leading).background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
    }
}

private struct SectionHeading: View {
    let title: String; let caption: String; var padding = true
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(caption).font(.caption2.bold()).tracking(1.5).foregroundStyle(TempoTheme.green)
            Text(title).font(.title3.bold())
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, padding ? 7 : 0)
    }
}

private struct ActivityRow: View {
    let activity: TempoActivity
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: activity.sport.symbol).font(.title3).foregroundStyle(TempoTheme.orange)
                .frame(width: 48, height: 48).background(TempoTheme.orange.opacity(0.11), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.name ?? activity.sport.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                Text("\(activity.sport.title) · \(activity.date.map { TempoFormat.shortDate.string(from: $0) } ?? "")").font(.caption).foregroundStyle(TempoTheme.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(TempoFormat.distance(activity.distanceKm)).font(.subheadline.bold()).foregroundStyle(.white)
                Text(TempoFormat.duration(activity.movingSeconds)).font(.caption).foregroundStyle(TempoTheme.secondary)
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.white.opacity(0.25))
        }
        .padding(14).background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
    }
}

private struct MoreLink: View {
    let title: String; let subtitle: String; let icon: String; let color: Color; let destination: AnyView
    var body: some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Image(systemName: icon).font(.title3).foregroundStyle(color); Spacer(); Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(TempoTheme.secondary) }
                Text(title).font(.headline).foregroundStyle(.white)
                Text(subtitle).font(.caption).foregroundStyle(TempoTheme.secondary)
            }.padding(17).frame(maxWidth: .infinity, minHeight: 135, alignment: .leading).background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }.buttonStyle(.plain)
    }
}

private struct EmptyCard: View {
    let icon: String; let text: String
    var body: some View {
        VStack(spacing: 11) { Image(systemName: icon).font(.title).foregroundStyle(TempoTheme.secondary); Text(text).font(.subheadline).foregroundStyle(TempoTheme.secondary).multilineTextAlignment(.center) }
            .padding(28).frame(maxWidth: .infinity).background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct LoadingDashboardCard: View {
    @EnvironmentObject private var model: TempoAppModel
    var body: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large).tint(TempoTheme.green)
            Text(model.dashboardError ?? "Strava verilerin hazırlanıyor…").foregroundStyle(TempoTheme.secondary).multilineTextAlignment(.center)
            if model.dashboardError != nil { Button("Yeniden dene") { Task { await model.refreshDashboard() } }.buttonStyle(TempoPrimaryButtonStyle()) }
        }.padding(35).frame(maxWidth: .infinity).background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

private struct SearchField: View {
    @Binding var text: String; let placeholder: String
    var body: some View {
        HStack { Image(systemName: "magnifyingglass").foregroundStyle(TempoTheme.secondary); TextField(placeholder, text: $text); if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }.foregroundStyle(TempoTheme.secondary) } }
            .padding(.horizontal, 16).frame(height: 48).background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}

private struct DetailLine: View {
    let label: String; let value: String
    var body: some View { HStack { Text(label).foregroundStyle(TempoTheme.secondary); Spacer(); Text(value).fontWeight(.semibold) }.font(.subheadline).padding(.vertical, 3) }
}

private struct SummaryLine: View {
    let icon: String; let title: String; let value: String; let color: Color
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 44, height: 44).background(color.opacity(0.12), in: Circle())
            Text(title).font(.headline); Spacer(); Text(value).font(.headline).foregroundStyle(color)
        }.padding(17).background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
    }
}

private struct TempoPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(.black).padding(.vertical, 15)
            .background(TempoTheme.green.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}

private struct TempoSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(.red).padding(.vertical, 15)
            .background(TempoTheme.card.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}

private func makeMonthStats(_ activities: [TempoActivity]) -> [TempoMonthStat] {
    let calendar = Calendar.current
    let current = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
    var result: [TempoMonthStat] = (0..<6).reversed().compactMap { offset in
        calendar.date(byAdding: .month, value: -offset, to: current).map { TempoMonthStat(date: $0, distanceKm: 0, count: 0, seconds: 0) }
    }
    for activity in activities {
        guard let date = activity.date, let index = result.firstIndex(where: { calendar.isDate($0.date, equalTo: date, toGranularity: .month) }) else { continue }
        result[index].distanceKm += activity.distanceKm
        result[index].count += 1
        result[index].seconds += activity.movingSeconds
    }
    return result
}

private func eddingtonNumber(_ activities: [TempoActivity]) -> Int {
    let calendar = Calendar.current
    var days: [Date: Double] = [:]
    for activity in activities where activity.sport == .run {
        guard let date = activity.date else { continue }
        days[calendar.startOfDay(for: date), default: 0] += activity.distanceKm
    }
    let distances = days.values.sorted(by: >)
    var result = 0
    for (index, distance) in distances.enumerated() where distance >= Double(index + 1) { result = index + 1 }
    return result
}

private extension Calendar {
    func isDateInCurrentWeek(_ date: Date) -> Bool { isDate(date, equalTo: Date(), toGranularity: .weekOfYear) }
}
