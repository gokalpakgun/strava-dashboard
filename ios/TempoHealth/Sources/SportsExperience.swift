import AVFoundation
import CoreLocation
import ImageIO
import Foundation
import MapKit
import SwiftUI
import UIKit
import Vision

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

                        NavigationLink(destination: PushUpCounterScreen()) {
                            FeaturedPushUpCard()
                        }
                        .buttonStyle(.plain)

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

private struct FeaturedPushUpCard: View {
    @AppStorage("tempo.pushup.best") private var bestSession = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 170, height: 170)
                .offset(x: 55, y: -64)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(TempoTheme.green)
                                .frame(width: 8, height: 8)
                            Text("KAMERA HAZIR · YAKIN ÇEKİM")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        Text("Akıllı şınav\nsayacı")
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineSpacing(-1)
                    }
                    Spacer()
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 29, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(.white.opacity(0.13), in: Circle())
                }

                HStack {
                    Label(
                        bestSession > 0 ? "En iyi set: \(bestSession)" : "İlk setini başlat",
                        systemImage: "trophy.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    Spacer()
                    HStack(spacing: 6) {
                        Text("Başla")
                            .font(.subheadline.bold())
                        Image(systemName: "arrow.right")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(TempoTheme.green, in: Capsule())
                }
            }
            .padding(20)
        }
        .frame(height: 196)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.21, green: 0.08, blue: 0.29),
                    Color(red: 0.46, green: 0.08, blue: 0.28),
                    Color(red: 0.12, green: 0.18, blue: 0.30),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 27, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .stroke(.white.opacity(0.1))
        )
        .shadow(color: Color.pink.opacity(0.18), radius: 20, y: 10)
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

struct PushUpCounterScreen: View {
    @StateObject private var counter = PushUpCounterModel()

    var body: some View {
        ZStack {
            TempoTheme.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("KAMERA İLE ANTRENMAN")
                            .font(.caption.bold())
                            .tracking(1.4)
                            .foregroundStyle(TempoTheme.green)
                        Text("Akıllı şınav sayacı")
                            .font(.system(size: 31, weight: .bold, design: .rounded))
                        Text("Telefonu yere yakın, üst gövdenin yanına yerleştir. Omuz, dirsek ve bileğinin görünmesi sayım için yeterli.")
                            .font(.subheadline)
                            .foregroundStyle(TempoTheme.secondary)
                            .lineSpacing(3)
                    }

                    if counter.permissionDenied {
                        cameraPermissionCard
                    } else {
                        cameraCard
                        controls
                        metrics
                        formGuide
                    }

                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(TempoTheme.green)
                        Text("Kamera görüntüsü yalnızca iPhone üzerinde işlenir; kaydedilmez veya sunucuya gönderilmez.")
                            .font(.caption)
                            .foregroundStyle(TempoTheme.secondary)
                            .lineSpacing(3)
                    }
                    .padding(.horizontal, 3)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 92)
            }
        }
        .navigationTitle("Şınav Sayacı")
        .navigationBarTitleDisplayMode(.inline)
        .tempoGlassBackButton()
        .onAppear { counter.prepareCamera() }
        .onDisappear { counter.stopCamera() }
    }

    private var cameraCard: some View {
        ZStack {
            PushUpCameraPreview(session: counter.session)
                .overlay {
                    LinearGradient(
                        colors: [.black.opacity(0.08), .clear, .black.opacity(0.46)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .overlay {
                    PushUpPoseOverlay(joints: counter.joints, isGoodForm: counter.hasGoodForm)
                }

            if !counter.isCameraReady {
                VStack(spacing: 12) {
                    ProgressView().tint(TempoTheme.green)
                    Text("Kamera hazırlanıyor…")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.76))
                }
            }

            VStack {
                HStack {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(counter.hasGoodForm ? TempoTheme.green : TempoTheme.orange)
                            .frame(width: 8, height: 8)
                        Text(counter.status)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                    if let angle = counter.elbowAngle {
                        Text("\(Int(angle.rounded()))°")
                            .font(.caption.monospacedDigit().bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }

                Spacer()

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("TEKRAR")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.68))
                        Text("\(counter.count)")
                            .font(.system(size: 68, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    if counter.isWorkoutActive {
                        Label("Canlı", systemImage: "record.circle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.78), in: Capsule())
                    }
                }
            }
            .padding(16)
        }
        .frame(height: 440)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.08))
        )
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                if counter.isWorkoutActive {
                    counter.stopWorkout()
                } else {
                    counter.startWorkout()
                }
            } label: {
                Label(
                    counter.isWorkoutActive ? "Antrenmanı bitir" : "Antrenmanı başlat",
                    systemImage: counter.isWorkoutActive ? "stop.fill" : "play.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PushUpPrimaryButtonStyle(active: counter.isWorkoutActive))
            .disabled(!counter.isCameraReady)

            Button {
                counter.resetWorkout()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 25, height: 25)
            }
            .buttonStyle(PushUpSecondaryButtonStyle())
            .disabled(counter.isWorkoutActive || counter.count == 0)
            .accessibilityLabel("Sayacı sıfırla")
        }
    }

    private var metrics: some View {
        HStack(spacing: 9) {
            PushUpMetric(
                title: "Süre",
                value: counter.elapsedText,
                icon: "timer",
                color: TempoTheme.blue
            )
            PushUpMetric(
                title: "Tempo",
                value: "\(counter.repsPerMinute)/dk",
                icon: "speedometer",
                color: TempoTheme.orange
            )
            PushUpMetric(
                title: "En iyi",
                value: "\(counter.bestSession)",
                icon: "trophy.fill",
                color: TempoTheme.green
            )
        }
    }

    private var formGuide: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(.pink)
                    .frame(width: 38, height: 38)
                    .background(Color.pink.opacity(0.11), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Doğru algılama için")
                        .font(.headline)
                    Text("Yakın yan görünüş · yalnızca üst gövde yeterli")
                        .font(.caption)
                        .foregroundStyle(TempoTheme.secondary)
                }
            }
            HStack(alignment: .top, spacing: 10) {
                PushUpGuideStep(number: "1", text: "Telefonu yere yakın, yaklaşık 1–1,5 metre yanına koy.")
                PushUpGuideStep(number: "2", text: "Omuz, dirsek ve bileğin kadrajda kalsın; bacakların görünmeyebilir.")
                PushUpGuideStep(number: "3", text: "Üstte kolunu aç, aşağı inerken dirseğini yaklaşık 90° bük.")
            }
        }
        .padding(17)
        .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.05)))
    }

    private var cameraPermissionCard: some View {
        VStack(spacing: 17) {
            Image(systemName: "camera.fill")
                .font(.system(size: 38))
                .foregroundStyle(TempoTheme.orange)
                .frame(width: 74, height: 74)
                .background(TempoTheme.orange.opacity(0.12), in: Circle())
            Text("Kamera izni gerekli")
                .font(.title3.bold())
            Text("Şınavlarını cihaz üzerinde sayabilmek için iPhone Ayarları’ndan Tempo’ya kamera erişimi ver.")
                .font(.subheadline)
                .foregroundStyle(TempoTheme.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            Button {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            } label: {
                Label("Ayarları aç", systemImage: "gear")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PushUpPrimaryButtonStyle(active: false))
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
    }
}

private struct PushUpMetric: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(TempoTheme.secondary)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct PushUpGuideStep: View {
    let number: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(number)
                .font(.caption2.bold())
                .foregroundStyle(.black)
                .frame(width: 23, height: 23)
                .background(TempoTheme.green, in: Circle())
            Text(text)
                .font(.caption2)
                .foregroundStyle(TempoTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct PushUpPrimaryButtonStyle: ButtonStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(active ? .white : .black)
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(
                active ? Color.red.opacity(configuration.isPressed ? 0.68 : 0.86) : TempoTheme.green.opacity(configuration.isPressed ? 0.74 : 1),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
    }
}

private struct PushUpSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(TempoTheme.card.opacity(configuration.isPressed ? 0.65 : 1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.07)))
    }
}

private struct PushUpCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PushUpPreviewView {
        let view = PushUpPreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        if let connection = view.previewLayer.connection {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        return view
    }

    func updateUIView(_ uiView: PushUpPreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

private final class PushUpPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

private struct PushUpPoseOverlay: View {
    let joints: [String: CGPoint]
    let isGoodForm: Bool

    private let bones = [
        ("shoulder", "elbow"),
        ("elbow", "wrist"),
        ("shoulder", "hip"),
        ("hip", "knee"),
        ("knee", "ankle"),
    ]

    var body: some View {
        Canvas { context, size in
            let color = isGoodForm ? TempoTheme.green : TempoTheme.orange
            for (startName, endName) in bones {
                guard let start = joints[startName], let end = joints[endName] else { continue }
                var line = Path()
                line.move(to: point(start, in: size))
                line.addLine(to: point(end, in: size))
                context.stroke(line, with: .color(color.opacity(0.92)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
            for joint in joints.values {
                let center = point(joint, in: size)
                let rect = CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
                context.fill(Path(ellipseIn: rect), with: .color(.white))
                context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
    }

    private func point(_ value: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: (1 - value.x) * size.width, y: (1 - value.y) * size.height)
    }
}

private struct PushUpPoseFrame {
    let elbowAngle: Double
    let bodyAlignment: Double?
    let confidence: Float
    let shoulderY: Double
    let upperArmLength: Double
    let joints: [String: CGPoint]
}

final class PushUpCounterModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()

    @Published private(set) var permissionDenied = false
    @Published private(set) var isCameraReady = false
    @Published private(set) var isWorkoutActive = false
    @Published private(set) var count = 0
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var status = "Omuz, dirsek ve bileğini kadraja al"
    @Published private(set) var elbowAngle: Double?
    @Published private(set) var bodyAlignment: Double?
    @Published private(set) var joints: [String: CGPoint] = [:]
    @Published private(set) var hasGoodForm = false
    @Published private(set) var bestSession: Int

    private let sessionQueue = DispatchQueue(label: "tempo.pushup.camera")
    private let visionQueue = DispatchQueue(label: "tempo.pushup.vision")
    private let poseRequest = VNDetectHumanBodyPoseRequest()
    private var configured = false
    private var smoothedElbowAngle: Double?
    private var reachedTop = false
    private var reachedBottom = false
    private var topShoulderY: Double?
    private var lastRepAt = Date.distantPast
    private var elapsedTimer: Timer?
    private let defaults = UserDefaults.standard

    override init() {
        bestSession = UserDefaults.standard.integer(forKey: "tempo.pushup.best")
        super.init()
    }

    var elapsedText: String {
        String(format: "%02d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
    }

    var repsPerMinute: Int {
        guard elapsedSeconds > 0 else { return 0 }
        return Int((Double(count) * 60 / Double(elapsedSeconds)).rounded())
    }

    func prepareCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionDenied = false
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.permissionDenied = !granted
                    if granted { self?.configureAndStart() }
                }
            }
        default:
            permissionDenied = true
            isCameraReady = false
        }
    }

    func stopCamera() {
        stopWorkout()
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func startWorkout() {
        guard isCameraReady else { return }
        count = 0
        elapsedSeconds = 0
        reachedTop = false
        reachedBottom = false
        topShoulderY = nil
        lastRepAt = .distantPast
        isWorkoutActive = true
        status = "Başlangıç pozisyonuna geç"
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.elapsedSeconds += 1
        }
    }

    func stopWorkout() {
        guard isWorkoutActive else {
            elapsedTimer?.invalidate()
            elapsedTimer = nil
            return
        }
        isWorkoutActive = false
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        if count > bestSession {
            bestSession = count
            defaults.set(count, forKey: "tempo.pushup.best")
        }
        status = count > 0 ? "Antrenman tamamlandı" : "Hazır olduğunda tekrar başlat"
    }

    func resetWorkout() {
        guard !isWorkoutActive else { return }
        count = 0
        elapsedSeconds = 0
        reachedTop = false
        reachedBottom = false
        topShoulderY = nil
        status = "Omuz, dirsek ve bileğini kadraja al"
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.configured {
                if !self.session.isRunning { self.session.startRunning() }
                DispatchQueue.main.async { self.isCameraReady = true }
                return
            }

            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                  let input = try? AVCaptureDeviceInput(device: camera),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.permissionDenied = true
                    self.status = "Kamera başlatılamadı"
                }
                return
            }
            self.session.addInput(input)

            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            output.setSampleBufferDelegate(self, queue: self.visionQueue)
            guard self.session.canAddOutput(output) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.status = "Kamera görüntüsü hazırlanamadı" }
                return
            }
            self.session.addOutput(output)
            if let connection = output.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }

            self.configured = true
            self.session.commitConfiguration()
            self.session.startRunning()
            DispatchQueue.main.async {
                self.isCameraReady = true
                self.status = "Omuz, dirsek ve bileğini kadraja al"
            }
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        do {
            let handler = VNImageRequestHandler(
                cmSampleBuffer: sampleBuffer,
                orientation: .leftMirrored,
                options: [:]
            )
            try handler.perform([poseRequest])
            guard let observation = poseRequest.results?.first,
                  let frame = Self.poseFrame(from: observation) else {
                DispatchQueue.main.async { [weak self] in
                    self?.hasGoodForm = false
                    self?.status = "Üst gövdeni yan profilden göster"
                    self?.joints = [:]
                }
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.consume(frame)
            }
        } catch {
            return
        }
    }

    private func consume(_ frame: PushUpPoseFrame) {
        let alpha = 0.34
        let smooth = smoothedElbowAngle.map { $0 + alpha * (frame.elbowAngle - $0) } ?? frame.elbowAngle
        smoothedElbowAngle = smooth
        elbowAngle = smooth
        bodyAlignment = frame.bodyAlignment
        joints = frame.joints

        let confident = frame.confidence > 0.25
        let optionalBodyForm = frame.bodyAlignment.map { $0 > 135 } ?? true
        hasGoodForm = confident && optionalBodyForm

        guard confident else {
            status = "Omuz, dirsek ve bileğini kameraya göster"
            return
        }

        guard isWorkoutActive else {
            status = optionalBodyForm ? "Yakın çekim hazır" : "Kalçanı omuz hizasında tut"
            return
        }

        if smooth >= 148 {
            reachedTop = true
            if !reachedBottom {
                topShoulderY = max(topShoulderY ?? frame.shoulderY, frame.shoulderY)
                status = optionalBodyForm ? "Aşağı in" : "Gövdeni biraz daha düz tut"
            }

            if reachedBottom && Date().timeIntervalSince(lastRepAt) > 0.55 {
                count += 1
                reachedBottom = false
                topShoulderY = frame.shoulderY
                lastRepAt = Date()
                status = "Güzel tekrar"
                if count > bestSession {
                    bestSession = count
                    defaults.set(count, forKey: "tempo.pushup.best")
                }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        } else if smooth <= 105 && reachedTop {
            let requiredDrop = max(0.008, frame.upperArmLength * 0.07)
            let shoulderDrop = (topShoulderY ?? frame.shoulderY) - frame.shoulderY
            if shoulderDrop >= requiredDrop {
                reachedBottom = true
                status = "Şimdi yukarı"
            } else {
                status = "Göğsünü biraz daha indir"
            }
        } else if reachedBottom {
            status = "Yukarı doğru devam et"
        } else {
            status = "Dirseklerini kontrollü bük"
        }
    }

    private static func poseFrame(from observation: VNHumanBodyPoseObservation) -> PushUpPoseFrame? {
        guard let points = try? observation.recognizedPoints(.all) else { return nil }
        let left = sideCandidate(
            points: points,
            shoulder: .leftShoulder,
            elbow: .leftElbow,
            wrist: .leftWrist,
            hip: .leftHip,
            knee: .leftKnee,
            ankle: .leftAnkle
        )
        let right = sideCandidate(
            points: points,
            shoulder: .rightShoulder,
            elbow: .rightElbow,
            wrist: .rightWrist,
            hip: .rightHip,
            knee: .rightKnee,
            ankle: .rightAnkle
        )
        guard let candidate = [left, right].compactMap({ $0 }).max(by: { $0.confidence < $1.confidence }) else {
            return nil
        }

        let elbow = angle(candidate.shoulder.location, candidate.elbow.location, candidate.wrist.location)
        let upperArmLength = Double(hypot(
            candidate.shoulder.location.x - candidate.elbow.location.x,
            candidate.shoulder.location.y - candidate.elbow.location.y
        ))

        var alignment: Double?
        if let hip = candidate.hip, let lowerBodyPoint = candidate.ankle ?? candidate.knee {
            alignment = angle(candidate.shoulder.location, hip.location, lowerBodyPoint.location)
        }

        var joints: [String: CGPoint] = [
            "shoulder": candidate.shoulder.location,
            "elbow": candidate.elbow.location,
            "wrist": candidate.wrist.location,
        ]
        if let hip = candidate.hip { joints["hip"] = hip.location }
        if let knee = candidate.knee { joints["knee"] = knee.location }
        if let ankle = candidate.ankle { joints["ankle"] = ankle.location }

        return PushUpPoseFrame(
            elbowAngle: elbow,
            bodyAlignment: alignment,
            confidence: candidate.confidence,
            shoulderY: Double(candidate.shoulder.location.y),
            upperArmLength: upperArmLength,
            joints: joints
        )
    }

    private struct SideCandidate {
        let shoulder: VNRecognizedPoint
        let elbow: VNRecognizedPoint
        let wrist: VNRecognizedPoint
        let hip: VNRecognizedPoint?
        let knee: VNRecognizedPoint?
        let ankle: VNRecognizedPoint?
        let confidence: Float
    }

    private static func sideCandidate(
        points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint],
        shoulder: VNHumanBodyPoseObservation.JointName,
        elbow: VNHumanBodyPoseObservation.JointName,
        wrist: VNHumanBodyPoseObservation.JointName,
        hip: VNHumanBodyPoseObservation.JointName,
        knee: VNHumanBodyPoseObservation.JointName,
        ankle: VNHumanBodyPoseObservation.JointName
    ) -> SideCandidate? {
        guard let shoulderPoint = points[shoulder],
              let elbowPoint = points[elbow],
              let wristPoint = points[wrist] else { return nil }

        let required = [shoulderPoint, elbowPoint, wristPoint]
        let confidence = required.map(\.confidence).min() ?? 0
        guard confidence > 0.18 else { return nil }

        let hipPoint = points[hip].flatMap { $0.confidence > 0.18 ? $0 : nil }
        let kneePoint = points[knee].flatMap { $0.confidence > 0.18 ? $0 : nil }
        let anklePoint = points[ankle].flatMap { $0.confidence > 0.18 ? $0 : nil }
        return SideCandidate(
            shoulder: shoulderPoint,
            elbow: elbowPoint,
            wrist: wristPoint,
            hip: hipPoint,
            knee: kneePoint,
            ankle: anklePoint,
            confidence: confidence
        )
    }

    private static func angle(_ first: CGPoint, _ center: CGPoint, _ last: CGPoint) -> Double {
        let firstVector = CGVector(dx: first.x - center.x, dy: first.y - center.y)
        let lastVector = CGVector(dx: last.x - center.x, dy: last.y - center.y)
        let dot = Double(firstVector.dx * lastVector.dx + firstVector.dy * lastVector.dy)
        let magnitude = Double(hypot(firstVector.dx, firstVector.dy) * hypot(lastVector.dx, lastVector.dy))
        guard magnitude > 0.0001 else { return 0 }
        let cosine = max(-1.0, min(1.0, dot / magnitude))
        return acos(cosine) * 180 / Double.pi
    }
}

private extension Calendar {
    func isDateInCurrentWeek(_ date: Date) -> Bool {
        isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
    }
}