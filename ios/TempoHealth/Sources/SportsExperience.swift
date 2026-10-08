import CoreLocation
import Foundation
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
    @State private var searchRadiusKm = 25
    @State private var camera: MapCameraPosition = .automatic

    private var availableSports: [TempoSportChoice] {
        let preferred = account.profile?.sports
            .compactMap(TempoSportChoice.init(rawValue:))
            .filter { $0.facilitySearchQuery != nil } ?? []
        let remaining = TempoSportChoice.allCases.filter { sport in
            sport.facilitySearchQuery != nil && !preferred.contains(sport)
        }
        return preferred + remaining
    }

    private var selectedPlace: NearbyPlace? {
        selectedPlaceID.flatMap { id in searchModel.places.first { $0.id == id } }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TempoTheme.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("YAKININDA").font(.caption.bold()).tracking(1.5).foregroundStyle(TempoTheme.green)
                            Text("Spor alanları").font(.system(size: 31, weight: .bold, design: .rounded))
                        }
                        Spacer()
                        Menu {
                            ForEach([10, 25, 50], id: \.self) { radius in
                                Button {
                                    searchRadiusKm = radius
                                    selectedPlaceID = nil
                                    if let selectedSport {
                                        Task { await searchModel.search(for: selectedSport, radiusKm: radius) }
                                    }
                                } label: {
                                    if searchRadiusKm == radius {
                                        Label("\(radius) km", systemImage: "checkmark")
                                    } else {
                                        Text("\(radius) km")
                                    }
                                }
                            }
                        } label: {
                            Label("\(searchRadiusKm) km", systemImage: "scope")
                                .font(.caption.bold())
                                .foregroundStyle(TempoTheme.green)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(TempoTheme.card, in: Capsule())
                        }
                    }
                    .padding(.horizontal, 16)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(availableSports) { sport in
                                Button {
                                    selectedSport = sport
                                    selectedPlaceID = nil
                                    Task { await searchModel.search(for: sport, radiusKm: searchRadiusKm) }
                                } label: {
                                    Label(sport.title, systemImage: sport.symbol)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(selectedSport == sport ? .black : .white)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
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
                                    .tint(place.source == .openStreetMap ? TempoTheme.green : TempoTheme.orange)
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
                            ProgressView(searchModel.places.isEmpty ? "Spor alanları aranıyor…" : "Daha fazla yer taranıyor…")
                                .padding(14)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if searchModel.hasOpenStreetMapPlaces {
                            Link(destination: URL(string: "https://www.openstreetmap.org/copyright")!) {
                                Text("© OpenStreetMap katkıda bulunanlar")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.78))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                            .padding(8)
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
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if selectedSport == nil { selectedSport = availableSports.first }
                searchModel.requestLocation()
            }
            .onChange(of: searchModel.region?.center.latitude) { _, _ in
                if let region = searchModel.region { camera = .region(region) }
                if let selectedSport {
                    Task { await searchModel.search(for: selectedSport, radiusKm: searchRadiusKm) }
                }
            }
            .onChange(of: searchModel.region?.span.latitudeDelta) { _, _ in
                if let region = searchModel.region { camera = .region(region) }
            }
        }
    }
}

private struct PlaceCard: View {
    let place: NearbyPlace

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: place.source == .openStreetMap ? "map.fill" : "mappin.and.ellipse")
                .font(.title2)
                .foregroundStyle(place.source == .openStreetMap ? TempoTheme.green : TempoTheme.orange)
                .frame(width: 48, height: 48)
                .background((place.source == .openStreetMap ? TempoTheme.green : TempoTheme.orange).opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(place.name).font(.headline).lineLimit(1)
                Text(place.address).font(.caption).foregroundStyle(TempoTheme.secondary).lineLimit(2)
                Text("\(place.distanceText) · \(place.sourceTitle)")
                    .font(.caption2.bold())
                    .foregroundStyle(place.source == .openStreetMap ? TempoTheme.green : TempoTheme.orange)
            }
            Spacer()
            Button { place.openDirections() } label: {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .foregroundStyle(.black)
                    .frame(width: 42, height: 42)
                    .background(TempoTheme.green, in: Circle())
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

    var hasOpenStreetMapPlaces: Bool { places.contains { $0.source == .openStreetMap } }

    private let manager = CLLocationManager()
    private var location: CLLocation?
    private var pendingSport: TempoSportChoice?
    private var pendingRadiusKm = 25
    private var searchGeneration = 0

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

    func search(for sport: TempoSportChoice, radiusKm: Int) async {
        guard let location else {
            pendingSport = sport
            pendingRadiusKm = radiusKm
            requestLocation()
            return
        }

        searchGeneration += 1
        let generation = searchGeneration
        isSearching = true
        message = nil
        let radiusMeters = max(5_000, min(radiusKm, 50) * 1_000)
        region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: CLLocationDistance(radiusMeters * 2),
            longitudinalMeters: CLLocationDistance(radiusMeters * 2)
        )

        let applePlaces = await searchAppleMaps(for: sport, location: location, radiusMeters: radiusMeters)
        guard generation == searchGeneration else { return }
        places = Self.deduplicated(applePlaces)
        message = places.isEmpty ? "Açık harita kayıtları da taranıyor…" : "Apple Haritalar’dan \(places.count) alan bulundu; açık veriler taranıyor."

        let openPlaces = await searchOpenStreetMap(for: sport, location: location, radiusMeters: radiusMeters)
        guard generation == searchGeneration else { return }
        places = Self.deduplicated(applePlaces + openPlaces)
        isSearching = false
        message = places.isEmpty
            ? "\(sport.title) için \(radiusKm) km çevrede kayıtlı bir alan bulunamadı."
            : "\(places.count) alan bulundu · yakından uzağa sıralandı."
    }

    private func searchAppleMaps(for sport: TempoSportChoice, location: CLLocation, radiusMeters: Int) async -> [NearbyPlace] {
        let searchRegion = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: CLLocationDistance(radiusMeters * 2),
            longitudinalMeters: CLLocationDistance(radiusMeters * 2)
        )
        var results: [NearbyPlace] = []

        for query in sport.facilitySearchQueries {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = searchRegion
            request.resultTypes = .pointOfInterest
            do {
                let response = try await MKLocalSearch(request: request).start()
                results.append(contentsOf: response.mapItems.prefix(35).map { NearbyPlace($0, origin: location) })
                results = Self.deduplicated(results)
                if results.count >= 70 { break }
            } catch {
                continue
            }
        }
        return results
    }

    private func searchOpenStreetMap(for sport: TempoSportChoice, location: CLLocation, radiusMeters: Int) async -> [NearbyPlace] {
        guard !sport.openStreetMapSelectors.isEmpty else { return [] }
        let latitude = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), location.coordinate.latitude)
        let longitude = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), location.coordinate.longitude)
        let selectors = sport.openStreetMapSelectors
            .map { "nwr(around:\(radiusMeters),\(latitude),\(longitude))\($0);" }
            .joined()
        let query = "[out:json][timeout:18];(\(selectors));out center tags;"

        var components = URLComponents(string: "https://overpass-api.de/api/interpreter")
        components?.queryItems = [URLQueryItem(name: "data", value: query)]
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 22
        request.setValue("Tempo/1.0 (https://apitempo.com)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
            let decoded = try JSONDecoder().decode(OpenStreetMapResponse.self, from: data)
            return decoded.elements.prefix(160).compactMap {
                NearbyPlace(openStreetMapElement: $0, sportTitle: sport.title, origin: location)
            }
        } catch {
            return []
        }
    }

    private static func deduplicated(_ input: [NearbyPlace]) -> [NearbyPlace] {
        let sorted = input.sorted { $0.distanceMeters < $1.distanceMeters }
        var result: [NearbyPlace] = []
        for place in sorted {
            let duplicate = result.contains { existing in
                let distance = CLLocation(latitude: existing.coordinate.latitude, longitude: existing.coordinate.longitude)
                    .distance(from: CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude))
                let sameName = existing.normalizedName == place.normalizedName
                return distance < 70 || (sameName && distance < 700)
            }
            if !duplicate { result.append(place) }
            if result.count >= 100 { break }
        }
        return result
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
            let radius = pendingRadiusKm
            self.pendingSport = nil
            Task { await search(for: pendingSport, radiusKm: radius) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isSearching = false
        message = "Konum alınamadı. Konum servislerini kontrol edip yeniden deneyebilirsin."
    }
}

struct OpenStreetMapResponse: Decodable {
    let elements: [OpenStreetMapElement]
}

struct OpenStreetMapElement: Decodable {
    struct Center: Decodable {
        let lat: Double
        let lon: Double
    }

    let type: String
    let id: Int64
    let lat: Double?
    let lon: Double?
    let center: Center?
    let tags: [String: String]?
}

struct NearbyPlace: Identifiable {
    enum Source: Equatable {
        case appleMaps
        case openStreetMap
    }

    let id: String
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let source: Source
    let distanceMeters: CLLocationDistance
    private let mapItem: MKMapItem?

    var sourceTitle: String {
        source == .openStreetMap ? "OpenStreetMap" : "Apple Haritalar"
    }

    var normalizedName: String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: " ", with: "")
    }

    var distanceText: String {
        if distanceMeters < 1_000 { return "\(max(1, Int(distanceMeters.rounded()))) m" }
        return String(format: "%.1f km", distanceMeters / 1_000)
    }

    init(_ mapItem: MKMapItem, origin: CLLocation) {
        self.mapItem = mapItem
        name = mapItem.name ?? "Spor alanı"
        coordinate = mapItem.placemark.coordinate
        address = mapItem.placemark.title ?? "Adres bilgisi yok"
        source = .appleMaps
        distanceMeters = origin.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        id = String(format: "apple:%.6f,%.6f,%@", coordinate.latitude, coordinate.longitude, name)
    }

    init?(openStreetMapElement element: OpenStreetMapElement, sportTitle: String, origin: CLLocation) {
        guard let latitude = element.lat ?? element.center?.lat,
              let longitude = element.lon ?? element.center?.lon else { return nil }

        let tags = element.tags ?? [:]
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        name = tags["name:tr"] ?? tags["name"] ?? tags["operator"] ?? "\(sportTitle) alanı"

        let street = [tags["addr:street"], tags["addr:housenumber"]].compactMap { $0 }.joined(separator: " ")
        let area = [tags["addr:district"], tags["addr:suburb"], tags["addr:city"]].compactMap { $0 }.joined(separator: ", ")
        let parts = [street, area].filter { !$0.isEmpty }
        address = parts.isEmpty ? "Açık harita kaydı" : parts.joined(separator: " · ")

        source = .openStreetMap
        mapItem = nil
        distanceMeters = origin.distance(from: CLLocation(latitude: latitude, longitude: longitude))
        id = "osm:\(element.type):\(element.id)"
    }

    func openDirections() {
        if let mapItem {
            mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
            return
        }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

private extension Calendar {
    func isDateInCurrentWeek(_ date: Date) -> Bool {
        isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
    }
}