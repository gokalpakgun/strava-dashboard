import Charts
import CoreLocation
import MapKit
import PhotosUI
import SwiftUI
import UIKit

enum TempoTheme {
    static let background = Color(red: 0.045, green: 0.055, blue: 0.058)
    static let card = Color(red: 0.075, green: 0.089, blue: 0.091)
    static let raised = Color(red: 0.108, green: 0.124, blue: 0.124)
    static let green = Color(red: 0.43, green: 0.77, blue: 0.57)
    static let orange = Color(red: 0.91, green: 0.53, blue: 0.37)
    static let blue = Color(red: 0.46, green: 0.68, blue: 0.72)
    static let purple = Color(red: 0.66, green: 0.59, blue: 0.75)
    static let secondary = Color.white.opacity(0.62)
    static let scrollBottomClearance: CGFloat = 132
}

struct ContentView: View {
    @EnvironmentObject private var model: TempoAppModel
    @EnvironmentObject private var account: TempoAccountStore
    @State private var selectedTab = 0
    @State private var minimumLaunchFinished = false

    var body: some View {
        Group {
            if !minimumLaunchFinished || account.isRestoring {
                TempoLaunchView()
            } else if !account.isAuthenticated {
                AccountWelcomeView()
            } else if account.profile?.onboardingComplete != true {
                AccountOnboardingView()
            } else {
                TempoMainShell(selectedTab: $selectedTab)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation(.easeOut(duration: 0.28)) {
                minimumLaunchFinished = true
            }
        }
        .task(id: account.isAuthenticated) {
            guard account.isAuthenticated else { return }
            model.setTempoAccount(account.profile?.id)
            await model.restoreConnectionIfNeeded(accountToken: account.authorizationToken, accountId: account.profile?.id)
        }
        .task(id: account.profile?.id) {
            model.setTempoAccount(account.profile?.id)
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
        ZStack {
            selectedScreen
                .id(selectedTab)
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.24), value: selectedTab)
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
                        Text("STRAVA BAĞLANTISI".tempoSentenceCased)
                            .font(.caption.weight(.semibold)).foregroundStyle(TempoTheme.secondary)
                        Spacer()
                    }
                    .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("HAREKETİNİ KEŞFET".tempoSentenceCased).font(.subheadline.weight(.semibold)).foregroundStyle(TempoTheme.orange)
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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Strava’ya devam ederek Tempo’nun Strava OAuth/API üzerinden profil bilgilerini (konum ve kilo dâhil), aktivitelerini, ekipmanını, favori segmentlerini, aktivite fotoğraflarını ve GPS rotalarını almasına izin verirsin. İzin verdiğin özel aktiviteler de dâhil olabilir. Veriler yalnızca sana ait Tempo panelinde gösterilir; Koç’a veya arkadaşlarına aktarılmaz. Bağlantıyı Tempo’dan veya Strava ayarlarından kesebilir, Tempo hesabını silerek Tempo’daki verilerini silebilirsin. Silme tamamlanınca uygulama onay gösterir.".tempoLocalized)
                            .font(.caption2)
                            .foregroundStyle(TempoTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 14) {
                            Link("Gizlilik Politikası".tempoLocalized, destination: URL(string: "https://apitempo.com/privacy")!)
                            Link("Kullanım Koşulları".tempoLocalized, destination: URL(string: "https://apitempo.com/terms")!)
                        }
                        .font(.caption2.weight(.semibold))
                        .tint(TempoTheme.green)
                    }
                    .padding(.horizontal, 2)

                    Button(action: model.connectStrava) {
                        HStack(spacing: 12) {
                            if model.isBusy {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "figure.run")
                                    .font(.title3)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text((model.isBusy ? "Strava açılıyor…" : "Strava ile devam et").tempoLocalized)
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
                    Text("Mesafe, süre ve rota".tempoLocalized).font(.title3.bold())
                    Text("Yeni antrenmanların Tempo’da görünür.".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
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
    private var weekManualWorkouts: [TempoManualWorkout] {
        model.manualWorkouts.filter { Calendar.current.isDateInCurrentWeek($0.startedAt) }
    }
    private var weekDistance: Double {
        weekActivities.reduce(0) { $0 + $1.distanceKm } + weekManualWorkouts.reduce(0) { $0 + ($1.distanceKm ?? 0) }
    }
    private var weekSeconds: Double {
        weekActivities.reduce(0) { $0 + $1.movingSeconds }
            + weekManualWorkouts.reduce(0) { $0 + Double($1.durationSeconds ?? $1.durationMinutes * 60) }
    }

    var body: some View {
        NavigationStack {
            TempoPage {
                HomeHeader()
                AppleHealthHomeCard(balance: model.tempoBalance, connected: model.healthSyncEnabled)
                HomeMovementMenuCard()
                if let dashboard = model.dashboard {
                    hero(dashboard.athlete)
                    SectionHeading(title: "Bu hafta", caption: "HAFTALIK ÖZET", padding: false)
                    weeklyMetrics
                } else if model.isConnected {
                    LoadingDashboardCard()
                } else {
                    StravaOptionalCard(
                        title: "Strava bağlantısı isteğe bağlı",
                        message: "Strava’yı bağlamadan da spor alanlarını keşfedebilir ve Apple Sağlık verilerini cihazında görüntüleyebilirsin."
                    )
                }
                HomeSocialCard()
                if let dashboard = model.dashboard {
                    RecentActivitiesPanel(activities: dashboard.activities)
                }
                quickActions
                dailyMotivation
            }
            .refreshable { await model.reloadAll() }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func hero(_ athlete: TempoAthlete) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("MERHABA, %@".tempoFormatted((athlete.firstname ?? "SPORCU").uppercased()))
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
            MetricCard(value: "\(weekActivities.count + weekManualWorkouts.count)", label: "Antrenman", icon: "figure.run", color: TempoTheme.green)
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

private struct HomeMovementMenuCard: View {
    var body: some View {
        NavigationLink(destination: TempoMovementMenuScreen()) {
            HStack(spacing: 13) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(TempoTheme.green)
                    .frame(width: 46, height: 46)
                    .background(TempoTheme.green.opacity(0.13), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("GÜNÜN HAREKET MENÜSÜ")
                        .font(.caption2.weight(.bold)).tracking(1).foregroundStyle(TempoTheme.green)
                    Text("Bugün ne yapsam?")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Text("Vaktine, enerjine ve ekipmanına göre kısa seçenekler")
                        .font(.caption).foregroundStyle(TempoTheme.secondary).lineLimit(2)
                }
                Spacer(minLength: 2)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(TempoTheme.secondary)
            }
            .padding(14)
            .background(
                LinearGradient(colors: [TempoTheme.green.opacity(0.10), TempoTheme.card, TempoTheme.blue.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 21, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

private struct HomeSocialCard: View {
    var body: some View {
        NavigationLink(destination: SocialScreen()) {
            HStack(spacing: 13) {
                Image(systemName: "person.2.wave.2.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(TempoTheme.green)
                    .frame(width: 48, height: 48)
                    .background(TempoTheme.green.opacity(0.13), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("TEMPO SOSYAL")
                        .font(.caption2.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(TempoTheme.green)
                    Text("Arkadaşlarınla hareket et")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Arkadaş ekle · haftalık yarışları takip et")
                        .font(.caption)
                        .foregroundStyle(TempoTheme.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 2)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TempoTheme.green)
                    .frame(width: 31, height: 31)
                    .background(TempoTheme.green.opacity(0.12), in: Circle())
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [TempoTheme.green.opacity(0.10), TempoTheme.card, TempoTheme.blue.opacity(0.055)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 21, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(.white.opacity(0.085), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Sosyal alana git")
    }
}

private struct AppleHealthHomeCard: View {
    let balance: TempoBalanceScore?
    let connected: Bool

    var body: some View {
        NavigationLink(destination: HealthScreen()) {
            HStack(spacing: 13) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.pink)
                    .frame(width: 48, height: 48)
                    .background(.pink.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text((connected ? "Günlük hazırlık" : "Apple Sağlık").tempoSentenceCased)
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(.pink.opacity(0.95))
                    Text((connected ? "Tempo Dengesi" : "Uyku, hareket ve toparlanma verilerini bağla").tempoLocalized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if connected, let balance {
                        Text(balance.state.tempoLocalized + " · " + balance.confidence.tempoLocalized)
                            .font(.caption)
                            .foregroundStyle(TempoTheme.secondary)
                    } else if !connected {
                        Text("Strava gerekmez".tempoLocalized)
                            .font(.caption)
                            .foregroundStyle(TempoTheme.secondary)
                    }
                }
                Spacer(minLength: 2)
                if connected, let balance {
                    TempoReadinessRing(value: balance.value, size: 66)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TempoTheme.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [TempoTheme.purple.opacity(0.11), TempoTheme.card], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 21, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(.white.opacity(0.075), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct TempoReadinessRing: View {
    let value: Int
    var size: CGFloat = 68

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.09), lineWidth: 6)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(value, 0), 100)) / 100)
                .stroke(
                    AngularGradient(colors: [TempoTheme.green, TempoTheme.blue, TempoTheme.green], center: .center),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: -2) {
                Text("\(value)").font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                Text("/100").font(.system(size: 8, weight: .semibold)).foregroundStyle(TempoTheme.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tempo Dengesi, %d / 100".tempoFormatted(value))
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
                Text("GÜNÜN RİTMİ".tempoSentenceCased)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(TempoTheme.green)
                Text(message.tempoLocalized)
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
    @State private var selectedFilter = ActivityTimelineFilter.all
    @State private var isShowingManualWorkoutForm = false
    @State private var isShowingPhoneTracker = false

    private var filterOptions: [ActivityTimelineFilter] {
        let featuredSports: [TempoSport] = [.run, .ride, .walk, .tennis, .basketball, .football, .swim]
        let presentSports = Set(allActivities.map(\.sport))
        let additionalSports = presentSports.subtracting(Set(featuredSports))
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        return [.all]
            + featuredSports.map(ActivityTimelineFilter.sport)
            + additionalSports.map(ActivityTimelineFilter.sport)
            + [.other]
    }

    private var filtered: [TempoActivity] {
        (model.dashboard?.activities ?? []).filter { activity in
            let matchesSearch = search.isEmpty
                || (activity.name ?? "").localizedCaseInsensitiveContains(search)
                || activity.sport.title.localizedCaseInsensitiveContains(search)
            return matchesSearch && selectedFilter.matches(activity)
        }
    }

    private var allActivities: [TempoActivity] { model.dashboard?.activities ?? [] }
    private var totalDistance: Double {
        allActivities.reduce(0) { $0 + $1.distanceKm } + model.manualWorkouts.reduce(0) { $0 + ($1.distanceKm ?? 0) }
    }
    private var totalTime: Double {
        allActivities.reduce(0) { $0 + $1.movingSeconds }
            + model.manualWorkouts.reduce(0) { $0 + Double($1.durationSeconds ?? $1.durationMinutes * 60) }
    }
    private var totalWorkoutCount: Int { allActivities.count + model.manualWorkouts.count }

    var body: some View {
        NavigationStack {
            TempoPage {
                PageTitle(title: "Aktiviteler", subtitle: "Tüm antrenman geçmişin")
                HStack(spacing: 9) {
                    Button { isShowingPhoneTracker = true } label: {
                        Label("Koşu / yürüyüş kaydet", systemImage: "location.north.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TempoPrimaryButtonStyle())
                    Button { isShowingManualWorkoutForm = true } label: {
                        Label("Manuel kayıt", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TempoSecondaryButtonStyle())
                }
                if !model.manualWorkouts.isEmpty {
                    VStack(alignment: .leading, spacing: 11) {
                        HStack {
                            Text("MANUEL KAYITLAR").font(.caption.weight(.semibold)).foregroundStyle(TempoTheme.secondary)
                            Spacer()
                            Text("%d antrenman".tempoFormatted(model.manualWorkouts.count)).font(.caption.weight(.medium)).foregroundStyle(TempoTheme.secondary)
                        }
                        LazyVStack(spacing: 10) {
                            ForEach(model.manualWorkouts) { workout in
                                ManualWorkoutRow(workout: workout)
                                    .contextMenu {
                                        Button(role: .destructive) { model.deleteManualWorkout(workout) } label: {
                                            Label("Antrenmanı sil", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                }
                if !model.isConnected {
                    StravaOptionalCard(
                        title: "Aktivitelerin burada görünsün",
                        message: "Aktivite geçmişi ve Strava istatistikleri için hesabını istediğin zaman bağlayabilirsin."
                    )
                } else if model.dashboard == nil {
                    LoadingDashboardCard()
                } else {
                    activitySnapshot
                    SearchField(text: $search, placeholder: "Aktivite ara")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(filterOptions) { filter in
                                Button {
                                    withAnimation(.snappy(duration: 0.2)) { selectedFilter = filter }
                                } label: {
                                    Text(filter.title.tempoLocalized)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(selectedFilter.id == filter.id ? .black : .white.opacity(0.78))
                                        .padding(.horizontal, 14).padding(.vertical, 10)
                                        .background(selectedFilter.id == filter.id ? TempoTheme.green : .white.opacity(0.045), in: Capsule())
                                        .overlay(Capsule().stroke(selectedFilter.id == filter.id ? .clear : .white.opacity(0.08), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    HStack {
                        Text("SON HAREKETLER".tempoSentenceCased).font(.caption.weight(.semibold)).foregroundStyle(TempoTheme.secondary)
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
            }
            .refreshable { await model.refreshDashboard() }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingManualWorkoutForm) {
                ManualWorkoutForm()
            }
            .sheet(isPresented: $isShowingPhoneTracker) {
                TempoPhoneTrackerScreen()
            }
        }
    }

    private var activitySnapshot: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("HAREKET ÖZETİ".tempoSentenceCased).font(.caption.weight(.semibold)).foregroundStyle(TempoTheme.secondary)
                Text("%d antrenman".tempoFormatted(totalWorkoutCount))
                    .font(.title3.bold())
                Text("Strava ve cihaz kayıtların".tempoLocalized)
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

private struct ManualWorkoutRow: View {
    @EnvironmentObject private var model: TempoAppModel
    @State private var isShowingPhotoEvidence = false
    @State private var isShowingRoute = false
    let workout: TempoManualWorkout

    private var sportChoice: TempoSportChoice? {
        TempoSportChoice.allCases.first { $0.rawValue == workout.sportId }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: sportChoice?.symbol ?? "figure.mixed.cardio")
                .font(.title3.weight(.semibold))
                .foregroundStyle(TempoTheme.green)
                .frame(width: 42, height: 42)
                .background(TempoTheme.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(workout.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                Text("%@ · %@ · %d dk".tempoFormatted(workout.sportTitle, workout.startedAt.formatted(date: .abbreviated, time: .shortened), workout.durationMinutes))
                    .font(.caption).foregroundStyle(TempoTheme.secondary)
                HStack(spacing: 5) {
                    Image(systemName: sourceSymbol).font(.caption2)
                    Text(sourceTitle).font(.caption2.weight(.semibold))
                    if let distance = workout.distanceKm, distance > 0 {
                        Text("· %@".tempoFormatted(TempoFormat.distance(distance))).font(.caption2)
                    }
                }
                .foregroundStyle(workout.recordSource == "phone-gps" ? TempoTheme.blue : TempoTheme.green)
                if let signal = workout.healthSignal {
                    WorkoutHealthSignalSummary(signal: signal, durationMinutes: workout.durationMinutes)
                }
                if workout.perceivedEffort != nil || workout.enjoyment != nil {
                    Text("Zorluk %@ · Keyif %@".tempoFormatted(rating(workout.perceivedEffort), rating(workout.enjoyment)))
                        .font(.caption2).foregroundStyle(TempoTheme.secondary)
                }
                if !workout.notes.isEmpty {
                    Text(workout.notes).font(.caption).foregroundStyle(TempoTheme.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if (workout.routeCoordinates?.count ?? 0) >= 2 {
                Button { isShowingRoute = true } label: {
                    Image(systemName: "map.fill")
                        .foregroundStyle(TempoTheme.blue)
                        .frame(width: 40, height: 40)
                        .background(TempoTheme.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Rotayı görüntüle")
            }
            if let url = model.manualWorkoutPhotoURL(for: workout), let image = UIImage(contentsOfFile: url.path) {
                Button { isShowingPhotoEvidence = true } label: {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            } else if workout.photoFilename != nil {
                Image(systemName: "photo").foregroundStyle(TempoTheme.secondary).frame(width: 40, height: 40)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.07), lineWidth: 1))
        .sheet(isPresented: $isShowingPhotoEvidence) {
            if let url = model.manualWorkoutPhotoURL(for: workout), let image = UIImage(contentsOfFile: url.path) {
                NavigationStack {
                    ZStack {
                        TempoTheme.background.ignoresSafeArea()
                        Image(uiImage: image).resizable().scaledToFit().padding(16)
                    }
                    .navigationTitle("Kanıt fotoğrafı")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Tamam") { isShowingPhotoEvidence = false } } }
                }
                .preferredColorScheme(.dark)
            }
        }
        .sheet(isPresented: $isShowingRoute) {
            ManualWorkoutRouteScreen(workout: workout)
        }
    }

    private var sourceTitle: String {
        switch workout.recordSource {
        case "phone-gps": return "iPhone GPS kaydı".tempoLocalized
        case "health-supported-manual": return "Elle eklendi · Sağlık sinyali".tempoLocalized
        default: return workout.healthSignal == nil ? "Elle eklendi".tempoLocalized : "Elle eklendi · Sağlık sinyali".tempoLocalized
        }
    }

    private var sourceSymbol: String { workout.recordSource == "phone-gps" ? "location.fill" : "heart.text.square.fill" }

    private func rating(_ value: Int?) -> String {
        guard let value else { return "—" }
        return "\(value)/5"
    }
}

private struct ManualWorkoutRouteScreen: View {
    let workout: TempoManualWorkout
    @Environment(\.dismiss) private var dismiss
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.0, longitude: 35.0),
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    )

    private var coordinates: [CLLocationCoordinate2D] {
        (workout.routeCoordinates ?? []).map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if coordinates.count >= 2 {
                    Map(coordinateRegion: $region, interactionModes: [.pan, .zoom]) {
                        MapPolyline(coordinates: coordinates).stroke(TempoTheme.green, lineWidth: 5)
                    }
                    .mapStyle(.standard(elevation: .flat))
                    .overlay(alignment: .top) {
                        HStack {
                            Label(workout.sportTitle, systemImage: workout.sportId == "run" ? "figure.run" : "figure.walk")
                            Spacer()
                            Text(TempoFormat.distance(workout.distanceKm ?? 0)).bold()
                        }
                        .font(.subheadline.weight(.semibold)).padding(14)
                        .background(.ultraThinMaterial, in: Capsule()).padding(14)
                    }
                } else {
                    EmptyCard(icon: "map", text: "Bu kayıtta görüntülenecek rota noktası yok.")
                }
            }
            .background(TempoTheme.background)
            .navigationTitle("iPhone GPS rotası")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Kapat") { dismiss() } }
            }
            .onAppear { updateRegion() }
        }
        .preferredColorScheme(.dark)
    }

    private func updateRegion() {
        guard !coordinates.isEmpty else { return }
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (latitudes.min()! + latitudes.max()!) / 2, longitude: (longitudes.min()! + longitudes.max()!) / 2)
        region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: max((latitudes.max()! - latitudes.min()!) * 1.6, 0.006), longitudeDelta: max((longitudes.max()! - longitudes.min()!) * 1.6, 0.006))
        )
    }
}

private struct WorkoutHealthSignalSummary: View {
    let signal: TempoWorkoutHealthSignal
    let durationMinutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let duration = signal.matchedHealthWorkoutMinutes {
                Text("Apple Sağlık’ta aynı zamanla eşleşen %d dk antrenman kaydı".tempoFormatted(duration))
                    .foregroundStyle(TempoTheme.green)
            }
            if let average = signal.averageHeartRateBpm {
                Text("Nabız ort. %d bpm · tepe %d bpm".tempoFormatted(Int(average), Int(signal.peakHeartRateBpm ?? average)))
            }
            if let rise = signal.heartRateRiseBpm {
                Text("Antrenman öncesine göre nabız %@%d bpm".tempoFormatted(rise >= 0 ? "+" : "", Int(rise.rounded())))
            }
            if let averageRate = signal.averageRespiratoryRatePerMinute {
                Text("Solunum ort. %.1f /dk".tempoFormatted(averageRate))
            }
            if let rise = signal.respiratoryRateRisePerMinute {
                Text("Antrenman öncesine göre solunum %@%.1f /dk".tempoFormatted(rise >= 0 ? "+" : "−", abs(rise)))
            }
            if let steps = signal.stepsDuringWorkout {
                Text("Apple Sağlık adımı: %d".tempoFormatted(steps))
            }
            if let steps = signal.phoneStepsDuringWorkout {
                Text("iPhone hareket sensörü: %d adım".tempoFormatted(steps))
            }
            if let difference = signal.stepDifferenceAdjustedForWorkout(durationMinutes: durationMinutes) {
                Text("Süreye uyarlanmış adım farkı: %@%d".tempoFormatted(difference >= 0 ? "+" : "−", abs(difference)))
            }
            if signal.movementIncreaseDetected {
                Text("Öncesine göre belirgin hareket artışı algılandı")
                    .foregroundStyle(TempoTheme.green)
            }
            if let energy = signal.activeEnergyKcal {
                Text("Aktif enerji %.0f kcal".tempoFormatted(energy))
            }
            if let minutes = signal.exerciseMinutes, minutes > 0 {
                Text("Apple Sağlık egzersiz süresi %.0f dk".tempoFormatted(minutes))
            }
            if !signal.hasSupportingMeasurement {
                Text("Bu aralıkta destekleyici Sağlık ölçümü bulunamadı")
                    .foregroundStyle(TempoTheme.secondary)
            }
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(TempoTheme.blue)
    }
}

private struct ManualWorkoutForm: View {
    @EnvironmentObject private var model: TempoAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var sportId = TempoSportChoice.run.rawValue
    @State private var title = ""
    @State private var startedAt = Date().addingTimeInterval(-45 * 60)
    @State private var durationMinutes = 45
    @State private var notes = ""
    @State private var perceivedEffort: Int?
    @State private var enjoyment: Int?
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoImage: UIImage?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var errorTitle = "Antrenman kaydedilemedi"
    @State private var showingError = false

    private var selectedChoice: TempoSportChoice? {
        TempoSportChoice.allCases.first { $0.rawValue == sportId }
    }
    private var sportTitle: String { selectedChoice?.title ?? "Diğer".tempoLocalized }

    var body: some View {
        NavigationStack {
            Form {
                ManualWorkoutDetailsSection(
                    sportId: $sportId,
                    title: $title,
                    startedAt: $startedAt,
                    durationMinutes: $durationMinutes
                )
                ManualWorkoutFeedbackSection(effort: $perceivedEffort, enjoyment: $enjoyment)
                ManualWorkoutEvidenceSection(
                    photoItem: $photoItem,
                    photoData: $photoData,
                    photoImage: $photoImage,
                    notes: $notes
                )
            }
            .scrollContentBackground(.hidden)
            .background(TempoTheme.background)
            .navigationTitle("Antrenman ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ManualWorkoutToolbar(isSaving: isSaving, onCancel: { dismiss() }, onSave: saveTapped)
            }
            .onChange(of: photoItem) { _, item in
                Task { await loadPhoto(item) }
            }
            .alert(errorTitle.tempoLocalized, isPresented: $showingError) {
                Button("Tamam") { dismiss() }
            } message: {
                Text(errorMessage ?? "Fotoğraf tek başına yeterli değil. Antrenman saatinde anlamlı bir hareket veya Sağlık sinyali bulunamadı.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        let bounded = image.preparingThumbnail(of: CGSize(width: 1400, height: 1400)) ?? image
        photoData = bounded.jpegData(compressionQuality: 0.78)
        photoImage = photoData.flatMap { UIImage(data: $0) }
    }

    private func saveTapped() {
        Task { await saveWorkout() }
    }

    @MainActor
    private func saveWorkout() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await model.addManualWorkout(
                sportId: sportId,
                sportTitle: sportTitle,
                title: title,
                startedAt: startedAt,
                durationMinutes: durationMinutes,
                notes: notes,
                photoData: photoData,
                perceivedEffort: perceivedEffort,
                enjoyment: enjoyment
            )
            dismiss()
        } catch {
            errorTitle = "Antrenman kaydedilemedi"
            errorMessage = error.localizedDescription.tempoLocalized
            showingError = true
        }
    }
}

private struct ManualWorkoutFeedbackSection: View {
    @Binding var effort: Int?
    @Binding var enjoyment: Int?

    var body: some View {
        Section {
            ratingRow(title: "Ne kadar zor hissettirdi?", selection: $effort, labels: ["Çok kolay", "Kolay", "Orta", "Zor", "Çok zor"])
            ratingRow(title: "Ne kadar keyif aldın?", selection: $enjoyment, labels: ["Hiç", "Az", "Orta", "İyi", "Çok"])
            Text("Bu geri bildirim yalnızca bu cihazdaki antrenman kaydında tutulur ve sonraki önerileri yumuşatmaya yardımcı olur.")
                .font(.caption2).foregroundStyle(TempoTheme.secondary)
        } header: {
            Text("Antrenman sonrası kısa not")
        }
    }

    private func ratingRow(title: String, selection: Binding<Int?>, labels: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.tempoLocalized).font(.subheadline.weight(.medium))
                Spacer()
                if selection.wrappedValue != nil {
                    Button("Temizle") { selection.wrappedValue = nil }
                        .font(.caption).foregroundStyle(TempoTheme.green)
                }
            }
            HStack(spacing: 7) {
                ForEach(1...5, id: \.self) { score in
                    Button {
                        selection.wrappedValue = selection.wrappedValue == score ? nil : score
                    } label: {
                        Text(labels[score - 1].tempoLocalized)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1).minimumScaleFactor(0.65)
                            .foregroundStyle(selection.wrappedValue == score ? .black : TempoTheme.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(selection.wrappedValue == score ? TempoTheme.green : TempoTheme.raised, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("%@, %d".tempoFormatted(title, score))
                    .accessibilityAddTraits(selection.wrappedValue == score ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ManualWorkoutToolbar: ToolbarContent {
    let isSaving: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("İptal", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(isSaving ? "Kaydediliyor…" : "Kaydet", action: onSave)
                .disabled(isSaving)
        }
    }
}

private struct ManualWorkoutDetailsSection: View {
    @Binding var sportId: String
    @Binding var title: String
    @Binding var startedAt: Date
    @Binding var durationMinutes: Int

    var body: some View {
        Section("Antrenman") {
            Picker("Spor", selection: $sportId) {
                ForEach(TempoSportChoice.allCases) { choice in
                    ManualWorkoutSportPickerOption(choice: choice)
                        .tag(choice.rawValue)
                }
                Label("Diğer", systemImage: "figure.mixed.cardio")
                    .tag("other")
            }
            TextField("Antrenman adı (isteğe bağlı)", text: $title)
            DatePicker("Başlangıç zamanı", selection: $startedAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
            Stepper("Süre: %d dk".tempoFormatted(durationMinutes), value: $durationMinutes, in: 5...360, step: 5)
        }
    }
}

private struct ManualWorkoutEvidenceSection: View {
    @Binding var photoItem: PhotosPickerItem?
    @Binding var photoData: Data?
    @Binding var photoImage: UIImage?
    @Binding var notes: String

    var body: some View {
        Section("Fotoğraf ve notlar") {
            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                Label(photoData == nil ? "Antrenman fotoğrafı ekle (isteğe bağlı)" : "Fotoğraf eklendi · değiştir", systemImage: "photo.badge.plus")
            }
            if let previewImage = photoImage {
                ManualWorkoutPhotoPreview(image: previewImage)
                Button("Fotoğrafı kaldır", role: .destructive) {
                    photoData = nil
                    photoImage = nil
                    photoItem = nil
                }
            }
            TextField("Not (isteğe bağlı)", text: $notes, axis: .vertical).lineLimit(2...5)
            Text("Apple Watch gerekmez; iPhone’un hareket sensörü de adım ölçebilir. Kaydetmek için antrenman saatinde anlamlı bir hareket veya Sağlık sinyali gerekir. Fotoğraf tek başına yeterli değildir; ölçümler kesin doğrulama sayılmaz ve kayıtlar cihazda kalır.")
                .font(.caption).foregroundStyle(TempoTheme.secondary)
            Text("iPhone adım ölçümü için Hareket ve Fitness izni gerekebilir. iPhone sensöründeki adım geçmişi son 7 gün için sorgulanabilir.")
                .font(.caption2).foregroundStyle(TempoTheme.secondary)
        }
    }
}

private struct ManualWorkoutPhotoPreview: View {
    let image: UIImage

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ManualWorkoutSportPickerOption: View {
    let choice: TempoSportChoice

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: choice.symbol)
            Text(choice.title)
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
                Label("View on Strava", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity)
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
                                Text("SON AKTİVİTE".tempoSentenceCased)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(TempoTheme.secondary)
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
                            Text("Dönemlere göre gruplanmış %d aktivite".tempoFormatted(activities.count))
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
    let sport: TempoSport?

    static let all = ActivityTimelineFilter(id: "all", title: "Tümü", sport: nil)
    static let other = ActivityTimelineFilter(id: "other", title: "Diğer", sport: nil)

    static func sport(_ sport: TempoSport) -> ActivityTimelineFilter {
        ActivityTimelineFilter(id: "sport:\(sport)", title: sport.title, sport: sport)
    }

    func matches(_ activity: TempoActivity) -> Bool {
        switch id {
        case Self.all.id:
            return true
        case Self.other.id:
            return activity.sport != .run && activity.sport != .ride && activity.sport != .walk
        default:
            guard let sport else { return false }
            return activity.sport == sport
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
        let coreSports: [TempoSport] = [.run, .ride, .walk]
        let otherSports = Set(activities.map(\.sport))
            .subtracting(Set(coreSports))
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            .map(ActivityTimelineFilter.sport)
        return [.all]
            + coreSports.map(ActivityTimelineFilter.sport)
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
                        Text("AKTİVİTE ARŞİVİ".tempoSentenceCased)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TempoTheme.secondary)
                        Text("Ritmini dönemlere göre incele.")
                            .font(.system(size: 28, weight: .bold, design: .rounded))

                        HStack(spacing: 9) {
                            MetricCard(value: "\(filteredActivities.count)", label: "Aktivite", icon: "figure.run", color: TempoTheme.green)
                            MetricCard(value: TempoFormat.distance(totalDistance), label: "Mesafe", icon: "arrow.left.and.right", color: TempoTheme.orange)
                            MetricCard(value: TempoFormat.duration(totalSeconds), label: "Süre", icon: "clock.fill", color: TempoTheme.blue)
                        }
                        if totalElevation > 0 {
                            Label("Toplam %@ m tırmanış".tempoFormatted(Int(totalElevation).formatted()), systemImage: "mountain.2.fill")
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
                if !model.isConnected {
                    StravaOptionalCard(
                        title: "Rotalarını görmek için Strava’yı bağla",
                        message: "Strava bağlantısı isteğe bağlı; bağladığında GPS rotaların burada görünür."
                    )
                } else {
                TempoCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("HARİTADA GÖSTER".tempoSentenceCased).font(.caption.weight(.semibold)).foregroundStyle(TempoTheme.secondary)
                            Text((selected?.name ?? "Tüm rotalar").tempoLocalized).font(.headline).lineLimit(1)
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
                    Text(selected == nil ? "%d GPS rotası gösteriliyor.".tempoFormatted(routes.count) : "Seçili rotayı yakınlaştırıp inceleyebilirsin.".tempoLocalized)
                        .font(.footnote).foregroundStyle(TempoTheme.secondary)
                }
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
    @State private var messages: [TempoCoachMessage] = []
    @State private var draft = ""
    @State private var includeHealth = false
    @FocusState private var composerFocused: Bool
    private let suggestions = ["Bugün nasıl antrenman yapayım?", "Dinlenme gününde ne yapabilirim?", "Koşuya yeni başlıyorum; nasıl ilerleyeyim?", "Uyku toparlanmayı nasıl etkiler?"]

    var body: some View {
        TempoPage {
            PageTitle(title: "Tempo Koç", subtitle: "Spor ve sağlıklı yaşam için sohbet asistanın")
            if messages.isEmpty {
                TempoCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .foregroundStyle(TempoTheme.green)
                        Text("Nereden başlamak istersin?")
                            .font(.title3.bold())
                        Text("Antrenman, toparlanma, uyku veya günlük iyi oluş hakkında dilediğini sor. Strava hesabı gerekmiyor.")
                            .font(.subheadline)
                            .foregroundStyle(TempoTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 9) {
                    Text("Örnek sorular".tempoSentenceCased).font(.caption2.bold()).tracking(1.1).foregroundStyle(TempoTheme.secondary)
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button { send(suggestion) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.up.left")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(TempoTheme.green)
                                Text(suggestion.tempoLocalized)
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.9))
                                Spacer()
                            }
                            .padding(13)
                            .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                HStack {
                    Label("Sohbet", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TempoTheme.secondary)
                    Spacer()
                    Button("Yeni sohbet") { messages.removeAll(); draft = "" }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TempoTheme.green)
                }
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(messages) { message in
                                chatBubble(message)
                                    .id(message.id)
                            }
                            if model.isCoachLoading {
                                HStack {
                                    ProgressView().tint(TempoTheme.green)
                                    Text("Tempo Koç düşünüyor…".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
                                    Spacer()
                                }
                                .padding(13)
                                .id("coach-loading")
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(minHeight: 220, maxHeight: 430)
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last { withAnimation { reader.scrollTo(last.id, anchor: .bottom) } }
                    }
                    .onChange(of: model.isCoachLoading) { _, loading in
                        if loading { withAnimation { reader.scrollTo("coach-loading", anchor: .bottom) } }
                    }
                }
            }

            TempoCard {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $includeHealth) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Apple Sağlık özetimi kullan".tempoLocalized)
                                .font(.subheadline.weight(.semibold))
                            Text((model.healthSyncEnabled ? "Yalnızca bu sohbet isteğinde paylaşılır." : "Kişisel sağlık ölçüsü eklemek için önce Apple Sağlık’ı bağla.").tempoLocalized)
                                .font(.caption)
                                .foregroundStyle(TempoTheme.secondary)
                        }
                    }
                    .tint(TempoTheme.green)
                    .disabled(!model.healthSyncEnabled)
                    Text("Kapalıyken Apple Sağlık verin gönderilmez. Sohbet geçmişi sunucuda saklanmaz. Strava verileri bu asistana aktarılmaz.".tempoLocalized)
                        .font(.caption2)
                        .foregroundStyle(TempoTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(alignment: .bottom, spacing: 9) {
                TextField("Tempo Koç’a bir şey sor…".tempoLocalized, text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(TempoTheme.raised, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                    .onSubmit { send() }
                Button { send() } label: {
                    Group {
                        if model.isCoachLoading { ProgressView().tint(.black) }
                        else { Image(systemName: "arrow.up").font(.headline.bold()) }
                    }
                    .frame(width: 46, height: 46)
                    .foregroundStyle(.black)
                    .background(TempoTheme.green, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(model.isCoachLoading || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(model.isCoachLoading || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
            }
            Text("Genel bilgilendirme içindir; tıbbi tanı veya tedavi yerine geçmez.".tempoLocalized)
                .font(.caption2)
                .foregroundStyle(TempoTheme.secondary)
        }
        .navigationTitle("Tempo Koç")
        .navigationBarTitleDisplayMode(.inline)
        .tempoGlassBackButton()
    }

    @ViewBuilder
    private func chatBubble(_ message: TempoCoachMessage) -> some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 36) }
            Text(message.content)
                .font(.subheadline)
                .lineSpacing(4)
                .textSelection(.enabled)
                .padding(13)
                .background(
                    message.role == "user" ? TempoTheme.green.opacity(0.18) : TempoTheme.card,
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                )
                .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(.white.opacity(0.06)))
            if message.role != "user" { Spacer(minLength: 36) }
        }
    }

    private func send(_ suggested: String? = nil) {
        let text = (suggested ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !model.isCoachLoading else { return }
        draft = ""
        composerFocused = false
        let updated = Array((messages + [TempoCoachMessage(role: "user", content: text)]).suffix(12))
        messages = updated
        Task {
            do {
                let answer = try await model.askSportsChat(messages: updated, includeHealth: includeHealth)
                messages.append(TempoCoachMessage(role: "assistant", content: answer))
                if messages.count > 12 { messages = Array(messages.suffix(12)) }
            } catch {
                messages.append(TempoCoachMessage(role: "assistant", content: "Yanıt alınamadı: %@".tempoFormatted(error.localizedDescription.tempoLocalized)))
            }
        }
    }
}

private enum SocialSection: String, CaseIterable, Identifiable {
    case overview
    case friends
    case challenges

    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "Genel"
        case .friends: return "Arkadaşlar"
        case .challenges: return "Yarışmalar"
        }
    }
}

private struct SocialScreen: View {
    @EnvironmentObject private var account: TempoAccountStore
    @EnvironmentObject private var model: TempoAppModel
    @State private var snapshot: TempoSocialSnapshot?
    @State private var username = ""
    @State private var title = ""
    @State private var metric: TempoSocialMetric = .steps
    @State private var selectedFriends: Set<String> = []
    @State private var selectedSection: SocialSection = .overview
    @State private var loading = false
    @State private var working = false
    @State private var notice = ""
    @State private var pendingBlockProfile: TempoSocialProfile?
    @State private var showBlockConfirmation = false

    private var friends: [TempoSocialProfile] { snapshot?.friends ?? [] }
    private var challenges: [TempoSocialChallenge] { snapshot?.challenges ?? [] }
    private var featuredChallenges: [TempoSocialChallenge] {
        Array(challenges.filter { $0.myStatus == "accepted" || $0.myStatus == "invited" }.prefix(2))
    }

    var body: some View {
        TempoPage {
            PageTitle(title: "Sosyal", subtitle: "Arkadaşlarınla hareket et")
            socialIntro
            Picker("Sosyal bölümü", selection: $selectedSection) {
                ForEach(SocialSection.allCases) { section in
                    Text(section.title.tempoLocalized).tag(section)
                }
            }
            .pickerStyle(.segmented)

            if !notice.isEmpty {
                Text(notice).font(.caption).foregroundStyle(TempoTheme.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            if loading && snapshot == nil {
                ProgressView().tint(TempoTheme.green).frame(maxWidth: .infinity).padding(22)
            } else if snapshot == nil, !notice.isEmpty {
                TempoCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Sosyal bilgiler yüklenemedi", systemImage: "wifi.exclamationmark").font(.subheadline.weight(.semibold))
                        Button("Tekrar dene") { Task { await refresh() } }.buttonStyle(TempoSecondaryButtonStyle())
                    }
                }
            } else {
                switch selectedSection {
                case .overview: overviewSection
                case .friends: friendsSection
                case .challenges: challengesSection
                }
            }
        }
        .navigationTitle("Sosyal").navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
        .task { await refresh() }
        .confirmationDialog("Bu kullanıcıyı engelle?", isPresented: $showBlockConfirmation, titleVisibility: .visible) {
            Button("Engelle", role: .destructive) {
                if let profile = pendingBlockProfile { Task { await setBlocked(profile, blocked: true) } }
            }
            Button("Vazgeç", role: .cancel) { pendingBlockProfile = nil }
        } message: {
            Text("Engellenen hesap arkadaş listesinden ve ortak yarışmalarından kaldırılır.")
        }
    }

    private var socialIntro: some View {
        TempoCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    Image(systemName: "person.2.wave.2.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(TempoTheme.green)
                        .frame(width: 38, height: 38)
                        .background(TempoTheme.green.opacity(0.13), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Birlikte, kendi ritminizde").font(.subheadline.weight(.semibold))
                        Text("Arkadaş bul, yarış başlat, ilerlemeni paylaş.").font(.caption).foregroundStyle(TempoTheme.secondary)
                    }
                    Spacer(minLength: 0)
                }
                Text("Apple Sağlık özeti her yarış için ayrı ve varsayılan olarak kapalıdır. Skorlar bağımsız doğrulanmaz; yarışmalar arkadaşlar arasında eğlence amaçlıdır. Strava gerekmez.")
                    .font(.caption2).foregroundStyle(TempoTheme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                SocialStatTile(title: "Arkadaş", value: friends.count, icon: "person.2.fill", color: TempoTheme.green)
                SocialStatTile(title: "Yarış", value: challenges.filter { $0.myStatus == "accepted" || $0.myStatus == "invited" }.count, icon: "trophy.fill", color: TempoTheme.orange)
                SocialStatTile(title: "Gelen istek", value: snapshot?.incoming.count ?? 0, icon: "person.badge.plus", color: TempoTheme.blue)
            }

            if !model.healthSyncEnabled {
                NavigationLink(destination: HealthScreen()) {
                    Label("Yarışma skorları için Apple Sağlık’ı bağla", systemImage: "heart.text.square.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.pink).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14).background(.pink.opacity(0.10), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                }.buttonStyle(.plain)
            }

            if !(snapshot?.incoming.isEmpty ?? true) {
                VStack(alignment: .leading, spacing: 9) {
                    SectionHeading(title: "Bekleyen istekler", caption: "%d YENİ".tempoFormatted(snapshot?.incoming.count ?? 0), padding: false)
                    ForEach(Array((snapshot?.incoming ?? []).prefix(2))) { request in
                        TempoCard {
                            VStack(spacing: 10) {
                                SocialPersonRow(profile: request.user, detail: "@\(request.user.username)")
                                HStack {
                                    Button("Kabul et") { Task { await answer(request, accept: true) } }
                                        .buttonStyle(TempoPrimaryButtonStyle()).disabled(working)
                                    Button("Reddet") { Task { await answer(request, accept: false) } }
                                        .buttonStyle(TempoSecondaryButtonStyle()).disabled(working)
                                }
                            }
                        }
                    }
                    if (snapshot?.incoming.count ?? 0) > 2 {
                        Button("Tüm istekleri gör") { selectedSection = .friends }
                            .font(.caption.weight(.semibold)).foregroundStyle(TempoTheme.green)
                    }
                }
            }

            HStack {
                SectionHeading(title: "Arkadaşların", caption: "%d KİŞİ".tempoFormatted(friends.count), padding: false)
                Spacer()
                Button { selectedSection = .friends } label: {
                    Label("Arkadaş bul", systemImage: "plus")
                        .font(.caption.weight(.semibold)).foregroundStyle(TempoTheme.green)
                }
            }
            if friends.isEmpty {
                EmptyCard(icon: "person.2", text: "Henüz arkadaş yok. Kullanıcı adıyla bir istek göndererek başlayabilirsin.")
            } else {
                ForEach(Array(friends.prefix(3))) { friend in
                    SocialPersonRow(profile: friend, detail: "@\(friend.username)")
                        .padding(11).background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                }
                if friends.count > 3 {
                    Button("%d arkadaşın tümünü gör".tempoFormatted(friends.count)) { selectedSection = .friends }
                        .font(.caption.weight(.semibold)).foregroundStyle(TempoTheme.green)
                }
            }

            HStack {
                SectionHeading(title: "Bu haftanın yarışları", caption: "%d AKTİF".tempoFormatted(challenges.filter { $0.myStatus == "accepted" }.count), padding: false)
                Spacer()
                Button { selectedSection = .challenges } label: {
                    Label("Yarışlar", systemImage: "arrow.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(TempoTheme.orange)
                }
            }
            if featuredChallenges.isEmpty {
                EmptyCard(icon: "trophy", text: "Henüz aktif yarışma yok. Arkadaşlarınla haftalık bir hedef başlat.")
                if !friends.isEmpty {
                    Button { selectedSection = .challenges } label: {
                        Label("İlk yarışmanı oluştur", systemImage: "flag.checkered").frame(maxWidth: .infinity)
                    }.buttonStyle(TempoPrimaryButtonStyle())
                }
            } else {
                ForEach(featuredChallenges) { challenge in challengeCard(challenge) }
            }
        }
    }

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 9) {
                SectionHeading(title: "Arkadaş ekle", caption: "TEMPO KULLANICI ADI", padding: false)
                HStack(spacing: 9) {
                    TextField("Kullanıcı adı", text: $username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(13).background(TempoTheme.raised, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .submitLabel(.send)
                        .onSubmit { Task { await sendRequest() } }
                    Button { Task { await sendRequest() } } label: {
                        if working { ProgressView().tint(.black).frame(width: 46, height: 46) }
                        else { Image(systemName: "person.badge.plus").foregroundStyle(.black).frame(width: 46, height: 46) }
                    }
                    .background(TempoTheme.green, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .disabled(working || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Arkadaşlık isteği gönder")
                }
                Text("@ işaretiyle veya işaretsiz Tempo kullanıcı adını yazabilirsin.")
                    .font(.caption2).foregroundStyle(TempoTheme.secondary)
            }

            if !(snapshot?.incoming.isEmpty ?? true) {
                VStack(alignment: .leading, spacing: 9) {
                    SectionHeading(title: "Arkadaşlık istekleri", caption: "GELEN", padding: false)
                    ForEach(snapshot?.incoming ?? []) { request in
                        TempoCard {
                            VStack(spacing: 10) {
                                SocialPersonRow(profile: request.user, detail: "@\(request.user.username)")
                                HStack {
                                    Button("Kabul et") { Task { await answer(request, accept: true) } }.buttonStyle(TempoPrimaryButtonStyle())
                                    Button("Reddet") { Task { await answer(request, accept: false) } }.buttonStyle(TempoSecondaryButtonStyle())
                                }
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    SectionHeading(title: "Arkadaşların", caption: "%d KİŞİ".tempoFormatted(friends.count), padding: false)
                    Spacer()
                    Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise").foregroundStyle(TempoTheme.green) }
                        .accessibilityLabel("Arkadaş listesini yenile")
                }
                if friends.isEmpty {
                    EmptyCard(icon: "person.2", text: "Henüz arkadaş yok. Kullanıcı adıyla bir istek göndererek başlayabilirsin.")
                } else {
                    ForEach(friends) { friend in
                        Button {
                            if selectedFriends.contains(friend.id) { selectedFriends.remove(friend.id) }
                            else { selectedFriends.insert(friend.id) }
                        } label: {
                            HStack {
                                SocialPersonRow(profile: friend, detail: "@\(friend.username)")
                                Image(systemName: selectedFriends.contains(friend.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedFriends.contains(friend.id) ? TempoTheme.green : TempoTheme.secondary)
                            }
                            .padding(10).background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .contextMenu { safetyMenu(for: friend) }
                    }
                }
            }

            if !(snapshot?.outgoing.isEmpty ?? true) {
                TempoCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Gönderilen istekler").font(.subheadline.bold())
                        ForEach(snapshot?.outgoing ?? []) { request in SocialPersonRow(profile: request.user, detail: "İstek bekliyor") }
                    }
                }
            }
            if !(snapshot?.blocked.isEmpty ?? true) {
                VStack(alignment: .leading, spacing: 9) {
                    SectionHeading(title: "Engellenen hesaplar", caption: "%d KİŞİ".tempoFormatted(snapshot?.blocked.count ?? 0), padding: false)
                    ForEach(snapshot?.blocked ?? []) { profile in
                        TempoCard {
                            HStack {
                                SocialPersonRow(profile: profile, detail: "Engellendi")
                                Button("Engeli kaldır") { Task { await setBlocked(profile, blocked: false) } }
                                    .font(.caption.weight(.semibold)).foregroundStyle(TempoTheme.green).disabled(working)
                            }
                        }
                    }
                }
            }
        }
    }

    private var challengesSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            if !model.healthSyncEnabled {
                NavigationLink(destination: HealthScreen()) {
                    Label("Yarışma skorları için Apple Sağlık’ı bağla", systemImage: "heart.text.square.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.pink).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14).background(.pink.opacity(0.10), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                }.buttonStyle(.plain)
            }

            if !friends.isEmpty {
                TempoCard {
                    VStack(alignment: .leading, spacing: 11) {
                        Label("Haftalık yarış oluştur", systemImage: "trophy.fill").font(.headline).foregroundStyle(TempoTheme.orange)
                        TextField("Yarışma adı", text: $title).padding(12).background(TempoTheme.raised, in: RoundedRectangle(cornerRadius: 14))
                        Picker("Hedef", selection: $metric) {
                            ForEach(TempoSocialMetric.allCases) { option in Label(option.title, systemImage: option.symbol).tag(option) }
                        }.pickerStyle(.menu)
                        if metric == .movementDays {
                            Text("Hareket günü, en az 3.000 adım veya 10 dakika egzersiz olarak sayılır.")
                                .font(.caption2).foregroundStyle(TempoTheme.secondary)
                        }
                        Button { selectedSection = .friends } label: {
                            HStack {
                                Label(selectedFriends.isEmpty ? "Arkadaş seç" : "%d arkadaş seçildi".tempoFormatted(selectedFriends.count), systemImage: "person.2.fill")
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.weight(.bold))
                            }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(TempoTheme.green)
                            .padding(12).background(TempoTheme.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        Button { Task { await createChallenge() } } label: {
                            Label("Seçilenlerle yarışı başlat", systemImage: "flag.checkered").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(TempoPrimaryButtonStyle())
                        .disabled(working || selectedFriends.isEmpty || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            } else {
                TempoCard {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("Önce arkadaşlarını ekle", systemImage: "person.2.fill").font(.headline).foregroundStyle(TempoTheme.orange)
                        Text("Bir yarışma başlatmak için Arkadaşlar bölümünden Tempo kullanıcı adıyla istek gönder.")
                            .font(.caption).foregroundStyle(TempoTheme.secondary)
                        Button { selectedSection = .friends } label: {
                            Label("Arkadaş bul", systemImage: "person.badge.plus").frame(maxWidth: .infinity)
                        }.buttonStyle(TempoSecondaryButtonStyle())
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeading(title: "Yarışmalar", caption: "APPLE SAĞLIK · İSTEĞE BAĞLI", padding: false)
                    Spacer()
                    Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise").foregroundStyle(TempoTheme.green) }
                        .accessibilityLabel("Yarışmaları yenile")
                }
                if challenges.isEmpty {
                    EmptyCard(icon: "trophy", text: "Aktif yarışma yok. Arkadaş ekleyip haftalık bir hedef başlat.")
                }
                ForEach(challenges) { challenge in challengeCard(challenge) }
            }
        }
    }

    private func challengeCard(_ challenge: TempoSocialChallenge) -> some View {
        SocialChallengeCard(challenge: challenge, isWorking: working, healthConnected: model.healthSyncEnabled) { action in
            Task { await updateChallenge(challenge, action: action) }
        } onShareChange: { enabled in
            Task { await shareHealth(challenge, enabled: enabled) }
        } onReport: { category in
            Task { await reportChallenge(challenge, category: category) }
        }
    }

    private func refresh(clearNotice: Bool = true) async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        do {
            snapshot = try await account.loadSocial()
            selectedFriends.formIntersection(Set(snapshot?.friends.map(\.id) ?? []))
            if clearNotice { notice = "" }
        } catch { notice = error.localizedDescription.tempoLocalized }
    }

    private func sendRequest() async {
        guard !working else { return }
        working = true; defer { working = false }
        do {
            let becameFriends = try await account.sendFriendRequest(username: username.trimmingCharacters(in: .whitespacesAndNewlines))
            username = ""
            notice = becameFriends ? "Karşılıklı istek eşleşti; artık arkadaşsınız." : "Arkadaşlık isteği gönderildi."
            await refresh(clearNotice: false)
        }
        catch { notice = error.localizedDescription.tempoLocalized }
    }

    private func answer(_ request: TempoSocialRequest, accept: Bool) async {
        guard !working else { return }
        working = true; defer { working = false }
        do { try await account.respondToFriendRequest(id: request.id, accept: accept); notice = accept ? "Arkadaşlık isteği kabul edildi." : "Arkadaşlık isteği reddedildi."; await refresh(clearNotice: false) }
        catch { notice = error.localizedDescription.tempoLocalized }
    }

    private func createChallenge() async {
        guard !working else { return }
        working = true; defer { working = false }
        do {
            try await account.createSocialChallenge(title: title, metric: metric, friendIds: Array(selectedFriends))
            title = ""; selectedFriends.removeAll(); notice = "Haftalık yarışma oluşturuldu."; await refresh()
        } catch { notice = error.localizedDescription.tempoLocalized }
    }

    private func updateChallenge(_ challenge: TempoSocialChallenge, action: String) async {
        guard !working else { return }
        working = true; defer { working = false }
        do { try await account.respondToSocialChallenge(id: challenge.id, action: action); notice = "Yarışma davetin güncellendi."; await refresh() }
        catch { notice = error.localizedDescription.tempoLocalized }
    }

    private func shareHealth(_ challenge: TempoSocialChallenge, enabled: Bool) async {
        guard !working else { return }
        working = true; defer { working = false }
        do { try await account.setSocialChallengeHealthSharing(id: challenge.id, enabled: enabled); notice = "Yarışma paylaşım tercihin kaydedildi."; await refresh() }
        catch { notice = error.localizedDescription.tempoLocalized }
    }

    @ViewBuilder
    private func safetyMenu(for profile: TempoSocialProfile) -> some View {
        Menu("Kullanıcıyı bildir", systemImage: "flag") {
            Button("Taciz veya nefret", systemImage: "hand.raised") { Task { await reportUser(profile, category: "harassment") } }
            Button("Spam", systemImage: "envelope.badge") { Task { await reportUser(profile, category: "spam") } }
            Button("Taklit", systemImage: "person.crop.circle.badge.exclamationmark") { Task { await reportUser(profile, category: "impersonation") } }
            Button("Uygunsuz içerik", systemImage: "exclamationmark.bubble") { Task { await reportUser(profile, category: "inappropriate") } }
        }
        Button("Engelle", systemImage: "hand.raised.fill", role: .destructive) {
            pendingBlockProfile = profile
            showBlockConfirmation = true
        }
    }

    private func setBlocked(_ profile: TempoSocialProfile, blocked: Bool) async {
        guard !working else { return }
        working = true; defer { working = false }
        do {
            try await account.setSocialBlock(userId: profile.id, blocked: blocked)
            notice = blocked ? "Kullanıcı engellendi." : "Engel kaldırıldı."
            pendingBlockProfile = nil
            await refresh()
        } catch { notice = error.localizedDescription.tempoLocalized }
    }

    private func reportUser(_ profile: TempoSocialProfile, category: String) async {
        guard !working else { return }
        working = true; defer { working = false }
        do {
            try await account.reportSocialUser(userId: profile.id, category: category)
            notice = "Bildirim inceleme kuyruğuna gönderildi."
        } catch { notice = error.localizedDescription.tempoLocalized }
    }

    private func reportChallenge(_ challenge: TempoSocialChallenge, category: String) async {
        guard !working else { return }
        working = true; defer { working = false }
        do {
            try await account.reportSocialChallenge(id: challenge.id, category: category)
            notice = "Bildirim inceleme kuyruğuna gönderildi."
        } catch { notice = error.localizedDescription.tempoLocalized }
    }
}

private struct SocialPersonRow: View {
    let profile: TempoSocialProfile
    let detail: String
    var body: some View {
        HStack(spacing: 10) {
            Text(String(profile.displayName.prefix(1)).uppercased()).font(.headline.bold()).foregroundStyle(TempoTheme.green)
                .frame(width: 40, height: 40).background(TempoTheme.green.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(detail).font(.caption).foregroundStyle(TempoTheme.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct SocialStatTile: View {
    let title: String
    let value: Int
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
                    .frame(width: 29, height: 29)
                    .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Spacer(minLength: 2)
                Text(value.formatted())
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(TempoTheme.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(.white.opacity(0.06), lineWidth: 1))
    }
}

private struct SocialParticipantRow: View {
    let participant: TempoSocialParticipant
    let rank: Int
    let myUserId: String
    let metric: TempoSocialMetric
    let maxScore: Int

    private var isCurrentUser: Bool { participant.userId == myUserId }
    private var status: String {
        if isCurrentUser { return "Sen" }
        if participant.status == "invited" { return "Davet bekliyor" }
        return participant.shareHealth ? "Paylaşım açık" : "Paylaşım kapalı"
    }
    private var rankColor: Color {
        switch rank {
        case 1: return TempoTheme.orange
        case 2: return TempoTheme.blue
        case 3: return TempoTheme.green
        default: return TempoTheme.secondary
        }
    }
    private var progress: CGFloat {
        guard let score = participant.score, maxScore > 0 else { return 0 }
        return min(max(CGFloat(score) / CGFloat(maxScore), 0), 1)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 9) {
                Text("%d".tempoFormatted(rank))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(rankColor)
                    .frame(width: 23)
                Text(String(participant.user.displayName.prefix(1)).uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isCurrentUser ? .black : TempoTheme.green)
                    .frame(width: 34, height: 34)
                    .background(isCurrentUser ? TempoTheme.green : TempoTheme.green.opacity(0.13), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(participant.user.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(status.tempoLocalized)
                        .font(.caption2)
                        .foregroundStyle(TempoTheme.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let score = participant.score {
                    Text("\(score.formatted()) \(metric.unit)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(isCurrentUser ? TempoTheme.green : .white.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else if participant.status == "accepted" {
                    Text(participant.shareHealth ? "Veri bekleniyor" : "—")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(TempoTheme.secondary)
                }
            }

            if participant.score != nil {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.08))
                        Capsule()
                            .fill(LinearGradient(colors: [TempoTheme.green, TempoTheme.blue], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geometry.size.width * progress)
                    }
                }
                .frame(height: 4)
                .padding(.leading, 32)
                .accessibilityLabel("Yarışma ilerlemesi")
            }
        }
        .padding(10)
        .background(isCurrentUser ? TempoTheme.green.opacity(0.075) : TempoTheme.raised.opacity(0.38), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(isCurrentUser ? TempoTheme.green.opacity(0.22) : .white.opacity(0.04), lineWidth: 1))
    }
}

private struct SocialChallengeCard: View {
    let challenge: TempoSocialChallenge
    let isWorking: Bool
    let healthConnected: Bool
    let onAction: (String) -> Void
    let onShareChange: (Bool) -> Void
    let onReport: (String) -> Void
    private var metric: TempoSocialMetric { TempoSocialMetric(rawValue: challenge.metric) ?? .steps }
    private var sortedParticipants: [TempoSocialParticipant] {
        challenge.participants.sorted {
            if $0.score != $1.score { return ($0.score ?? -1) > ($1.score ?? -1) }
            return $0.user.displayName.localizedStandardCompare($1.user.displayName) == .orderedAscending
        }
    }
    private var leaderScore: Int { sortedParticipants.compactMap(\.score).max() ?? 0 }
    var body: some View {
        TempoCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(challenge.title).font(.headline)
                        Label("7 günlük · %@".tempoFormatted(metric.title), systemImage: metric.symbol).font(.caption).foregroundStyle(TempoTheme.secondary)
                    }
                    Spacer()
                    Menu {
                        Menu("Yarışmayı bildir", systemImage: "flag") {
                            Button("Taciz veya nefret", systemImage: "hand.raised") { onReport("harassment") }
                            Button("Spam", systemImage: "envelope.badge") { onReport("spam") }
                            Button("Taklit", systemImage: "person.crop.circle.badge.exclamationmark") { onReport("impersonation") }
                            Button("Uygunsuz içerik", systemImage: "exclamationmark.bubble") { onReport("inappropriate") }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(TempoTheme.secondary)
                    }
                    Image(systemName: "trophy.fill").foregroundStyle(TempoTheme.orange)
                }
                if challenge.myStatus == "invited" {
                    Text("Bir arkadaşın seni bu haftalık yarışmaya çağırdı.").font(.caption).foregroundStyle(TempoTheme.secondary)
                    HStack {
                        Button("Katıl") { onAction("accept") }.buttonStyle(TempoPrimaryButtonStyle()).disabled(isWorking)
                        Button("Reddet") { onAction("decline") }.buttonStyle(TempoSecondaryButtonStyle()).disabled(isWorking)
                    }
                } else if challenge.myStatus == "accepted" {
                    Button { onShareChange(!challenge.myShareHealth) } label: {
                        Label(challenge.myShareHealth ? "Bu yarışmada Sağlık paylaşımı açık · Kapat" : "Sadece bu yarışmada günlük toplamlarımı paylaş", systemImage: challenge.myShareHealth ? "heart.fill" : "heart")
                            .font(.caption.weight(.semibold)).foregroundStyle(challenge.myShareHealth ? TempoTheme.green : TempoTheme.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).disabled(isWorking || !healthConnected)
                    Text("Paylaşım yalnızca %@ toplamını kapsar. Günlük kayıtların ve diğer Sağlık verilerin görünmez.".tempoFormatted(metric.title.lowercased()))
                        .font(.caption2).foregroundStyle(TempoTheme.secondary).fixedSize(horizontal: false, vertical: true)
                    ForEach(sortedParticipants.indices, id: \.self) { index in
                        let participant = sortedParticipants[index]
                        SocialParticipantRow(participant: participant, rank: index + 1, myUserId: challenge.myUserId, metric: metric, maxScore: leaderScore)
                    }
                    Text("Skorlar yalnızca paylaşmayı açan katılımcılar için görünür.").font(.caption2).foregroundStyle(TempoTheme.secondary)
                }
            }
        }
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
                NavigationLink(destination: TempoProfileShareScreen()) {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.up.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(TempoTheme.green)
                            .frame(width: 42, height: 42)
                            .background(TempoTheme.green.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Profil kartını oluştur")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                            Text("PNG olarak kaydet veya paylaş")
                                .font(.caption).foregroundStyle(TempoTheme.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(TempoTheme.secondary)
                    }
                    .padding(13)
                    .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.07), lineWidth: 1))
                }
                .buttonStyle(.plain)
                if let dashboard = model.dashboard { StravaConnectionCard(dashboard: dashboard) }
                else if model.isConnected { LoadingDashboardCard() }
                else {
                    StravaOptionalCard(
                        title: "Strava bağlantısı isteğe bağlı",
                        message: "İstersen şimdi bağla; aktivitelerin ve Strava’ya özel araçların burada görünür."
                    )
                }
                LazyVGrid(columns: columns, spacing: 12) {
                    MoreLink(title: "Sosyal", subtitle: "Arkadaşlar ve yarışlar", icon: "person.2.fill", color: TempoTheme.green, destination: AnyView(SocialScreen()))
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
                        Text("BAĞLANTI DURUMU".tempoSentenceCased).font(.subheadline.weight(.semibold)).foregroundStyle(TempoTheme.secondary)
                        Text(model.status.tempoLocalized).font(.subheadline).foregroundStyle(TempoTheme.secondary)
                    }
                }
                if model.isConnected {
                    Button(role: .destructive, action: model.disconnect) {
                        Label("Strava bağlantısını kes", systemImage: "rectangle.portrait.and.arrow.right").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TempoSecondaryButtonStyle())
                    .disabled(model.isBusy)
                }
                HStack(spacing: 18) {
                    Link(destination: URL(string: "https://apitempo.com/privacy")!) {
                        Text("Gizlilik Politikası".tempoLocalized)
                    }
                    Link(destination: URL(string: "https://apitempo.com/terms")!) {
                        Text("Kullanım Koşulları".tempoLocalized)
                    }
                }
                .font(.footnote)
                .tint(TempoTheme.secondary)
                .frame(maxWidth: .infinity)
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
                Text(error.tempoLocalized).font(.footnote).foregroundStyle(TempoTheme.orange).frame(maxWidth: .infinity, alignment: .leading)
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
                        Text("Hedef: %d ml".tempoFormatted(model.dailyGoalMl)).font(.caption).foregroundStyle(TempoTheme.secondary)
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
                            AxisValueLabel { if let hours = value.as(Double.self) { Text("%d sa".tempoFormatted(Int(hours))) } }
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
                Text("TEMPO DENGESİ".tempoSentenceCased)
                    .font(.caption.weight(.semibold))
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
                        Text("TEMPO DENGESİ".tempoSentenceCased)
                            .font(.subheadline.weight(.semibold))
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

                Text("Puan; kişisel geçmişindeki uyku, HRV, dinlenik nabız, hareket yükü ve sıvı ölçümlerinden mevcut olanlarla hesaplanır. Tıbbi değerlendirme değildir.".tempoLocalized)
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
            if !model.isConnected {
                StravaOptionalCard(title: "Strava bağlantısı isteğe bağlı", message: "Aylık aktivite istatistiklerini görmek için Strava’yı istediğin zaman bağlayabilirsin.")
            } else if model.dashboard == nil {
                LoadingDashboardCard()
            } else {
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
            if !model.isConnected {
                StravaOptionalCard(title: "Strava bağlantısı isteğe bağlı", message: "Strava profilindeki bisiklet ve ayakkabı kayıtları bağladıktan sonra burada görünür.")
            } else if model.dashboard == nil {
                LoadingDashboardCard()
            } else {
                ForEach(gear) { item in
                    TempoCard {
                        HStack(spacing: 15) {
                            Image(systemName: item.type == "Bisiklet" ? "bicycle" : "shoe.2.fill").font(.title2).foregroundStyle(TempoTheme.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name ?? item.localizedType).font(.headline)
                                Text("\(item.localizedType) · \(TempoFormat.distance((item.distance ?? 0) / 1000))").font(.caption).foregroundStyle(TempoTheme.secondary)
                            }
                            Spacer(); if item.primary == true { Image(systemName: "star.fill").foregroundStyle(TempoTheme.green) }
                        }
                    }
                }
                if gear.isEmpty { EmptyCard(icon: "bicycle", text: "Strava profilinde ekipman bulunamadı.") }
            }
        }.navigationTitle("Ekipman").navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
    }
}

private struct SegmentsScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    var body: some View {
        TempoPage {
            PageTitle(title: "Segmentler", subtitle: "Favori Strava segmentlerin")
            if !model.isConnected {
                StravaOptionalCard(title: "Strava bağlantısı isteğe bağlı", message: "Favori segmentlerin bağladıktan sonra burada listelenir.")
            } else if model.dashboard == nil {
                LoadingDashboardCard()
            } else {
                ForEach(model.dashboard?.segments ?? []) { segment in
                    Link(destination: URL(string: "https://www.strava.com/segments/\(segment.id)")!) {
                        TempoCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(segment.name ?? "İsimsiz segment".tempoLocalized).font(.headline).foregroundStyle(.white)
                                    Text("%@ · %@%% eğim".tempoFormatted(
                                        TempoFormat.distance((segment.distance ?? 0) / 1000),
                                        (segment.averageGrade ?? 0).formatted(.number.precision(.fractionLength(1)))
                                    )).font(.caption).foregroundStyle(TempoTheme.secondary)
                                }
                                Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(TempoTheme.green)
                            }
                        }
                    }.buttonStyle(.plain)
                }
                if model.dashboard?.segments.isEmpty != false { EmptyCard(icon: "flag.checkered", text: "Favori segment bulunamadı.") }
            }
        }.navigationTitle("Segmentler").navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
    }
}

private struct EddingtonScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    private var number: Int { eddingtonNumber(model.dashboard?.activities ?? []) }
    var body: some View {
        TempoPage {
            PageTitle(title: "Eddington Sayısı", subtitle: "Koşu istikrarın")
            if !model.isConnected {
                StravaOptionalCard(title: "Strava bağlantısı isteğe bağlı", message: "Koşu istikrarı hesabın Strava aktivitelerin bağlandığında oluşturulur.")
            } else if model.dashboard == nil {
                LoadingDashboardCard()
            } else {
                TempoCard {
                    VStack(spacing: 16) {
                        Text("\(number)").font(.system(size: 92, weight: .bold, design: .rounded)).foregroundStyle(TempoTheme.green)
                        Text("%d farklı günde en az %d km koştun.".tempoFormatted(number, number)).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                        Text("Bu sayı düzenli ve uzun mesafeli koşular yaptıkça yükselir.").font(.subheadline).foregroundStyle(TempoTheme.secondary).multilineTextAlignment(.center)
                    }.padding(.vertical, 28).frame(maxWidth: .infinity)
                }
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
            PageTitle(title: "%d Özeti".tempoFormatted(Calendar.current.component(.year, from: Date())), subtitle: "Yıl içindeki hareketin")
            if !model.isConnected {
                StravaOptionalCard(title: "Strava bağlantısı isteğe bağlı", message: "Yıllık aktivite özetin Strava verilerini bağladıktan sonra burada görünür.")
            } else if model.dashboard == nil {
                LoadingDashboardCard()
            } else {
                VStack(spacing: 10) {
                    SummaryLine(icon: "figure.run", title: "Aktivite", value: "\(activities.count)", color: TempoTheme.orange)
                    SummaryLine(icon: "arrow.left.and.right", title: "Toplam mesafe", value: TempoFormat.distance(activities.reduce(0) { $0 + $1.distanceKm }), color: TempoTheme.green)
                    SummaryLine(icon: "clock.fill", title: "Hareket süresi", value: TempoFormat.duration(activities.reduce(0) { $0 + $1.movingSeconds }), color: TempoTheme.blue)
                    SummaryLine(icon: "mountain.2.fill", title: "Yükseklik", value: "\(Int(activities.reduce(0) { $0 + $1.elevationMeters })) m", color: TempoTheme.purple)
                    SummaryLine(icon: "trophy.fill", title: "En uzun", value: TempoFormat.distance(activities.map(\.distanceKm).max() ?? 0), color: TempoTheme.orange)
                }
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
            if !model.isConnected {
                StravaOptionalCard(title: "Strava bağlantısı isteğe bağlı", message: "Aktivite fotoğrafların Strava’yı bağladıktan sonra burada görünür.")
            } else if model.dashboard == nil {
                LoadingDashboardCard()
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(model.dashboard?.photos ?? []) { photo in
                        Link(destination: URL(string: "https://www.strava.com/activities/\(photo.activityId)")!) {
                            VStack(alignment: .leading, spacing: 8) {
                                AsyncImage(url: URL(string: photo.image)) { phase in
                                    if let image = phase.image { image.resizable().scaledToFill() }
                                    else { ZStack { TempoTheme.raised; ProgressView() } }
                                }
                                .frame(height: 160).clipped().clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                                Text(photo.activityName ?? "Aktivite".tempoLocalized).font(.caption.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if model.dashboard?.photos.isEmpty != false { EmptyCard(icon: "photo", text: "Gösterilecek aktivite fotoğrafı bulunamadı.") }
            }
        }.navigationTitle("Fotoğraflar").navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
    }
}

struct TempoPage<Content: View>: View {
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

struct PageTitle: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(subtitle.tempoLocalized).font(.subheadline.weight(.medium)).foregroundStyle(TempoTheme.secondary)
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
                        Text("STRAVA HESABI".tempoSentenceCased).font(.caption.weight(.semibold)).foregroundStyle(TempoTheme.orange)
                        Text("BAĞLI".tempoSentenceCased)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(TempoTheme.green)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(TempoTheme.green.opacity(0.12), in: Capsule())
                    }
                    Text(athlete.fullName.isEmpty ? "Strava Sporcusu".tempoLocalized : athlete.fullName)
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
                            .fill(TempoTheme.card.opacity(0.92))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.075), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
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
            Text(caption.tempoLocalized).font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(TempoTheme.secondary)
            Text(title.tempoLocalized).font(.title3.weight(.semibold))
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

struct EmptyCard: View {
    let icon: String; let text: String
    var body: some View {
        VStack(spacing: 11) { Image(systemName: icon).font(.title).foregroundStyle(TempoTheme.secondary); Text(text.tempoLocalized).font(.subheadline).foregroundStyle(TempoTheme.secondary).multilineTextAlignment(.center) }
            .padding(28).frame(maxWidth: .infinity).background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct StravaOptionalCard: View {
    @EnvironmentObject private var model: TempoAppModel
    let title: String
    let message: String

    var body: some View {
        TempoCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 12) {
                    Image(systemName: "figure.run")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(TempoTheme.orange)
                        .frame(width: 44, height: 44)
                        .background(TempoTheme.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Text(title.tempoLocalized)
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                Text(message.tempoLocalized)
                    .font(.subheadline)
                    .foregroundStyle(TempoTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: model.connectStrava) {
                    Label((model.isBusy ? "Strava açılıyor…" : "Strava’yı bağla").tempoLocalized, systemImage: "figure.run")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TempoPrimaryButtonStyle())
                .disabled(model.isBusy)
            }
        }
    }
}

private struct LoadingDashboardCard: View {
    @EnvironmentObject private var model: TempoAppModel
    var body: some View {
        VStack(spacing: 16) {
            if model.dashboardError == nil {
                ProgressView().controlSize(.large).tint(TempoTheme.green)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(TempoTheme.orange)
                    .accessibilityHidden(true)
            }
            Text((model.dashboardError ?? "Strava verilerin hazırlanıyor…").tempoLocalized).foregroundStyle(TempoTheme.secondary).multilineTextAlignment(.center)
            if let details = model.dashboardErrorDetails {
                Text("Tanı: %@".tempoFormatted(details))
                    .font(.caption2.monospaced())
                    .foregroundStyle(TempoTheme.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .accessibilityLabel("Tanı: %@".tempoFormatted(details))
            }
            if model.dashboardError != nil { Button("Yeniden dene") { Task { await model.refreshDashboard() } }.buttonStyle(TempoPrimaryButtonStyle()).disabled(model.isLoadingDashboard) }
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

struct TempoPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(.black).padding(.vertical, 15)
            .background(TempoTheme.green.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}

struct TempoSecondaryButtonStyle: ButtonStyle {
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

