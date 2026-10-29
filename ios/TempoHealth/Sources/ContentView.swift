import Charts
import Combine
import CoreLocation
import MapKit
import PhotosUI
import SwiftUI
import UIKit

enum TempoTheme {
    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light })
    }
    static let background = adaptive(light: UIColor(red: 0.96, green: 0.97, blue: 0.965, alpha: 1), dark: UIColor(red: 0.055, green: 0.058, blue: 0.065, alpha: 1))
    static let card = adaptive(light: .white, dark: UIColor(red: 0.085, green: 0.09, blue: 0.10, alpha: 1))
    static let raised = adaptive(light: UIColor(red: 0.92, green: 0.94, blue: 0.93, alpha: 1), dark: UIColor(red: 0.115, green: 0.12, blue: 0.13, alpha: 1))
    static let green = adaptive(light: UIColor(red: 0.12, green: 0.43, blue: 0.29, alpha: 1), dark: UIColor(red: 0.43, green: 0.77, blue: 0.57, alpha: 1))
    static let orange = adaptive(light: UIColor(red: 0.69, green: 0.27, blue: 0.12, alpha: 1), dark: UIColor(red: 0.91, green: 0.53, blue: 0.37, alpha: 1))
    static let blue = adaptive(light: UIColor(red: 0.16, green: 0.42, blue: 0.52, alpha: 1), dark: UIColor(red: 0.46, green: 0.68, blue: 0.72, alpha: 1))
    static let purple = adaptive(light: UIColor(red: 0.47, green: 0.34, blue: 0.64, alpha: 1), dark: UIColor(red: 0.66, green: 0.59, blue: 0.75, alpha: 1))
    static let primary = Color(uiColor: .label)
    static let secondary = Color(uiColor: .secondaryLabel)
    static let onAccent = adaptive(light: .white, dark: .black)
    static let scrollBottomClearance: CGFloat = 132
}

enum TempoAppearance: String, CaseIterable, Identifiable {
    static let storageKey = "tempo.appearance"
    case system, light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
    var title: String { ("appearance." + rawValue).tempoLocalized }
    var symbol: String {
        switch self { case .system: return "circle.lefthalf.filled"; case .light: return "sun.max.fill"; case .dark: return "moon.fill" }
    }
}

// Ortak yüzey dili: içerik okunaklı kalır, cam yalnız vurgulanan katmanlarda kullanılır.
struct TempoSurface: ViewModifier {
    var glass = false
    var radius: CGFloat = 24
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                if glass && !reduceTransparency {
                    shape.fill(.ultraThinMaterial).background(shape.fill(TempoTheme.card.opacity(0.86)))
                } else { shape.fill(TempoTheme.card) }
            }
            .overlay(shape.strokeBorder(TempoTheme.primary.opacity(contrast == .increased ? 0.28 : 0.08), lineWidth: 1))
            .shadow(color: .black.opacity(scheme == .dark ? 0.12 : 0.045), radius: 16, x: 0, y: 6)
    }
}

struct TempoSoftPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.84 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct TempoMetricGrid<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var textSize
    private let count: Int
    private let content: Content
    init(columns: Int = 3, @ViewBuilder content: () -> Content) {
        self.count = columns
        self.content = content()
    }
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12, alignment: .topLeading), count: textSize.isAccessibilitySize ? 1 : textSize >= .xxxLarge ? min(2, max(1, count)) : max(1, count)), alignment: .leading, spacing: 12) { content }
    }
}

struct TempoDisclosureSection<Content: View>: View {
    let title: String
    let icon: String
    private let content: Content
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.icon = icon; self.content = content()
    }
    var body: some View {
        DisclosureGroup {
            content.padding(.top, 12)
        } label: {
            Label(title.tempoLocalized, systemImage: icon)
                .font(.subheadline.weight(.semibold)).foregroundStyle(TempoTheme.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tint(TempoTheme.green)
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .modifier(TempoSurface())
        .multilineTextAlignment(.leading)
    }
}

private struct TempoMenuRow: View {
    let title: String
    let subtitle: String
    let icon: String
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon).font(.system(size: 17, weight: .medium)).foregroundStyle(TempoTheme.green)
                .frame(width: 38, height: 38).background(TempoTheme.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(title.tempoLocalized).font(.subheadline.weight(.semibold)).foregroundStyle(TempoTheme.primary)
                Text(subtitle.tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
            }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption.weight(.medium)).foregroundStyle(TempoTheme.secondary).accessibilityHidden(true)
        }.padding(.vertical, 14).frame(maxWidth: .infinity, minHeight: 68, alignment: .leading).contentShape(Rectangle()).multilineTextAlignment(.leading)
            .accessibilityElement(children: .combine)
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: TempoAppModel
    @EnvironmentObject private var account: TempoAccountStore
    @State private var selectedTab = 0
    @State private var minimumLaunchFinished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if !minimumLaunchFinished || account.isRestoring {
                TempoLaunchView()
                    .transition(.opacity)
            } else if !account.isAuthenticated {
                AccountWelcomeView()
            } else if account.profile?.onboardingComplete != true {
                AccountOnboardingView()
            } else {
                TempoMainShell(selectedTab: $selectedTab)
            }
        }
        .background(TempoTheme.background.ignoresSafeArea())
        .task {
            do { try await Task.sleep(nanoseconds: reduceMotion ? 200_000_000 : 1_150_000_000) }
            catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                minimumLaunchFinished = true
            }
        }
        .task(id: account.isAuthenticated) {
#if DEBUG
            guard !ProcessInfo.processInfo.arguments.contains("--ui-testing-authenticated") else { return }
#endif
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
        TempoMainTab(id: 4, title: "Profil", icon: "ellipsis.circle", selectedIcon: "ellipsis.circle.fill")
    ]
}

private struct TempoChatTabBarPreference: PreferenceKey {
    static var defaultValue: Bool { false }
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

private struct TempoMainShell: View {
    @Binding var selectedTab: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var notifications = TempoNotifications.shared
    @State private var presentedRoute: NotificationRoute?
    @State private var hidesTabBarForChat = false
    private struct NotificationRoute: Identifiable { let id: String }

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
            NavigationStack { HealthScreen() }
        default:
            MoreScreen()
        }
    }

    var body: some View {
        ZStack {
            // Full-bleed background stays outside the tab animation.
            TempoAmbientBackground()
            selectedScreen
                .id(selectedTab)
                .transition(reduceMotion ? .identity : .opacity)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: selectedTab)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !hidesTabBarForChat {
                    TempoGlassTabBar(selectedTab: $selectedTab)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, 6)
                }
            }
        .onPreferenceChange(TempoChatTabBarPreference.self) { hidesTabBarForChat = $0 }
        .onChange(of: notifications.route, initial: true) { _, nextRoute in
            guard let route = nextRoute else { return }
            switch route {
            case "summary": selectedTab = 0
            case "sports": selectedTab = 2
            default: presentedRoute = NotificationRoute(id: route)
            }
            notifications.route = nil
        }
        .sheet(item: $presentedRoute) { route in
            NavigationStack {
                Group {
                    switch route.id {
                    case "social": SocialScreen()
                    case "achievements": AchievementsScreen()
                    default: TempoNotificationsScreen()
                    }
                }
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Kapat") { presentedRoute = nil } } }
            }
        }
    }
}

private struct TempoGlassTabBar: View {
    @Binding var selectedTab: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var textSize
    @Namespace private var liquidGlassNamespace

    var body: some View {
        Group {
            if reduceTransparency {
                accessibleItems(usesNativeGlass: false).padding(6).background(TempoTheme.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(TempoTheme.primary.opacity(0.18)))
            } else if #available(iOS 26.0, *) {
                GlassEffectContainer {
                    accessibleItems(usesNativeGlass: true)
                        .padding(6)
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
            } else {
                accessibleItems(usesNativeGlass: false)
                    .padding(6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .background(
                        LinearGradient(
                            colors: [TempoTheme.primary.opacity(0.12), TempoTheme.green.opacity(0.045), .black.opacity(0.11)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [TempoTheme.primary.opacity(0.38), TempoTheme.primary.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            }
        }
        .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.88), value: selectedTab)
    }

    @ViewBuilder private func accessibleItems(usesNativeGlass: Bool) -> some View {
        if textSize.isAccessibilitySize {
            ScrollView(.horizontal, showsIndicators: false) { tabItems(usesNativeGlass: usesNativeGlass) }
                .scrollClipDisabled()
        } else { tabItems(usesNativeGlass: usesNativeGlass) }
    }

    private func tabItems(usesNativeGlass: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(TempoMainTab.all) { tab in
                let isSelected = selectedTab == tab.id
                Button {
                    selectedTab = tab.id
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                            .font(.system(size: 18, weight: isSelected ? .semibold : .medium))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(isSelected ? TempoTheme.green : TempoTheme.primary.opacity(0.76))
                            .frame(height: 22)

                        Text(tab.title.tempoLocalized)
                            .font(.caption2.weight(isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? TempoTheme.primary : TempoTheme.primary.opacity(0.64))
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minWidth: textSize.isAccessibilitySize ? 112 : 0, minHeight: 44)
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
                                            colors: [TempoTheme.primary.opacity(0.14), TempoTheme.green.opacity(0.18), TempoTheme.primary.opacity(0.045)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(TempoTheme.primary.opacity(0.22), lineWidth: 0.8)
                                    )
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tab.\(tab.id)")
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
                        .foregroundStyle(TempoTheme.primary.opacity(0.7))
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
        .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(TempoTheme.primary.opacity(0.07)))
    }

    private func trustItem(icon: String, title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(TempoTheme.green)
            Text(title.tempoLocalized)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TempoTheme.primary.opacity(0.7))
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
                    .foregroundStyle(TempoTheme.primary)
                Spacer()
                Text("STRAVA")
                    .font(.caption2.bold()).tracking(1.3).foregroundStyle(TempoTheme.orange)
            }

            HStack(spacing: 13) {
                Image(systemName: "figure.run")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(TempoTheme.primary)
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
                .stroke(LinearGradient(colors: [TempoTheme.primary.opacity(0.16), TempoTheme.primary.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing))
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
                .foregroundStyle(TempoTheme.primary.opacity(0.82))
        }
        .font(.caption.weight(.semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(TempoTheme.primary.opacity(0.045), in: Capsule())
    }
}

private struct HomeScreen: View {
    @EnvironmentObject private var model: TempoAppModel

    private var weekManualWorkouts: [TempoManualWorkout] { model.weekActivityWorkouts }
    private var weekDistance: Double {
        weekManualWorkouts.filter { TempoSport(rawValue: $0.sportId).supportsDistance }
            .reduce(0) { $0 + ($1.distanceKm ?? 0) }
    }
    private var weekSeconds: Double {
        weekManualWorkouts.reduce(0) { $0 + Double($1.durationSeconds ?? $1.durationMinutes * 60) }
    }

    var body: some View {
        NavigationStack {
            TempoPage {
                HomeHeader()
                AppleHealthHomeCard(balance: model.tempoBalance, connected: model.healthSyncEnabled)
                weeklyOverview
                if let error = model.manualWorkoutError {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(TempoTheme.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                quickActions
                if let workout = model.activityWorkouts.first {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Son antrenman".tempoLocalized).font(.headline)
                            Spacer(minLength: 12)
                            NavigationLink(destination: TempoWorkoutHistoryScreen()) {
                                HStack(spacing: 5) {
                                    Text("Tümünü gör".tempoLocalized).font(.caption.weight(.medium))
                                    Image(systemName: "arrow.up.right").font(.caption2.weight(.semibold))
                                }
                                .frame(minHeight: 44).padding(.horizontal, 4)
                            }
                            .buttonStyle(.plain).foregroundStyle(TempoTheme.secondary)
                            .accessibilityLabel("Antrenman geçmişi".tempoLocalized)
                        }
                        TempoCard { ManualWorkoutRow(workout: workout) }
                    }
                }
                TempoDisclosureSection(title: "Strava araçları", icon: "link") {
                    NavigationLink(destination: RoutesScreen()) {
                        TempoMenuRow(title: "Rotalar", subtitle: "Strava’daki kayıtların", icon: "map")
                    }.buttonStyle(.plain)
                    if let dashboard = model.dashboard {
                        RecentActivitiesPanel(activities: dashboard.activities)
                    } else if model.isConnected {
                        LoadingDashboardCard()
                    } else {
                        StravaOptionalCard(title: "Strava bağlantısı isteğe bağlı", message: "Bağladığında Strava kayıtlarını burada ayrı kaynak etiketiyle görebilirsin.")
                    }
                }
                dailyMotivation
            }
            .refreshable { await model.reloadAll() }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var weeklyOverview: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bu hafta".tempoLocalized).font(.headline)
            weeklyMetrics
            NavigationLink(destination: MonthlyStatsScreen()) {
                HStack(spacing: 10) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(TempoTheme.blue)
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                    Text("Aylık ilerlemeni gör".tempoLocalized)
                        .font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(TempoTheme.secondary)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(TempoTheme.primary)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .background(TempoTheme.raised.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain).accessibilityIdentifier("home.monthly")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(TempoSurface(glass: true))
    }

    private var weeklyMetrics: some View {
        TempoMetricGrid {
            HomeWeekMetric(value: "\(weekManualWorkouts.count)", title: "Antrenman", color: TempoTheme.green)
                .accessibilityElement(children: .ignore).accessibilityLabel("Antrenman".tempoLocalized).accessibilityValue("\(weekManualWorkouts.count)").accessibilityIdentifier("home.week.workouts")
            HomeWeekMetric(value: TempoFormat.duration(weekSeconds), title: "Süre", color: TempoTheme.blue)
                .accessibilityElement(children: .ignore).accessibilityLabel("Süre".tempoLocalized).accessibilityValue(TempoFormat.duration(weekSeconds)).accessibilityIdentifier("home.week.duration")
            if weekDistance > 0 {
                HomeWeekMetric(value: TempoFormat.distance(weekDistance), title: "Mesafe", color: TempoTheme.purple)
                    .accessibilityElement(children: .ignore).accessibilityLabel("Mesafe".tempoLocalized).accessibilityValue(TempoFormat.distance(weekDistance)).accessibilityIdentifier("home.week.distance")
            } else {
                HomeWeekMetric(value: "\(Set(weekManualWorkouts.map { Calendar.current.startOfDay(for: $0.startedAt) }).count)", title: "Hareketli gün", color: TempoTheme.purple)
            }
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hızlı erişim".tempoLocalized).font(.headline)
            TempoMetricGrid(columns: 2) {
                HomeQuickAction(title: "Bugün ne yapsam?", icon: "figure.mixed.cardio", color: TempoTheme.green, destination: AnyView(TempoMovementMenuScreen()))
                HomeQuickAction(title: "Tempo Koç", icon: "sparkles", color: TempoTheme.purple, destination: AnyView(CoachScreen()))
                HomeQuickAction(title: "Spor alanları", icon: "mappin.and.ellipse", color: TempoTheme.blue, destination: AnyView(NearbyFacilitiesScreen()))
                HomeQuickAction(title: "Sosyal", icon: "person.2", color: TempoTheme.green, destination: AnyView(SocialScreen()))
            }
            .padding(12)
            .modifier(TempoSurface())
        }
    }

    private var dailyMotivation: some View { DailyMotivationCard(compact: true) }
}

private struct HomeWeekMetric: View {
    let value: String
    let title: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
            Text(title.tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .background(TempoTheme.raised.opacity(0.42), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(color.opacity(0.24), lineWidth: 1))
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
                        .font(.subheadline.weight(.semibold)).foregroundStyle(TempoTheme.primary)
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
            .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(TempoTheme.primary.opacity(0.08)))
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
                        .foregroundStyle(TempoTheme.primary)
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
            .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(TempoTheme.primary.opacity(0.085), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Sosyal alana git")
    }
}

private struct AppleHealthHomeCard: View {
    let balance: TempoBalanceScore?
    let connected: Bool
    @EnvironmentObject private var model: TempoAppModel
    @EnvironmentObject private var account: TempoAccountStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var metrics = SportMetricsStore()
    @State private var currentStrain: Int?

    var body: some View {
        NavigationLink(destination: HealthScreen()) {
            VStack(alignment: .leading, spacing: 14) {
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
                        .foregroundStyle(TempoTheme.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if connected, let balance {
                        Text(balance.state.tempoLocalized + " · " + balance.confidence.tempoLocalized)
                            .font(.caption)
                            .foregroundStyle(TempoTheme.secondary)
                        if let note = balance.dataNote {
                            Text(note).font(.caption2).foregroundStyle(TempoTheme.secondary)
                        }
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
            if connected, let balance { DailyStrainTargetView(balance: balance, current: currentStrain) }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [TempoTheme.purple.opacity(0.11), TempoTheme.card], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 21, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(TempoTheme.primary.opacity(0.075), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .task(id: account.profile?.id) { metrics.bind(account.profile?.id); refreshStrain() }
        .onAppear { metrics.reload(); refreshStrain() }
        .onChange(of: metrics.revision) { _, _ in refreshStrain() }
        .onChange(of: model.activityWorkouts) { _, _ in refreshStrain() }
        .onChange(of: connected) { _, _ in refreshStrain() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { metrics.reload(); refreshStrain() } }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in refreshStrain() }
    }
    private func refreshStrain() { currentStrain = model.dailyStrainSummary(using: metrics).value }
}

private struct TempoReadinessRing: View {
    let value: Int
    var size: CGFloat = 68

    var body: some View {
        ZStack {
            Circle().stroke(TempoTheme.primary.opacity(0.09), lineWidth: 6)
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
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium)).foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                Text(title.tempoLocalized)
                    .font(.subheadline.weight(.medium)).foregroundStyle(TempoTheme.primary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
            .background(color.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(color.opacity(0.12)))
        }
        .buttonStyle(TempoSoftPressStyle())
    }
}

private struct DailyMotivationCard: View {
    var compact = false
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

    @ViewBuilder var body: some View {
        if compact {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "quote.opening").font(.caption2).foregroundStyle(TempoTheme.green)
                    .accessibilityHidden(true)
                Text(message.tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4).padding(.vertical, 6)
        } else {
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
                        .foregroundStyle(TempoTheme.primary.opacity(0.82))
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [TempoTheme.primary.opacity(0.035), TempoTheme.green.opacity(0.035)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(TempoTheme.primary.opacity(0.055))
            )
        }
    }
}

private struct ActivitiesScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    @State private var search = ""
    @State private var deletionError: String?
    @State private var selectedFilter = ActivityTimelineFilter.all
    @State private var isShowingManualWorkoutForm = false
    @State private var isShowingPhoneTracker = false
    @State private var trackingSport = "run"
    private var filterOptions: [ActivityTimelineFilter] {
        let featured: [TempoSport] = [.run, .ride, .walk, .tennis, .basketball, .football, .swim]
        let present = Set(model.activityWorkouts.map { TempoSport(rawValue: $0.sportId) } + (model.dashboard?.activities ?? []).map(\.sport))
        let other = present.subtracting(Set(featured + [.other])).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        return [.all] + featured.map(ActivityTimelineFilter.sport) + other.map(ActivityTimelineFilter.sport) + [.other]
    }
    private var localRecords: [TempoManualWorkout] {
        model.activityWorkouts.filter { workout in
            let sport = TempoSport(rawValue: workout.sportId)
            return selectedFilter.matchesSport(sport) && (search.isEmpty || workout.title.localizedCaseInsensitiveContains(search) || workout.sportTitle.localizedCaseInsensitiveContains(search) || workout.sourceTitle.localizedCaseInsensitiveContains(search))
        }
    }
    private var stravaRecords: [TempoActivity] {
        (model.dashboard?.activities ?? []).filter { selectedFilter.matches($0) && (search.isEmpty || ($0.name ?? "").localizedCaseInsensitiveContains(search) || $0.sport.title.localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        NavigationStack {
            TempoPage {
                PageTitle(title: "Aktiviteler", subtitle: "Tüm antrenman geçmişin")
                TempoCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("record.start".tempoLocalized).font(.headline)
                        Text("record.startHint".tempoLocalized).font(.subheadline).foregroundStyle(TempoTheme.secondary)
                        TempoMetricGrid(columns: 2) {
                            Button { trackingSport = "run"; isShowingPhoneTracker = true } label: { WorkoutEntryActionCard(title: "Koşu", subtitle: "record.routeTimer", icon: "figure.run", color: TempoTheme.green) }.accessibilityIdentifier("activity.record.run")
                            Button { trackingSport = "walking"; isShowingPhoneTracker = true } label: { WorkoutEntryActionCard(title: "Yürüyüş", subtitle: "record.routeTimer", icon: "figure.walk", color: TempoTheme.blue) }.accessibilityIdentifier("activity.record.walk")
                        }
                        Button { isShowingManualWorkoutForm = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(TempoTheme.purple)
                                VStack(alignment: .leading, spacing: 4) { Text("record.completed".tempoLocalized).font(.subheadline.weight(.semibold)); Text("record.completedHint".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary) }
                                Spacer(minLength: 6)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(TempoTheme.secondary)
                            }.foregroundStyle(TempoTheme.primary).padding(14).frame(maxWidth: .infinity, minHeight: 64).background(TempoTheme.raised, in: RoundedRectangle(cornerRadius: 17))
                        }.accessibilityIdentifier("activity.manual.add")
                    }.buttonStyle(.plain)
                }
                if !model.activityWorkouts.isEmpty {
                    TempoMetricGrid {
                        MetricCard(value: "\(localRecords.count)", label: "Antrenman", icon: "figure.run", color: TempoTheme.green)
                        MetricCard(value: TempoFormat.duration(localRecords.reduce(0) { $0 + Double($1.durationSeconds ?? $1.durationMinutes * 60) }), label: "Süre", icon: "clock", color: TempoTheme.blue)
                        if localRecords.contains(where: { TempoSport(rawValue: $0.sportId).supportsDistance && ($0.distanceKm ?? 0) > 0 }) {
                            MetricCard(value: TempoFormat.distance(localRecords.reduce(0) { $0 + ($1.distanceKm ?? 0) }), label: "Mesafe", icon: "point.topleft.down.to.point.bottomright.curvepath", color: TempoTheme.purple)
                        } else {
                            MetricCard(value: "\(Set(localRecords.map { Calendar.current.startOfDay(for: $0.startedAt) }).count)", label: "Hareketli gün", icon: "calendar", color: TempoTheme.purple)
                        }
                    }
                    Text("Toplamlar Tempo ve Apple Sağlık kayıtlarını içerir. Aynı antrenmanın farklı kaynaklardaki kopyaları birleştirilir.").font(.caption2).foregroundStyle(TempoTheme.secondary)
                }
                if let error = model.manualWorkoutError {
                    Text(error).font(.footnote).foregroundStyle(TempoTheme.orange).frame(maxWidth: .infinity, alignment: .leading)
                }
                if let error = model.healthWorkoutError {
                    Text(error).font(.footnote).foregroundStyle(TempoTheme.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                SearchField(text: $search, placeholder: "Aktivite ara")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filterOptions) { option in
                            Button { selectedFilter = option } label: {
                                Text(option.title.tempoLocalized).font(.caption.weight(.semibold)).foregroundStyle(selectedFilter.id == option.id ? TempoTheme.onAccent : TempoTheme.primary.opacity(0.8)).padding(.horizontal, 14).padding(.vertical, 10).background(selectedFilter.id == option.id ? TempoTheme.green : TempoTheme.card, in: Capsule())
                            }.buttonStyle(.plain).accessibilityIdentifier("activity.filter.\(option.id)")
                        }
                    }
                }.accessibilityIdentifier("activity.filters")
                SectionHeading(title: "Antrenmanların", caption: "TEMPO + APPLE SAĞLIK", padding: false)
                ForEach(localRecords) { workout in
                    ManualWorkoutRow(workout: workout).accessibilityIdentifier("workout.record.\(workout.sportId)").contextMenu {
                        if workout.isLocalRecord { Button(role: .destructive) {
                            do { try model.deleteManualWorkout(workout) }
                            catch { deletionError = error.localizedDescription.tempoLocalized }
                        } label: { Label("Antrenmanı sil", systemImage: "trash") } }
                    }
                }
                if localRecords.isEmpty { EmptyCard(icon: "figure.run", text: "Bu filtrede Tempo veya Apple Sağlık antrenmanı yok.") }
                if model.isConnected {
                    SectionHeading(title: "Strava aktiviteleri", caption: "STRAVA", padding: false)
                    Text("Strava kayıtları burada doğrudan görüntülenir; Tempo puanlarına ve hedeflerine katılmaz.").font(.caption2).foregroundStyle(TempoTheme.secondary)
                    if model.dashboard == nil { LoadingDashboardCard() }
                    else {
                        ForEach(stravaRecords) { activity in NavigationLink(destination: ActivityDetailScreen(activity: activity)) { ActivityRow(activity: activity) }.buttonStyle(.plain) }
                        if stravaRecords.isEmpty { EmptyCard(icon: "magnifyingglass", text: "Bu filtreye uygun Strava aktivitesi yok.") }
                    }
                } else { StravaOptionalCard(title: "Strava bağlantısı isteğe bağlı", message: "Bağladığında Strava kayıtlarını burada ayrı kaynak etiketiyle görebilirsin.") }
            }.refreshable { await model.reloadAll() }
            .toolbar(.hidden, for: .navigationBar)
            .alert("Antrenman silinemedi".tempoLocalized, isPresented: Binding(get: { deletionError != nil }, set: { if !$0 { deletionError = nil } })) {
                Button("Tamam") { deletionError = nil }
            } message: { Text(deletionError ?? "") }
            .sheet(isPresented: $isShowingManualWorkoutForm) { ManualWorkoutForm() }
            .sheet(isPresented: $isShowingPhoneTracker) { TempoPhoneTrackerScreen(initialSportID: trackingSport) }
        }
    }
}

private struct WorkoutEntryActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.title2.weight(.medium)).foregroundStyle(color)
            Text(title.tempoLocalized).font(.headline).foregroundStyle(TempoTheme.primary)
            Text(subtitle.tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, minHeight: 105, alignment: .leading).padding(15)
            .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(color.opacity(0.14)))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct TempoWorkoutHistoryScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    var body: some View {
        TempoPage {
            PageTitle(title: "Antrenman geçmişi", subtitle: "TEMPO + APPLE SAĞLIK")
            if let error = model.manualWorkoutError { Text(error).font(.footnote).foregroundStyle(TempoTheme.orange) }
            ForEach(model.activityWorkouts) { workout in ManualWorkoutRow(workout: workout) }
            if model.activityWorkouts.isEmpty { EmptyCard(icon: "figure.run", text: "Henüz antrenman kaydı yok.") }
        }.navigationTitle("Antrenman geçmişi").navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
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
                Text(workout.title).font(.subheadline.weight(.semibold)).foregroundStyle(TempoTheme.primary).lineLimit(2)
                Text("%@ · %@".tempoFormatted(workout.sportTitle, TempoFormat.duration(Double(workout.durationSeconds ?? workout.durationMinutes * 60))))
                    .font(.caption).foregroundStyle(TempoTheme.secondary)
                Text(workout.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(TempoTheme.secondary)
                HStack(spacing: 5) {
                    Image(systemName: sourceSymbol).font(.caption2)
                    Text(sourceTitle).font(.caption2.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    if TempoSport(rawValue: workout.sportId).supportsDistance, let distance = workout.distanceKm, distance > 0 {
                        Text("· %@".tempoFormatted(TempoSport(rawValue: workout.sportId).distanceText(distance))).font(.caption2)
                    }
                }
                .foregroundStyle(workout.recordSource == "phone-gps" ? TempoTheme.blue : TempoTheme.green)
                if workout.isSensorVerified {
                    Label("progress.sensorVerified".tempoLocalized, systemImage: "checkmark.shield.fill")
                        .font(.caption2.weight(.semibold)).foregroundStyle(TempoTheme.blue)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(TempoTheme.blue.opacity(0.1), in: Capsule())
                        .accessibilityHint("progress.sensorHint".tempoLocalized)
                }
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
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(TempoTheme.primary.opacity(0.07), lineWidth: 1))
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
            }
        }
        .sheet(isPresented: $isShowingRoute) {
            ManualWorkoutRouteScreen(workout: workout)
        }
    }

    private var sourceTitle: String { workout.sourceTitle }

    private var sourceSymbol: String {
        switch workout.recordSource { case "phone-gps": return "location.fill"; case "phone-timer": return "timer"; case "manual": return "square.and.pencil"; default: return "heart.text.square.fill" }
    }

    private func rating(_ value: Int?) -> String {
        guard let value else { return "—" }
        return "\(value)/5"
    }
}

private struct ManualWorkoutRouteScreen: View {
    let workout: TempoManualWorkout
    @Environment(\.dismiss) private var dismiss
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.0, longitude: 35.0),
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    ))

    private var routeSegments: [[CLLocationCoordinate2D]] {
        TempoCoordinate.segments(workout.routeCoordinates ?? []).map { $0.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) } }
    }

    private var coordinates: [CLLocationCoordinate2D] {
        (workout.routeCoordinates ?? []).map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if coordinates.count >= 2 {
                    Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
                        ForEach(routeSegments.indices, id: \.self) { index in
                            MapPolyline(coordinates: routeSegments[index]).stroke(TempoTheme.green, lineWidth: 5)
                        }
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
    }

    private func updateRegion() {
        guard !coordinates.isEmpty else { return }
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (latitudes.min()! + latitudes.max()!) / 2, longitude: (longitudes.min()! + longitudes.max()!) / 2)
        cameraPosition = .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: max((latitudes.max()! - latitudes.min()!) * 1.6, 0.006), longitudeDelta: max((longitudes.max()! - longitudes.min()!) * 1.6, 0.006))
        ))
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
    @State private var checkHealthSignals = false
    @State private var workoutSessionID: UUID?
    @State private var isSaving = false
    @State private var isPreparingPhoto = false
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
                Section {
                    Label("record.completed".tempoLocalized, systemImage: selectedChoice?.symbol ?? "figure.mixed.cardio").font(.title3.weight(.semibold))
                    Text("record.formHint".tempoLocalized).font(.subheadline).foregroundStyle(TempoTheme.secondary)
                }.listRowBackground(Color.clear)
                ManualWorkoutDetailsSection(
                    sportId: $sportId,
                    title: $title,
                    startedAt: $startedAt,
                    durationMinutes: $durationMinutes
                )
                Section("Kayıt türü") {
                    DisclosureGroup("record.signalOptions".tempoLocalized) {
                        Toggle("Sağlık ve hareket sinyali ekle (isteğe bağlı)", isOn: $checkHealthSignals)
                        Text("Sinyal olmadan kişisel kayıt tutulur; doğrulanmış antrenman veya mücadele puanı sayılmaz.").font(.caption).foregroundStyle(TempoTheme.secondary)
                    }
                }
                ManualWorkoutFeedbackSection(effort: $perceivedEffort, enjoyment: $enjoyment)
                ManualWorkoutEvidenceSection(
                    photoItem: $photoItem,
                    photoData: $photoData,
                    photoImage: $photoImage,
                    notes: $notes
                )
            }
            .disabled(isSaving)
            .accessibilityIdentifier("activity.manual.form")
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(TempoTheme.background)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button(action: saveTapped) {
                    HStack(spacing: 10) {
                        if isSaving || isPreparingPhoto || photoItem != nil { ProgressView().tint(TempoTheme.onAccent) }
                        Text((isSaving ? "Kaydediliyor…" : (isPreparingPhoto || photoItem != nil ? "Fotoğraf hazırlanıyor…" : "record.save")).tempoLocalized)
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(TempoPrimaryButtonStyle()).disabled(isSaving || isPreparingPhoto || photoItem != nil)
                    .accessibilityIdentifier("activity.manual.save")
                    .padding(.horizontal, 16).padding(.vertical, 12).background(TempoTheme.background)
            }
            .navigationTitle("Antrenman ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ManualWorkoutToolbar(isSaving: isSaving, isPreparingPhoto: isPreparingPhoto || photoItem != nil, onCancel: { dismiss() }, onSave: saveTapped)
            }
            .task(id: photoItem) {
                await loadPhoto(photoItem)
            }
            .alert(errorTitle.tempoLocalized, isPresented: $showingError) {
                Button("Tamam") { }
            } message: {
                Text(errorMessage ?? "Fotoğraf tek başına yeterli değil. Antrenman saatinde anlamlı bir hareket veya Sağlık sinyali bulunamadı.")
            }
        }
        .interactiveDismissDisabled(isSaving)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .onAppear { if workoutSessionID == nil { workoutSessionID = model.activitySessionID } }
        .onChange(of: model.activitySessionID) { _, _ in dismiss() }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { isPreparingPhoto = false; return }
        isPreparingPhoto = true
        defer {
            if photoItem == item {
                isPreparingPhoto = false
                photoItem = nil
            }
        }
        do {
            let data = try await item.loadTransferable(type: Data.self)
            guard !Task.isCancelled, photoItem == item else { return }
            guard let data, let image = UIImage(data: data) else { throw ProfilePhotoLoadError.unreadable }
            let bounded = image.preparingThumbnail(of: CGSize(width: 1400, height: 1400)) ?? image
            guard let jpeg = bounded.jpegData(compressionQuality: 0.78) else { throw ProfilePhotoLoadError.unreadable }
            photoData = jpeg
            photoImage = UIImage(data: jpeg)
        } catch {
            guard !Task.isCancelled, photoItem == item else { return }
            errorTitle = "Antrenman kaydedilemedi"
            errorMessage = "Fotoğraf hazırlanamadı. Başka bir fotoğraf seçip tekrar dene.".tempoLocalized
            showingError = true
        }
    }

    private enum ProfilePhotoLoadError: Error { case unreadable }

    private func saveTapped() {
        guard !isSaving, !isPreparingPhoto, photoItem == nil else { return }
        isSaving = true
        Task { await saveWorkout() }
    }

    @MainActor
    private func saveWorkout() async {
        do {
            guard workoutSessionID == model.activitySessionID else {
                throw NSError(domain: "TempoWorkoutSession", code: 1, userInfo: [NSLocalizedDescriptionKey: "Tempo hesabı değişti. Antrenman bu hesapta kaydedilmedi.".tempoLocalized])
            }
            try await model.addManualWorkout(
                sportId: sportId,
                sportTitle: sportTitle,
                title: title,
                startedAt: startedAt,
                durationMinutes: durationMinutes,
                notes: notes,
                photoData: photoData,
                checkHealthSignals: checkHealthSignals,
                perceivedEffort: perceivedEffort,
                enjoyment: enjoyment
            )
            dismiss()
        } catch {
            isSaving = false
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
            DisclosureGroup("Antrenman sonrası kısa not".tempoLocalized) {
            ratingRow(title: "Ne kadar zor hissettirdi?", selection: $effort, labels: ["Çok kolay", "Kolay", "Orta", "Zor", "Çok zor"])
            ratingRow(title: "Ne kadar keyif aldın?", selection: $enjoyment, labels: ["Hiç", "Az", "Orta", "İyi", "Çok"])
            Text("Bu geri bildirim yalnızca bu cihazdaki antrenman kaydında tutulur ve sonraki önerileri yumuşatmaya yardımcı olur.")
                .font(.caption2).foregroundStyle(TempoTheme.secondary)
            }
        } header: {
            Text("Antrenman sonrası kısa not")
        }
    }

    private func ratingRow(title: String, selection: Binding<Int?>, labels: [String]) -> some View {
        Picker(title.tempoLocalized, selection: selection) {
            Text("record.notSet".tempoLocalized).tag(Optional<Int>.none)
            ForEach(1...5, id: \.self) { score in Text(labels[score - 1].tempoLocalized).tag(Optional(score)) }
        }.pickerStyle(.menu).tint(TempoTheme.green).padding(.vertical, 4)
    }
}

private struct ManualWorkoutToolbar: ToolbarContent {
    let isSaving: Bool
    let isPreparingPhoto: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("İptal", action: onCancel)
                .disabled(isSaving)
                .accessibilityIdentifier("activity.manual.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button((isPreparingPhoto ? "Fotoğraf hazırlanıyor…" : (isSaving ? "Kaydediliyor…" : "Kaydet")).tempoLocalized, action: onSave)
                .disabled(isSaving || isPreparingPhoto)
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
            DatePicker("Başlangıç zamanı", selection: $startedAt, in: ...Date().addingTimeInterval(-Double(durationMinutes) * 60), displayedComponents: [.date, .hourAndMinute])
            TempoMetricGrid(columns: 4) {
                ForEach([15, 30, 45, 60], id: \.self) { minutes in
                    Button("record.minutes".tempoFormatted(minutes)) {
                        durationMinutes = minutes
                        startedAt = min(startedAt, Date().addingTimeInterval(-Double(minutes) * 60))
                    }.font(.caption.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(durationMinutes == minutes ? TempoTheme.onAccent : TempoTheme.primary)
                        .background(durationMinutes == minutes ? TempoTheme.green : TempoTheme.raised, in: RoundedRectangle(cornerRadius: 12))
                        .buttonStyle(.plain)
                }
            }
            Stepper("Süre: %d dk".tempoFormatted(durationMinutes), value: $durationMinutes, in: 1...360)
                .onChange(of: durationMinutes) { _, duration in
                    startedAt = min(startedAt, Date().addingTimeInterval(-Double(duration) * 60))
                }
            Text("Bitiş: %@".tempoFormatted(startedAt.addingTimeInterval(Double(durationMinutes) * 60).formatted(date: .abbreviated, time: .shortened))).font(.caption).foregroundStyle(TempoTheme.secondary)
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
            DisclosureGroup("record.evidenceOptions".tempoLocalized) {
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
            Text("Apple Watch gerekmez. İstersen antrenman saatindeki hareket veya Sağlık sinyallerini ekleyebilirsin. Fotoğraf tek başına doğrulama değildir. Sinyal bulunamazsa kayıt doğrulanmamış olarak cihazında kalır.")
                .font(.caption).foregroundStyle(TempoTheme.secondary)
            Text("iPhone adım ölçümü için Hareket ve Fitness izni gerekebilir. iPhone sensöründeki adım geçmişi son 7 gün için sorgulanabilir.")
                .font(.caption2).foregroundStyle(TempoTheme.secondary)
            }
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
            TempoMetricGrid(columns: activity.sport.supportsElevation ? 3 : (activity.sport.supportsDistance ? 2 : 1)) {
                MetricCard(value: TempoFormat.duration(activity.movingSeconds), label: "Süre", icon: "clock.fill", color: TempoTheme.blue)
                if activity.sport.supportsDistance { MetricCard(value: activity.sport.distanceText(activity.distanceKm), label: "Mesafe", icon: "arrow.left.and.right", color: TempoTheme.orange) }
                if activity.sport.supportsElevation { MetricCard(value: "\(Int(activity.elevationMeters)) m", label: "Yükseklik", icon: "mountain.2.fill", color: TempoTheme.purple) }
            }
            if activity.route.count > 1 {
                RouteMap(routes: [activity], selectedActivity: activity)
                    .frame(height: 330).clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            TempoCard {
                DetailLine(label: "Spor", value: activity.sport.title)
                Divider().overlay(TempoTheme.primary.opacity(0.08))
                if activity.sport.supportsElevation {
                    DetailLine(label: "Ortalama hız", value: String(format: "%.1f km/sa", activity.speedKmh))
                    Divider().overlay(TempoTheme.primary.opacity(0.08))
                }
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
                                .background(TempoTheme.primary.opacity(0.10), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text("SON AKTİVİTE".tempoSentenceCased)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(TempoTheme.secondary)
                                Text(latest.date.map { TempoFormat.shortDate.string(from: $0) } ?? latest.sport.title)
                                    .font(.caption)
                                    .foregroundStyle(TempoTheme.primary.opacity(0.62))
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption.bold())
                                .foregroundStyle(TempoTheme.primary.opacity(0.82))
                                .frame(width: 34, height: 34)
                                .background(TempoTheme.primary.opacity(0.09), in: Circle())
                        }

                        Text(latest.name ?? latest.sport.title)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(TempoTheme.primary)
                            .lineLimit(2)

                        HStack(spacing: 18) {
                            if latest.sport.supportsDistance { Label(latest.sport.distanceText(latest.distanceKm), systemImage: "arrow.left.and.right") }
                            Label(TempoFormat.duration(latest.movingSeconds), systemImage: "clock.fill")
                            if latest.elevationMeters > 0 {
                                Label("\(Int(latest.elevationMeters)) m", systemImage: "mountain.2.fill")
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TempoTheme.primary.opacity(0.74))
                    }
                    .padding(19)
                    .background(
                        LinearGradient(
                            colors: [TempoTheme.green.opacity(0.12), TempoTheme.blue.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 25, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 25, style: .continuous)
                            .stroke(LinearGradient(colors: [TempoTheme.green.opacity(0.24), TempoTheme.primary.opacity(0.045)], startPoint: .topLeading, endPoint: .bottomTrailing))
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
                                        .foregroundStyle(TempoTheme.primary)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
                                    Text(TempoFormat.distance(activity.distanceKm))
                                        .font(.headline)
                                        .foregroundStyle(TempoTheme.primary)
                                    Text(activity.date.map { TempoFormat.shortDate.string(from: $0) } ?? activity.sport.title)
                                        .font(.caption2)
                                        .foregroundStyle(TempoTheme.secondary)
                                }
                                .padding(15)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(TempoTheme.primary.opacity(0.05)))
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
                                .foregroundStyle(TempoTheme.primary)
                            Text("Aktiviteleri tarihe göre görüntüle")
                                .font(.caption)
                                .foregroundStyle(TempoTheme.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(TempoTheme.primary.opacity(0.32))
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

    func matches(_ activity: TempoActivity) -> Bool { matchesSport(activity.sport) }

    func matchesSport(_ value: TempoSport) -> Bool {
        switch id {
        case Self.all.id:
            return true
        case Self.other.id:
            return value != .run && value != .ride && value != .walk
        default:
            guard let sport else { return false }
            return value == sport
        }
    }
}

private struct ActivityTimelineGroup: Identifiable {
    let id: String
    let title: String
    var activities: [TempoActivity]

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

    var body: some View {
        ZStack {
            TempoTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("AKTİVİTE ARŞİVİ".tempoSentenceCased)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TempoTheme.secondary)
                        Text("Strava’dan gelen aktiviteleri tarih sırasıyla görüntüle.")
                            .font(.system(size: 28, weight: .bold, design: .rounded))

                        Text("Strava kayıtları burada doğrudan görüntülenir; Tempo puanlarına ve hedeflerine katılmaz.")
                            .font(.caption)
                            .foregroundStyle(TempoTheme.secondary)
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
                                        .foregroundStyle(filter.id == option.id ? TempoTheme.onAccent : TempoTheme.primary)
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
                                    }
                                    Spacer()
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
    @EnvironmentObject private var account: TempoAccountStore
    var sportContext: ActiveSportContext? = nil
    @StateObject private var sportMetrics = SportMetricsStore()
    @State private var selectedSportID = "general"
    @State private var strengthFocus: StrengthSessionFocus = .unspecified
    @State private var includeTraining = false
    @State private var messages: [TempoCoachMessage] = []
    @State private var draft = ""
    @State private var includeHealth = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var requestID: UUID?
    @State private var requestTask: Task<Void, Never>?
    @State private var scrollTarget: String?
    @FocusState private var composerFocused: Bool
    private let suggestions = ["Bugün nasıl antrenman yapayım?", "Dinlenme gününde ne yapabilirim?", "Koşuya yeni başlıyorum; nasıl ilerleyeyim?", "Uyku toparlanmayı nasıl etkiler?"]

    var body: some View {
        ZStack {
            TempoAmbientBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    PageTitle(title: "Tempo Koç", subtitle: "cross.coachSubtitle")
                    sportControls
                    privacyControls
                    if messages.isEmpty { welcome }
                    ForEach(messages) { message in
                        chatBubble(message).id(message.id.uuidString)
                    }
                    if isSending {
                        HStack(spacing: 10) {
                            ProgressView().tint(TempoTheme.green)
                            Text("Tempo Koç düşünüyor…").font(.caption).foregroundStyle(TempoTheme.secondary)
                        }.padding(14).accessibilityIdentifier("coach.loading")
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.bubble")
                            .font(.footnote).foregroundStyle(TempoTheme.orange)
                            .padding(14).accessibilityIdentifier("coach.error")
                    }
                    Color.clear.frame(height: 1).id("coach-bottom")
                }
                .scrollTargetLayout()
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
            }
            .scrollPosition(id: $scrollTarget, anchor: .bottom)
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .preference(key: TempoChatTabBarPreference.self, value: true)
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle("Tempo Koç").navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {
                    if isSending {
                        Button("Durdur") { cancelRequest() }.accessibilityIdentifier("coach.stop")
                    }
                    Button { newConversation() } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("Yeni sohbet".tempoLocalized).accessibilityIdentifier("coach.new")
                }.tint(TempoTheme.green)
            }
        }
        .onDisappear { cancelRequest() }
        .task(id: account.profile?.id) { sportMetrics.bind(account.profile?.id); strengthFocus = sportContext?.strengthFocus ?? strengthFocus }
        .onChange(of: account.profile?.id) { _, _ in newConversation(); includeHealth = false; includeTraining = false }
        .onChange(of: includeHealth) { _, enabled in if !enabled { clearPersonalConversation() } }
        .onChange(of: includeTraining) { _, enabled in if !enabled { clearPersonalConversation() } }
        .onChange(of: model.healthSyncEnabled) { _, enabled in if !enabled { includeHealth = false } }
    }

    private var activeSport: ActiveSportContext {
        if var context = sportContext {
            if context.archetype == .strengthAndHypertrophy { context.strengthFocus = strengthFocus }
            return context
        }
        return .selected(selectedSportID, focus: strengthFocus)
    }
    private var sportControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let sportContext {
                Label(TempoSportChoice(rawValue: sportContext.sportID)?.title ?? "cross.general".tempoLocalized, systemImage: "figure.mixed.cardio").font(.subheadline.weight(.semibold))
            } else {
                Picker("cross.sport".tempoLocalized, selection: $selectedSportID) {
                    Text("cross.general".tempoLocalized).tag("general")
                    ForEach(TempoSportChoice.allCases) { Text($0.title).tag($0.rawValue) }
                }.pickerStyle(.menu)
            }
            if activeSport.archetype == .strengthAndHypertrophy {
                Picker("cross.focusTitle".tempoLocalized, selection: $strengthFocus) {
                    ForEach(StrengthSessionFocus.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.menu)
            }
        }.tint(TempoTheme.green).padding(.horizontal, 4).disabled(isSending)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            TempoCard {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "sparkles").font(.title2).foregroundStyle(TempoTheme.green)
                    Text("Nereden başlamak istersin?").font(.title3.bold())
                    Text("cross.welcome".tempoLocalized)
                        .font(.subheadline).foregroundStyle(TempoTheme.secondary)
                }
            }
            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                Button { send(suggestion.tempoLocalized) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.left").font(.caption.weight(.semibold)).foregroundStyle(TempoTheme.green)
                        Text(suggestion.tempoLocalized).font(.subheadline).foregroundStyle(TempoTheme.primary.opacity(0.9))
                        Spacer()
                    }.padding(13).background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }.buttonStyle(.plain).disabled(isSending || model.isCoachLoading).accessibilityIdentifier("coach.suggestion.\(index)")
            }
        }
    }

    private var privacyControls: some View {
        DisclosureGroup("Sohbet gizliliği") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Apple Sağlık özetimi kullan", isOn: $includeHealth)
                    .font(.subheadline).tint(TempoTheme.green)
                    .disabled(!model.healthSyncEnabled || isSending)
                Toggle("cross.shareTraining".tempoLocalized, isOn: $includeTraining)
                    .font(.subheadline).tint(TempoTheme.green).disabled(isSending)
                Text("cross.privacy".tempoLocalized).font(.caption2).foregroundStyle(TempoTheme.secondary)
                Text("cross.privacyHistory".tempoLocalized).font(.caption2).foregroundStyle(TempoTheme.secondary)
                Text((model.healthSyncEnabled ? "Yalnızca bu sohbet isteğinde paylaşılır." : "Kişisel sağlık ölçüsü eklemek için önce Apple Sağlık’ı bağla.").tempoLocalized)
                    .font(.caption).foregroundStyle(TempoTheme.secondary)
                Text("Kapalıyken Apple Sağlık verin gönderilmez. Sohbet geçmişi sunucuda saklanmaz. Strava verileri bu asistana aktarılmaz.")
                    .font(.caption2).foregroundStyle(TempoTheme.secondary)
            }.padding(.top, 8)
        }.font(.caption.weight(.medium)).tint(TempoTheme.secondary)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 9) {
                TextField("Tempo Koç’a bir şey sor…".tempoLocalized, text: $draft, axis: .vertical)
                    .lineLimit(1...4).focused($composerFocused)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(TempoTheme.raised, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                    .accessibilityIdentifier("coach.draft")
                    .submitLabel(.send)
                    .onSubmit { send() }
                Button { send() } label: {
                    Image(systemName: "arrow.up").font(.headline.bold())
                        .frame(width: 46, height: 46).foregroundStyle(TempoTheme.onAccent)
                        .background(TempoTheme.green, in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("Gönder".tempoLocalized).accessibilityIdentifier("coach.send")
                    .disabled(isSending || model.isCoachLoading || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.utf16.count > 1_500)
                    .opacity(isSending || model.isCoachLoading || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
            }
            if draft.utf16.count > 1_500 {
                Text("Her mesaj 1.500 karakteri aşmamalı.").font(.caption2).foregroundStyle(TempoTheme.orange)
            }
            Text("Genel bilgilendirme içindir; tıbbi tanı veya tedavi yerine geçmez.")
                .font(.caption2).foregroundStyle(TempoTheme.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(TempoTheme.background.opacity(0.98))
    }

    private func chatBubble(_ message: TempoCoachMessage) -> some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 36) }
            Text(message.content)
                .font(.subheadline).lineSpacing(4).padding(13)
                .background(message.role == "user" ? TempoTheme.green.opacity(0.18) : TempoTheme.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(TempoTheme.primary.opacity(0.06)))
                .accessibilityIdentifier("coach.message.\(message.role)")
                .contextMenu { Button("Kopyala", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.content } }
            if message.role != "user" { Spacer(minLength: 36) }
        }
    }

    private func cancelRequest() {
        requestID = nil
        requestTask?.cancel()
        requestTask = nil
        isSending = false
    }
    private func newConversation() {
        cancelRequest()
        messages = []
        draft = ""
        errorMessage = nil
        scrollTarget = nil
    }
    private func clearPersonalConversation() {
        let unsent = draft
        newConversation()
        draft = unsent
    }
    private func send(_ suggested: String? = nil) {
        let text = (suggested ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf16.count <= 1_500, !isSending, !model.isCoachLoading else { return }
        // Lock synchronously, before creating a Task. Button taps and keyboard
        // submission in the same run-loop turn cannot enqueue duplicate calls.
        isSending = true
        errorMessage = nil
        let id = UUID()
        requestID = id
        let previous = messages
        let updated = Array((previous + [TempoCoachMessage(role: "user", content: text)]).suffix(12))
        let shareHealth = includeHealth && model.healthSyncEnabled
        sportMetrics.bind(account.profile?.id)
        sportMetrics.reload()
        let shareTraining = includeTraining
        let athleticContext = CrossSportAIService().context(active: activeSport,
            workouts: shareTraining ? CrossSportInputAdapter.workouts(model.activityWorkouts, store: sportMetrics, includeHealth: shareHealth) : [],
            includeTraining: shareTraining, includeHealth: shareHealth)
        messages = updated
        if suggested == nil || draft.trimmingCharacters(in: .whitespacesAndNewlines) == text { draft = "" }
        scrollTarget = "coach-bottom"
        requestTask = Task { @MainActor in
            defer {
                if requestID == id { isSending = false; requestTask = nil; requestID = nil }
            }
            do {
                let answer = try await model.askSportsChat(messages: updated, includeHealth: shareHealth, includeTraining: shareTraining, athleticContext: athleticContext)
                try Task.checkCancellation()
                guard requestID == id else { return }
                messages = Array((updated + [TempoCoachMessage(role: "assistant", content: answer)]).suffix(12))
                scrollTarget = "coach-bottom"
            } catch {
                guard requestID == id, !Task.isCancelled, (error as? URLError)?.code != .cancelled else { return }
                messages = previous
                if draft.isEmpty { draft = text }
                errorMessage = "Yanıt alınamadı: %@".tempoFormatted(error.localizedDescription.tempoLocalized)
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

struct SocialScreen: View {
    @EnvironmentObject private var account: TempoAccountStore
    @EnvironmentObject private var model: TempoAppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAddFriend = false
    @State private var showChallengeComposer = false
    @State private var friendQuery = ""
    @State private var snapshot: TempoSocialSnapshot?
    @State private var username = ""
    @State private var title = ""
    @State private var metric: TempoSocialMetric = .steps
    @State private var selectedFriends: Set<String> = []
    @State private var selectedSection: SocialSection = .overview
    @State private var refreshGeneration = UUID()
    @State private var loading = false
    @State private var working = false
    @State private var notice = ""
    @State private var pendingBlockProfile: TempoSocialProfile?
    @State private var showBlockConfirmation = false
    @State private var createdChallenges: [TempoSocialChallenge] = []
    @State private var showChallengeFeedback = false
    @State private var creationHealthSharing: Bool?
    @State private var pendingHealthChallenge: TempoSocialChallenge?
    @State private var pendingRemoveFriend: TempoSocialProfile?
    @State private var showRemoveFriendConfirmation = false
    @State private var pendingCancelChallenge: TempoSocialChallenge?
    @State private var showCancelChallengeConfirmation = false
    @State private var removedFriendIds: Set<String> = []
    @State private var cancelledChallengeIds: Set<String> = []

    private var friends: [TempoSocialProfile] { (snapshot?.friends ?? []).filter { !removedFriendIds.contains($0.id) } }
    private var filteredFriends: [TempoSocialProfile] {
        let query = friendQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? friends : friends.filter { $0.displayName.localizedStandardContains(query) || $0.username.localizedStandardContains(query) }
    }
    private var challenges: [TempoSocialChallenge] {
        var seen = Set<String>()
        return (createdChallenges + (snapshot?.challenges ?? [])).filter {
            seen.insert($0.id).inserted && !cancelledChallengeIds.contains($0.id) && $0.myStatus != "declined" && (TempoFormat.date(from: $0.endsAt) ?? .distantPast) > Date()
        }
    }
    private var featuredChallenges: [TempoSocialChallenge] {
        Array(challenges.filter { $0.myStatus == "accepted" || $0.myStatus == "invited" }.prefix(2))
    }

    var body: some View {
        TempoPage {
            HStack(alignment: .center, spacing: 12) {
                PageTitle(title: "Sosyal", subtitle: "Arkadaşlarınla hareket et")
                Button { selectedSection = .friends; showAddFriend = true } label: {
                    Image(systemName: "person.badge.plus").font(.system(size: 18, weight: .medium))
                        .frame(width: 48, height: 48).background(TempoTheme.green.opacity(0.12), in: Circle())
                }.buttonStyle(.plain).foregroundStyle(TempoTheme.green).disabled(working)
                    .accessibilityLabel("Arkadaş ekle".tempoLocalized)
            }
            sectionSelector
            if !notice.isEmpty {
                Label(notice, systemImage: "info.circle").font(.caption).foregroundStyle(TempoTheme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
            if loading && snapshot == nil {
                ProgressView().tint(TempoTheme.green).frame(maxWidth: .infinity).padding(22)
            } else if snapshot == nil, !notice.isEmpty {
                TempoCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Sosyal bilgiler yüklenemedi", systemImage: "wifi.exclamationmark").font(.subheadline.weight(.semibold))
                        Button("Tekrar dene") { Task { await refresh() } }.buttonStyle(TempoSecondaryButtonStyle()).disabled(loading || working)
                    }
                }
            } else {
                switch selectedSection {
                case .overview: socialIntro; overviewSection
                case .friends: friendsSection
                case .challenges: challengesSection
                }
            }
            TempoDisclosureSection(title: "Paylaşım ve güvenlik", icon: "hand.raised") {
                Text("Apple Sağlık özeti her yarış için ayrı ve varsayılan olarak kapalıdır. Skorlar bağımsız doğrulanmaz; yarışmalar arkadaşlar arasında eğlence amaçlıdır. Strava gerekmez.".tempoLocalized)
                    .font(.caption).foregroundStyle(TempoTheme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .refreshable { await refresh() }
        .sheet(isPresented: $showAddFriend) { friendComposer }
        .sheet(isPresented: $showChallengeComposer) { challengeSheet }
        .sheet(item: $pendingHealthChallenge) { challenge in healthConsentSheet(for: challenge) }
        .onChange(of: showChallengeComposer) { _, shown in if shown { creationHealthSharing = nil } }
        .confirmationDialog("social.friend.removeTitle".tempoLocalized, isPresented: $showRemoveFriendConfirmation, titleVisibility: .visible) {
            Button("social.friend.remove".tempoLocalized, role: .destructive) { if let profile = pendingRemoveFriend { Task { await removeFriend(profile) } } }
            Button("Vazgeç", role: .cancel) { pendingRemoveFriend = nil }
        } message: { Text("social.friend.removeDetail".tempoLocalized) }
        .confirmationDialog("social.challenge.cancelTitle".tempoLocalized, isPresented: $showCancelChallengeConfirmation, titleVisibility: .visible) {
            Button("social.challenge.cancel".tempoLocalized, role: .destructive) { if let challenge = pendingCancelChallenge { Task { await cancelChallenge(challenge) } } }
            Button("Vazgeç", role: .cancel) { pendingCancelChallenge = nil }
        } message: { Text("social.challenge.cancelDetail".tempoLocalized) }
        .navigationTitle("Sosyal").navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
        .task {
#if DEBUG
            guard !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
#endif
            await refresh()
        }
        .alert("Mücadele", isPresented: Binding(get: { showChallengeFeedback && !showChallengeComposer }, set: { showChallengeFeedback = $0 })) { Button("Tamam") {} } message: { Text(notice) }
        .confirmationDialog("Bu kullanıcıyı engelle?", isPresented: $showBlockConfirmation, titleVisibility: .visible) {
            Button("Engelle", role: .destructive) {
                if let profile = pendingBlockProfile { Task { await setBlocked(profile, blocked: true) } }
            }
            Button("Vazgeç", role: .cancel) { pendingBlockProfile = nil }
        } message: {
            Text("Engellenen hesap arkadaş listesinden ve ortak yarışmalarından kaldırılır.")
        }
    }

    private func healthConsentSheet(for challenge: TempoSocialChallenge) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(challenge.title).font(.title2.bold())
                    SocialHealthConsent(metric: TempoSocialMetric(rawValue: challenge.metric) ?? .steps, isWorking: working, selected: challenge.myStatus == "accepted" ? challenge.myShareHealth : nil) { enabled in
                        Task { await confirmChallengeHealth(challenge, enabled: enabled) }
                    }
                    if !notice.isEmpty { Text(notice).font(.footnote).foregroundStyle(TempoTheme.secondary) }
                }.padding(20).padding(.bottom, 32)
            }.background(TempoTheme.background.ignoresSafeArea())
                .navigationTitle("social.health.title".tempoLocalized).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Kapat") { pendingHealthChallenge = nil }.disabled(working) } }
        }.presentationDetents([.large]).presentationDragIndicator(.visible).interactiveDismissDisabled(working)
    }

    private var sectionSelector: some View {
        HStack(spacing: 4) {
            ForEach(SocialSection.allCases) { section in
                Button { selectedSection = section } label: {
                    Text(section.title.tempoLocalized).font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 6)
                        .foregroundStyle(selectedSection == section ? TempoTheme.primary : TempoTheme.secondary)
                        .background(selectedSection == section ? TempoTheme.raised : Color.clear, in: Capsule())
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
                    .accessibilityIdentifier("social.section.\(section.rawValue)")
            }
        }.padding(5).background(TempoTheme.card, in: Capsule())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: selectedSection)
            .accessibilityIdentifier("social.sections")
    }

    private var socialIntro: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Birlikte, kendi ritminizde".tempoLocalized).font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Arkadaş bul, yarış başlat, ilerlemeni paylaş.".tempoLocalized)
                        .font(.subheadline).foregroundStyle(TempoTheme.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "person.2.fill").font(.system(size: 26, weight: .medium))
                    .foregroundStyle(TempoTheme.green).frame(width: 58, height: 58)
                    .background(TempoTheme.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
                    .accessibilityHidden(true)
            }
            TempoMetricGrid {
                SocialStatTile(title: "Arkadaş", value: friends.count, icon: "person.2", color: TempoTheme.green)
                SocialStatTile(title: "Yarış", value: challenges.filter { $0.myStatus == "accepted" || $0.myStatus == "invited" }.count, icon: "trophy", color: TempoTheme.orange)
                SocialStatTile(title: "Gelen istek", value: snapshot?.incoming.count ?? 0, icon: "person.badge.plus", color: TempoTheme.blue)
            }
            HStack(spacing: 10) {
                Button { selectedSection = .friends; showAddFriend = true } label: { Label("Arkadaş ekle", systemImage: "plus") }
                    .buttonStyle(TempoPrimaryButtonStyle()).disabled(working)
                Button { selectedSection = .challenges; showChallengeComposer = true } label: { Label("Yarış oluştur", systemImage: "flag") }
                    .buttonStyle(TempoSecondaryButtonStyle()).disabled(working)
            }
        }.padding(18).background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(TempoTheme.green.opacity(0.12), lineWidth: 1))
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
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
        VStack(alignment: .leading, spacing: 18) {
            Button { showAddFriend = true } label: { Label("Arkadaş ekle", systemImage: "person.badge.plus") }
                .buttonStyle(TempoPrimaryButtonStyle()).disabled(working)
            if !(snapshot?.incoming.isEmpty ?? true) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeading(title: "Arkadaşlık istekleri", caption: "GELEN", padding: false)
                    ForEach(snapshot?.incoming ?? []) { request in requestCard(request) }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Arkadaşların".tempoLocalized).font(.headline)
                    Spacer(minLength: 12)
                    Text(friends.count.formatted()).font(.caption.monospacedDigit()).foregroundStyle(TempoTheme.secondary)
                }
                if !friends.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(TempoTheme.secondary)
                        TextField("Arkadaşlarında ara".tempoLocalized, text: $friendQuery)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }.padding(14).background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 16))
                    Text("Birlikte yarışmak için arkadaşlarını seç.".tempoLocalized)
                        .font(.caption).foregroundStyle(TempoTheme.secondary)
                }
                if friends.isEmpty {
                    EmptyCard(icon: "person.2", text: "Henüz arkadaş yok. Kullanıcı adıyla bir istek göndererek başlayabilirsin.")
                } else if filteredFriends.isEmpty {
                    EmptyCard(icon: "magnifyingglass", text: "Bu aramaya uygun arkadaş bulunamadı.")
                } else {
                    ForEach(filteredFriends) { friend in
                        HStack(spacing: 10) {
                            Button {
                                if selectedFriends.contains(friend.id) { selectedFriends.remove(friend.id) }
                                else if selectedFriends.count < 20 { selectedFriends.insert(friend.id) }
                            } label: {
                                HStack(spacing: 10) {
                                    SocialPersonRow(profile: friend, detail: "@\(friend.username)")
                                    Image(systemName: selectedFriends.contains(friend.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedFriends.contains(friend.id) ? TempoTheme.green : TempoTheme.secondary)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(working)
                                .accessibilityAddTraits(selectedFriends.contains(friend.id) ? .isSelected : [])
                            Menu { safetyMenu(for: friend) } label: {
                                Image(systemName: "ellipsis").font(.headline).foregroundStyle(TempoTheme.secondary)
                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                            }.disabled(working).accessibilityLabel("Kullanıcı seçenekleri".tempoLocalized)
                        }
                        .padding(14).background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(selectedFriends.contains(friend.id) ? TempoTheme.green.opacity(0.45) : TempoTheme.primary.opacity(0.07), lineWidth: 1))
                        .contextMenu { safetyMenu(for: friend) }
                    }
                }
                if !selectedFriends.isEmpty {
                    Button { selectedSection = .challenges; showChallengeComposer = true } label: {
                        Label("Seçtiklerinle yarış oluştur".tempoLocalized, systemImage: "flag.checkered")
                    }.buttonStyle(TempoPrimaryButtonStyle()).disabled(working)
                }
            }
            if !(snapshot?.outgoing.isEmpty ?? true) {
                TempoDisclosureSection(title: "Gönderilen istekler", icon: "paperplane") {
                    VStack(spacing: 14) { ForEach(snapshot?.outgoing ?? []) { request in SocialPersonRow(profile: request.user, detail: "İstek bekliyor".tempoLocalized) } }
                }
            }
            if !(snapshot?.blocked.isEmpty ?? true) {
                TempoDisclosureSection(title: "Engellenen hesaplar", icon: "hand.raised") {
                    VStack(spacing: 14) {
                        ForEach(snapshot?.blocked ?? []) { profile in
                            VStack(alignment: .leading, spacing: 8) {
                                SocialPersonRow(profile: profile, detail: "Engellendi".tempoLocalized)
                                Button("Engeli kaldır") { Task { await setBlocked(profile, blocked: false) } }
                                    .buttonStyle(TempoSecondaryButtonStyle()).disabled(working)
                            }
                        }
                    }
                }
            }
        }
    }

    private func requestCard(_ request: TempoSocialRequest) -> some View {
        TempoCard {
            VStack(spacing: 14) {
                SocialPersonRow(profile: request.user, detail: "@\(request.user.username)")
                HStack(spacing: 10) {
                    Button("Kabul et") { Task { await answer(request, accept: true) } }.buttonStyle(TempoPrimaryButtonStyle()).disabled(working)
                    Button("Reddet") { Task { await answer(request, accept: false) } }.buttonStyle(TempoSecondaryButtonStyle()).disabled(working)
                }
            }
        }
    }

    private var friendComposer: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Arkadaşının Tempo kullanıcı adını yaz.".tempoLocalized).font(.subheadline).foregroundStyle(TempoTheme.secondary)
                    HStack(spacing: 10) {
                        Image(systemName: "at").foregroundStyle(TempoTheme.green)
                        TextField("Kullanıcı adı", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .submitLabel(.send).onSubmit { Task { await sendRequest() } }
                            .accessibilityIdentifier("social.friendUsername")
                    }.padding(16).background(TempoTheme.raised, in: RoundedRectangle(cornerRadius: 18))
                    Text("@ işaretiyle veya işaretsiz Tempo kullanıcı adını yazabilirsin.".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
                    Button { Task { await sendRequest() } } label: {
                        HStack { if working { ProgressView().tint(TempoTheme.onAccent) }; Label("Arkadaşlık isteği gönder", systemImage: "paperplane") }
                    }.buttonStyle(TempoPrimaryButtonStyle())
                        .disabled(working || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("social.sendFriendRequest")
                    if !notice.isEmpty { Text(notice).font(.footnote).foregroundStyle(TempoTheme.secondary).fixedSize(horizontal: false, vertical: true) }
                }.padding(20).padding(.bottom, 28)
            }.scrollDismissesKeyboard(.interactively).background(TempoTheme.background.ignoresSafeArea())
                .navigationTitle("Arkadaş ekle").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Kapat") { showAddFriend = false }.disabled(working) } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible).interactiveDismissDisabled(working)
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

            Button { showChallengeComposer = true } label: { Label("Yarış oluştur", systemImage: "plus") }
                .buttonStyle(TempoPrimaryButtonStyle()).disabled(working)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeading(title: "Yarışmalar", caption: "APPLE SAĞLIK · İSTEĞE BAĞLI", padding: false)
                    Spacer()
                    Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise").foregroundStyle(TempoTheme.green) }
                        .disabled(loading || working)
                        .accessibilityLabel("Yarışmaları yenile")
                }
                if challenges.isEmpty {
                    EmptyCard(icon: "trophy", text: "Aktif yarışma yok. Arkadaş ekleyip haftalık bir hedef başlat.")
                }
                ForEach(challenges) { challenge in challengeCard(challenge) }
            }
        }
    }

    private var challengeSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
            if !friends.isEmpty {
                TempoCard {
                    VStack(alignment: .leading, spacing: 11) {
                        Label("Haftalık yarış oluştur", systemImage: "trophy.fill").font(.headline).foregroundStyle(TempoTheme.orange)
                        TextField("Yarışma adı (isteğe bağlı)", text: $title).padding(12).background(TempoTheme.raised, in: RoundedRectangle(cornerRadius: 14))
                            .onChange(of: title) { _, value in if value.count > 60 { title = String(value.prefix(60)) } }
                        Picker("Hedef", selection: $metric) {
                            ForEach(TempoSocialMetric.allCases) { option in Label(option.title, systemImage: option.symbol).tag(option) }
                        }.pickerStyle(.menu)
                        if metric == .movementDays {
                            Text("Hareket günü, en az 3.000 adım veya 10 dakika egzersiz olarak sayılır.")
                                .font(.caption2).foregroundStyle(TempoTheme.secondary)
                        }
                        Text("Davet göndermek istediğin arkadaşları seç.").font(.caption).foregroundStyle(TempoTheme.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(friends) { friend in
                                    Button {
                                        if selectedFriends.contains(friend.id) { selectedFriends.remove(friend.id) }
                                        else if selectedFriends.count < 20 { selectedFriends.insert(friend.id) }
                                    } label: {
                                        Label(friend.displayName.isEmpty ? friend.username : friend.displayName, systemImage: selectedFriends.contains(friend.id) ? "checkmark.circle.fill" : "person.crop.circle")
                                            .font(.caption.weight(.semibold)).padding(.horizontal, 13).padding(.vertical, 11)
                                            .foregroundStyle(selectedFriends.contains(friend.id) ? TempoTheme.onAccent : TempoTheme.primary)
                                            .background(selectedFriends.contains(friend.id) ? TempoTheme.green : TempoTheme.raised, in: Capsule())
                                    }.buttonStyle(.plain).disabled(working)
                                        .accessibilityIdentifier("social.challenge.friend.\(friend.id)")
                                }
                            }
                        }
                        SocialHealthConsent(metric: metric, isWorking: working, selected: creationHealthSharing) { creationHealthSharing = $0 }
                        Button { Task { await createChallenge() } } label: {
                            HStack {
                                if working { ProgressView().tint(TempoTheme.onAccent) }
                                Label("Mücadele daveti gönder", systemImage: "flag.checkered")
                            }.frame(maxWidth: .infinity)
                        }
                        .buttonStyle(TempoPrimaryButtonStyle())
                        .disabled(working || selectedFriends.isEmpty || creationHealthSharing == nil || (creationHealthSharing == true && (!model.healthSyncEnabled || model.isHealthSyncing)))
                        .accessibilityIdentifier("social.challenge.send")
                    }
                }
            } else {
                TempoCard {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("Önce arkadaşlarını ekle", systemImage: "person.2.fill").font(.headline).foregroundStyle(TempoTheme.orange)
                        Text("Bir mücadele başlatmak için önce arkadaşlık isteğinin kabul edilmesi gerekiyor.")
                            .font(.caption).foregroundStyle(TempoTheme.secondary)
                        Button { showChallengeComposer = false; selectedSection = .friends } label: {
                            Label("Arkadaş bul", systemImage: "person.badge.plus").frame(maxWidth: .infinity)
                        }.buttonStyle(TempoSecondaryButtonStyle())
                    }
                }
            }

                    if !notice.isEmpty { Text(notice).font(.footnote).foregroundStyle(TempoTheme.secondary).fixedSize(horizontal: false, vertical: true) }
                }.padding(16).padding(.bottom, 32)
            }.scrollDismissesKeyboard(.interactively).background(TempoTheme.background.ignoresSafeArea())
                .navigationTitle("Yarış oluştur").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Kapat") { showChallengeComposer = false }.disabled(working) } }
        }.presentationDetents([.large]).presentationDragIndicator(.visible).interactiveDismissDisabled(working)
        .alert("Mücadele", isPresented: Binding(get: { showChallengeFeedback && showChallengeComposer }, set: { showChallengeFeedback = $0 })) { Button("Tamam") {} } message: { Text(notice) }
    }

    private func challengeCard(_ challenge: TempoSocialChallenge) -> some View {
        SocialChallengeCard(challenge: challenge, isWorking: working) { action in
            if action == "accept" { notice = ""; pendingHealthChallenge = challenge }
            else { Task { await updateChallenge(challenge, action: action) } }
        } onShareChange: { enabled in
            notice = ""; pendingHealthChallenge = challenge
        } onReport: { category in
            Task { await reportChallenge(challenge, category: category) }
        } onCancel: {
            pendingCancelChallenge = challenge; showCancelChallengeConfirmation = true
        }
    }

    private func refresh(clearNotice: Bool = true) async {
        let generation = UUID()
        refreshGeneration = generation
        loading = true
        defer { if refreshGeneration == generation { loading = false } }
        do {
            let updated = try await account.loadSocial()
            guard !Task.isCancelled, refreshGeneration == generation else { return }
            snapshot = updated
            removedFriendIds.formIntersection(Set(updated.friends.map(\.id)))
            selectedFriends.formIntersection(Set(snapshot?.friends.map(\.id) ?? []))
            let serverChallenges = snapshot?.challenges ?? []
            createdChallenges.removeAll { local in
                serverChallenges.contains { remote in
                    remote.id == local.id && remote.myStatus == local.myStatus && remote.myShareHealth == local.myShareHealth
                }
            }
            if clearNotice { notice = "" }
        } catch {
            guard !Task.isCancelled, refreshGeneration == generation, !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
            notice = error.localizedDescription.tempoLocalized
        }
    }

    private func sendRequest() async {
        guard !working, !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        working = true; defer { working = false }
        do {
            let submittedUsername = username
            let becameFriends = try await account.sendFriendRequest(username: submittedUsername.trimmingCharacters(in: .whitespacesAndNewlines))
            if username == submittedUsername { username = "" }
            showAddFriend = false
            notice = (becameFriends ? "Karşılıklı istek eşleşti; artık arkadaşsınız." : "Arkadaşlık isteği gönderildi.").tempoLocalized
            await refresh(clearNotice: false)
        }
        catch { notice = error.localizedDescription.tempoLocalized }
    }

    private func answer(_ request: TempoSocialRequest, accept: Bool) async {
        guard !working else { return }
        working = true; defer { working = false }
        do { try await account.respondToFriendRequest(id: request.id, accept: accept); notice = (accept ? "Arkadaşlık isteği kabul edildi." : "Arkadaşlık isteği reddedildi.").tempoLocalized; await refresh(clearNotice: false) }
        catch { notice = error.localizedDescription.tempoLocalized }
    }

    private func createChallenge() async {
        guard !working, let share = creationHealthSharing, !share || (model.healthSyncEnabled && !model.isHealthSyncing) else { return }
        working = true; defer { working = false }
        do {
            let submittedTitle = title
            let submittedFriends = selectedFriends
            let name = submittedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let created = try await account.createSocialChallenge(title: name.isEmpty ? "Haftalık hareket".tempoLocalized : name, metric: metric, friendIds: Array(submittedFriends), shareHealth: share)
            retainChallengeResponse(created)
            if title == submittedTitle { title = "" }
            if selectedFriends == submittedFriends { selectedFriends.removeAll() }
            notice = "Mücadele daveti gönderildi. Arkadaşın kabul ettiğinde katılır.".tempoLocalized
            showChallengeComposer = false
            selectedSection = .challenges
            showChallengeFeedback = true
        } catch { notice = error.localizedDescription.tempoLocalized; showChallengeFeedback = true }
    }

    private func retainChallengeResponse(_ challenge: TempoSocialChallenge) {
        createdChallenges.removeAll { $0.id == challenge.id }
        createdChallenges.insert(challenge, at: 0)
        if createdChallenges.count > 40 { createdChallenges = Array(createdChallenges.prefix(40)) }
    }

    private func confirmChallengeHealth(_ challenge: TempoSocialChallenge, enabled: Bool) async {
        guard !working, !enabled || (model.healthSyncEnabled && !model.isHealthSyncing) else { return }
        working = true; defer { working = false }
        do {
            let updated: TempoSocialChallenge
            if challenge.myStatus == "invited" {
                updated = try await account.respondToSocialChallenge(id: challenge.id, action: "accept", share: enabled)
            } else {
                updated = try await account.setSocialChallengeHealthSharing(id: challenge.id, enabled: enabled)
            }
            retainChallengeResponse(updated)
            pendingHealthChallenge = nil
            notice = "Yarışma paylaşım tercihin kaydedildi.".tempoLocalized
            await refresh(clearNotice: false)
        } catch { notice = error.localizedDescription.tempoLocalized }
    }

    private func removeFriend(_ profile: TempoSocialProfile) async {
        guard !working else { return }
        working = true; defer { working = false }
        do {
            try await account.removeSocialFriend(userId: profile.id)
            removedFriendIds.insert(profile.id)
            selectedFriends.remove(profile.id)
            pendingRemoveFriend = nil
            notice = "social.friend.removed".tempoLocalized
            await refresh(clearNotice: false)
        } catch { notice = error.localizedDescription.tempoLocalized }
    }

    private func cancelChallenge(_ challenge: TempoSocialChallenge) async {
        guard !working else { return }
        working = true; defer { working = false }
        do {
            try await account.cancelSocialChallenge(id: challenge.id)
            cancelledChallengeIds.insert(challenge.id)
            createdChallenges.removeAll { $0.id == challenge.id }
            pendingCancelChallenge = nil
            notice = "social.challenge.cancelled".tempoLocalized
            await refresh(clearNotice: false)
        } catch { notice = error.localizedDescription.tempoLocalized }
    }

    private func updateChallenge(_ challenge: TempoSocialChallenge, action: String) async {
        guard !working else { return }
        working = true; defer { working = false }
        do {
            let updated = try await account.respondToSocialChallenge(id: challenge.id, action: action)
            retainChallengeResponse(updated)
            notice = "Yarışma davetin güncellendi.".tempoLocalized
            await refresh(clearNotice: false)
        } catch { notice = error.localizedDescription.tempoLocalized }
    }

    private func shareHealth(_ challenge: TempoSocialChallenge, enabled: Bool) async {
        guard !working else { return }
        working = true; defer { working = false }
        do {
            let updated = try await account.setSocialChallengeHealthSharing(id: challenge.id, enabled: enabled)
            retainChallengeResponse(updated)
            notice = "Yarışma paylaşım tercihin kaydedildi.".tempoLocalized
            await refresh(clearNotice: false)
        } catch { notice = error.localizedDescription.tempoLocalized }
    }

    @ViewBuilder
    private func safetyMenu(for profile: TempoSocialProfile) -> some View {
        if friends.contains(where: { $0.id == profile.id }) {
            Button("social.friend.remove".tempoLocalized, systemImage: "person.badge.minus", role: .destructive) {
                pendingRemoveFriend = profile; showRemoveFriendConfirmation = true
            }
        }
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
            if blocked { createdChallenges.removeAll { $0.participants.contains(where: { $0.userId == profile.id }) } }
            notice = (blocked ? "Kullanıcı engellendi." : "Engel kaldırıldı.").tempoLocalized
            pendingBlockProfile = nil
            await refresh(clearNotice: false)
        } catch { notice = error.localizedDescription.tempoLocalized }
    }

    private func reportUser(_ profile: TempoSocialProfile, category: String) async {
        guard !working else { return }
        working = true; defer { working = false }
        do {
            try await account.reportSocialUser(userId: profile.id, category: category)
            notice = "Bildirim inceleme kuyruğuna gönderildi.".tempoLocalized
        } catch { notice = error.localizedDescription.tempoLocalized }
    }

    private func reportChallenge(_ challenge: TempoSocialChallenge, category: String) async {
        guard !working else { return }
        working = true; defer { working = false }
        do {
            try await account.reportSocialChallenge(id: challenge.id, category: category)
            notice = "Bildirim inceleme kuyruğuna gönderildi.".tempoLocalized
        } catch { notice = error.localizedDescription.tempoLocalized }
    }
}

private struct SocialHealthConsent: View {
    @EnvironmentObject private var model: TempoAppModel
    let metric: TempoSocialMetric
    let isWorking: Bool
    var selected: Bool? = nil
    let onChoose: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("social.health.title".tempoLocalized, systemImage: "heart.text.square.fill")
                .font(.headline).foregroundStyle(.pink)
            Text("social.health.detail".tempoFormatted(metric.title))
                .font(.subheadline).foregroundStyle(TempoTheme.secondary).fixedSize(horizontal: false, vertical: true)
            if !model.healthSyncEnabled {
                Button { model.connectAppleHealth() } label: {
                    Label("social.health.connect".tempoLocalized, systemImage: "heart.fill")
                }.buttonStyle(TempoPrimaryButtonStyle()).disabled(isWorking || model.isHealthSyncing)
            }
            if model.isHealthSyncing {
                ProgressView("social.health.connecting".tempoLocalized).tint(TempoTheme.green)
            }
            if let error = model.healthError {
                Text(error.tempoLocalized).font(.footnote).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Button { onChoose(true) } label: {
                Label("social.health.share".tempoLocalized, systemImage: selected == true ? "checkmark.circle.fill" : "heart.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(TempoSecondaryButtonStyle()).disabled(isWorking || !model.healthSyncEnabled || model.isHealthSyncing)
                .accessibilityIdentifier("social.health.share")
            Button { onChoose(false) } label: {
                Label("social.health.private".tempoLocalized, systemImage: selected == false ? "checkmark.circle.fill" : "hand.raised")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(TempoSecondaryButtonStyle()).disabled(isWorking)
                .accessibilityIdentifier("social.health.private")
            Text("social.health.noData".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(16).background(TempoTheme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct SocialAvatar: View {
    let profile: TempoSocialProfile
    var size: CGFloat = 44
    @State private var image: UIImage?
    private var name: String { profile.displayName.isEmpty ? profile.username : profile.displayName }

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Text(String(name.prefix(1)).uppercased()).font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(TempoTheme.green).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .frame(width: size, height: size).background(TempoTheme.green.opacity(0.12))
        .clipShape(Circle()).overlay(Circle().stroke(TempoTheme.primary.opacity(0.10), lineWidth: 1))
        .accessibilityHidden(true)
        .task(id: profile.avatarBase64) {
            image = nil
            guard let raw = profile.avatarBase64 else { return }
            let encoded = raw.contains(",") ? String(raw.split(separator: ",", maxSplits: 1).last ?? "") : raw
            guard let data = Data(base64Encoded: encoded), let source = UIImage(data: data) else { return }
            image = source.preparingThumbnail(of: CGSize(width: 128, height: 128)) ?? source
        }
    }
}

private struct SocialPersonRow: View {
    let profile: TempoSocialProfile
    let detail: String
    var body: some View {
        HStack(spacing: 12) {
            SocialAvatar(profile: profile)
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName.isEmpty ? profile.username : profile.displayName)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(TempoTheme.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail).font(.caption).foregroundStyle(TempoTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
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
                    .foregroundStyle(TempoTheme.primary)
            }
            Text(title.tempoLocalized)
                .font(.caption.weight(.medium))
                .foregroundStyle(TempoTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(color.opacity(0.18), lineWidth: 1))
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
                SocialAvatar(profile: participant.user, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(participant.user.displayName.isEmpty ? participant.user.username : participant.user.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TempoTheme.primary)
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
                        .foregroundStyle(isCurrentUser ? TempoTheme.green : TempoTheme.primary.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else if participant.status == "accepted" {
                    Text((participant.shareHealth ? "Veri bekleniyor" : "—").tempoLocalized)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(TempoTheme.secondary)
                }
            }

            if participant.score != nil {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(TempoTheme.primary.opacity(0.08))
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
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(isCurrentUser ? TempoTheme.green.opacity(0.22) : TempoTheme.primary.opacity(0.04), lineWidth: 1))
    }
}

private struct SocialChallengeCard: View {
    let challenge: TempoSocialChallenge
    let isWorking: Bool
    let onAction: (String) -> Void
    let onShareChange: (Bool) -> Void
    let onReport: (String) -> Void
    let onCancel: () -> Void
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
                if let starts = TempoFormat.date(from: challenge.startsAt) {
                    Text("Başlangıç: %@".tempoFormatted(starts.formatted(date: .abbreviated, time: .shortened)))
                        .font(.caption).foregroundStyle(TempoTheme.secondary)
                    if starts > Date() {
                        Text("Skorlar mücadele başladığında hesaplanır.").font(.caption2).foregroundStyle(TempoTheme.secondary)
                    }
                }
                if challenge.myStatus == "invited" {
                    Text("Bir arkadaşın seni bu haftalık yarışmaya çağırdı.").font(.caption).foregroundStyle(TempoTheme.secondary)
                    HStack {
                        Button("Katıl") { onAction("accept") }.buttonStyle(TempoPrimaryButtonStyle()).disabled(isWorking)
                        Button("Reddet") { onAction("decline") }.buttonStyle(TempoSecondaryButtonStyle()).disabled(isWorking)
                    }
                } else if challenge.myStatus == "accepted" {
                    Button { onShareChange(!challenge.myShareHealth) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("social.health.manage".tempoLocalized, systemImage: challenge.myShareHealth ? "heart.fill" : "heart")
                                .font(.subheadline.weight(.semibold))
                            Text((challenge.myShareHealth ? "Paylaşım açık" : "Paylaşım kapalı").tempoLocalized)
                                .font(.caption).foregroundStyle(TempoTheme.secondary)
                        }.foregroundStyle(challenge.myShareHealth ? TempoTheme.green : TempoTheme.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(TempoSecondaryButtonStyle()).disabled(isWorking)
                        .accessibilityValue((challenge.myShareHealth ? "Paylaşım açık" : "Paylaşım kapalı").tempoLocalized)
                    Text("Paylaşım yalnızca %@ toplamını kapsar. Günlük kayıtların ve diğer Sağlık verilerin görünmez.".tempoFormatted(metric.title.lowercased()))
                        .font(.caption2).foregroundStyle(TempoTheme.secondary).fixedSize(horizontal: false, vertical: true)
                    ForEach(sortedParticipants.indices, id: \.self) { index in
                        let participant = sortedParticipants[index]
                        SocialParticipantRow(participant: participant, rank: index + 1, myUserId: challenge.myUserId, metric: metric, maxScore: leaderScore)
                    }
                    Text("Skorlar yalnızca paylaşmayı açan katılımcılar için görünür.").font(.caption2).foregroundStyle(TempoTheme.secondary)
                }
                if challenge.creatorId == challenge.myUserId {
                    Button(role: .destructive) { onCancel() } label: {
                        Label("social.challenge.cancel".tempoLocalized, systemImage: "xmark.circle")
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.plain).disabled(isWorking).accessibilityIdentifier("social.challenge.cancel.\(challenge.id)")
                }
            }
        }
    }
}

private struct MoreScreen: View {
    @EnvironmentObject private var model: TempoAppModel

    var body: some View {
        NavigationStack {
            TempoPage {
                PageTitle(title: "Profil", subtitle: "Hesabın, araçların ve bağlantıların")
                AccountProfileCard()
                SectionHeading(title: "Hesabın", caption: "", padding: false)
                TempoCard {
                    VStack(spacing: 0) {
                        item("Hesap ayarları", "Profilini, sporlarını ve güvenliği düzenle", "gearshape", destination: AccountSettingsScreen()).accessibilityIdentifier("more.accountSettings")
                        Divider().overlay(TempoTheme.primary.opacity(0.06))
                        item("appearance.title", "appearance.subtitle", "circle.lefthalf.filled", destination: TempoAppearanceSettingsScreen()).accessibilityIdentifier("more.appearance")
                        Divider().overlay(TempoTheme.primary.opacity(0.06))
                        item("Bildirimler", "Tercihler ve gelen bildirimler", "bell", destination: TempoNotificationsScreen()).accessibilityIdentifier("more.notifications")
                        Divider().overlay(TempoTheme.primary.opacity(0.06))
                        item("Profil kartını oluştur", "PNG olarak kaydet veya paylaş", "square.and.arrow.up", destination: TempoProfileShareScreen())
                    }
                }
                SectionHeading(title: "Topluluk ve koçluk", caption: "", padding: false)
                TempoCard {
                    VStack(spacing: 0) {
                        item("Sosyal", "Arkadaşlar ve mücadeleler", "person.2", destination: SocialScreen()).accessibilityIdentifier("more.social")
                        Divider().overlay(TempoTheme.primary.opacity(0.06))
                        item("Tempo Koç", "Spor ve sağlıklı yaşam için sohbet", "sparkles", destination: CoachScreen()).accessibilityIdentifier("more.coach")
                        Divider().overlay(TempoTheme.primary.opacity(0.06))
                        item("Başarılar", "Seviye ve rozetlerin", "medal", destination: AchievementsScreen())
                    }
                }
                SectionHeading(title: "İlerlemen", caption: "", padding: false)
                TempoCard {
                    VStack(spacing: 0) {
                        item("Aylık", "Son 6 ay", "chart.bar", destination: MonthlyStatsScreen()).accessibilityIdentifier("more.monthly")
                        Divider().overlay(TempoTheme.primary.opacity(0.06))
                        item("Yıl Özeti", "Bu yılın", "calendar", destination: YearSummaryScreen())
                        Divider().overlay(TempoTheme.primary.opacity(0.06))
                        item("Eddington", "Koşu istikrarın", "figure.run", destination: EddingtonScreen())
                    }
                }
                SectionHeading(title: "Keşfet", caption: "", padding: false)
                TempoCard {
                    VStack(spacing: 0) {
                        item("Spor Alanları", "Yakınındaki tesisler", "mappin.and.ellipse", destination: NearbyFacilitiesScreen())
                        Divider().overlay(TempoTheme.primary.opacity(0.06))
                        item("Rotalar", "Aktivite rotaların", "map", destination: RoutesScreen())
                    }
                }
                SectionHeading(title: "Bağlantılar", caption: "", padding: false)
                TempoCard {
                    item("Apple Sağlık", "Uyku, hareket ve sağlık izinleri", "heart.text.square", destination: HealthScreen())
                }
                TempoDisclosureSection(title: "Strava araçları", icon: "link") {
                    VStack(spacing: 10) {
                        if let dashboard = model.dashboard { StravaConnectionCard(dashboard: dashboard) }
                        else if model.isConnected { LoadingDashboardCard() }
                        else { StravaOptionalCard(title: "Strava bağlantısı isteğe bağlı", message: "Strava araçlarını kullanmak istersen buradan bağlanabilirsin.") }
                        item("Ekipman", "Bisiklet ve ayakkabı", "bicycle", destination: GearScreen())
                        item("Segmentler", "Favorilerin", "flag.checkered", destination: SegmentsScreen())
                        item("Fotoğraflar", "Aktivitelerden", "photo", destination: PhotosScreen())
                        if model.isConnected {
                            Button(role: .destructive, action: model.disconnect) {
                                Label("Strava bağlantısını kes", systemImage: "link.badge.minus").frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(TempoSecondaryButtonStyle()).disabled(model.isBusy)
                        }
                        Text(model.status.tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) { legalLinks }
                    VStack(spacing: 12) { legalLinks }
                }.font(.footnote).tint(TempoTheme.secondary).padding(.vertical, 10)
            }
            .refreshable { await model.reloadAll() }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func item<Destination: View>(_ title: String, _ subtitle: String, _ icon: String, destination: Destination) -> some View {
        NavigationLink(destination: destination) { TempoMenuRow(title: title, subtitle: subtitle, icon: icon) }.buttonStyle(TempoSoftPressStyle())
    }
    @ViewBuilder private var legalLinks: some View {
        Link("Gizlilik Politikası".tempoLocalized, destination: URL(string: "https://apitempo.com/privacy")!)
        Link("Kullanım Koşulları".tempoLocalized, destination: URL(string: "https://apitempo.com/terms")!)
    }
}

private struct HealthScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    @EnvironmentObject private var account: TempoAccountStore
    @StateObject private var wellness = TempoWellnessStore()
    @State private var selectedHealthDay: Date?
    @Environment(\.dynamicTypeSize) private var textSize
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12), count: textSize.isAccessibilitySize ? 1 : 2) }
    private var progress: Double { min(Double(model.todayWaterMl) / Double(model.dailyGoalMl), 1) }

    var body: some View {
        TempoPage {
            PageTitle(title: "Sağlık", subtitle: "wellness.health.subtitle")
#if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-healthkit") { SimulatorHealthIntegrationPanel() }
#endif
            wellnessHero
            if let checkIn = wellness.todayCheckIn { TempoCard { TempoCheckInComparison(entry: checkIn, balance: model.tempoBalance) } }
            dailyRings
            if model.healthSyncEnabled { sleepPreview }
            TempoWellnessTools(store: wellness)
            healthOverview
            if !model.healthAvailable {
                TempoCard { Label("Apple Sağlık bu cihazda kullanılamıyor.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(TempoTheme.orange) }
            } else if !model.healthSyncEnabled { connectCard }
            if let error = model.healthError {
                Label(error.tempoLocalized, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(TempoTheme.orange)
            }
            if let error = model.healthWorkoutError {
                Text(error).font(.footnote).foregroundStyle(TempoTheme.orange).frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.healthSyncEnabled {
                TempoDisclosureSection(title: "wellness.measurements", icon: "chart.xyaxis.line") {
                    VStack(spacing: 16) {
                        HealthDaySelector(points: healthPoints, selectedDay: $selectedHealthDay)
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
                        TempoDisclosureSection(title: "Uyku ayrıntıları", icon: "moon") { SleepDetailCard(points: healthPoints, selectedDay: $selectedHealthDay) }
                        TempoDisclosureSection(title: "Kalp ve kondisyon", icon: "heart") { CardioFitnessCard(points: healthPoints) }
                        if let balance = model.tempoBalance {
                            TempoDisclosureSection(title: "Tempo Dengesi ayrıntıları", icon: "gauge.with.dots.needle.33percent") { TempoBalanceDetailCard(balance: balance) }
                        }

                    }
                }
            }
            TempoDisclosureSection(title: "wellness.connection", icon: "heart.text.square") {
                VStack(alignment: .leading, spacing: 14) {
                    if let sync = model.healthLastSync {
                        Text("wellness.lastSync".tempoFormatted(sync.formatted(date: .abbreviated, time: .shortened))).font(.caption).foregroundStyle(TempoTheme.secondary)
                    }
                    if let error = model.healthError {
                        Text(error.tempoLocalized).font(.footnote).foregroundStyle(TempoTheme.orange).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let error = model.healthWorkoutError {
                        Text(error).font(.footnote).foregroundStyle(TempoTheme.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
            }
        }
        .navigationTitle("Sağlık").navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
        .onAppear { selectLatestHealthDayIfNeeded(); wellness.reload() }
        .onChange(of: model.healthDays) { _, _ in selectLatestHealthDayIfNeeded() }
        .task(id: account.profile?.id) { wellness.bind(account.profile?.id) }
    }

    private var wellnessHero: some View {
        TempoCard {
            VStack(spacing: 16) {
                HStack {
                    Label("wellness.daily".tempoLocalized, systemImage: "heart.text.square").font(.caption).foregroundStyle(TempoTheme.secondary)
                    Spacer()
                    Text(Date.now.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(TempoTheme.secondary)
                }
                ZStack {
                    Circle().stroke(TempoTheme.primary.opacity(0.06), lineWidth: 12)
                    if let balance = model.tempoBalance {
                        Circle().trim(from: 0, to: CGFloat(min(100, max(0, balance.value))) / 100)
                            .stroke(AngularGradient(colors: [TempoTheme.blue, TempoTheme.green], center: .center), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    VStack(spacing: 8) {
                        Text("Tempo Dengesi".tempoLocalized).font(.subheadline).foregroundStyle(TempoTheme.secondary)
                        if let balance = model.tempoBalance {
                            Text("\(balance.value)").font(.system(size: 48, weight: .medium, design: .rounded).monospacedDigit())
                            Text("/ 100").font(.subheadline).foregroundStyle(TempoTheme.secondary)
                        } else {
                            Text("—").font(.system(size: 48, weight: .light))
                            Text("wellness.waitingData".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary).multilineTextAlignment(.center)
                        }
                    }.padding(20)
                }.frame(width: 224, height: 224).padding(.vertical, 8)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Tempo Dengesi".tempoLocalized)
                    .accessibilityValue(model.tempoBalance.map { "\($0.value) / 100" } ?? "wellness.waitingData".tempoLocalized)
                if let balance = model.tempoBalance {
                    Text(balance.state.tempoLocalized).font(.headline).foregroundStyle(TempoTheme.green)
                    Text(balance.confidence.tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
                    if let note = balance.dataNote { Text(note).font(.caption).foregroundStyle(TempoTheme.secondary).multilineTextAlignment(.center) }
                    NavigationLink(destination: TempoPage { TempoBalanceDetailCard(balance: balance) }.navigationTitle("Tempo Dengesi").tempoGlassBackButton()) {
                        Label("wellness.scoreDetails".tempoLocalized, systemImage: "arrow.up.right").font(.subheadline.weight(.medium)).frame(minHeight: 44)
                    }.buttonStyle(.plain).foregroundStyle(TempoTheme.green)
                } else {
                    Text("Tempo Dengesi için henüz yeterli ölçüm yok. Apple Sağlık verileri geldikçe puanın oluşacak.").font(.caption).foregroundStyle(TempoTheme.secondary).multilineTextAlignment(.center)
                }
            }.frame(maxWidth: .infinity)
        }
    }

    private var dailyRings: some View {
        let steps = model.todayHealth.steps
        let minutes = model.todayHealth.exerciseMinutes
        let water = (model.healthSyncEnabled ? model.todayWaterMl : 0) + wellness.localWaterTotal
        return TempoMetricGrid(columns: 3) {
            HealthSummaryRing(title: "Adım", value: whole(steps), caption: "wellness.today", symbol: "figure.walk", color: TempoTheme.blue, progress: nil)
            HealthSummaryRing(title: "Egzersiz", value: whole(minutes), caption: "dk", symbol: "figure.run", color: TempoTheme.green, progress: nil)
            HealthSummaryRing(title: "Su", value: water.formatted(), caption: "ml", symbol: "drop.fill", color: TempoTheme.orange, progress: Double(water) / Double(max(1, wellness.waterGoal)))
        }
    }

    private var sleepPreview: some View {
        let point = healthPoints.last { ($0.metrics.sleepMinutes ?? 0) > 0 }
        return NavigationLink(destination: TempoPage {
            PageTitle(title: "Uyku ayrıntıları", subtitle: "wellness.sleep.history")
            SleepDetailCard(points: healthPoints, selectedDay: $selectedHealthDay)
        }.navigationTitle("Uyku ayrıntıları").tempoGlassBackButton().onAppear {
            if selectedPoint?.metrics.sleepMinutes == nil, let point { selectedHealthDay = point.day }
        }) {
            TempoCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("wellness.sleep".tempoLocalized, systemImage: "moon.zzz.fill").font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(TempoTheme.secondary)
                    }
                    if let point {
                        Text(TempoFormat.duration((point.metrics.sleepMinutes ?? 0) * 60)).font(.title2.weight(.semibold)).foregroundStyle(TempoTheme.blue)
                        Text(point.day.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(TempoTheme.secondary)
                        HStack(alignment: .top, spacing: 12) {
                            sleepStage("wellness.sleep.core", minutes: point.metrics.sleepCoreMinutes, color: TempoTheme.blue)
                            sleepStage("wellness.sleep.deep", minutes: point.metrics.sleepDeepMinutes, color: TempoTheme.purple)
                            sleepStage("REM", minutes: point.metrics.sleepREMMinutes, color: TempoTheme.green)
                        }
                    } else { Text("wellness.sleep.empty".tempoLocalized).font(.subheadline).foregroundStyle(TempoTheme.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.buttonStyle(.plain).foregroundStyle(TempoTheme.primary)
            .simultaneousGesture(TapGesture().onEnded { if let point { selectedHealthDay = point.day } })
    }

    private func sleepStage(_ title: String, minutes: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Capsule().fill(color.opacity(0.6)).frame(height: 4)
            Text(title.tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
            Text(minutes.map { TempoFormat.duration($0 * 60) } ?? "—").font(.caption.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
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

    private var healthOverview: some View { TempoWellnessWaterCard(store: wellness) }

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

private struct HealthSummaryRing: View {
    let title: String
    let value: String
    let caption: String
    let symbol: String
    let color: Color
    let progress: Double?
    var body: some View {
        VStack(spacing: 8) {
            Text(title.tempoLocalized).font(.caption.weight(.medium)).foregroundStyle(TempoTheme.secondary)
            ZStack {
                Circle().stroke(color.opacity(0.13), lineWidth: 5)
                Circle().trim(from: 0, to: CGFloat(min(1, max(0, progress ?? (value == "—" ? 0 : 1)))))
                    .stroke(color.opacity(progress == nil ? 0.55 : 1), style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                VStack(spacing: 3) {
                    Image(systemName: symbol).font(.caption).foregroundStyle(color)
                    Text(value).font(.subheadline.weight(.semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.65)
                    Text(caption.tempoLocalized).font(.system(size: 9)).foregroundStyle(TempoTheme.secondary)
                }.padding(9)
            }.frame(maxWidth: 110).aspectRatio(1, contentMode: .fit)
        }.padding(10).frame(maxWidth: .infinity).background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .ignore).accessibilityLabel(title.tempoLocalized).accessibilityValue(value + " " + caption.tempoLocalized)
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
                                    .foregroundStyle(isSelected ? TempoTheme.onAccent : TempoTheme.primary)
                                    .frame(width: 64, height: 76)
                                    .background(isSelected ? TempoTheme.green : TempoTheme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(isSelected ? TempoTheme.green : TempoTheme.primary.opacity(0.06)))
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
                            Circle().stroke(TempoTheme.primary.opacity(0.08), lineWidth: 10)
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
                        .font(.subheadline).foregroundStyle(TempoTheme.primary.opacity(0.76)).lineSpacing(3)
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
                            AxisGridLine().foregroundStyle(TempoTheme.primary.opacity(0.06))
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
                            AxisGridLine().foregroundStyle(TempoTheme.primary.opacity(0.06))
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
                        Divider().overlay(TempoTheme.primary.opacity(0.08))
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
                        Capsule().fill(TempoTheme.primary.opacity(0.07))
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 15, weight: .medium)).foregroundStyle(color)
                    .frame(width: 30, height: 30).background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                Text(title.tempoLocalized).font(.caption.weight(.medium)).foregroundStyle(TempoTheme.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(minHeight: 34, alignment: .leading)
            Text(value).font(.system(.title2, design: .rounded).weight(.semibold).monospacedDigit()).fixedSize(horizontal: false, vertical: true)
            Text(unit.isEmpty ? " " : unit.tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading).padding(16)
        .modifier(TempoSurface())
        .accessibilityElement(children: .combine)
        .multilineTextAlignment(.leading)
    }
}

private struct TempoBalanceHomeCard: View {
    let balance: TempoBalanceScore

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(TempoTheme.primary.opacity(0.08), lineWidth: 7)
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
                if let note = balance.dataNote { Text(note).font(.caption2).foregroundStyle(TempoTheme.secondary) }
                Text(balance.recommendation.tempoLocalized)
                    .font(.caption)
                    .foregroundStyle(TempoTheme.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(TempoTheme.primary.opacity(0.3))
        }
        .foregroundStyle(TempoTheme.primary)
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
    @EnvironmentObject private var account: TempoAccountStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var wellness = TempoWellnessStore()

    var body: some View {
        TempoCard {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 18) {
                    ZStack {
                        Circle().stroke(TempoTheme.primary.opacity(0.08), lineWidth: 11)
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

                if let note = balance.dataNote { Text(note).font(.caption).foregroundStyle(TempoTheme.secondary) }
                if let checkIn = wellness.todayCheckIn { TempoCheckInComparison(entry: checkIn, balance: balance) }
                Text(balance.recommendation.tempoLocalized)
                    .font(.subheadline)
                    .foregroundStyle(TempoTheme.primary.opacity(0.76))
                    .lineSpacing(4)

                Divider().overlay(TempoTheme.primary.opacity(0.08))

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
        .task(id: account.profile?.id) { wellness.bind(account.profile?.id) }
        .onAppear { wellness.reload() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { wellness.reload() } }
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
                        Capsule().fill(TempoTheme.primary.opacity(0.07))
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedMonth: Date?
    @State private var metric = 0

    private var workouts: [TempoManualWorkout] { model.activityWorkouts }
    private var stats: [TempoMonthStat] {
        TempoWorkoutLedger.months(workouts.map { TempoWorkoutLedger.Record(id: $0.id, sportID: $0.sportId, startedAt: $0.startedAt, seconds: Double($0.durationSeconds ?? $0.durationMinutes * 60), distanceKm: $0.distanceKm, source: $0.recordSource ?? "manual") })
    }
    private var selection: TempoMonthStat? { stats.first { $0.date == selectedMonth } ?? stats.last }
    private var selectedWorkouts: [TempoManualWorkout] {
        guard let month = selection?.date else { return [] }
        return workouts.filter { Calendar.current.isDate($0.startedAt, equalTo: month, toGranularity: .month) }
    }
    private var accent: Color { metric == 1 ? TempoTheme.blue : metric == 2 ? TempoTheme.purple : TempoTheme.green }
    private var metricTitle: String { metric == 1 ? "Dakika".tempoLocalized : metric == 2 ? "Kilometre".tempoLocalized : "Antrenman".tempoLocalized }
    private func value(_ item: TempoMonthStat) -> Double { metric == 1 ? item.seconds / 60 : metric == 2 ? item.distanceKm : Double(item.count) }

    var body: some View {
        TempoPage {
            PageTitle(title: "Aylık İstatistikler", subtitle: "Son altı ay · Tempo ve Apple Sağlık")
            TempoCard {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(selection?.date.formatted(.dateTime.month(.wide).year()) ?? "")
                                .font(.title3.weight(.semibold))
                            Text("Hareketine daha geniş bak.").font(.caption).foregroundStyle(TempoTheme.secondary)
                        }
                        Spacer()
                        Image(systemName: "chart.bar.xaxis").font(.title2).foregroundStyle(accent)
                    }
                    Picker("Ölçüm", selection: $metric) {
                        Text("Antrenman").tag(0)
                        Text("Süre").tag(1)
                        Text("Mesafe").tag(2)
                    }.pickerStyle(.segmented).accessibilityIdentifier("monthly.metric")
                    Chart(stats) { item in
                        BarMark(x: .value("Ay".tempoLocalized, item.date, unit: .month), y: .value(metricTitle, value(item)))
                            .foregroundStyle(accent.opacity(item.date == selection?.date ? 1 : 0.35).gradient)
                            .cornerRadius(6)
                            .accessibilityLabel(item.date.formatted(.dateTime.month(.wide).year()))
                            .accessibilityValue("\(value(item).formatted(.number.precision(.fractionLength(0...1)))) \(metricTitle)")
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                    .chartYAxis { AxisMarks(position: .leading) }
                    .chartYScale(domain: 0...max(1, (stats.map(value).max() ?? 0) * 1.15))
                    .frame(height: 185)
                    .accessibilityIdentifier("monthly.chart")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(stats) { item in
                                Button {
                                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { selectedMonth = item.date }
                                } label: {
                                    Text(item.date.formatted(.dateTime.month(.abbreviated)))
                                        .font(.caption.weight(.semibold)).padding(.horizontal, 13).padding(.vertical, 10)
                                        .foregroundStyle(item.date == selection?.date ? TempoTheme.onAccent : TempoTheme.primary.opacity(0.8))
                                        .background(item.date == selection?.date ? accent : TempoTheme.raised, in: Capsule())
                                }.buttonStyle(.plain)
                                    .accessibilityLabel(item.date.formatted(.dateTime.month(.wide).year()))
                                    .accessibilityIdentifier(item.id == stats.last?.id ? "monthly.month.current" : "monthly.month.\(item.date.timeIntervalSince1970)")
                            }
                        }
                    }
                }
            }
            if let selection {
                TempoMetricGrid {
                    MetricCard(value: "\(selection.count)", label: "Antrenman", icon: "figure.run", color: TempoTheme.green)
                        .accessibilityElement(children: .ignore).accessibilityLabel("Antrenman".tempoLocalized).accessibilityValue("\(selection.count)").accessibilityIdentifier("monthly.total.workouts")
                    MetricCard(value: TempoFormat.duration(selection.seconds), label: "Süre", icon: "clock", color: TempoTheme.blue)
                        .accessibilityElement(children: .ignore).accessibilityLabel("Süre".tempoLocalized).accessibilityValue(TempoFormat.duration(selection.seconds)).accessibilityIdentifier("monthly.total.duration")
                    MetricCard(value: TempoFormat.distance(selection.distanceKm), label: "Mesafe", icon: "point.topleft.down.to.point.bottomright.curvepath", color: TempoTheme.purple)
                        .accessibilityElement(children: .ignore).accessibilityLabel("Mesafe".tempoLocalized).accessibilityValue(TempoFormat.distance(selection.distanceKm)).accessibilityIdentifier("monthly.total.distance")
                }
                Text("%d hareketli gün".tempoFormatted(selection.activeDays)).font(.subheadline.weight(.medium)).foregroundStyle(TempoTheme.secondary)
                if selection.count > 0 && selection.distanceRecordCount == 0 {
                    Text("Bu ayki sporlarda mesafe kaydı yok. Süre ve antrenman sayısı yine de özetine katılır.")
                        .font(.caption).foregroundStyle(TempoTheme.secondary)
                }
            }
            Text("Tempo ve Apple Sağlık kayıtları kullanılır; aynı antrenman bir kez sayılır. Apple Sağlık geçmişi son 12 ayla sınırlıdır.")
                .font(.caption2).foregroundStyle(TempoTheme.secondary).lineSpacing(3)
            SectionHeading(title: "Ayın antrenmanları", caption: "TEMPO + APPLE SAĞLIK", padding: false)
            if selectedWorkouts.isEmpty {
                EmptyCard(icon: "calendar", text: "Bu ay henüz antrenman yok. Başka bir ay seçebilir veya Apple Sağlık kayıtlarını eşitleyebilirsin.")
            } else {
                ForEach(selectedWorkouts) { workout in
                    ManualWorkoutRow(workout: workout).accessibilityIdentifier("monthly.workout.\(workout.sportId)")
                }
            }
        }
        .refreshable { await model.reloadAll() }
        .navigationTitle("Aylık").navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
        .accessibilityIdentifier("screen.monthly")
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
                                    Text(segment.name ?? "İsimsiz segment".tempoLocalized).font(.headline).foregroundStyle(TempoTheme.primary)
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
    private var number: Int { eddingtonNumber(model.activityWorkouts) }
    var body: some View {
        TempoPage {
            PageTitle(title: "Eddington Sayısı", subtitle: "Tempo ve Apple Sağlık koşuların")
            if !model.activityWorkouts.contains(where: { $0.sportId == "run" && ($0.distanceKm ?? 0) > 0 }) {
                EmptyCard(icon: "figure.run", text: "Mesafesi bulunan koşuların geldikçe Eddington sayın oluşur.")
            } else {
                TempoCard {
                    VStack(spacing: 16) {
                        Text("\(number)").font(.system(size: 92, weight: .bold, design: .rounded)).foregroundStyle(TempoTheme.green)
                        Text("%d farklı günde en az %d km koştun.".tempoFormatted(number, number)).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                        Text("Mesafesi bulunan Tempo ve Apple Sağlık koşuları sayılır.").font(.subheadline).foregroundStyle(TempoTheme.secondary).multilineTextAlignment(.center)
                    }.padding(.vertical, 28).frame(maxWidth: .infinity)
                }
            }
        }.navigationTitle("Eddington").navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
    }
}

private struct YearSummaryScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    private var workouts: [TempoManualWorkout] {
        model.activityWorkouts.filter { workout in
            Calendar.current.isDate(workout.startedAt, equalTo: Date(), toGranularity: .year)
        }
    }
    var body: some View {
        TempoPage {
            PageTitle(title: "%d Özeti".tempoFormatted(Calendar.current.component(.year, from: Date())), subtitle: "Tempo ve Apple Sağlık antrenmanların")
            if workouts.isEmpty {
                EmptyCard(icon: "calendar", text: "Bu yılki Tempo ve Apple Sağlık antrenmanların burada görünür.")
            } else {
                VStack(spacing: 10) {
                    SummaryLine(icon: "figure.run", title: "Antrenman", value: "\(workouts.count)", color: TempoTheme.orange)
                    SummaryLine(icon: "arrow.left.and.right", title: "Toplam mesafe", value: TempoFormat.distance(workouts.reduce(0) { $0 + ($1.distanceKm ?? 0) }), color: TempoTheme.green)
                    SummaryLine(icon: "clock.fill", title: "Hareket süresi", value: TempoFormat.duration(workouts.reduce(0) { $0 + Double($1.durationSeconds ?? $1.durationMinutes * 60) }), color: TempoTheme.blue)
                    SummaryLine(icon: "trophy.fill", title: "En uzun seans", value: TempoFormat.duration(workouts.map { Double($0.durationSeconds ?? $0.durationMinutes * 60) }.max() ?? 0), color: TempoTheme.orange)
                }
            }
        }.navigationTitle("Yıl Özeti").navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
    }
}

private struct PhotosScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    private let columns = [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)]
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
                                Text(photo.activityName ?? "Aktivite".tempoLocalized).font(.caption.weight(.semibold)).foregroundStyle(TempoTheme.primary).lineLimit(1)
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
        .multilineTextAlignment(.leading)
    }
}

private struct HomeHeader: View {
    @ObservedObject private var notifications = TempoNotifications.shared
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
                    .accessibilityIdentifier("screen.summary")
                Text(dateText.prefix(1).uppercased() + dateText.dropFirst())
                    .font(.title3.bold())
            }
            Spacer()
            NavigationLink(destination: TempoNotificationsScreen()) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell").font(.system(size: 18, weight: .medium)).frame(width: 44, height: 44)
                    if notifications.unreadCount > 0 { Circle().fill(TempoTheme.green).frame(width: 7, height: 7).offset(x: -7, y: 6) }
                }.foregroundStyle(TempoTheme.primary.opacity(0.88)).background(.ultraThinMaterial, in: Circle())
            }.buttonStyle(.plain).accessibilityLabel("Bildirimler".tempoLocalized).accessibilityIdentifier("home.notifications")
        }
    }
}

struct PageTitle: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.tempoLocalized)
                .font(.title.weight(.bold)).tracking(-0.4)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("page.title.\(title)")
                .accessibilityAddTraits(.isHeader)
            Text(subtitle.tempoLocalized).font(.subheadline).foregroundStyle(TempoTheme.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
    }
}

private struct StravaConnectionCard: View {
    let dashboard: TempoDashboard

    private var athlete: TempoAthlete { dashboard.athlete }

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
                        .foregroundStyle(TempoTheme.primary)
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
                        .font(.headline).foregroundStyle(TempoTheme.primary).lineLimit(1)
                    Text("Strava hesabın bağlı".tempoLocalized)
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

struct TempoCard<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(textSize.isAccessibilitySize ? 16 : 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(TempoSurface())
    }
}

private struct MetricCard: View {
    let value: String; let label: String; let icon: String; let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(color)
            Text(value).font(.title3.monospacedDigit().weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Text(label.tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .modifier(TempoSurface(radius: 22))
        .accessibilityElement(children: .combine)
    }
}

struct SectionHeading: View {
    let title: String; let caption: String; var padding = true
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !caption.isEmpty { Text(caption.tempoLocalized).font(.caption2.weight(.medium)).foregroundStyle(TempoTheme.secondary).fixedSize(horizontal: false, vertical: true) }
            Text(title.tempoLocalized).font(.headline).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
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
                Text(activity.name ?? activity.sport.title).font(.subheadline.weight(.semibold)).foregroundStyle(TempoTheme.primary).lineLimit(1)
                Text("\(activity.sport.title) · \(activity.date.map { TempoFormat.shortDate.string(from: $0) } ?? "")").font(.caption).foregroundStyle(TempoTheme.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if activity.sport.supportsDistance { Text(activity.sport.distanceText(activity.distanceKm)).font(.subheadline.bold()).foregroundStyle(TempoTheme.primary) }
                Text(TempoFormat.duration(activity.movingSeconds)).font(.subheadline.weight(.medium)).foregroundStyle(TempoTheme.primary.opacity(0.85))
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(TempoTheme.primary.opacity(0.25))
        }
        .padding(14)
        .background(TempoTheme.card.opacity(0.88), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(TempoTheme.primary.opacity(0.065), lineWidth: 1))
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
                        .foregroundStyle(TempoTheme.primary)
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
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(TempoTheme.primary.opacity(0.075), lineWidth: 1))
    }
}

private struct DetailLine: View {
    let label: String; let value: String
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(label.tempoLocalized).foregroundStyle(TempoTheme.secondary).fixedSize()
                Spacer(minLength: 8)
                Text(value).fontWeight(.semibold).fixedSize()
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(label.tempoLocalized).foregroundStyle(TempoTheme.secondary)
                Text(value).fontWeight(.semibold)
            }
        }.font(.subheadline).padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SummaryLine: View {
    let icon: String; let title: String; let value: String; let color: Color
    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 40, height: 40).background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 16) { Text(title.tempoLocalized).fixedSize(); Spacer(minLength: 8); Text(value).foregroundStyle(color).fixedSize() }
                VStack(alignment: .leading, spacing: 6) { Text(title.tempoLocalized); Text(value).foregroundStyle(color) }
            }.font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct TempoPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold)).foregroundStyle(TempoTheme.onAccent)
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity, minHeight: 48)
            .background(TempoTheme.green.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .opacity(isEnabled ? 1 : 0.48)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct TempoSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold)).foregroundStyle(configuration.role == .destructive ? Color.red : TempoTheme.green)
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity, minHeight: 48)
            .background(TempoTheme.card.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(TempoTheme.primary.opacity(0.10), lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.48)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private func eddingtonNumber(_ workouts: [TempoManualWorkout]) -> Int {
    let calendar = Calendar.current
    var days: [Date: Double] = [:]
    for workout in workouts where workout.sportId == "run" {
        guard let distance = workout.distanceKm, distance > 0 else { continue }
        days[calendar.startOfDay(for: workout.startedAt), default: 0] += distance
    }
    let distances = days.values.sorted(by: >)
    var result = 0
    for (index, distance) in distances.enumerated() where distance >= Double(index + 1) { result = index + 1 }
    return result
}

private extension Calendar {
    func isDateInCurrentWeek(_ date: Date) -> Bool { isDate(date, equalTo: Date(), toGranularity: .weekOfYear) }
}

#if DEBUG && targetEnvironment(simulator)
private struct SimulatorHealthIntegrationPanel: View {
    @State private var result = "HEALTHKIT_READY"
    @State private var running = false
    var body: some View {
        VStack {
            Button("Run HealthKit integration") {
                running = true
                result = "HEALTHKIT_RUNNING"
                Task { @MainActor in
                    do { result = try await TempoHealthStore().runSimulatorIntegrationCheck() }
                    catch { result = "HEALTHKIT_FAIL " + error.localizedDescription }
                    running = false
                }
            }
            .accessibilityIdentifier("healthkit.integration.start")
            .disabled(running)
            Text(result).font(.caption)
                .accessibilityIdentifier("healthkit.integration.result")
        }
    }
}
#endif

