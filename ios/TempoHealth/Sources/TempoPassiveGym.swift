import Combine
import CoreLocation
import CryptoKit
import Foundation
import UIKit

/// Sürekli GPS yerine kayıtlı salonun bölge olayları izlenir; ziyaret önce diske yazılır.
@MainActor
final class TempoPassiveGym: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = TempoPassiveGym()
    @Published private(set) var configuration: PassiveGymConfiguration?
    @Published private(set) var enabled = false
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var location: CLLocationCoordinate2D?
    @Published private(set) var locating = false
    @Published private(set) var monitoring = false
    @Published private(set) var activeSince: Date?
    @Published private(set) var backgroundAvailable = true
    @Published private(set) var message = ""
    private let manager = CLLocationManager()
    private var owner: String?
    private var session = PassiveGymSession()
    private var pendingVisits: [PassiveGymVisit] = []
    private var storageReady = true
    private var locationTimeout: Task<Void, Never>?
    private var pendingLocation = false
    private var wantsBackgroundAccess = false
    private var scope = UUID()
    private var draining = false
    private struct State: Codable {
        let configuration: PassiveGymConfiguration
        let enabled: Bool
        let session: PassiveGymSession
        var pendingVisits: [PassiveGymVisit]? = nil
    }
    private override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyHundredMeters }
    private var identifier: String? { owner.map { "tempo.gym." + hash($0) } }
    private func disabledKey(_ id: String) -> String { "tempo.gym.disabled." + hash(id) }

    func bootstrap() {
        if let saved = UserDefaults.standard.string(forKey: "tempo.gym.activeOwner") { bind(owner: saved) }
    }
    func bind(owner next: String?) {
        if owner != next || !storageReady {
            stopMonitoring(); locationTimeout?.cancel(); scope = UUID(); draining = false
            owner = next; session = PassiveGymSession(); pendingVisits = []; configuration = nil
            enabled = false; location = nil; locating = false; pendingLocation = false; wantsBackgroundAccess = false; message = ""
            storageReady = true
            if let next {
                let url = fileURL(next)
                if FileManager.default.fileExists(atPath: url.path) {
                    if let data = try? Data(contentsOf: url), data.count <= 100_000,
                       let state = try? JSONDecoder().decode(State.self, from: data), state.configuration.isValid {
                        configuration = state.configuration
                        enabled = state.enabled && !UserDefaults.standard.bool(forKey: disabledKey(next))
                        session = enabled ? state.session : PassiveGymSession()
                        pendingVisits = Array((state.pendingVisits ?? []).filter { $0.end <= Date() && $0.end > Date().addingTimeInterval(-7 * 86400) && (900...14_400).contains($0.end.timeIntervalSince($0.start)) }.suffix(16))
                    } else { storageReady = false; message = "detection.storageError".tempoLocalized }
                }
            }
        }
        if let next { UserDefaults.standard.set(next, forKey: "tempo.gym.activeOwner") }
        else { UserDefaults.standard.removeObject(forKey: "tempo.gym.activeOwner") }
        refreshStatus()
    }
    func refreshStatus() {
        authorization = manager.authorizationStatus
        backgroundAvailable = UIApplication.shared.backgroundRefreshStatus == .available
        activeSince = session.enteredAt
        reconcileMonitoring()
        Task { await deliverPendingVisits() }
    }
    func useCurrentLocation() {
        guard !locating else { return }
        message = ""
        if manager.authorizationStatus == .notDetermined {
            pendingLocation = true; locating = true; armLocationTimeout(); manager.requestWhenInUseAuthorization(); return
        }
        guard [.authorizedAlways, .authorizedWhenInUse].contains(manager.authorizationStatus) else {
            message = "passive.gym.locationDenied".tempoLocalized; return
        }
        pendingLocation = false; locating = true; armLocationTimeout(); manager.requestLocation()
    }
    private func armLocationTimeout() {
        locationTimeout?.cancel()
        let token = scope
        locationTimeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
            guard let self, self.scope == token else { return }
            self.locating = false; self.pendingLocation = false; self.message = "passive.gym.locationFailed".tempoLocalized
        }
    }
    func save(_ config: PassiveGymConfiguration) throws {
        guard storageReady else { throw failure("detection.storageError") }
        guard let owner, TempoWorkoutDetection.shared.owner == owner else {
            throw failure("passive.gym.accountPreparing")
        }
        guard config.isValid else { throw failure("passive.gym.invalid") }
        guard TempoWorkoutDetection.shared.enableVenueDetection() else { throw failure("detection.storageError") }
        let previous = (configuration, enabled, session)
        let moved = configuration.map { abs($0.latitude - config.latitude) > 0.00001 || abs($0.longitude - config.longitude) > 0.00001 } ?? true
        configuration = config; enabled = true
        if moved { session = PassiveGymSession() }
        do { try persist() } catch {
            configuration = previous.0; enabled = previous.1; session = previous.2
            throw failure("detection.storageError")
        }
        UserDefaults.standard.removeObject(forKey: disabledKey(owner))
        if moved { stopMonitoring() }
        message = ""; wantsBackgroundAccess = true; requestBackgroundAccess(); refreshStatus()
    }
    func requestBackgroundAccess() {
        switch manager.authorizationStatus {
        case .notDetermined: wantsBackgroundAccess = true; manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse: wantsBackgroundAccess = false; manager.requestAlwaysAuthorization()
        default: wantsBackgroundAccess = false
        }
    }
    func disable() {
        if let owner { UserDefaults.standard.set(true, forKey: disabledKey(owner)) }
        enabled = false; session = PassiveGymSession(); activeSince = nil; pendingVisits = []; stopMonitoring()
        do { try persist() } catch { message = "detection.storageError".tempoLocalized }
    }
    func removeAccount(_ id: String) {
        if owner == id { bind(owner: nil) }
        UserDefaults.standard.removeObject(forKey: disabledKey(id))
        try? FileManager.default.removeItem(at: fileURL(id))
    }
    private func reconcileMonitoring() {
        // Hesap/algılayıcı henüz geri yükleniyorsa saklanmış giriş zamanını silme.
        guard let identifier, let configuration, configuration.isValid, enabled,
              TempoWorkoutDetection.shared.enabled, TempoWorkoutDetection.shared.owner == owner,
              manager.authorizationStatus == .authorizedAlways,
              CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self), manager.maximumRegionMonitoringDistance > 0 else {
            stopMonitoring(); return
        }
        if let existing = manager.monitoredRegions.first(where: { $0.identifier == identifier }) {
            monitoring = true; manager.requestState(for: existing); return
        }
        let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: configuration.latitude, longitude: configuration.longitude), radius: min(200, manager.maximumRegionMonitoringDistance), identifier: identifier)
        region.notifyOnEntry = true; region.notifyOnExit = true
        manager.startMonitoring(for: region)
    }
    private func stopMonitoring() {
        monitoring = false
        for region in manager.monitoredRegions where region.identifier.hasPrefix("tempo.gym.") { manager.stopMonitoring(for: region) }
    }
    private func receive(inside: Bool, regionID: String) {
        guard regionID == identifier, enabled, let owner, let configuration,
              manager.authorizationStatus == .authorizedAlways,
              TempoWorkoutDetection.shared.enabled, TempoWorkoutDetection.shared.owner == owner else { return }
        let previous = (session, pendingVisits)
        if inside { session.enter(at: Date()) }
        else if let visit = session.exit(at: Date(), configuration: configuration) {
            pendingVisits.append(visit); pendingVisits = Array(pendingVisits.suffix(16))
        }
        do { try persist(); activeSince = session.enteredAt }
        catch { session = previous.0; pendingVisits = previous.1; message = "detection.storageError".tempoLocalized; return }
        Task { await deliverPendingVisits() }
    }
    /// Diske kaydedilmiş teslim kuyruğu, öneri de kalıcı yazılmadan silinmez.
    private func deliverPendingVisits() async {
        guard !draining, enabled, storageReady, let owner, TempoWorkoutDetection.shared.owner == owner,
              TempoWorkoutDetection.shared.enabled else { return }
        draining = true; let token = scope
        defer { if token == scope { draining = false } }
        for visit in pendingVisits {
            guard token == scope, self.owner == owner, enabled else { return }
            guard await TempoWorkoutDetection.shared.addGymVisit(visit, owner: owner) else { message = "detection.storageError".tempoLocalized; return }
            guard token == scope, self.owner == owner, enabled else { return }
            let previous = pendingVisits
            pendingVisits.removeAll { $0.id == visit.id }
            do { try persist() } catch { pendingVisits = previous; message = "detection.storageError".tempoLocalized; return }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let id = region.identifier; Task { @MainActor in self.receive(inside: true, regionID: id) }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        let id = region.identifier; Task { @MainActor in self.receive(inside: false, regionID: id) }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        let id = region.identifier
        Task { @MainActor in guard id == self.identifier else { return }; self.monitoring = true; manager.requestState(for: region) }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard state != .unknown else { return }
        let inside = state == .inside, id = region.identifier
        Task { @MainActor in self.receive(inside: inside, regionID: id) }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if self.pendingLocation {
                if [.authorizedAlways, .authorizedWhenInUse].contains(status) { self.locating = false; self.useCurrentLocation() }
                else if status == .denied || status == .restricted {
                    self.pendingLocation = false; self.locating = false; self.locationTimeout?.cancel(); self.message = "passive.gym.locationDenied".tempoLocalized
                }
            }
            if self.wantsBackgroundAccess, status == .authorizedWhenInUse { self.requestBackgroundAccess() }
            self.refreshStatus()
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let value = locations.last
        Task { @MainActor in
            self.locationTimeout?.cancel(); self.locating = false
            guard let value, value.horizontalAccuracy >= 0, value.horizontalAccuracy <= 150, abs(value.timestamp.timeIntervalSinceNow) <= 30 else { self.message = "passive.gym.locationFailed".tempoLocalized; return }
            self.location = value.coordinate
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.locationTimeout?.cancel(); self.locating = false; self.pendingLocation = false; self.message = "passive.gym.locationFailed".tempoLocalized }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        Task { @MainActor in self.monitoring = false; self.message = "passive.gym.monitorFailed".tempoLocalized }
    }
    private func failure(_ key: String) -> NSError { NSError(domain: "TempoPassiveGym", code: 1, userInfo: [NSLocalizedDescriptionKey: key.tempoLocalized]) }
    private func hash(_ id: String) -> String { SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined() }
    private func fileURL(_ id: String) -> URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PassiveGym", isDirectory: true).appendingPathComponent(hash(id) + ".json") }
    private func persist() throws {
        guard storageReady, let owner, let configuration else { throw failure("detection.storageError") }
        let url = fileURL(owner)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(State(configuration: configuration, enabled: enabled, session: session, pendingVisits: pendingVisits)).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var resource = url; try? resource.setResourceValues(values)
    }
}
