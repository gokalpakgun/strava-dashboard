import CoreLocation
import MapKit
import SwiftUI

struct SportsHubScreen: View {
    @EnvironmentObject private var account: TempoAccountStore
    @EnvironmentObject private var model: TempoAppModel

    private var selectedSports: [TempoSportChoice] {
        account.profile?.sports.compactMap(TempoSportChoice.init(rawValue:)) ?? []
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TempoTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("SANA ÖZEL").font(.caption.bold()).tracking(1.5).foregroundStyle(TempoTheme.green)
                            Text("Sporlarım").font(.system(size: 31, weight: .bold, design: .rounded))
                            Text("Seçtiğin sporlara göre aktivite geçmişin ve hızlı araçların.")
                                .font(.subheadline).foregroundStyle(TempoTheme.secondary)
                        }

                        if selectedSports.isEmpty {
                            Text("Profilinden ilgilendiğin sporları seçerek bu alanı kişiselleştirebilirsin.")
                                .padding(20).frame(maxWidth: .infinity)
                                .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        } else {
                            ForEach(selectedSports) { sport in
                                SportSummaryCard(sport: sport, activities: model.dashboard?.activities ?? [])
                            }
                        }

                        Text("HIZLI ARAÇLAR").font(.caption.bold()).tracking(1.5).foregroundStyle(TempoTheme.green).padding(.top, 4)
                        NavigationLink(destination: CoachScreen()) {
                            ToolCard(title: "Tempo Koç", subtitle: "Tüm spor verilerine göre kişisel değerlendirme", icon: "sparkles", color: TempoTheme.blue)
                        }
                        .buttonStyle(.plain)
                        NavigationLink(destination: RoutesScreen()) {
                            ToolCard(title: "Aktivite rotaları", subtitle: "Strava GPS rotalarını tek haritada incele", icon: "map.fill", color: TempoTheme.orange)
                        }
                        .buttonStyle(.plain)
                        NavigationLink(destination: NearbyFacilitiesScreen()) {
                            ToolCard(title: "Yakındaki spor alanları", subtitle: "Kort, saha, havuz ve spor salonlarını bul", icon: "location.fill", color: TempoTheme.green)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 34)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct SportSummaryCard: View {
    let sport: TempoSportChoice
    let activities: [TempoActivity]

    private var matching: [TempoActivity] { activities.filter { sport.matches(activityType: $0.type) } }
    private var distance: Double { matching.reduce(0) { $0 + $1.distanceKm } }
    private var seconds: Double { matching.reduce(0) { $0 + $1.movingSeconds } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: sport.symbol).font(.title2).foregroundStyle(.black)
                    .frame(width: 50, height: 50).background(TempoTheme.green, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(sport.title).font(.title3.bold())
                    Text("\(matching.count) kayıtlı aktivite").font(.caption).foregroundStyle(TempoTheme.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(TempoTheme.secondary)
            }
            HStack(spacing: 8) {
                SportMetric(value: TempoFormat.distance(distance), label: "Mesafe")
                SportMetric(value: TempoFormat.duration(seconds), label: "Süre")
                SportMetric(value: "\(matching.filter { $0.date.map(Calendar.current.isDateInCurrentWeek) ?? false }.count)", label: "Bu hafta")
            }
        }
        .padding(18)
        .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct SportMetric: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(TempoTheme.secondary)
        }
        .padding(11).frame(maxWidth: .infinity, alignment: .leading)
        .background(TempoTheme.raised, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct ToolCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon).font(.title2).foregroundStyle(color)
                .frame(width: 52, height: 52).background(color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(.white)
                Text(subtitle).font(.caption).foregroundStyle(TempoTheme.secondary).lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(TempoTheme.secondary)
        }
        .padding(17)
        .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct NearbyFacilitiesScreen: View {
    @EnvironmentObject private var account: TempoAccountStore
    @StateObject private var searchModel = FacilitySearchModel()
    @State private var selectedSport: TempoSportChoice?
    @State private var selectedPlaceID: String?
    @State private var camera: MapCameraPosition = .automatic

    private var availableSports: [TempoSportChoice] {
        let selected = account.profile?.sports.compactMap(TempoSportChoice.init(rawValue:)).filter { $0.facilitySearchQuery != nil } ?? []
        return selected.isEmpty ? TempoSportChoice.allCases.filter { $0.facilitySearchQuery != nil } : selected
    }

    private var selectedPlace: NearbyPlace? {
        selectedPlaceID.flatMap { id in searchModel.places.first { $0.id == id } }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TempoTheme.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 13) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("YAKININDA").font(.caption.bold()).tracking(1.5).foregroundStyle(TempoTheme.green)
                        Text("Spor alanları").font(.system(size: 31, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 16)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(availableSports) { sport in
                                Button {
                                    selectedSport = sport
                                    selectedPlaceID = nil
                                    Task { await searchModel.search(for: sport) }
                                } label: {
                                    Label(sport.title, systemImage: sport.symbol)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(selectedSport == sport ? .black : .white)
                                        .padding(.horizontal, 14).padding(.vertical, 10)
                                        .background(selectedSport == sport ? TempoTheme.green : TempoTheme.card, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    ZStack {
                        Map(position: $camera, selection: $selectedPlaceID) {
                            UserAnnotation()
                            ForEach(searchModel.places) { place in
                                Marker(place.name, coordinate: place.coordinate)
                                    .tint(TempoTheme.orange)
                                    .tag(place.id)
                            }
                        }
                        .mapStyle(.standard(elevation: .realistic))
                        .mapControls {
                            MapUserLocationButton()
                            MapCompass()
                            MapScaleView()
                        }

                        if searchModel.isSearching {
                            ProgressView("Yakındaki alanlar aranıyor…")
                                .padding(16).background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                    .padding(.horizontal, 12)

                    if let place = selectedPlace {
                        PlaceCard(place: place)
                            .padding(.horizontal, 16)
                    } else if let message = searchModel.message {
                        HStack(spacing: 10) {
                            Image(systemName: "location.circle.fill").foregroundStyle(TempoTheme.green)
                            Text(message).font(.footnote).foregroundStyle(TempoTheme.secondary)
                            Spacer()
                            if searchModel.needsPermission {
                                Button("İzin ver") { searchModel.requestLocation() }
                                    .font(.caption.bold()).foregroundStyle(TempoTheme.green)
                            }
                        }
                        .padding(.horizontal, 18)
                    }
                }
                .padding(.top, 12).padding(.bottom, 8)
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if selectedSport == nil { selectedSport = availableSports.first }
                searchModel.requestLocation()
            }
            .onChange(of: searchModel.region?.center.latitude) { _, _ in
                if let region = searchModel.region { camera = .region(region) }
                if let selectedSport { Task { await searchModel.search(for: selectedSport) } }
            }
        }
    }
}

private struct PlaceCard: View {
    let place: NearbyPlace
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "mappin.and.ellipse").font(.title2).foregroundStyle(TempoTheme.orange)
                .frame(width: 48, height: 48).background(TempoTheme.orange.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(place.name).font(.headline).lineLimit(1)
                Text(place.address).font(.caption).foregroundStyle(TempoTheme.secondary).lineLimit(2)
            }
            Spacer()
            Button { place.openDirections() } label: {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .foregroundStyle(.black).frame(width: 42, height: 42).background(TempoTheme.green, in: Circle())
            }
        }
        .padding(15)
        .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
    }
}

@MainActor
final class FacilitySearchModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var places: [NearbyPlace] = []
    @Published var isSearching = false
    @Published var message: String? = "Yakındaki spor alanlarını görmek için konum izni ver."
    @Published var region: MKCoordinateRegion?
    @Published var needsPermission = true

    private let manager = CLLocationManager()
    private var location: CLLocation?
    private var pendingSport: TempoSportChoice?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            needsPermission = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            needsPermission = false
            manager.requestLocation()
        case .denied, .restricted:
            needsPermission = true
            message = "Konum izni kapalı. iPhone Ayarlar’dan Tempo için konuma izin verebilirsin."
        @unknown default:
            needsPermission = true
        }
    }

    func search(for sport: TempoSportChoice) async {
        guard let query = sport.facilitySearchQuery else { return }
        guard let location else {
            pendingSport = sport
            requestLocation()
            return
        }

        isSearching = true
        message = nil
        defer { isSearching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 20_000, longitudinalMeters: 20_000)

        do {
            let response = try await MKLocalSearch(request: request).start()
            places = response.mapItems.prefix(40).map(NearbyPlace.init)
            message = places.isEmpty ? "\(sport.title) için yakında kayıtlı bir alan bulunamadı." : "\(places.count) alan bulundu."
        } catch {
            places = []
            message = "Spor alanları şu anda aranamadı. Biraz sonra tekrar dene."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            needsPermission = false
            manager.requestLocation()
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            needsPermission = true
            message = "Konum izni kapalı. iPhone Ayarlar’dan Tempo için konuma izin verebilirsin."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let value = locations.last else { return }
        location = value
        region = MKCoordinateRegion(center: value.coordinate, latitudinalMeters: 16_000, longitudinalMeters: 16_000)
        if let pendingSport {
            self.pendingSport = nil
            Task { await search(for: pendingSport) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        message = "Konum alınamadı. Konum servislerini kontrol edip yeniden deneyebilirsin."
    }
}

struct NearbyPlace: Identifiable {
    let id: String
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    private let mapItem: MKMapItem

    init(_ mapItem: MKMapItem) {
        self.mapItem = mapItem
        name = mapItem.name ?? "Spor alanı"
        coordinate = mapItem.placemark.coordinate
        address = mapItem.placemark.title ?? "Adres bilgisi yok"
        id = String(format: "%.6f,%.6f,%@", coordinate.latitude, coordinate.longitude, name)
    }

    func openDirections() {
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

private extension Calendar {
    func isDateInCurrentWeek(_ date: Date) -> Bool {
        isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
    }
}