import Charts
import MapKit
import SwiftUI

enum TempoTheme {
    static let background = Color(red: 0.025, green: 0.035, blue: 0.052)
    static let card = Color(red: 0.055, green: 0.073, blue: 0.095)
    static let raised = Color(red: 0.082, green: 0.105, blue: 0.132)
    static let green = Color(red: 0.37, green: 0.94, blue: 0.56)
    static let orange = Color(red: 1.0, green: 0.39, blue: 0.20)
    static let blue = Color(red: 0.32, green: 0.65, blue: 1.0)
    static let purple = Color(red: 0.71, green: 0.52, blue: 1.0)
    static let secondary = Color.white.opacity(0.55)
    static let scrollBottomClearance: CGFloat = 132
}

struct ContentView: View {
    @EnvironmentObject private var model: TempoAppModel
    @EnvironmentObject private var account: TempoAccountStore
    @State private var selectedTab = 0

    var body: some View {
        Group {
            if account.isRestoring {
                TempoLaunchView()
            } else if !account.isAuthenticated {
                AccountWelcomeView()
            } else if account.profile?.onboardingComplete != true {
                AccountOnboardingView()
            } else if model.isRestoringConnection {
                TempoLaunchView()
            } else if model.isConnected {
                TempoMainShell(selectedTab: $selectedTab)
            } else {
                WelcomeScreen()
            }
        }
        .preferredColorScheme(.dark)
        .task(id: account.isAuthenticated) {
            guard account.isAuthenticated else { return }
            await model.restoreConnectionIfNeeded(accountToken: account.authorizationToken)
        }
    }
}

private struct TempoMainTab: Identifiable {
    let id: Int
    let title: String
    let icon: String
    let selectedIcon: String

    static let all: [TempoMainTab] = [
        TempoMainTab(id: 0, title: "Özet", icon: "square.grid.2x2", selectedIcon: "square.grid.2x2.fill"),
        TempoMainTab(id: 1, title: "Aktivite", icon: "figure.run", selectedIcon: "figure.run"),
        TempoMainTab(id: 2, title: "Sporlar", icon: "trophy", selectedIcon: "trophy.fill"),
        TempoMainTab(id: 3, title: "Sağlık", icon: "heart.text.square", selectedIcon: "heart.text.square.fill"),
        TempoMainTab(id: 4, title: "Daha Fazla", icon: "ellipsis.circle", selectedIcon: "ellipsis.circle.fill")
    ]
}

private struct TempoMainShell: View {
    @Binding var selectedTab: Int

    @ViewBuilder
    private var selectedScreen: some View {
        switch selectedTab {
        case 0:
            HomeScreen()
        case 1:
            ActivitiesScreen()
        case 2:
            SportsHubScreen()
        case 3:
            HealthScreen()
        default:
            MoreScreen()
        }
    }

    var body: some View {
        selectedScreen
            .safeAreaInset(edge: .bottom, spacing: 0) {
                TempoGlassTabBar(selectedTab: $selectedTab)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
            }
    }
}

private struct TempoGlassTabBar: View {
    @Binding var selectedTab: Int
    @Namespace private var liquidGlassNamespace

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer {
                    tabItems(usesNativeGlass: true)
                        .padding(6)
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
            } else {
                tabItems(usesNativeGlass: false)
                    .padding(6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .background(
                        LinearGradient(
                            colors: [.white.opacity(0.12), TempoTheme.green.opacity(0.045), .black.opacity(0.11)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.38), .white.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            }
        }
        .shadow(color: .black.opacity(0.34), radius: 22, y: 12)
    }

    private func tabItems(usesNativeGlass: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(TempoMainTab.all) { tab in
                let isSelected = selectedTab == tab.id
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.80)) {
                        selectedTab = tab.id
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                            .font(.system(size: 18, weight: isSelected ? .semibold : .medium))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(isSelected ? TempoTheme.green : .white.opacity(0.76))
                            .frame(height: 22)

                        Text(tab.title.tempoLocalized)
                            .font(.system(size: 9.5, weight: isSelected ? .bold : .medium, design: .rounded))
                            .foregroundStyle(isSelected ? .white : .white.opacity(0.64))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(Capsule())
                    .background {
                        if isSelected {
                            if #available(iOS 26.0, *), usesNativeGlass {
                                Capsule()
                                    .fill(.clear)
                                    .glassEffect(
                                        .regular
                                            .tint(TempoTheme.green.opacity(0.18))
                                            .interactive(),
                                        in: .capsule
                                    )
                                    .glassEffectID("selected-tab", in: liquidGlassNamespace)
                            } else {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [.white.opacity(0.14), TempoTheme.green.opacity(0.18), .white.opacity(0.045)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(.white.opacity(0.22), lineWidth: 0.8)
                                    )
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title.tempoLocalized)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

private struct WelcomeScreen: View {
    @EnvironmentObject private var model: TempoAppModel

    var body: some View {
        ZStack {
            TempoAmbientBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    HStack(spacing: 8) {
                        Circle().fill(TempoTheme.orange).frame(width: 7, height: 7)
                        Text("STRAVA BAĞLANTISI")
                            .font(.caption2.bold()).tracking(1.5).foregroundStyle(TempoTheme.secondary)
                        Spacer()
                    }
                    .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("HAREKETİNİ KEŞFET").font(.caption.bold()).tracking(1.7).foregroundStyle(TempoTheme.orange)
                        Text("Strava’yı bağla,\nritmini yakala.")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .tracking(-1.1)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Aktivitelerin, rotaların ve kişisel gelişimin Tempo’da bir araya gelsin.")
                            .font(.subheadline)
                            .foregroundStyle(TempoTheme.secondary)
                            .lineSpacing(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 14)

                    ConnectedAppsCard()

                    Button(action: model.connectStrava) {
                        HStack(spacing: 12) {
                            if model.isBusy {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "figure.run")
                                    .font(.title3)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.isBusy ? "Strava açılıyor…" : "Strava ile devam et")
                                    .font(.headline)
                                if !model.isBusy {
                                    Text("Aktivitelerin Tempo ile eşitlensin")
                                        .font(.caption2)
                                        .opacity(0.78)
                                }
                            }
                            Spacer()
                            if !model.isBusy {
                                Image(systemName: "arrow.right")
                                    .font(.subheadline.bold())
                                    .frame(width: 34, height: 34)
                                    .background(.white.opacity(0.14), in: Circle())
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 64)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 1, green: 0.36, blue: 0.18), TempoTheme.orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 21, style: .continuous)
                        )
                        .shadow(color: TempoTheme.orange.opacity(0.24), radius: 18, y: 9)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isBusy)
                    .opacity(model.isBusy ? 0.76 : 1)

                    if !model.status.isEmpty {
                        HStack(spacing: 10) {
                            if model.isBusy {
                                ProgressView().tint(TempoTheme.green)
                            } else {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(TempoTheme.green)
                            }
                            Text(model.status.tempoLocalized)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    }
                }
                .padding(.horizontal, 21)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
        }
    }
}

private struct StravaTrustRow: View {
    var body: some View {
        HStack(spacing: 0) {
            trustItem(icon: "lock.shield.fill", title: "Güvenli")
            trustItem(icon: "arrow.triangle.2.circlepath", title: "Otomatik")
            trustItem(icon: "person.crop.circle.badge.checkmark", title: "Kontrol sende")
        }
        .padding(.vertical, 13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(.white.opacity(0.07)))
    }

    private func trustItem(icon: String, title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(TempoTheme.green)
            Text(title.tempoLocalized)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ConnectedAppsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Label("Aktivitelerin hazır olsun", systemImage: "figure.run.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("STRAVA")
                    .font(.caption2.bold()).tracking(1.3).foregroundStyle(TempoTheme.orange)
            }

            HStack(spacing: 13) {
                Image(systemName: "figure.run")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(TempoTheme.orange, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("Son aktiviten").font(.caption).foregroundStyle(TempoTheme.secondary)
                    Text("Mesafe, süre ve rota").font(.title3.bold())
                    Text("Yeni antrenmanların Tempo’da görünür.").font(.caption).foregroundStyle(TempoTheme.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                ImportPill(icon: "chart.line.uptrend.xyaxis", title: "İstatistik")
                ImportPill(icon: "map", title: "Rotalar")
                ImportPill(icon: "sparkles", title: "Koç")
            }
        }
        .padding(19)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .background(
            LinearGradient(
                colors: [TempoTheme.orange.opacity(0.08), TempoTheme.blue.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }
}

private struct ImportPill: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(TempoTheme.green)
            Text(title.tempoLocalized)
                .foregroundStyle(.white.opacity(0.82))
        }
        .font(.caption.weight(.semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.white.opacity(0.045), in: Capsule())
    }
}

private struct HomeScreen: View {
    @EnvironmentObject private var model: TempoAppModel

    private var activities: [TempoActivity] { model.dashboard?.activities ?? [] }
    private var weekActivities: [TempoActivity] { activities.filter { $0.date.map(Calendar.current.isDateInCurrentWeek) ?? false } }
    private var weekDistance: Double { weekActivities.reduce(0) { $0 + $1.distanceKm } }
    private var weekSeconds: Double { weekActivities.reduce(0) { $0 + $1.movingSeconds } }

    var body: some View {
        NavigationStack {
            TempoPage {
                HomeHeader()
                if let dashboard = model.dashboard {
                    hero(dashboard.athlete)
                    if let balance = model.tempoBalance {
                        NavigationLink(destination: HealthScreen()) {
                            TempoBalanceHomeCard(balance: balance)
                        }
                        .buttonStyle(.plain)
                    }
                    SectionHeading(title: "Bu hafta", caption: "HAFTALIK ÖZET", padding: false)
                    weeklyMetrics
                    quickActions
                    RecentActivitiesPanel(activities: dashboard.activities)
                    dailyMotivation
                } else {
                    LoadingDashboardCard()
                }
            }
            .refreshable { await model.reloadAll() }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func hero(_ athlete: TempoAthlete) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("MERHABA, \((athlete.firstname ?? "SPORCU").uppercased())")
                .font(.caption.bold())
                .tracking(1.7)
                .foregroundStyle(TempoTheme.green)
            Text("Bugünkü durumun ve hareket özetin".tempoLocalized)
                .font(.subheadline)
                .foregroundStyle(TempoTheme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }

    private var weeklyMetrics: some View {
        HStack(spacing: 10) {
            MetricCard(value: "\(weekActivities.count)", label: "Antrenman", icon: "figure.run", color: TempoTheme.green)
            MetricCard(value: TempoFormat.duration(weekSeconds), label: "Süre", icon: "clock.fill", color: TempoTheme.blue)
            MetricCard(value: TempoFormat.distance(weekDistance), label: "Mesafe", icon: "point.topleft.down.to.point.bottomright.curvepath", color: TempoTheme.purple)
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: "Hızlı erişim", caption: "KEŞFET", padding: false)
            HStack(spacing: 10) {
                HomeQuickAction(title: "Rotalar", icon: "map.fill", color: TempoTheme.green, destination: AnyView(RoutesScreen()))
                HomeQuickAction(title: "Spor alanları", icon: "mappin.and.ellipse", color: TempoTheme.blue, destination: AnyView(NearbyFacilitiesScreen()))
                HomeQuickAction(title: "Tempo Koç", icon: "sparkles", color: TempoTheme.purple, destination: AnyView(CoachScreen()))
            }
        }
    }

    private var dailyMotivation: some View {
        DailyMotivationCard()
    }
}

private struct HomeQuickAction: View {
    let title: String
    let icon: String
    let color: Color
    let destination: AnyView

    var body: some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 34, height: 34)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(title.tempoLocalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .padding(12)
            .background(TempoTheme.card.opacity(0.82), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(.white.opacity(0.065)))
            .contentShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct DailyMotivationCard: View {
    private let messages = [
        "Bugünün küçük adımı, yarının gücü.",
        "Ritmini koru; sonuçlar peşinden gelir.",
        "İstikrar, en güçlü antrenmandır.",
        "Kendinle yarış, dünden ileri git.",
        "Güç, devam etmeyi seçtiğin anda başlar.",
        "Her hareket gelişimin bir parçası.",
        "Mükemmel olma; bugün hareket et.",
        "Tempo sende. Bir adım daha.",
        "Dinlen, toparlan, yeniden güçlen.",
        "Bugünkü emeğin yarına birikir.",
        "Yavaş ilerlemek de ilerlemektir.",
        "Bedenini dinle, ritmini kaybetme."
    ]

    private var message: String {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return messages[day % messages.count]
    }

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "quote.opening")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(TempoTheme.green)
                .frame(width: 30, height: 30)
                .background(TempoTheme.green.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("GÜNÜN RİTMİ")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.25)
                    .foregroundStyle(TempoTheme.green)
                Text(message)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [.white.opacity(0.035), TempoTheme.green.opacity(0.035)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(.white.opacity(0.055))
        )
    }
}

private struct ActivitiesScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    @State private var search = ""
    @State private var selectedSport = "Tümü"
    private let filters = ["Tümü", "Koşu", "Bisiklet", "Yürüyüş", "Tenis", "Basketbol", "Futbol", "Yüzme", "Diğer"]

    private var filtered: [TempoActivity] {
        (model.dashboard?.activities ?? []).filter { activity in
            let matchesSearch = search.isEmpty || (activity.name ?? "").localizedCaseInsensitiveContains(search)
            let sport = activity.sport.title
            let matchesSport = selectedSport == "Tümü" || sport == selectedSport || (selectedSport == "Diğer" && !["Koşu", "Bisiklet", "Yürüyüş"].contains(sport))
            return matchesSearch && matchesSport
        }
    }

    private var allActivities: [TempoActivity] { model.dashboard?.activities ?? [] }
    private var totalDistance: Double { allActivities.reduce(0) { $0 + $1.distanceKm } }
    private var totalTime: Double { allActivities.reduce(0) { $0 + $1.movingSeconds } }

    var body: some View {
        NavigationStack {
            TempoPage {
                PageTitle(title: "Aktiviteler", subtitle: "Tüm antrenman geçmişin")
                activitySnapshot
                SearchField(text: $search, placeholder: "Aktivite ara")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filters, id: \.self) { filter in
                            Button {
                                withAnimation(.snappy(duration: 0.2)) { selectedSport = filter }
                            } label: {
                                Text(filter.tempoLocalized)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(selectedSport == filter ? .black : .white.opacity(0.78))
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(selectedSport == filter ? TempoTheme.green : .white.opacity(0.045), in: Capsule())
                                    .overlay(Capsule().stroke(selectedSport == filter ? .clear : .white.opacity(0.08), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack {
                    Text("SON HAREKETLER").font(.caption2.bold()).tracking(1.4).foregroundStyle(TempoTheme.green)
                    Spacer()
                    Text("%d aktivite".tempoFormatted(filtered.count)).font(.caption.weight(.medium)).foregroundStyle(TempoTheme.secondary)
                }
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

    private var activitySnapshot: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("HAREKET ÖZETİ").font(.caption2.bold()).tracking(1.3).foregroundStyle(TempoTheme.green)
                Text("%d antrenman".tempoFormatted(allActivities.count))
                    .font(.title3.bold())
                Text("Strava geçmişinden derlendi")
                    .font(.caption).foregroundStyle(TempoTheme.secondary)
            }
            Spacer(minLength: 10)
            VStack(alignment: .trailing, spacing: 6) {
                Text(TempoFormat.distance(totalDistance)).font(.title3.bold().monospacedDigit()).foregroundStyle(.white)
                Text(TempoFormat.duration(totalTime)).font(.caption.weight(.medium).monospacedDigit()).foregroundStyle(TempoTheme.blue)
            }
        }
        .padding(17)
        .background(
            LinearGradient(colors: [TempoTheme.green.opacity(0.12), TempoTheme.card, TempoTheme.blue.opacity(0.07)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 23, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1))
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
        .navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
    }
}

private struct RecentActivitiesPanel: View {
    let activities: [TempoActivity]

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .bottom) {
                SectionHeading(title: "Son aktiviteler", caption: "STRAVA", padding: false)
                Spacer()
                if !activities.isEmpty {
                    NavigationLink(destination: ActivityTimelineScreen()) {
                        Text("Tümünü gör")
                            .font(.caption.bold())
                            .foregroundStyle(TempoTheme.green)
                    }
                }
            }

            if let latest = activities.first {
                NavigationLink(destination: ActivityDetailScreen(activity: latest)) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Image(systemName: latest.sport.symbol)
                                .font(.title2)
                                .foregroundStyle(TempoTheme.green)
                                .frame(width: 48, height: 48)
                                .background(.white.opacity(0.10), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text("SON AKTİVİTE")
                                    .font(.caption2.bold())
                                    .tracking(1.4)
                                    .foregroundStyle(TempoTheme.green)
                                Text(latest.date.map { TempoFormat.shortDate.string(from: $0) } ?? latest.sport.title)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.62))
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption.bold())
                                .foregroundStyle(.white.opacity(0.82))
                                .frame(width: 34, height: 34)
                                .background(.white.opacity(0.09), in: Circle())
                        }

                        Text(latest.name ?? latest.sport.title)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        HStack(spacing: 18) {
                            Label(TempoFormat.distance(latest.distanceKm), systemImage: "arrow.left.and.right")
                            Label(TempoFormat.duration(latest.movingSeconds), systemImage: "clock.fill")
                            if latest.elevationMeters > 0 {
                                Label("\(Int(latest.elevationMeters)) m", systemImage: "mountain.2.fill")
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.74))
                    }
                    .padding(19)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.10, green: 0.20, blue: 0.15), Color(red: 0.075, green: 0.12, blue: 0.16)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 25, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 25, style: .continuous)
                            .stroke(LinearGradient(colors: [TempoTheme.green.opacity(0.24), .white.opacity(0.045)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                }
                .buttonStyle(.plain)

                let secondary = Array(activities.dropFirst().prefix(2))
                if !secondary.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(secondary) { activity in
                            NavigationLink(destination: ActivityDetailScreen(activity: activity)) {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Image(systemName: activity.sport.symbol)
                                            .foregroundStyle(TempoTheme.orange)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption2.bold())
                                            .foregroundStyle(TempoTheme.secondary)
                                    }
                                    Text(activity.name ?? activity.sport.title)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
                                    Text(TempoFormat.distance(activity.distanceKm))
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                    Text(activity.date.map { TempoFormat.shortDate.string(from: $0) } ?? activity.sport.title)
                                        .font(.caption2)
                                        .foregroundStyle(TempoTheme.secondary)
                                }
                                .padding(15)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(.white.opacity(0.05)))
                            }
                            .buttonStyle(.plain)
                        }
                        if secondary.count == 1 { Color.clear.frame(maxWidth: .infinity) }
                    }
                }

                NavigationLink(destination: ActivityTimelineScreen()) {
                    HStack(spacing: 13) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title3)
                            .foregroundStyle(TempoTheme.green)
                            .frame(width: 44, height: 44)
                            .background(TempoTheme.green.opacity(0.11), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Aktivite geçmişi")
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                            Text("Dönemlere göre gruplanmış \(activities.count) aktivite")
                                .font(.caption)
                                .foregroundStyle(TempoTheme.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.white.opacity(0.32))
                    }
                    .padding(14)
                    .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                EmptyCard(icon: "figure.run", text: "Henüz aktivite bulunamadı.")
            }
        }
    }
}

private struct ActivityTimelineFilter: Identifiable {
    let id: String
    let title: String

    static let all = ActivityTimelineFilter(id: "all", title: "Tümü")
    static let other = ActivityTimelineFilter(id: "other", title: "Diğer")

    static func sport(_ title: String) -> ActivityTimelineFilter {
        ActivityTimelineFilter(id: "sport:\(title)", title: title)
    }

    func matches(_ activity: TempoActivity) -> Bool {
        switch id {
        case Self.all.id:
            return true
        case Self.other.id:
            return activity.sport != .run && activity.sport != .ride && activity.sport != .walk
        default:
            return activity.sport.title == title
        }
    }
}

private struct ActivityTimelineGroup: Identifiable {
    let id: String
    let title: String
    var activities: [TempoActivity]

    var distanceKm: Double { activities.reduce(0) { $0 + $1.distanceKm } }
}

private struct ActivityTimelineScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    @State private var filter = ActivityTimelineFilter.all

    private var filterOptions: [ActivityTimelineFilter] {
        let activities = model.dashboard?.activities ?? []
        let coreTitles = Set(["Koşu".tempoLocalized, "Bisiklet".tempoLocalized, "Yürüyüş".tempoLocalized])
        let otherSports = Set(activities.map { $0.sport.title })
            .subtracting(coreTitles)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map(ActivityTimelineFilter.sport)
        return [.all]
            + ["Koşu".tempoLocalized, "Bisiklet".tempoLocalized, "Yürüyüş".tempoLocalized].map(ActivityTimelineFilter.sport)
            + otherSports
            + [.other]
    }

    private var filteredActivities: [TempoActivity] {
        (model.dashboard?.activities ?? [])
            .filter(filter.matches)
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private var groups: [ActivityTimelineGroup] {
        let calendar = Calendar.current
        let now = Date()
        let previousWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
        let locale = Locale.autoupdatingCurrent
        let monthFormatter = DateFormatter()
        monthFormatter.locale = locale
        monthFormatter.dateFormat = "LLLL yyyy"

        var result: [ActivityTimelineGroup] = []
        for activity in filteredActivities {
            let date = activity.date ?? .distantPast
            let identity: String
            let title: String

            if calendar.isDateInToday(date) {
                identity = "today"
                title = "Bugün"
            } else if calendar.isDateInYesterday(date) {
                identity = "yesterday"
                title = "Dün"
            } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
                identity = "this-week"
                title = "Bu hafta"
            } else if calendar.isDate(date, equalTo: previousWeek, toGranularity: .weekOfYear) {
                identity = "last-week"
                title = "Geçen hafta"
            } else {
                identity = monthFormatter.string(from: date)
                title = identity.capitalized(with: locale)
            }

            if let index = result.firstIndex(where: { $0.id == identity }) {
                result[index].activities.append(activity)
            } else {
                result.append(ActivityTimelineGroup(id: identity, title: title, activities: [activity]))
            }
        }
        return result
    }

    private var totalDistance: Double { filteredActivities.reduce(0) { $0 + $1.distanceKm } }
    private var totalSeconds: Double { filteredActivities.reduce(0) { $0 + $1.movingSeconds } }
    private var totalElevation: Double { filteredActivities.reduce(0) { $0 + $1.elevationMeters } }

    var body: some View {
        ZStack {
            TempoTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("AKTİVİTE ARŞİVİ")
                            .font(.caption.bold())
                            .tracking(1.5)
                            .foregroundStyle(TempoTheme.green)
                        Text("Ritmini dönemlere göre incele.")
                            .font(.system(size: 28, weight: .bold, design: .rounded))

                        HStack(spacing: 9) {
                            MetricCard(value: "\(filteredActivities.count)", label: "Aktivite", icon: "figure.run", color: TempoTheme.green)
                            MetricCard(value: TempoFormat.distance(totalDistance), label: "Mesafe", icon: "arrow.left.and.right", color: TempoTheme.orange)
                            MetricCard(value: TempoFormat.duration(totalSeconds), label: "Süre", icon: "clock.fill", color: TempoTheme.blue)
                        }
                        if totalElevation > 0 {
                            Label("Toplam \(Int(totalElevation).formatted()) m tırmanış", systemImage: "mountain.2.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(TempoTheme.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(filterOptions) { option in
                                Button {
                                    withAnimation(.easeOut(duration: 0.18)) { filter = option }
                                } label: {
                                    Text(option.title.tempoLocalized)
                                        .font(.caption.bold())
                                        .foregroundStyle(filter.id == option.id ? .black : .white)
                                        .padding(.horizontal, 15)
                                        .padding(.vertical, 10)
                                        .background(filter.id == option.id ? TempoTheme.green : TempoTheme.card, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if groups.isEmpty {
                        EmptyCard(icon: "calendar.badge.exclamationmark", text: "Bu filtrede gösterilecek aktivite yok.")
                    } else {
                        ForEach(groups) { group in
                            VStack(spacing: 9) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(group.title.tempoLocalized).font(.headline)
                                        Text("%d aktivite".tempoFormatted(group.activities.count))
                                            .font(.caption)
                                            .foregroundStyle(TempoTheme.secondary)
                                    }
                                    Spacer()
                                    Text(TempoFormat.distance(group.distanceKm))
                                        .font(.subheadline.bold())
                                        .foregroundStyle(TempoTheme.green)
                                }
                                .padding(.top, 5)

                                ForEach(group.activities) { activity in
                                    NavigationLink(destination: ActivityDetailScreen(activity: activity)) {
                                        ActivityRow(activity: activity)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, TempoTheme.scrollBottomClearance)
            }
        }
        .navigationTitle("Aktivite Geçmişi")
        .navigationBarTitleDisplayMode(.inline)
        .tempoGlassBackButton()
    }
}

struct RoutesScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    @State private var selectedId: Int64?

    private var routes: [TempoActivity] { (model.dashboard?.activities ?? []).filter { $0.route.count > 1 }.prefix(300).map { $0 } }
    private var selected: TempoActivity? { selectedId.flatMap { id in routes.first { $0.id == id } } }

    var body: some View {
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
        .navigationTitle("Rotalar")
        .navigationBarTitleDisplayMode(.inline)
        .tempoGlassBackButton()
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
                MapPolyline(coordinates: optimizedRoute(activity.route))
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
        let points = visible.flatMap { optimizedRoute($0.route) }
        guard let first = points.first else { return }
        var rect = MKMapRect(origin: MKMapPoint(first), size: MKMapSize(width: 1, height: 1))
        for point in points.dropFirst() { rect = rect.union(MKMapRect(origin: MKMapPoint(point), size: MKMapSize(width: 1, height: 1))) }
        camera = .rect(rect.insetBy(dx: -max(rect.width * 0.12, 1_500), dy: -max(rect.height * 0.12, 1_500)))
    }

    private func optimizedRoute(_ points: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        let limit = selectedActivity == nil ? 220 : 900
        guard points.count > limit else { return points }
        let step = max(1, Int(ceil(Double(points.count) / Double(limit))))
        var sampled = stride(from: 0, to: points.count, by: step).map { points[$0] }
        if let last = points.last,
           sampled.last?.latitude != last.latitude || sampled.last?.longitude != last.longitude {
            sampled.append(last)
        }
        return sampled
    }
}

struct CoachScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    @State private var period = "90"
    @State private var question = ""
    private let periods = [("30", "30 gün"), ("90", "90 gün"), ("180", "6 ay"), ("365", "1 yıl"), ("all", "Tümü")]
    private let suggestions = ["Gelişimimi değerlendir", "Koşu tempomu yorumla", "Antrenman düzenim nasıl?", "Bir sonraki hedefim ne olmalı?"]

    var body: some View {
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
        .navigationTitle("Tempo Koç")
        .navigationBarTitleDisplayMode(.inline)
        .tempoGlassBackButton()
    }
}

private struct MoreScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    @EnvironmentObject private var account: TempoAccountStore
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            TempoPage {
                PageTitle(title: "Profil ve araçlar", subtitle: "TEMPO ALANIN")
                AccountProfileCard()
                if let dashboard = model.dashboard { StravaConnectionCard(dashboard: dashboard) }
                else { PageTitle(title: "Profil", subtitle: "Tempo hesabın") }
                LazyVGrid(columns: columns, spacing: 12) {
                    MoreLink(title: "Tempo Hesabı", subtitle: "Profil ve sporların", icon: "person.crop.circle.badge.checkmark", color: TempoTheme.green, destination: AnyView(AccountSettingsScreen()))
                    MoreLink(title: "Başarılar", subtitle: "Seviye ve rozetlerin", icon: "medal.fill", color: TempoTheme.orange, destination: AnyView(AchievementsScreen()))
                    MoreLink(title: "Tempo Koç", subtitle: "Kişisel değerlendirme", icon: "sparkles", color: TempoTheme.blue, destination: AnyView(CoachScreen()))
                    MoreLink(title: "Rotalar", subtitle: "GPS ısı haritan", icon: "map.fill", color: TempoTheme.orange, destination: AnyView(RoutesScreen()))
                    MoreLink(title: "Spor Alanları", subtitle: "Yakınındaki tesisler", icon: "mappin.and.ellipse", color: TempoTheme.blue, destination: AnyView(NearbyFacilitiesScreen()))
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
                        Text(model.status.tempoLocalized).font(.subheadline).foregroundStyle(TempoTheme.secondary)
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
    @State private var selectedHealthDay: Date?
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    private var progress: Double { min(Double(model.todayWaterMl) / Double(model.dailyGoalMl), 1) }

    var body: some View {
        TempoPage {
            PageTitle(title: "Apple Sağlık", subtitle: "Günlük sağlık ve toparlanma görünümün")
            healthIntro
            if !model.healthAvailable {
                TempoCard {
                    Label("Apple Sağlık bu cihazda kullanılamıyor.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(TempoTheme.orange)
                }
            } else if !model.healthSyncEnabled {
                connectCard
            } else {
                if let balance = model.tempoBalance {
                    TempoBalanceDetailCard(balance: balance)
                } else {
                    TempoCard {
                        Label("Tempo Dengesi için henüz yeterli ölçüm yok. Apple Sağlık verileri geldikçe puanın oluşacak.", systemImage: "gauge.with.dots.needle.33percent")
                            .font(.subheadline)
                            .foregroundStyle(TempoTheme.secondary)
                    }
                }
                healthOverview
                HealthDaySelector(points: healthPoints, selectedDay: $selectedHealthDay)
                SleepDetailCard(points: healthPoints, selectedDay: $selectedHealthDay)
                CardioFitnessCard(points: healthPoints)
                SectionHeading(title: selectedHealthDayTitle, caption: "APPLE SAĞLIK", padding: false)
                LazyVGrid(columns: columns, spacing: 12) {
                    HealthMetricTile(title: "Adım", value: whole(selectedMetrics.steps), unit: "adım", icon: "figure.walk", color: TempoTheme.green)
                    HealthMetricTile(title: "Aktif enerji", value: whole(selectedMetrics.activeEnergyKcal), unit: "kcal", icon: "flame.fill", color: TempoTheme.orange)
                    HealthMetricTile(title: "Egzersiz", value: whole(selectedMetrics.exerciseMinutes), unit: "dk", icon: "figure.run", color: TempoTheme.green)
                    HealthMetricTile(title: "Dinlenik nabız", value: decimal(selectedMetrics.restingHeartRateBpm), unit: "atım/dk", icon: "heart.fill", color: .pink)
                    HealthMetricTile(title: "HRV", value: decimal(selectedMetrics.hrvMs), unit: "ms", icon: "waveform.path.ecg", color: TempoTheme.purple)
                    HealthMetricTile(title: "Uyku", value: selectedSleepText, unit: selectedMetrics.sleepMinutes == nil ? "veri yok" : "", icon: "moon.zzz.fill", color: TempoTheme.blue)
                    HealthMetricTile(title: "Su", value: whole(selectedMetrics.waterMl), unit: "ml", icon: "drop.fill", color: TempoTheme.blue)
                    HealthMetricTile(title: "Kilo", value: decimal(selectedMetrics.bodyMassKg), unit: "kg", icon: "scalemass.fill", color: TempoTheme.green)
                }
            }
            if let error = model.healthError {
                Text(error).font(.footnote).foregroundStyle(TempoTheme.orange).frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(model.status.tempoLocalized).font(.footnote).foregroundStyle(TempoTheme.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
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
                Button(action: model.connectAppleHealth) {
                    Label("Sağlık izinlerini yeniden iste", systemImage: "hand.raised.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TempoPrimaryButtonStyle())
                .disabled(model.isHealthSyncing)
                Text("Tempo yalnızca verdiğin Apple Sağlık izinlerindeki ölçüleri okur. Apple, reddedilen okuma izinlerini uygulamaya açıklamaz; eksik ölçüler boş görünür.")
                    .font(.caption).foregroundStyle(TempoTheme.secondary).lineSpacing(3)
            }
        }
        .navigationTitle("Sağlık")
        .navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
        .onAppear { selectLatestHealthDayIfNeeded() }
        .onChange(of: model.healthDays) { _, _ in selectLatestHealthDayIfNeeded() }
    }

    private var healthIntro: some View {
        HStack(spacing: 13) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.pink)
                .frame(width: 48, height: 48)
                .background(.pink.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("Günlük iyilik hâlin").font(.subheadline.bold())
                Text("Uyku, toparlanma ve hareket ölçülerin")
                    .font(.caption).foregroundStyle(TempoTheme.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.pink.opacity(0.85))
        }
        .padding(14)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.075), lineWidth: 1))
    }

    private var connectCard: some View {
        TempoCard {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "heart.text.square.fill").font(.system(size: 42)).foregroundStyle(.pink)
                Text("Sağlık verilerini Tempo’ya bağla").font(.title3.bold())
                Text("Son 90 gündeki su, uyku evreleri, hareket, kalp, solunum ve kondisyon ölçülerini tek ekranda gör. Hızlı su ekleme de Apple Sağlık’a kaydedilir.")
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

    private var selectedSleepText: String {
        guard let minutes = selectedMetrics.sleepMinutes else { return "—" }
        return TempoFormat.duration(minutes * 60)
    }

    private var selectedMetrics: TempoHealthMetrics {
        selectedPoint?.metrics ?? model.todayHealth
    }

    private var selectedPoint: HealthDayPoint? {
        guard let selectedHealthDay else { return healthPoints.last }
        return healthPoints.first { Calendar.autoupdatingCurrent.isDate($0.day, inSameDayAs: selectedHealthDay) }
    }

    private var selectedHealthDayTitle: String {
        guard let selectedPoint else { return "Bugünkü ölçüler".tempoLocalized }
        if Calendar.autoupdatingCurrent.isDateInToday(selectedPoint.day) { return "Bugünkü ölçüler".tempoLocalized }
        return selectedPoint.day.formatted(.dateTime.day().month(.wide).weekday(.wide)).capitalized
    }

    private var healthPoints: [HealthDayPoint] {
        model.healthDays.compactMap { day, metrics in
            guard let date = TempoFormat.dayFormatter.date(from: day) else { return nil }
            return HealthDayPoint(day: date, metrics: metrics)
        }
        .sorted { $0.day < $1.day }
    }

    private func selectLatestHealthDayIfNeeded() {
        guard !healthPoints.isEmpty else { selectedHealthDay = nil; return }
        if let selectedHealthDay,
           healthPoints.contains(where: { Calendar.autoupdatingCurrent.isDate($0.day, inSameDayAs: selectedHealthDay) }) {
            return
        }
        selectedHealthDay = healthPoints.last?.day
    }

    private func whole(_ value: Double?) -> String {
        guard let value else { return "—" }
        return Int(value.rounded()).formatted(.number.locale(Locale.autoupdatingCurrent))
    }

    private func decimal(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.locale(Locale.autoupdatingCurrent).precision(.fractionLength(1)))
    }
}

private struct HealthDayPoint: Identifiable {
    let day: Date
    let metrics: TempoHealthMetrics
    var id: Date { day }
}

private struct HealthDaySelector: View {
    let points: [HealthDayPoint]
    @Binding var selectedDay: Date?

    var body: some View {
        TempoCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SAĞLIK GEÇMİŞİ".tempoLocalized)
                            .font(.caption2.bold()).tracking(1.2).foregroundStyle(TempoTheme.green)
                        Text("Önceki kayıtların".tempoLocalized).font(.headline)
                    }
                    Spacer()
                    Text("Son 90 gün".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
                }

                if points.isEmpty {
                    Label("Henüz geçmiş sağlık kaydı bulunamadı.", systemImage: "calendar.badge.exclamationmark")
                        .font(.subheadline).foregroundStyle(TempoTheme.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 9) {
                            ForEach(Array(points.suffix(30).reversed())) { point in
                                let isSelected = selectedDay.map { Calendar.autoupdatingCurrent.isDate($0, inSameDayAs: point.day) } ?? false
                                let sleepScore = TempoSleepAssessment.evaluate(point.metrics)?.value
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) { selectedDay = point.day }
                                } label: {
                                    VStack(spacing: 5) {
                                        Text(point.day.formatted(.dateTime.day()))
                                            .font(.headline.monospacedDigit())
                                        Text(point.day.formatted(.dateTime.month(.abbreviated)))
                                            .font(.caption2)
                                        if let sleepScore {
                                            Label("\(sleepScore)", systemImage: "moon.fill")
                                                .font(.caption2.bold())
                                        } else {
                                            Text("Ölçüm".tempoLocalized).font(.caption2.bold())
                                        }
                                    }
                                    .foregroundStyle(isSelected ? Color.black : Color.white)
                                    .frame(width: 64, height: 76)
                                    .background(isSelected ? TempoTheme.green : TempoTheme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(isSelected ? TempoTheme.green : .white.opacity(0.06)))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(point.day.formatted(date: .complete, time: .omitted))
                            }
                        }
                    }
                    Text("Bir güne dokunarak o tarihteki uyku puanını, evreleri ve diğer Apple Sağlık ölçülerini inceleyebilirsin.")
                        .font(.caption2).foregroundStyle(TempoTheme.secondary).lineSpacing(3)
                }
            }
        }
    }
}

private struct SleepDetailCard: View {
    let points: [HealthDayPoint]
    @Binding var selectedDay: Date?

    private var sleepPoints: [HealthDayPoint] {
        points.filter { ($0.metrics.sleepMinutes ?? 0) > 0 }
    }

    private var selectedPoint: HealthDayPoint? {
        guard let selectedDay else { return sleepPoints.last }
        return sleepPoints.first { Calendar.autoupdatingCurrent.isDate($0.day, inSameDayAs: selectedDay) }
    }

    private var selectedMetrics: TempoHealthMetrics? { selectedPoint?.metrics }
    private var assessment: TempoSleepAssessment? { selectedMetrics.flatMap(TempoSleepAssessment.evaluate) }

    private var weeklyAverage: Double? {
        let values = sleepPoints.suffix(7).compactMap(\.metrics.sleepMinutes)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var body: some View {
        TempoCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("UYKU ANALİZİ".tempoLocalized)
                            .font(.caption2.bold()).tracking(1.25).foregroundStyle(TempoTheme.blue)
                        Text("Uyku evreleri".tempoLocalized).font(.title3.bold())
                    }
                    Spacer()
                    if let average = weeklyAverage {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(TempoFormat.duration(average * 60)).font(.subheadline.bold())
                            Text("7 gün ortalaması".tempoLocalized).font(.caption2).foregroundStyle(TempoTheme.secondary)
                        }
                    }
                }

                if let selectedMetrics, let assessment {
                    HStack(spacing: 17) {
                        ZStack {
                            Circle().stroke(.white.opacity(0.08), lineWidth: 10)
                            Circle()
                                .trim(from: 0, to: CGFloat(assessment.value) / 100)
                                .stroke(
                                    AngularGradient(colors: [TempoTheme.blue, TempoTheme.purple, TempoTheme.green], center: .center),
                                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: 0) {
                                Text("\(assessment.value)").font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                                Text("UYKU PUANI".tempoLocalized).font(.system(size: 8, weight: .bold)).foregroundStyle(TempoTheme.secondary)
                            }
                        }
                        .frame(width: 102, height: 102)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(selectedPoint?.day.formatted(date: .long, time: .omitted).capitalized ?? "")
                                .font(.caption).foregroundStyle(TempoTheme.secondary)
                            Text(assessment.state.tempoLocalized).font(.title3.bold())
                            Text(TempoFormat.duration((selectedMetrics.sleepMinutes ?? 0) * 60))
                                .font(.headline).foregroundStyle(TempoTheme.blue)
                            Text(assessment.confidence.tempoLocalized)
                                .font(.caption2.bold()).foregroundStyle(TempoTheme.green)
                        }
                    }

                    Text(assessment.summary.tempoLocalized)
                        .font(.subheadline).foregroundStyle(.white.opacity(0.76)).lineSpacing(3)
                }

                if !sleepPoints.isEmpty {
                    Text("Uyku süresi · 14 gün".tempoLocalized).font(.caption.bold()).foregroundStyle(TempoTheme.secondary)
                    Chart(Array(sleepPoints.suffix(14))) { point in
                        BarMark(
                            x: .value("Gün".tempoLocalized, point.day, unit: .day),
                            y: .value("Saat".tempoLocalized, (point.metrics.sleepMinutes ?? 0) / 60)
                        )
                        .foregroundStyle(
                            LinearGradient(colors: [TempoTheme.blue, TempoTheme.purple], startPoint: .bottom, endPoint: .top)
                        )
                        .cornerRadius(5)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.narrow))
                                .foregroundStyle(TempoTheme.secondary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                            AxisGridLine().foregroundStyle(.white.opacity(0.06))
                            AxisValueLabel { if let hours = value.as(Double.self) { Text("\(Int(hours))s") } }
                                .foregroundStyle(TempoTheme.secondary)
                        }
                    }
                    .frame(height: 138)

                    Text("Uyku puanı · 14 gün".tempoLocalized).font(.caption.bold()).foregroundStyle(TempoTheme.secondary)
                    Chart(Array(sleepPoints.suffix(14))) { point in
                        if let score = TempoSleepAssessment.evaluate(point.metrics)?.value {
                            LineMark(
                                x: .value("Gün".tempoLocalized, point.day, unit: .day),
                                y: .value("Puan".tempoLocalized, score)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(TempoTheme.green)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                            PointMark(
                                x: .value("Gün".tempoLocalized, point.day, unit: .day),
                                y: .value("Puan".tempoLocalized, score)
                            )
                            .foregroundStyle(TempoTheme.green)
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                            AxisGridLine().foregroundStyle(.white.opacity(0.06))
                            AxisValueLabel().foregroundStyle(TempoTheme.secondary)
                        }
                    }
                    .frame(height: 105)
                }

                if let selectedMetrics {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                        SleepStagePill(title: "Çekirdek", minutes: selectedMetrics.sleepCoreMinutes, color: TempoTheme.blue)
                        SleepStagePill(title: "Derin", minutes: selectedMetrics.sleepDeepMinutes, color: TempoTheme.purple)
                        SleepStagePill(title: "REM", minutes: selectedMetrics.sleepREMMinutes, color: TempoTheme.green)
                        SleepStagePill(title: "Uyanık", minutes: selectedMetrics.sleepAwakeMinutes, color: TempoTheme.orange)
                    }

                    if let assessment {
                        Divider().overlay(.white.opacity(0.08))
                        VStack(spacing: 13) {
                            ForEach(assessment.factors) { factor in
                                SleepFactorRow(factor: factor)
                            }
                        }
                    }
                } else {
                    Label("Uyku evresi verisi henüz bulunamadı.", systemImage: "moon.zzz")
                        .font(.subheadline).foregroundStyle(TempoTheme.secondary)
                }
            }
        }
    }
}

private struct SleepFactorRow: View {
    let factor: TempoSleepFactor

    private var color: Color {
        switch factor.score {
        case 85...: return TempoTheme.green
        case 65..<85: return TempoTheme.blue
        case 45..<65: return TempoTheme.orange
        default: return .pink
        }
    }

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: factor.symbol)
                .font(.caption.bold()).foregroundStyle(color)
                .frame(width: 32, height: 32).background(color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(factor.title.tempoLocalized).font(.caption.weight(.semibold))
                    Spacer()
                    Text(factor.value).font(.caption2).foregroundStyle(TempoTheme.secondary)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.07))
                        Capsule().fill(color).frame(width: proxy.size.width * CGFloat(factor.score) / 100)
                    }
                }
                .frame(height: 5)
            }
            Text("\(factor.score)").font(.caption.monospacedDigit().bold()).foregroundStyle(color).frame(width: 26)
        }
    }
}

private struct SleepStagePill: View {
    let title: String
    let minutes: Double?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title.tempoLocalized).font(.caption2).foregroundStyle(TempoTheme.secondary)
            }
            Text(minutes.map { TempoFormat.duration($0 * 60) } ?? "—")
                .font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct CardioFitnessCard: View {
    let points: [HealthDayPoint]

    private func latest(_ keyPath: KeyPath<TempoHealthMetrics, Double?>) -> Double? {
        points.reversed().compactMap { $0.metrics[keyPath: keyPath] }.first
    }

    private func series(_ keyPath: KeyPath<TempoHealthMetrics, Double?>) -> [HealthTrendPoint] {
        points.suffix(14).compactMap { point in
            guard let value = point.metrics[keyPath: keyPath] else { return nil }
            return HealthTrendPoint(day: point.day, value: value)
        }
    }

    private func value(_ number: Double?, digits: Int = 1) -> String {
        guard let number else { return "—" }
        return number.formatted(.number.locale(.autoupdatingCurrent).precision(.fractionLength(digits)))
    }

    var body: some View {
        TempoCard {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("KALP VE KONDİSYON".tempoLocalized)
                        .font(.caption2.bold()).tracking(1.25).foregroundStyle(.pink)
                    Text("Kişisel eğilimlerin".tempoLocalized).font(.title3.bold())
                    Text("Son ölçümler ve 14 günlük değişim".tempoLocalized)
                        .font(.caption).foregroundStyle(TempoTheme.secondary)
                }

                HStack(spacing: 10) {
                    HealthTrendTile(
                        title: "Dinlenik nabız", value: value(latest(\.restingHeartRateBpm)), unit: "atım/dk",
                        icon: "heart.fill", color: .pink, points: series(\.restingHeartRateBpm)
                    )
                    HealthTrendTile(
                        title: "HRV", value: value(latest(\.hrvMs)), unit: "ms",
                        icon: "waveform.path.ecg", color: TempoTheme.purple, points: series(\.hrvMs)
                    )
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    CompactHealthValue(title: "Kardiyo kondisyonu", value: value(latest(\.vo2Max)), unit: "VO₂ max", icon: "lungs.fill", color: TempoTheme.green)
                    CompactHealthValue(title: "Solunum", value: value(latest(\.respiratoryRate)), unit: "nefes/dk", icon: "wind", color: TempoTheme.blue)
                    CompactHealthValue(title: "Kandaki oksijen", value: value(latest(\.oxygenSaturationPct)), unit: "%", icon: "drop.degreesign.fill", color: TempoTheme.blue)
                    CompactHealthValue(title: "Nabız toparlanması", value: value(latest(\.heartRateRecoveryBpm)), unit: "atım/dk", icon: "heart.arrow.triangle.branch", color: TempoTheme.green)
                    CompactHealthValue(title: "Yürüme nabzı", value: value(latest(\.walkingHeartRateBpm)), unit: "atım/dk", icon: "figure.walk", color: TempoTheme.orange)
                    CompactHealthValue(title: "Bilek sıcaklığı", value: value(latest(\.wristTemperatureC)), unit: "°C", icon: "thermometer.medium", color: TempoTheme.orange)
                }

                Text("Boş ölçüler, Apple Sağlık’ta veri olmadığı veya ilgili okuma izninin verilmediği anlamına gelebilir.".tempoLocalized)
                    .font(.caption2).foregroundStyle(TempoTheme.secondary).lineSpacing(3)
            }
        }
    }
}

private struct HealthTrendPoint: Identifiable {
    let day: Date
    let value: Double
    var id: Date { day }
}

private struct HealthTrendTile: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    let points: [HealthTrendPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon).foregroundStyle(color)
                Text(title.tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.title3.bold().monospacedDigit())
                Text(unit.tempoLocalized).font(.caption2).foregroundStyle(TempoTheme.secondary)
            }
            Chart(points) { point in
                LineMark(x: .value("Gün".tempoLocalized, point.day), y: .value(title.tempoLocalized, point.value))
                    .foregroundStyle(color).interpolationMethod(.catmullRom)
                AreaMark(x: .value("Gün".tempoLocalized, point.day), y: .value(title.tempoLocalized, point.value))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
            }
            .chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 52)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(TempoTheme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct CompactHealthValue: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(color)
                .frame(width: 32, height: 32).background(color.opacity(0.11), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title.tempoLocalized).font(.caption2).foregroundStyle(TempoTheme.secondary).lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(.subheadline.bold().monospacedDigit())
                    Text(unit.tempoLocalized).font(.system(size: 9)).foregroundStyle(TempoTheme.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(TempoTheme.raised.opacity(0.75), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                Text(title.tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value).font(.title3.bold())
                    if !unit.isEmpty { Text(unit.tempoLocalized).font(.caption2).foregroundStyle(TempoTheme.secondary) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [color.opacity(0.075), TempoTheme.card], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.065), lineWidth: 1))
    }
}

private struct TempoBalanceHomeCard: View {
    let balance: TempoBalanceScore

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(.white.opacity(0.08), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: CGFloat(balance.value) / 100)
                    .stroke(
                        LinearGradient(colors: [TempoTheme.green, TempoTheme.blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text("\(balance.value)")
                    .font(.title3.monospacedDigit().bold())
            }
            .frame(width: 66, height: 66)

            VStack(alignment: .leading, spacing: 5) {
                Text("TEMPO DENGESİ")
                    .font(.caption2.bold())
                    .tracking(1.25)
                    .foregroundStyle(TempoTheme.green)
                Text(balance.state.tempoLocalized).font(.headline)
                Text(balance.recommendation.tempoLocalized)
                    .font(.caption)
                    .foregroundStyle(TempoTheme.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.3))
        }
        .foregroundStyle(.white)
        .padding(17)
        .background(
            LinearGradient(
                colors: [TempoTheme.green.opacity(0.11), TempoTheme.blue.opacity(0.07), TempoTheme.card],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(TempoTheme.green.opacity(0.18)))
    }
}

private struct TempoBalanceDetailCard: View {
    let balance: TempoBalanceScore

    var body: some View {
        TempoCard {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 18) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.08), lineWidth: 11)
                        Circle()
                            .trim(from: 0, to: CGFloat(balance.value) / 100)
                            .stroke(
                                AngularGradient(colors: [TempoTheme.green, TempoTheme.blue, TempoTheme.green], center: .center),
                                style: StrokeStyle(lineWidth: 11, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text("\(balance.value)")
                                .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                            Text("/ 100")
                                .font(.caption2)
                                .foregroundStyle(TempoTheme.secondary)
                        }
                    }
                    .frame(width: 112, height: 112)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("TEMPO DENGESİ")
                            .font(.caption.bold())
                            .tracking(1.35)
                            .foregroundStyle(TempoTheme.green)
                        Text(balance.state.tempoLocalized)
                            .font(.title2.bold())
                        Text(balance.confidence.tempoLocalized)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TempoTheme.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(TempoTheme.blue.opacity(0.12), in: Capsule())
                    }
                }

                Text(balance.recommendation.tempoLocalized)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.76))
                    .lineSpacing(4)

                Divider().overlay(.white.opacity(0.08))

                VStack(spacing: 15) {
                    ForEach(balance.factors) { factor in
                        TempoBalanceFactorRow(factor: factor)
                    }
                }

                Text("Puan; kişisel geçmişindeki uyku, HRV, dinlenik nabız, hareket yükü ve sıvı ölçümlerinden mevcut olanlarla hesaplanır. Tıbbi değerlendirme değildir.")
                    .font(.caption2)
                    .foregroundStyle(TempoTheme.secondary)
                    .lineSpacing(3)
            }
        }
    }
}

private struct TempoBalanceFactorRow: View {
    let factor: TempoBalanceFactor

    private var color: Color {
        switch factor.tint {
        case "orange": return TempoTheme.orange
        case "blue": return TempoTheme.blue
        case "purple": return TempoTheme.purple
        case "pink": return .pink
        default: return TempoTheme.green
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: factor.symbol)
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(factor.title.tempoLocalized).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(factor.value).font(.caption).foregroundStyle(TempoTheme.secondary).lineLimit(1)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.07))
                        Capsule().fill(color).frame(width: proxy.size.width * CGFloat(factor.score) / 100)
                    }
                }
                .frame(height: 5)
            }
            Text("\(factor.score)")
                .font(.caption.monospacedDigit().bold())
                .foregroundStyle(color)
                .frame(width: 27, alignment: .trailing)
        }
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
                            Text("%d aktivite · %@".tempoFormatted(item.count, TempoFormat.duration(item.seconds))).font(.caption).foregroundStyle(TempoTheme.secondary)
                        }
                        Spacer(); Text(TempoFormat.distance(item.distanceKm)).font(.headline).foregroundStyle(TempoTheme.green)
                    }
                }
            }
        }.navigationTitle("Aylık").navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
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
        }.navigationTitle("Ekipman").navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
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
        }.navigationTitle("Segmentler").navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
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
                    Text("%d farklı günde en az %d km koştun.".tempoFormatted(number, number)).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                    Text("Bu sayı düzenli ve uzun mesafeli koşular yaptıkça yükselir.").font(.subheadline).foregroundStyle(TempoTheme.secondary).multilineTextAlignment(.center)
                }.padding(.vertical, 28).frame(maxWidth: .infinity)
            }
        }.navigationTitle("Eddington").navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
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
        }.navigationTitle("Yıl Özeti").navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
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
        }.navigationTitle("Fotoğraflar").navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
    }
}

private struct TempoPage<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ZStack {
            TempoAmbientBackground()
            ScrollView {
                VStack(spacing: 16) { content }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, TempoTheme.scrollBottomClearance)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

private struct HomeHeader: View {
    private var dateText: String {
        Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("TEMPO")
                    .font(.caption.bold())
                    .tracking(3)
                    .foregroundStyle(TempoTheme.green)
                Text(dateText.prefix(1).uppercased() + dateText.dropFirst())
                    .font(.title3.bold())
            }
            Spacer()
        }
    }
}

private struct PageTitle: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(subtitle.tempoLocalized.uppercased()).font(.caption.bold()).tracking(1.5).foregroundStyle(TempoTheme.green)
            Text(title.tempoLocalized).font(.system(size: 31, weight: .bold, design: .rounded))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
    }
}

private struct StravaConnectionCard: View {
    let dashboard: TempoDashboard

    private var athlete: TempoAthlete { dashboard.athlete }
    private var totalDistance: Double { dashboard.activities.reduce(0) { $0 + $1.distanceKm } }

    var body: some View {
        Link(destination: URL(string: "https://www.strava.com/athletes/\(athlete.id)")!) {
            HStack(spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: athlete.profile.flatMap(URL.init(string:))) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            ZStack {
                                TempoTheme.raised
                                Image(systemName: "person.fill").font(.title3).foregroundStyle(TempoTheme.orange)
                            }
                        }
                    }
                    .frame(width: 56, height: 56)
                    .background(TempoTheme.raised)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(TempoTheme.orange.opacity(0.65), lineWidth: 2))

                    Image(systemName: "figure.run")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 23, height: 23)
                        .background(TempoTheme.orange, in: Circle())
                        .overlay(Circle().stroke(TempoTheme.card, lineWidth: 2))
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text("STRAVA HESABI").font(.caption2.bold()).tracking(1.2).foregroundStyle(TempoTheme.orange)
                        Text("BAĞLI")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(TempoTheme.green)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(TempoTheme.green.opacity(0.12), in: Capsule())
                    }
                    Text(athlete.fullName.isEmpty ? "Strava Sporcusu" : athlete.fullName)
                        .font(.headline).foregroundStyle(.white).lineLimit(1)
                    Text("%d aktivite · %@".tempoFormatted(dashboard.activities.count, TempoFormat.distance(totalDistance)))
                        .font(.caption).foregroundStyle(TempoTheme.secondary).lineLimit(1)
                }

                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
                    .font(.caption.bold())
                    .foregroundStyle(TempoTheme.orange)
                    .frame(width: 34, height: 34)
                    .background(TempoTheme.orange.opacity(0.1), in: Circle())
            }
            .padding(15)
            .background(
                LinearGradient(
                    colors: [TempoTheme.orange.opacity(0.12), TempoTheme.card],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(TempoTheme.orange.opacity(0.18)))
        }
        .buttonStyle(.plain)
    }
}

private struct TempoCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(LinearGradient(colors: [TempoTheme.card.opacity(0.88), TempoTheme.card.opacity(0.97)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.13), .white.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.13), radius: 16, y: 8)
    }
}

private struct MetricCard: View {
    let value: String; let label: String; let icon: String; let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(color)
            Text(value).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.7)
            Text(label.tempoLocalized).font(.caption2).foregroundStyle(TempoTheme.secondary)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TempoTheme.card.opacity(0.88), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(.white.opacity(0.065), lineWidth: 1))
    }
}

private struct SectionHeading: View {
    let title: String; let caption: String; var padding = true
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(caption.tempoLocalized).font(.caption2.bold()).tracking(1.5).foregroundStyle(TempoTheme.green)
            Text(title.tempoLocalized).font(.title3.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, padding ? 7 : 0)
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
        .padding(14)
        .background(TempoTheme.card.opacity(0.88), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(.white.opacity(0.065), lineWidth: 1))
    }
}

private struct MoreLink: View {
    let title: String; let subtitle: String; let icon: String; let color: Color; let destination: AnyView
    var body: some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Image(systemName: icon).font(.title3).foregroundStyle(color); Spacer(); Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(TempoTheme.secondary) }
                Text(title.tempoLocalized).font(.headline).foregroundStyle(.white)
                Text(subtitle.tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
            }
            .padding(17)
            .frame(maxWidth: .infinity, minHeight: 135, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [color.opacity(0.11), TempoTheme.card], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.07), lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

private struct EmptyCard: View {
    let icon: String; let text: String
    var body: some View {
        VStack(spacing: 11) { Image(systemName: icon).font(.title).foregroundStyle(TempoTheme.secondary); Text(text.tempoLocalized).font(.subheadline).foregroundStyle(TempoTheme.secondary).multilineTextAlignment(.center) }
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
        HStack { Image(systemName: "magnifyingglass").foregroundStyle(TempoTheme.secondary); TextField(placeholder.tempoLocalized, text: $text); if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }.foregroundStyle(TempoTheme.secondary) } }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .background(TempoTheme.card.opacity(0.80), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(.white.opacity(0.075), lineWidth: 1))
    }
}

private struct DetailLine: View {
    let label: String; let value: String
    var body: some View { HStack { Text(label.tempoLocalized).foregroundStyle(TempoTheme.secondary); Spacer(); Text(value).fontWeight(.semibold) }.font(.subheadline).padding(.vertical, 3) }
}

private struct SummaryLine: View {
    let icon: String; let title: String; let value: String; let color: Color
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 44, height: 44).background(color.opacity(0.12), in: Circle())
            Text(title.tempoLocalized).font(.headline); Spacer(); Text(value).font(.headline).foregroundStyle(color)
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
