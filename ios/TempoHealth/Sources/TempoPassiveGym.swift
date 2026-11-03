import Combine
import CoreLocation
import CryptoKit
import Foundation

/// Sürekli GPS açmaz. Bir salonun bölge olaylarını iOS'a bırakır.
@MainActor
final class TempoPassiveGym: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = TempoPassiveGym()
    @Published private(set) var configuration: PassiveGymConfiguration?
    @Published private(set) var enabled = false
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var location: CLLocationCoordinate2D?
    @Published private(set) var locating = false
    @Published private(set) var message = ""
    private let manager = CLLocationManager()
    private var owner: String?
    private var session = PassiveGymSession()
    private var storageReady = true
    private var locationTimeout: Task<Void, Never>?
    private struct State: Codable { let configuration: PassiveGymConfiguration; let enabled: Bool; let session: PassiveGymSession }
    private override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyHundredMeters }
    private var identifier: String? { owner.map { "tempo.gym." + hash($0) } }

    func bootstrap() {
        if let saved = UserDefaults.standard.string(forKey: "tempo.gym.activeOwner") { bind(owner: saved) }
    }
    func bind(owner next: String?) {
        if owner != next || !storageReady {
            stopMonitoring(); owner = next; session = PassiveGymSession(); configuration = nil; enabled = false; location = nil
            storageReady = true
            if let next {
                let url = fileURL(next)
                if FileManager.default.fileExists(atPath: url.path) {
                    if let data = try? Data(contentsOf: url), data.count <= 100_000, let state = try? JSONDecoder().decode(State.self, from: data), state.configuration.isValid {
                    configuration = state.configuration; enabled = state.enabled; session = state.session
                    } else { storageReady = false; message = "detection.storageError".tempoLocalized }
                }
            }
        }
        authorization = manager.authorizationStatus
        if let next { UserDefaults.standard.set(next, forKey: "tempo.gym.activeOwner") }
        else { UserDefaults.standard.removeObject(forKey: "tempo.gym.activeOwner") }
        reconcileMonitoring()
    }
    func useCurrentLocation() {
        guard !locating else { return }
        message = ""
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization(); return }
        guard [.authorizedAlways, .authorizedWhenInUse].contains(manager.authorizationStatus) else { message = "passive.gym.locationDenied".tempoLocalized; return }
        locating = true; manager.requestLocation()
        locationTimeout?.cancel()
        locationTimeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 12_000_000_000) } catch { return }
            self?.locating = false; self?.message = "passive.gym.locationFailed".tempoLocalized
        }
    }
    func save(_ config: PassiveGymConfiguration) throws {
        guard storageReady, owner != nil, config.isValid else { throw NSError(domain: "TempoPassiveGym", code: 1, userInfo: [NSLocalizedDescriptionKey: "passive.gym.invalid".tempoLocalized]) }
        stopMonitoring(); configuration = config; session = PassiveGymSession(); enabled = true
        try persist()
        TempoWorkoutDetection.shared.enableVenueDetection()
        if manager.authorizationStatus != .authorizedAlways { manager.requestAlwaysAuthorization() }
        reconcileMonitoring()
    }
    func disable() {
        enabled = false; session = PassiveGymSession(); stopMonitoring()
        try? persist()
    }
    func removeAccount(_ id: String) {
        if owner == id { bind(owner: nil) }
        try? FileManager.default.removeItem(at: fileURL(id))
    }
    private func reconcileMonitoring() {
        guard let identifier, let configuration, configuration.isValid, enabled,
              TempoWorkoutDetection.shared.enabled, TempoWorkoutDetection.shared.owner == owner,
              manager.authorizationStatus == .authorizedAlways,
              CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self), manager.maximumRegionMonitoringDistance > 0 else {
            stopMonitoring()
            if session.enteredAt != nil { session = PassiveGymSession(); try? persist() }
            return
        }
        guard !manager.monitoredRegions.contains(where: { $0.identifier == identifier }) else { return }
        // 200 m sınırı bina içi GPS hassasiyeti iddiasında bulunmaz; süre yaklaşık bir ziyarettir.
        let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: configuration.latitude, longitude: configuration.longitude), radius: min(200, manager.maximumRegionMonitoringDistance), identifier: identifier)
        region.notifyOnEntry = true; region.notifyOnExit = true
        manager.startMonitoring(for: region)
    }
    private func stopMonitoring() {
        for region in manager.monitoredRegions where region.identifier.hasPrefix("tempo.gym.") { manager.stopMonitoring(for: region) }
    }
    private func receive(inside: Bool, regionID: String) {
        guard regionID == identifier, enabled, let owner, let configuration,
              manager.authorizationStatus == .authorizedAlways,
              TempoWorkoutDetection.shared.enabled, TempoWorkoutDetection.shared.owner == owner else { return }
        if inside { session.enter(at: Date()) }
        else if let visit = session.exit(at: Date(), configuration: configuration) {
            Task { await TempoWorkoutDetection.shared.addGymVisit(visit, owner: owner) }
        }
        do { try persist() } catch { message = "detection.storageError".tempoLocalized }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let id = region.identifier; Task { @MainActor in self.receive(inside: true, regionID: id) }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        let id = region.identifier; Task { @MainActor in self.receive(inside: false, regionID: id) }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) { manager.requestState(for: region) }
    nonisolated func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard state != .unknown else { return }
        let inside = state == .inside, id = region.identifier
        Task { @MainActor in self.receive(inside: inside, regionID: id) }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorization = status; self.reconcileMonitoring() }
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
        Task { @MainActor in self.locationTimeout?.cancel(); self.locating = false; self.message = "passive.gym.locationFailed".tempoLocalized }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        Task { @MainActor in self.message = "passive.gym.monitorFailed".tempoLocalized }
    }
    private func hash(_ id: String) -> String { SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined() }
    private func fileURL(_ id: String) -> URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PassiveGym", isDirectory: true).appendingPathComponent(hash(id) + ".json") }
    private func persist() throws {
        guard storageReady, let owner, let configuration else { return }
        let url = fileURL(owner)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(State(configuration: configuration, enabled: enabled, session: session)).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var resource = url; try resource.setResourceValues(values)
    }
}
