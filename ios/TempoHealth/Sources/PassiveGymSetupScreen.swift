import Combine
import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct PassiveGymSetupScreen: View {
    @EnvironmentObject private var account: TempoAccountStore
    @EnvironmentObject private var model: TempoAppModel
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var gym = TempoPassiveGym.shared
    @ObservedObject private var detector = TempoWorkoutDetection.shared
    @StateObject private var places = GymPlaceSearch()
    @State private var name = ""
    @State private var query = ""
    @State private var chosen: CLLocationCoordinate2D?
    @State private var chosenPlace: MKMapItem?
    @State private var editingID: String?
    @State private var removal: PassiveGymConfiguration?
    @State private var routines: [Int: String] = [:]
    @State private var notice = ""
    @State private var saveSucceeded = false
    @State private var loadedOwner: String?
    private let weekdays = [2, 3, 4, 5, 6, 7, 1]
    private var coordinate: CLLocationCoordinate2D? { chosen }
    private var ready: Bool { account.profile?.id != nil && account.profile?.id == model.activityAccountID && detector.owner == account.profile?.id }
    private var locationKey: String { gym.location.map { "\($0.latitude)|\($0.longitude)" } ?? "" }
    private var accountKey: [String] { [account.profile?.id ?? "", model.activityAccountID ?? "", detector.owner ?? "", String(account.isRestoring)] }
    var body: some View {
        TempoPage {
            PageTitle(title: "passive.gym.title", subtitle: "passive.gym.subtitle")
            statusCard
            savedGyms
            locationCard
            TempoDisclosureSection(title: "passive.gym.routine", icon: "calendar") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("passive.gym.routineHint".tempoLocalized).font(.footnote).foregroundStyle(TempoTheme.secondary)
                    ForEach(weekdays, id: \.self) { day in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(Calendar.current.weekdaySymbols[day - 1]).font(.caption.weight(.medium))
                            TextField("passive.gym.program".tempoLocalized, text: Binding(get: { routines[day] ?? "" }, set: { routines[day] = String($0.prefix(64)) })).textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }
            TempoCard {
                VStack(alignment: .leading, spacing: 14) {
                    Button(action: save) { Text("passive.gym.save".tempoLocalized).frame(maxWidth: .infinity) }
                        .buttonStyle(TempoPrimaryButtonStyle())
                        .disabled(!ready || coordinate == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 64 || (chosenPlace == nil && !gym.configurations.contains { $0.id == editingID && $0.isVerifiedGym }))
                        .accessibilityIdentifier("gym.save")
                    if !notice.isEmpty { Text(notice).font(.subheadline).foregroundStyle(saveSucceeded ? TempoTheme.green : TempoTheme.orange).accessibilityIdentifier("gym.saveStatus") }
                    if !gym.message.isEmpty { Text(gym.message).font(.footnote).foregroundStyle(TempoTheme.orange) }
                    if gym.enabled {
                        Button("passive.gym.checkStatus".tempoLocalized) { gym.refreshStatus() }.frame(minHeight: 44)
                        Button("passive.gym.disable".tempoLocalized, role: .destructive) { gym.disable(); notice = "" }.frame(minHeight: 44)
                    }
                    Text("passive.gym.privacy".tempoLocalized).font(.footnote).foregroundStyle(TempoTheme.secondary)
                }
            }
        }
        .navigationTitle("passive.gym.title".tempoLocalized).navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
        .task(id: accountKey) {
            guard ready, let id = account.profile?.id else {
                if loadedOwner != account.profile?.id { resetEditor(); places.clear(); notice = ""; loadedOwner = nil }
                return
            }
            gym.bind(owner: id)
            if loadedOwner != id { loadedOwner = id; resetEditor(); places.clear(); notice = "" }
        }
        .onChange(of: locationKey) { _, _ in
            guard let location = gym.location, ready else { return }
            places.search(near: location)
        }
        .onChange(of: scenePhase) { _, value in if value == .active { gym.refreshStatus() } }
        .onChange(of: name) { _, _ in notice = ""; saveSucceeded = false }
        .onDisappear { places.cancel(); gym.cancelLocationRequest() }
    }
    private var savedGyms: some View {
        TempoCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("gym.saved".tempoLocalized, systemImage: "building.2.fill").font(.headline)
                    Spacer()
                    Text("\(gym.configurations.count)/10").font(.caption.monospacedDigit()).foregroundStyle(TempoTheme.secondary)
                }
                if gym.configurations.isEmpty { Text("gym.empty".tempoLocalized).font(.subheadline).foregroundStyle(TempoTheme.secondary) }
                ForEach(gym.configurations, id: \.id) { config in
                    HStack(spacing: 12) {
                        Button {
                            gym.cancelLocationRequest(); places.clear(); editingID = config.id; chosenPlace = nil
                            chosen = .init(latitude: config.latitude, longitude: config.longitude); name = config.name; routines = config.routines; query = config.name; notice = ""
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(config.name).font(.subheadline.weight(.semibold)).foregroundStyle(TempoTheme.primary)
                                Label((config.isVerifiedGym ? "gym.verified" : "gym.reverify").tempoLocalized, systemImage: config.isVerifiedGym ? "checkmark.seal.fill" : "exclamationmark.circle")
                                    .font(.caption).foregroundStyle(config.isVerifiedGym ? TempoTheme.green : TempoTheme.orange)
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }.buttonStyle(.plain)
                        Button(role: .destructive) { removal = config } label: { Image(systemName: "trash").frame(width: 44, height: 44) }.accessibilityLabel("gym.remove".tempoLocalized)
                    }
                }
                Button { resetEditor(); places.clear(); notice = "" } label: { Label("gym.addAnother".tempoLocalized, systemImage: "plus.circle.fill").frame(minHeight: 44) }
                    .disabled(gym.configurations.count >= 10)
            }
        }
        .alert("gym.removeConfirm".tempoLocalized, isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } })) {
            Button("gym.remove".tempoLocalized, role: .destructive) {
                guard let removal else { return }
                do { try gym.remove(removal); if editingID == removal.id { resetEditor() } }
                catch { notice = error.localizedDescription }
                self.removal = nil
            }
            Button("İptal".tempoLocalized, role: .cancel) { removal = nil }
        }
    }
    private func resetEditor() { name = ""; query = ""; chosen = nil; chosenPlace = nil; editingID = nil; routines = [:]; saveSucceeded = false }
    private var statusCard: some View {
        TempoCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(statusTitle.tempoLocalized, systemImage: gym.monitoring && detector.enabled ? "checkmark.circle.fill" : "location.slash")
                    .font(.headline).foregroundStyle(gym.monitoring && detector.enabled ? TempoTheme.green : TempoTheme.orange)
                if let since = gym.activeSince, gym.monitoring {
                    Text("passive.gym.insideSince".tempoFormatted(since.formatted(date: .omitted, time: .shortened))).font(.subheadline)
                    Text("passive.gym.afterExit".tempoLocalized).font(.footnote).foregroundStyle(TempoTheme.secondary)
                }
                if !detector.pending.filter({ $0.origin == .gym }).isEmpty {
                    NavigationLink(destination: WorkoutDetectionScreen()) {
                        Label("passive.gym.reviewVisits".tempoFormatted(detector.pending.filter { $0.origin == .gym }.count), systemImage: "checkmark.circle")
                    }.buttonStyle(TempoSecondaryButtonStyle())
                }
                if !ready { Text("passive.gym.accountPreparing".tempoLocalized).font(.footnote).foregroundStyle(TempoTheme.secondary) }
                if gym.enabled && gym.authorization != .authorizedAlways {
                    Text("passive.gym.needsAlways".tempoLocalized).font(.footnote).foregroundStyle(TempoTheme.secondary)
                    Button("permissions.settings".tempoLocalized, action: openSettings).frame(minHeight: 44)
                }
                if gym.enabled && !gym.backgroundAvailable {
                    Text("passive.gym.backgroundOff".tempoLocalized).font(.footnote).foregroundStyle(TempoTheme.orange)
                    Button("permissions.settings".tempoLocalized, action: openSettings).frame(minHeight: 44)
                }
                NavigationLink(destination: TempoNotificationSettingsScreen()) { Label("Bildirim tercihleri".tempoLocalized, systemImage: "bell.badge").frame(minHeight: 44) }
                Text("passive.gym.setupHint".tempoLocalized).font(.footnote).foregroundStyle(TempoTheme.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var statusTitle: String {
        if !gym.enabled { return "passive.gym.setupTitle" }
        if gym.authorization != .authorizedAlways { return "passive.gym.waitingPermission" }
        if !detector.enabled { return "detection.optional" }
        return gym.monitoring ? "passive.gym.enabled" : "passive.gym.starting"
    }
    private var locationCard: some View {
        TempoCard {
            VStack(alignment: .leading, spacing: 16) {
                Label("passive.gym.chooseLocation".tempoLocalized, systemImage: "mappin.and.ellipse").font(.headline)
                HStack(spacing: 10) {
                    TextField("passive.gym.search".tempoLocalized, text: $query).textFieldStyle(.roundedBorder).submitLabel(.search)
                        .onSubmit { search() }
                    Button(action: search) { Image(systemName: "magnifyingglass").frame(width: 44, height: 44) }.disabled(places.searching || query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                        .accessibilityLabel("passive.gym.searchAction".tempoLocalized)
                }
                Button { gym.useCurrentLocation() } label: {
                    Label(gym.locating ? "passive.gym.locating".tempoLocalized : "passive.gym.useHere".tempoLocalized, systemImage: "location.fill").frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(TempoSecondaryButtonStyle()).disabled(gym.locating || !ready)
                if places.searching { HStack { ProgressView(); Text("passive.gym.searching".tempoLocalized).font(.footnote) } }
                if !places.message.isEmpty { Text(places.message).font(.footnote).foregroundStyle(TempoTheme.secondary) }
                ForEach(places.results) { item in
                    Button {
                        gym.cancelLocationRequest()
                        chosen = item.coordinate; chosenPlace = item.mapItem; name = String(item.name.prefix(64)); notice = ""
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "building.2.fill").foregroundStyle(TempoTheme.green)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name).font(.subheadline.weight(.medium)).foregroundStyle(TempoTheme.primary)
                                Text(item.address).font(.caption).foregroundStyle(TempoTheme.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            if chosen?.latitude == item.coordinate.latitude && chosen?.longitude == item.coordinate.longitude { Image(systemName: "checkmark.circle.fill").foregroundStyle(TempoTheme.green) }
                        }.padding(.vertical, 10).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Divider()
                }
                if let coordinate {
                    Map(initialPosition: .region(.init(center: coordinate, latitudinalMeters: 800, longitudinalMeters: 800))) {
                        Marker(name, coordinate: coordinate)
                    }.id("\(coordinate.latitude)|\(coordinate.longitude)").frame(height: 148).clipShape(RoundedRectangle(cornerRadius: 18)).allowsHitTesting(false).accessibilityHidden(true)
                    TextField("passive.gym.name".tempoLocalized, text: $name).textFieldStyle(.roundedBorder)
                    Text("passive.gym.confirmLocation".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
                }
            }
        }
    }
    private func search() {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else { return }
        places.search(near: coordinate, query: query)
    }
    private func openSettings() { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
    private func save() {
        saveSucceeded = false
        guard ready, let coordinate else { notice = "passive.gym.accountPreparing".tempoLocalized; return }
        do {
            try gym.save(.init(name: name.trimmingCharacters(in: .whitespacesAndNewlines), latitude: coordinate.latitude, longitude: coordinate.longitude, routines: routines), place: chosenPlace, editingID: editingID)
            resetEditor()
            notice = "passive.gym.saved".tempoLocalized
            saveSucceeded = true
        } catch { notice = error.localizedDescription }
    }
}

private struct GymPlace: Identifiable {
    let id: String
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let mapItem: MKMapItem
}

/// Tek seferlik arama; eski veya zaman aşımına uğramış sonuçlar ekrana geri yazılamaz.
@MainActor
private final class GymPlaceSearch: ObservableObject {
    @Published private(set) var results: [GymPlace] = []
    @Published private(set) var searching = false
    @Published private(set) var message = ""
    private var request: MKLocalSearch?
    private var timeout: Task<Void, Never>?
    private var revision = UUID()
    func clear() { cancel(); results = []; message = "" }
    func cancel() { revision = UUID(); request?.cancel(); request = nil; timeout?.cancel(); searching = false }
    func search(near coordinate: CLLocationCoordinate2D?, query: String = "") {
        cancel(); let token = revision
        results = []; message = ""; searching = true
        let options = MKLocalSearch.Request()
        options.naturalLanguageQuery = query.isEmpty ? "fitness center gym" : query
        options.resultTypes = .pointOfInterest
        options.pointOfInterestFilter = .init(including: [.fitnessCenter])
        if let coordinate { options.region = .init(center: coordinate, latitudinalMeters: 12_000, longitudinalMeters: 12_000) }
        let search = MKLocalSearch(request: options); request = search
        timeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 12_000_000_000) } catch { return }
            guard let self, self.revision == token else { return }
            self.cancel(); self.message = "passive.gym.searchFailed".tempoLocalized
        }
        search.start { [weak self] response, error in
            Task { @MainActor in
                guard let self, self.revision == token else { return }
                self.timeout?.cancel(); self.searching = false; self.request = nil
                guard error == nil, let response else { self.message = "passive.gym.searchFailed".tempoLocalized; return }
                var seen = Set<String>()
                self.results = response.mapItems.filter { $0.pointOfInterestCategory == .fitnessCenter }.compactMap { item in
                    let coordinate = item.placemark.coordinate
                    guard CLLocationCoordinate2DIsValid(coordinate), let name = item.name, !name.isEmpty else { return nil }
                    let id = "\(name)|\(coordinate.latitude)|\(coordinate.longitude)"
                    guard seen.insert(id).inserted else { return nil }
                    return GymPlace(id: id, name: name, address: [item.placemark.thoroughfare, item.placemark.locality].compactMap { $0 }.joined(separator: ", "), coordinate: coordinate, mapItem: item)
                }.prefix(6).map { $0 }
                if self.results.isEmpty { self.message = "passive.gym.noResults".tempoLocalized }
            }
        }
    }
}
