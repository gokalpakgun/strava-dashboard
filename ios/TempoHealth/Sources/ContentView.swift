import SwiftUI
import UIKit
import WebKit

private let tempoGreen = Color(red: 0.39, green: 0.95, blue: 0.58)
private let tempoCard = Color(red: 0.07, green: 0.09, blue: 0.08)

struct ContentView: View {
    @EnvironmentObject private var model: TempoAppModel
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardScreen()
                .tag(0)
                .tabItem { Label("Panel", systemImage: "square.grid.2x2.fill") }

            WaterTrackingScreen()
                .tag(1)
                .tabItem { Label("Su", systemImage: "drop.fill") }
        }
        .tint(tempoGreen)
        .preferredColorScheme(.dark)
        .toolbarBackground(.black, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onChange(of: model.isConnected) { _, connected in
            if connected { selectedTab = 0 }
        }
    }
}

private struct DashboardScreen: View {
    @EnvironmentObject private var model: TempoAppModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if model.isConnected {
                VStack(spacing: 0) {
                    appHeader(title: "Tempo", subtitle: "ANTRENMAN PANELİN")
                    DashboardWebView(url: model.dashboardURL)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .padding(.horizontal, 10)
                        .padding(.bottom, 6)
                }
            } else {
                SignInView()
            }
        }
    }
}

private struct WaterTrackingScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    @AppStorage("tempoCloudSyncConsent") private var agreesToCloudSync = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    appHeader(title: "Su Takibi", subtitle: "GÜNLÜK HEDEFİN")

                    if model.isConnected {
                        waterCard
                        quickAddCard
                        connectionCard
                    } else {
                        SignInView(compact: true)
                    }

                    Text(model.status)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 34)

                    Link("Gizlilik bilgisi", destination: URL(string: "https://apitempo.com/privacy")!)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(tempoGreen)
                        .padding(.bottom, 16)
                }
                .padding(.horizontal, 16)
            }
        }
        .onChange(of: agreesToCloudSync) { _, agrees in
            if !agrees { model.disableHealthSync() }
        }
    }

    private var waterCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("BUGÜN İÇİLEN")
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(tempoGreen)
                    Text("\(model.todayWaterMl)")
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("mililitre")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.48))
                }
                Spacer()
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.08), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: min(CGFloat(model.todayWaterMl) / CGFloat(model.dailyGoalMl), 1))
                        .stroke(tempoGreen, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 1) {
                        Text("%\(min(model.todayWaterMl * 100 / model.dailyGoalMl, 100))")
                            .font(.headline.bold())
                        Text("HEDEF")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .frame(width: 104, height: 104)
            }

            HStack {
                Label("Hedef", systemImage: "flag.fill")
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text("\(model.dailyGoalMl) ml")
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
        }
        .padding(22)
        .background(cardBackground)
    }

    private var quickAddCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("HIZLI EKLE")
                .font(.caption.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.45))

            HStack(spacing: 10) {
                ForEach([200, 250, 500], id: \.self) { amount in
                    Button {
                        model.addWater(amount)
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: amount == 500 ? "waterbottle.fill" : "cup.and.saucer.fill")
                                .font(.title3)
                            Text("+\(amount)")
                                .font(.headline)
                            Text("ml")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(tempoGreen.opacity(0.11), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(tempoGreen.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(tempoGreen)
                }
            }
            .disabled(model.isBusy || !agreesToCloudSync)

            Toggle(isOn: $agreesToCloudSync) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Bulut eşitleme")
                        .font(.subheadline.weight(.semibold))
                    Text("Günlük toplamı apitempo.com panelinde göster")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .tint(tempoGreen)
        }
        .padding(20)
        .background(cardBackground)
    }

    private var connectionCard: some View {
        VStack(spacing: 12) {
            Button {
                Task { await model.refreshWater() }
            } label: {
                Label("Toplamı yenile", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(DarkButtonStyle())
            .disabled(model.isBusy)

            Button("Strava bağlantısını kes", role: .destructive) {
                model.disconnect()
            }
            .font(.footnote.weight(.semibold))
            .disabled(model.isBusy)
        }
        .padding(18)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(tempoCard)
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.07)))
    }
}

private struct SignInView: View {
    @EnvironmentObject private var model: TempoAppModel
    var compact = false

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().fill(tempoGreen.opacity(0.12))
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: compact ? 54 : 72))
                    .foregroundStyle(tempoGreen)
            }
            .frame(width: compact ? 92 : 120, height: compact ? 92 : 120)

            VStack(spacing: 8) {
                Text("Tempo’ya hoş geldin")
                    .font(.system(size: compact ? 25 : 32, weight: .bold, design: .rounded))
                Text("Strava hesabını bir kez bağla; panelin ve su takibin aynı uygulamada açılsın.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }

            Button {
                model.connectStrava()
            } label: {
                Label("Strava ile devam et", systemImage: "arrow.up.right")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.black)
            .background(tempoGreen, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .disabled(model.isBusy)
        }
        .padding(28)
        .frame(maxWidth: 520)
        .background(tempoCard, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.white.opacity(0.07)))
        .padding(20)
    }
}

private func appHeader(title: String, subtitle: String) -> some View {
    HStack {
        VStack(alignment: .leading, spacing: 3) {
            Text(subtitle)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(tempoGreen)
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
        }
        Spacer()
        Image(systemName: "waveform.path.ecg")
            .font(.title2.weight(.semibold))
            .foregroundStyle(tempoGreen)
            .padding(12)
            .background(tempoGreen.opacity(0.1), in: Circle())
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
    .background(Color.black)
}

private struct DarkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 13)
            .background(.white.opacity(configuration.isPressed ? 0.12 : 0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct DashboardWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.darkModeScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.backgroundColor = .black
        webView.backgroundColor = .black
        webView.isOpaque = false
        let refresh = UIRefreshControl()
        refresh.tintColor = UIColor(red: 0.39, green: 0.95, blue: 0.58, alpha: 1)
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.refresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh
        context.coordinator.webView = webView
        context.coordinator.lastRequestedURL = url.absoluteString
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastRequestedURL != url.absoluteString else { return }
        context.coordinator.lastRequestedURL = url.absoluteString
        webView.load(URLRequest(url: url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var lastRequestedURL = ""

        @objc func refresh(_ sender: UIRefreshControl) {
            webView?.reload()
            sender.endRefreshing()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(DashboardWebView.darkModeScript)
        }
    }

    private static let darkModeScript = #"""
    (() => {
      if (location.hostname !== 'apitempo.com') return;
      document.documentElement.style.colorScheme = 'dark';
      let style = document.getElementById('tempo-native-dark');
      if (!style) {
        style = document.createElement('style');
        style.id = 'tempo-native-dark';
        style.textContent = `
          html, body, main, .app-shell, .page-shell { background:#050706 !important; color:#f4f7f5 !important; }
          header, nav, aside, .sidebar, .topbar { background:#080b09 !important; border-color:#202622 !important; }
          .panel, .feature-panel, .metric-card, .profile-card, .activity-card, .coach-card, .water-day, .data-list > * { background:#111512 !important; color:#f4f7f5 !important; border-color:#242b26 !important; box-shadow:none !important; }
          h1, h2, h3, strong, p, span, label { color:inherit; }
          .eyebrow, a, .nav-item.active, .big-metric { color:#64f294 !important; }
          .nav-item, .data-empty, .hydration-note, small { color:#9ba69f !important; }
          button, select, input, textarea, code { background:#171c18 !important; color:#f4f7f5 !important; border-color:#2a332d !important; }
          .nav-item:hover, button:hover { background:#1a211c !important; }
          footer { border-color:#202622 !important; color:#7f8b83 !important; }
          ::-webkit-scrollbar { width:0; height:0; }
        `;
        document.head.appendChild(style);
      }
    })();
    """#
}
