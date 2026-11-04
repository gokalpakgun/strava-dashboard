import Combine
import CoreLocation
import CryptoKit
import Foundation
import MapKit
import UIKit

/// Sürekli GPS yerine kayıtlı salonun bölge olayları izlenir; ziyaret önce diske yazılır.
@MainActor
final class TempoPassiveGym: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = TempoPassiveGym()
    @Published private(set) var configurations: [PassiveGymConfiguration] = []
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
    private var registry = PassiveGymRegistry()
    private var storageReady = true
    private var locationTimeout: Task<Void, Never>?
    private var pendingLocation = false
    private var wantsBackgroundAccess = false
    private var scope = UUID()
    private var draining = false
    private override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyHundredMeters }
    private var regionPrefix: String? { owner.map { "tempo.gym." + hash($0) + "." } }
    private func identifier(for config: PassiveGymConfiguration) -> String { (regionPrefix ?? "") + config.id }
    private func configuration(for regionID: String) -> PassiveGymConfiguration? { configurations.first { identifier(for: $0) == regionID && $0.isVerifiedGym } }
    private func disabledKey(_ id: String) -> String { "tempo.gym.disabled." + hash(id) }

    func bootstrap() {
        if let saved = UserDefaults.standard.string(forKey: "tempo.gym.activeOwner") { bind(owner: saved) }
    }
    func bind(owner next: String?) {
        if owner != next || !storageReady {
            stopMonitoring(); locationTimeout?.cancel(); scope = UUID(); draining = false
            owner = next; registry = PassiveGymRegistry(); configurations = []
            enabled = false; location = nil; locating = false; pendingLocation = false; wantsBackgroundAccess = false; message = ""
            storageReady = true
            if let next {
                let url = fileURL(next)
                if FileManager.default.fileExists(atPath: url.path) {
                    if let data = try? Data(contentsOf: url), data.count <= 100_000,
                       let state = try? JSONDecoder().decode(PassiveGymRegistry.self, from: data) {
                        registry = state; configurations = state.configurations
                        enabled = state.enabled && !UserDefaults.standard.bool(forKey: disabledKey(next))
                        registry.enabled = enabled
                        if !enabled { registry.sessions = [:] }
                        registry.pendingVisits = Array(state.pendingVisits.filter { $0.end <= Date() && $0.end > Date().addingTimeInterval(-7 * 86400) && (900...14_400).contains($0.end.timeIntervalSince($0.start)) }.suffix(16))
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
        activeSince = registry.sessions.values.compactMap(\.enteredAt).min()
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
    func cancelLocationRequest() {
        locationTimeout?.cancel(); pendingLocation = false; locating = false
    }
    /// Yeni konum yalnız MapKit işletme kategorisiyle kabul edilir; serbest GPS noktası kaydedilmez.
    func save(_ proposed: PassiveGymConfiguration, place: MKMapItem?, editingID: String?) throws {
        guard storageReady else { throw failure("detection.storageError") }
        guard let owner, TempoWorkoutDetection.shared.owner == owner else { throw failure("passive.gym.accountPreparing") }
        var config = proposed
        if let place {
            guard place.pointOfInterestCategory == .fitnessCenter else { throw failure("gym.verifiedOnly") }
            config.latitude = place.placemark.coordinate.latitude; config.longitude = place.placemark.coordinate.longitude
            config.placeCategory = "fitness-center"
        } else {
            guard let existing = configurations.first(where: { $0.id == editingID }), existing.isVerifiedGym,
                  existing.id == config.id else { throw failure("gym.verifiedOnly") }
            config.placeCategory = existing.placeCategory
        }
        guard config.isValid, editingID == nil || configurations.contains(where: { $0.id == editingID }) else { throw failure("passive.gym.invalid") }
        let duplicate = configurations.first { $0.id != editingID && distance($0, config) < 100 }
        guard duplicate == nil else { throw failure("gym.duplicate") }
        guard editingID != nil || configurations.count < 10 else { throw failure("gym.limit") }
        guard TempoWorkoutDetection.shared.enableVenueDetection() else { throw failure("detection.storageError") }
        let previous = registry
        if let editingID { registry.configurations.removeAll { $0.id == editingID }; if editingID != config.id { registry.sessions.removeValue(forKey: editingID) } }
        registry.configurations.append(config); registry.enabled = true
        do { try persist() } catch { registry = previous; throw failure("detection.storageError") }
        configurations = registry.configurations; enabled = true
        UserDefaults.standard.removeObject(forKey: disabledKey(owner))
        message = ""; wantsBackgroundAccess = true; requestBackgroundAccess(); refreshStatus()
    }
    func remove(_ config: PassiveGymConfiguration) throws {
        let previous = registry
        registry.configurations.removeAll { $0.id == config.id }; registry.sessions.removeValue(forKey: config.id)
        if registry.configurations.isEmpty { registry.enabled = false }
        do { try persist() } catch { registry = previous; throw failure("detection.storageError") }
        configurations = registry.configurations; enabled = registry.enabled; refreshStatus()
    }
    private func distance(_ first: PassiveGymConfiguration, _ second: PassiveGymConfiguration) -> Double {
        CLLocation(latitude: first.latitude, longitude: first.longitude).distance(from: CLLocation(latitude: second.latitude, longitude: second.longitude))
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
        enabled = false; registry.enabled = false; registry.sessions = [:]; activeSince = nil; registry.pendingVisits = []; stopMonitoring()
        do { try persist() } catch { message = "detection.storageError".tempoLocalized }
    }
    func pauseForDetectionDisable() {
        stopMonitoring(); registry.sessions = [:]; activeSince = nil
        guard owner != nil else { return }
        do { try persist() } catch { message = "detection.storageError".tempoLocalized }
    }
    func removeAccount(_ id: String) {
        if owner == id { bind(owner: nil) }
        UserDefaults.standard.removeObject(forKey: disabledKey(id))
        try? FileManager.default.removeItem(at: fileURL(id))
    }
    private func reconcileMonitoring() {
        guard regionPrefix != nil, enabled, TempoWorkoutDetection.shared.enabled,
              TempoWorkoutDetection.shared.owner == owner, manager.authorizationStatus == .authorizedAlways,
              CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self), manager.maximumRegionMonitoringDistance > 0 else {
            stopMonitoring(); return
        }
        let gyms = configurations.filter { $0.isValid && $0.isVerifiedGym }
        let wanted = Set(gyms.map { identifier(for: $0) })
        for region in manager.monitoredRegions where region.identifier.hasPrefix("tempo.gym.") && !wanted.contains(region.identifier) { manager.stopMonitoring(for: region) }
        for config in gyms {
            let id = identifier(for: config)
            if let region = manager.monitoredRegions.first(where: { $0.identifier == id }) { manager.requestState(for: region); continue }
            let region = CLCircularRegion(center: .init(latitude: config.latitude, longitude: config.longitude), radius: min(200, manager.maximumRegionMonitoringDistance), identifier: id)
            region.notifyOnEntry = true; region.notifyOnExit = true; manager.startMonitoring(for: region)
        }
        monitoring = !wanted.isEmpty && wanted.isSubset(of: Set(manager.monitoredRegions.map(\.identifier)))
    }
    private func stopMonitoring() {
        monitoring = false
        for region in manager.monitoredRegions where region.identifier.hasPrefix("tempo.gym.") { manager.stopMonitoring(for: region) }
    }
    private func receive(inside: Bool, regionID: String) {
        guard enabled, let owner, let config = configuration(for: regionID), manager.authorizationStatus == .authorizedAlways,
              TempoWorkoutDetection.shared.enabled, TempoWorkoutDetection.shared.owner == owner else { return }
        let previous = registry
        registry.receive(inside: inside, gymID: config.id, at: Date())
        do { try persist(); activeSince = registry.sessions.values.compactMap(\.enteredAt).min() }
        catch { registry = previous; message = "detection.storageError".tempoLocalized; return }
        Task { await deliverPendingVisits() }
    }
    /// Diske kaydedilmiş teslim kuyruğu, öneri de kalıcı yazılmadan silinmez.
    private func deliverPendingVisits() async {
        guard !draining, enabled, storageReady, let owner, TempoWorkoutDetection.shared.owner == owner,
              TempoWorkoutDetection.shared.enabled else { return }
        draining = true; let token = scope
        defer { if token == scope { draining = false } }
        for visit in registry.pendingVisits {
            guard token == scope, self.owner == owner, enabled else { return }
            guard await TempoWorkoutDetection.shared.addGymVisit(visit, owner: owner) else { message = "detection.storageError".tempoLocalized; return }
            guard token == scope, self.owner == owner, enabled else { return }
            let previous = registry.pendingVisits
            registry.pendingVisits.removeAll { $0.id == visit.id }
            do { try persist() } catch { registry.pendingVisits = previous; message = "detection.storageError".tempoLocalized; return }
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
        Task { @MainActor in guard self.configuration(for: id) != nil else { return }; self.monitoring = self.configurations.filter { $0.isVerifiedGym }.allSatisfy { config in manager.monitoredRegions.contains { $0.identifier == self.identifier(for: config) } }; manager.requestState(for: region) }
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
            guard self.locating else { return }
            self.locationTimeout?.cancel(); self.locating = false
            guard let value, value.horizontalAccuracy >= 0, value.horizontalAccuracy <= 150, abs(value.timestamp.timeIntervalSinceNow) <= 30 else { self.message = "passive.gym.locationFailed".tempoLocalized; return }
            self.location = value.coordinate
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in guard self.locating else { return }; self.cancelLocationRequest(); self.message = "passive.gym.locationFailed".tempoLocalized }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        Task { @MainActor in self.monitoring = false; self.message = "passive.gym.monitorFailed".tempoLocalized }
    }
    private func failure(_ key: String) -> NSError { NSError(domain: "TempoPassiveGym", code: 1, userInfo: [NSLocalizedDescriptionKey: key.tempoLocalized]) }
    private func hash(_ id: String) -> String { SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined() }
    private func fileURL(_ id: String) -> URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PassiveGym", isDirectory: true).appendingPathComponent(hash(id) + ".json") }
    private func persist() throws {
        guard storageReady, let owner else { throw failure("detection.storageError") }
        let url = fileURL(owner)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(registry).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var resource = url; try? resource.setResourceValues(values)
    }
}
