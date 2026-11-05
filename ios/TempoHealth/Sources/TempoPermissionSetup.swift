import Combine
import CoreLocation
import CoreMotion
import Photos
import SwiftUI
import UIKit
import UserNotifications

private enum TempoSetupPermission: String, CaseIterable, Identifiable {
    case health, location, motion, notifications, photos
    static var allCases: [TempoSetupPermission] { [.health, .location, .motion, .notifications] }
    var id: String { rawValue }
    var title: String { "permissions.\(rawValue).title".tempoLocalized }
    var detail: String { "permissions.\(rawValue).detail".tempoLocalized }
    var symbol: String {
        switch self {
        case .health: return "heart.text.square.fill"
        case .location: return "location.fill"
        case .motion: return "figure.walk.motion"
        case .notifications: return "bell.badge.fill"
        case .photos: return "photo.on.rectangle.angled"
        }
    }
}

/// Sistem izinleri cihazda kalıcıdır; kurulum her açılışta yeniden gösterilmez.
struct TempoStartupPermissionGate<Content: View>: View {
    @AppStorage("tempo.permissions.setup.v1") private var completed = false
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    private var isUITest: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--ui-testing") }
#else
        false
#endif
    }
    var body: some View {
        if completed || isUITest { content }
        else {
            NavigationStack {
                TempoPermissionSetupScreen { completed = true }
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
    }
}

struct TempoPermissionSetupScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    @EnvironmentObject private var account: TempoAccountStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var permissions = TempoSetupPermissionRequests()
    @State private var index = 0
    @State private var requesting = false
    @State private var response: String?
    @State private var requestTask: Task<Void, Never>?
    let onFinish: () -> Void
    private var step: TempoSetupPermission { TempoSetupPermission.allCases[index] }

    var body: some View {
        TempoPage {
            PageTitle(title: "permissions.title", subtitle: "permissions.subtitle")
            HStack(spacing: 8) {
                ForEach(Array(TempoSetupPermission.allCases.enumerated()), id: \.element.id) { position, _ in
                    Capsule().fill(position <= index ? TempoTheme.green : TempoTheme.raised).frame(height: 4)
                }
            }.accessibilityElement(children: .ignore)
                .accessibilityLabel("permissions.step".tempoFormatted(index + 1, TempoSetupPermission.allCases.count))
            TempoCard {
                VStack(alignment: .leading, spacing: 22) {
                    TempoIconBadge(symbol: step.symbol, color: TempoTheme.green, size: 64)
                    Text(step.title).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    Text(step.detail).font(.body).foregroundStyle(TempoTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Label("permissions.choice".tempoLocalized, systemImage: "hand.raised")
                        .font(.footnote).foregroundStyle(TempoTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let response {
                        Text(response).font(.subheadline).foregroundStyle(TempoTheme.primary)
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("permissions.result")
                    }
                    if requesting {
                        HStack(spacing: 12) {
                            ProgressView().tint(TempoTheme.green)
                            Text("permissions.waiting".tempoLocalized).font(.subheadline)
                        }.frame(minHeight: 44)
                    } else if response != nil {
                        Button(action: advance) {
                            Text((index == TempoSetupPermission.allCases.count - 1 ? "permissions.finish" : "permissions.next").tempoLocalized)
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(TempoPrimaryButtonStyle())
                        Button("permissions.settings".tempoLocalized) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }.font(.subheadline).frame(minHeight: 44)
                    } else {
                        Button(action: requestCurrent) {
                            Text("permissions.openPrompt".tempoLocalized).frame(maxWidth: .infinity)
                        }.buttonStyle(TempoPrimaryButtonStyle()).accessibilityIdentifier("permissions.request")
                        Button("permissions.skip".tempoLocalized, action: advance)
                            .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(TempoTheme.secondary).accessibilityIdentifier("permissions.skip")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("permissions.later".tempoLocalized).font(.footnote).foregroundStyle(TempoTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .navigationTitle("permissions.title".tempoLocalized).navigationBarTitleDisplayMode(.inline)
        .onDisappear { requestTask?.cancel(); permissions.cancel() }
    }

    private func advance() {
        response = nil
        if index + 1 < TempoSetupPermission.allCases.count { index += 1 }
        else { onFinish(); dismiss() }
    }
    private func requestCurrent() {
        guard !requesting else { return }
        requesting = true
        let selected = step
        requestTask = Task { @MainActor in
            let result: String
            switch selected {
            case .health:
                if model.healthSyncEnabled { result = "permissions.health.already".tempoLocalized }
                else {
                    let connected = await model.connectAppleHealthForSetup()
                    result = connected ? "permissions.health.result".tempoLocalized : (model.healthError ?? "permissions.unavailable".tempoLocalized)
                }
            case .location: result = await permissions.requestLocation()
            case .motion: result = await permissions.requestMotion()
            case .notifications:
                do {
                    let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                    await TempoNotifications.shared.refreshPermission()
                    if allowed {
#if !targetEnvironment(simulator)
                        UIApplication.shared.registerForRemoteNotifications()
#endif
                        // Cihaz anahtarı mevcut bildirim servisiyle aynı hesaba bağlanır.
                        Task { await TempoNotifications.shared.bind(account: account) }
                    }
                    result = (allowed ? "permissions.allowed" : "permissions.denied").tempoLocalized
                } catch { result = "permissions.unavailable".tempoLocalized }
            case .photos:
                let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                result = (status == .authorized || status == .limited ? "permissions.allowed" : "permissions.denied").tempoLocalized
            }
            guard !Task.isCancelled else { return }
            response = result; requesting = false; requestTask = nil
        }
    }
}

/// İzin talebi hareket takibini açmaz, konum örneklemesi veya rota kaydı başlatmaz.
@MainActor
private final class TempoSetupPermissionRequests: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let location = CLLocationManager()
    private let motion = CMMotionActivityManager()
    private var locationReply: CheckedContinuation<String, Never>?
    private var motionReply: CheckedContinuation<String, Never>?
    private var motionTimeout: Task<Void, Never>?
    override init() { super.init(); location.delegate = self }

    func requestLocation() async -> String {
        guard CLLocationManager.locationServicesEnabled() else { return "permissions.denied".tempoLocalized }
        let status = location.authorizationStatus
        if status != .notDetermined { return locationResult(status) }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { reply in
                guard !Task.isCancelled else { reply.resume(returning: "permissions.unavailable".tempoLocalized); return }
                locationReply = reply
                location.requestWhenInUseAuthorization()
            }
        } onCancel: { Task { @MainActor in self.cancel() } }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard status != .notDetermined else { return }
            let reply = locationReply; locationReply = nil
            reply?.resume(returning: locationResult(status))
        }
    }
    private func locationResult(_ status: CLAuthorizationStatus) -> String {
        (status == .authorizedAlways || status == .authorizedWhenInUse ? "permissions.allowed" : "permissions.denied").tempoLocalized
    }
    func requestMotion() async -> String {
        guard CMMotionActivityManager.isActivityAvailable() else { return "permissions.unavailable".tempoLocalized }
        switch CMMotionActivityManager.authorizationStatus() {
        case .authorized: return "permissions.allowed".tempoLocalized
        case .denied, .restricted: return "permissions.denied".tempoLocalized
        default: break
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { reply in
                guard !Task.isCancelled else { reply.resume(returning: "permissions.unavailable".tempoLocalized); return }
                motionReply = reply
                motion.queryActivityStarting(from: Date().addingTimeInterval(-1), to: Date(), to: .main) { [weak self] _, _ in
                    Task { @MainActor in
                        self?.finishMotion((CMMotionActivityManager.authorizationStatus() == .authorized ? "permissions.allowed" : "permissions.denied").tempoLocalized)
                    }
                }
                motionTimeout = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
                    self?.finishMotion("permissions.unavailable".tempoLocalized)
                }
            }
        } onCancel: { Task { @MainActor in self.cancel() } }
    }
    private func finishMotion(_ result: String) {
        motionTimeout?.cancel(); motionTimeout = nil
        let reply = motionReply; motionReply = nil
        reply?.resume(returning: result)
    }
    func cancel() {
        let reply = locationReply; locationReply = nil
        reply?.resume(returning: "permissions.unavailable".tempoLocalized)
        finishMotion("permissions.unavailable".tempoLocalized)
    }
}
