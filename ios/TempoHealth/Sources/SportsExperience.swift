import AVFoundation
import CoreLocation
import CoreMotion
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
                            Text("ÖN KAMERA · YÜZ TAKİBİ")
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
                        Text("Telefonu yere, yüzüne bakacak şekilde yerleştir. Tempo yüzünün kameraya yaklaşıp uzaklaşmasını takip ederek tekrarlarını saysın.")
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
                        Text("Yüz ve omuz konumları yalnızca iPhone üzerinde işlenir; görüntü kaydedilmez veya sunucuya gönderilmez.")
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
                    PushUpFaceOverlay(
                        trackingReady: counter.trackingReady,
                        shouldersDetected: counter.shouldersDetected,
                        phoneIsStable: counter.phoneIsStable,
                        isNear: counter.isAtBottom,
                        isCalibrating: counter.isCalibrating
                    )
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
                            .fill(counter.trackingReady ? TempoTheme.green : TempoTheme.orange)
                            .frame(width: 8, height: 8)
                        Text(counter.status)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                    if counter.faceDetected {
                        HStack(spacing: 5) {
                            Image(systemName: "viewfinder")
                            Text(counter.isCalibrating ? "%\(Int((counter.calibrationProgress * 100).rounded()))" : "%\(counter.proximityPercent)")
                        }
                        .font(.caption.monospacedDigit().bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                }

                Spacer()

                if counter.isCalibrating {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("BAŞLANGIÇ MESAFESİ AYARLANIYOR")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(.white.opacity(0.72))
                        ProgressView(value: counter.calibrationProgress)
                            .tint(TempoTheme.green)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.bottom, 12)
                }

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
                        Label(counter.isAtBottom ? "Aşağı" : "Canlı", systemImage: counter.isAtBottom ? "arrow.down.circle.fill" : "record.circle.fill")
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
        .frame(height: 430)
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
                    Text("Önden yüz ve omuz takibi · sabit telefon")
                        .font(.caption)
                        .foregroundStyle(TempoTheme.secondary)
                }
            }
            HStack(alignment: .top, spacing: 10) {
                PushUpGuideStep(number: "1", text: "Telefonu yere, ekranı sana bakacak şekilde yaklaşık 60–100 cm önüne koy.")
                PushUpGuideStep(number: "2", text: "Üst pozisyonda yüzün ve iki omzun halkada görünürken Başlat’a dokun.")
                PushUpGuideStep(number: "3", text: "Telefonu sabit bırak; yüzünle omuzların birlikte yaklaşınca tekrar algılanır.")
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

private struct PushUpFaceOverlay: View {
    let trackingReady: Bool
    let shouldersDetected: Bool
    let phoneIsStable: Bool
    let isNear: Bool
    let isCalibrating: Bool

    private var ringColor: Color {
        if !phoneIsStable { return TempoTheme.orange }
        if isNear { return .pink }
        return trackingReady ? TempoTheme.green : .white.opacity(0.48)
    }

    private var helperText: String {
        if !phoneIsStable { return "Telefonu sabit bir yere bırak" }
        if !shouldersDetected { return "Yüzünle iki omzunu halkaya getir" }
        return trackingReady ? "Hareket takibi hazır" : "Yüzünü halkaya getir"
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Circle()
                    .fill(.black.opacity(0.13))
                    .frame(width: 154, height: 154)
                    .overlay(
                        Circle()
                            .stroke(ringColor.opacity(0.22), lineWidth: 18)
                            .blur(radius: 11)
                    )
                    .overlay(
                        Circle()
                            .trim(from: 0.04, to: 0.96)
                            .stroke(
                                ringColor,
                                style: StrokeStyle(
                                    lineWidth: 3,
                                    lineCap: .round,
                                    dash: isCalibrating ? [10, 7] : []
                                )
                            )
                            .rotationEffect(.degrees(-90))
                    )
                    .overlay(
                        Image(systemName: trackingReady ? "face.smiling.inverse" : "viewfinder")
                            .font(.system(size: 35, weight: .light))
                            .foregroundStyle(.white.opacity(trackingReady ? 0.9 : 0.5))
                    )
                    .scaleEffect(isNear ? 1.1 : 1)
                    .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isNear)
                    .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.38)

                HStack(spacing: 7) {
                    Image(systemName: !phoneIsStable ? "iphone.gen3.radiowaves.left.and.right" : (trackingReady ? "checkmark.circle.fill" : "person.crop.circle.badge.exclamationmark"))
                    Text(helperText)
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.86))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .position(x: proxy.size.width * 0.5, y: proxy.size.height - 118)
            }
        }
        .allowsHitTesting(false)
    }
}

final class PushUpCounterModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()

    @Published private(set) var permissionDenied = false
    @Published private(set) var isCameraReady = false
    @Published private(set) var isWorkoutActive = false
    @Published private(set) var isCalibrating = false
    @Published private(set) var calibrationProgress = 0.0
    @Published private(set) var faceDetected = false
    @Published private(set) var shouldersDetected = false
    @Published private(set) var phoneIsStable = true
    @Published private(set) var proximityPercent = 0
    @Published private(set) var isAtBottom = false
    @Published private(set) var count = 0
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var status = "Yüzünle iki omzunu kameraya göster"
    @Published private(set) var bestSession: Int

    var trackingReady: Bool {
        faceDetected && shouldersDetected && phoneIsStable
    }

    private enum MotionPhase {
        case idle
        case calibrating
        case top
        case bottom
    }

    private let sessionQueue = DispatchQueue(label: "tempo.pushup.camera")
    private let visionQueue = DispatchQueue(label: "tempo.pushup.face-shoulder")
    private let faceRequest = VNDetectFaceRectanglesRequest()
    private let poseRequest = VNDetectHumanBodyPoseRequest()
    private let motionManager = CMMotionManager()
    private var configured = false
    private var phase: MotionPhase = .idle
    private var calibrationFaceSamples: [Double] = []
    private var calibrationShoulderSamples: [Double] = []
    private var baselineFaceScale: Double?
    private var baselineShoulderWidth: Double?
    private var smoothedFaceScale: Double?
    private var smoothedShoulderWidth: Double?
    private var nearFrameCount = 0
    private var farFrameCount = 0
    private var missingFaceFrames = 0
    private var phoneMovementBlockUntil = Date.distantPast
    private var lastProcessedAt = Date.distantPast
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
        startMotionMonitoring()
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
        motionManager.stopDeviceMotionUpdates()
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func startWorkout() {
        guard isCameraReady else { return }
        count = 0
        elapsedSeconds = 0
        phase = .calibrating
        isWorkoutActive = true
        isCalibrating = true
        calibrationProgress = 0
        calibrationFaceSamples = []
        calibrationShoulderSamples = []
        baselineFaceScale = nil
        baselineShoulderWidth = nil
        nearFrameCount = 0
        farFrameCount = 0
        isAtBottom = false
        lastRepAt = .distantPast
        status = trackingReady ? "Üst pozisyonda kısa süre sabit kal" : "Yüzünle iki omzunu halkaya getir"
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
        isCalibrating = false
        phase = .idle
        isAtBottom = false
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
        phase = .idle
        baselineFaceScale = nil
        baselineShoulderWidth = nil
        smoothedFaceScale = nil
        smoothedShoulderWidth = nil
        calibrationFaceSamples = []
        calibrationShoulderSamples = []
        calibrationProgress = 0
        isCalibrating = false
        isAtBottom = false
        proximityPercent = 0
        status = trackingReady ? "Takip hazır · Başlatmaya hazır" : "Yüzünle iki omzunu kameraya göster"
    }

    private func startMotionMonitoring() {
        guard motionManager.isDeviceMotionAvailable, !motionManager.isDeviceMotionActive else {
            phoneIsStable = true
            return
        }
        motionManager.deviceMotionUpdateInterval = 0.05
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let rotation = sqrt(
                motion.rotationRate.x * motion.rotationRate.x +
                motion.rotationRate.y * motion.rotationRate.y +
                motion.rotationRate.z * motion.rotationRate.z
            )
            let acceleration = sqrt(
                motion.userAcceleration.x * motion.userAcceleration.x +
                motion.userAcceleration.y * motion.userAcceleration.y +
                motion.userAcceleration.z * motion.userAcceleration.z
            )
            if rotation > 0.32 || acceleration > 0.075 {
                self.phoneMovementBlockUntil = Date().addingTimeInterval(0.9)
                self.phoneIsStable = false
                self.nearFrameCount = 0
                self.farFrameCount = 0
                if self.isWorkoutActive { self.status = "Telefon hareket etti · sabit bırak" }
            } else if Date() >= self.phoneMovementBlockUntil {
                self.phoneIsStable = true
            }
        }
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.configured {
                if !self.session.isRunning { self.session.startRunning() }
                DispatchQueue.main.async {
                    self.isCameraReady = true
                    self.startMotionMonitoring()
                }
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

            let device = input.device
            try? device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
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
                self.status = "Yüzünle iki omzunu kameraya göster"
                self.startMotionMonitoring()
            }
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = Date()
        guard now.timeIntervalSince(lastProcessedAt) >= 0.075 else { return }
        lastProcessedAt = now

        do {
            let handler = VNImageRequestHandler(
                cmSampleBuffer: sampleBuffer,
                orientation: .leftMirrored,
                options: [:]
            )
            try handler.perform([faceRequest, poseRequest])
            let face = faceRequest.results?.max(by: {
                $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
            })
            let shoulderWidth = poseRequest.results?.first.flatMap(Self.shoulderWidth(from:))

            guard let face else {
                DispatchQueue.main.async { [weak self] in
                    self?.consumeMissingFace()
                }
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.consume(face.boundingBox, shoulderWidth: shoulderWidth)
            }
        } catch {
            return
        }
    }

    private func consumeMissingFace() {
        missingFaceFrames += 1
        guard missingFaceFrames >= 4 else { return }
        faceDetected = false
        shouldersDetected = false
        proximityPercent = 0
        nearFrameCount = 0
        farFrameCount = 0
        status = isWorkoutActive ? "Yüzünü tekrar halkaya getir" : "Yüzünle iki omzunu kameraya göster"
    }

    private func consume(_ box: CGRect, shoulderWidth rawShoulderWidth: Double?) {
        missingFaceFrames = 0
        faceDetected = true
        shouldersDetected = rawShoulderWidth != nil

        guard phoneIsStable else {
            nearFrameCount = 0
            farFrameCount = 0
            status = "Telefon hareket etti · sabit bırak"
            return
        }

        let rawFaceScale = Double(sqrt(box.width * box.height))
        guard rawFaceScale > 0.045 else {
            status = "Telefonu biraz daha yakına getir"
            return
        }
        guard rawFaceScale < 0.62 else {
            status = "Telefonu biraz uzaklaştır"
            return
        }
        guard let rawShoulderWidth, rawShoulderWidth > 0.08 else {
            status = "İki omzunu da kadraja al"
            nearFrameCount = 0
            farFrameCount = 0
            return
        }

        let alpha = 0.26
        let faceScale = smoothedFaceScale.map { $0 + alpha * (rawFaceScale - $0) } ?? rawFaceScale
        let shoulderWidth = smoothedShoulderWidth.map { $0 + alpha * (rawShoulderWidth - $0) } ?? rawShoulderWidth
        smoothedFaceScale = faceScale
        smoothedShoulderWidth = shoulderWidth

        guard isWorkoutActive else {
            if count == 0 { status = "Yüz ve omuz takibi hazır" }
            proximityPercent = 100
            return
        }

        if phase == .calibrating {
            calibrationFaceSamples.append(faceScale)
            calibrationShoulderSamples.append(shoulderWidth)
            calibrationProgress = min(1, Double(calibrationFaceSamples.count) / 18)
            status = "Üst pozisyonda sabit kal · kalibrasyon"
            guard calibrationFaceSamples.count >= 18 else { return }

            baselineFaceScale = Self.median(calibrationFaceSamples)
            baselineShoulderWidth = Self.median(calibrationShoulderSamples)
            calibrationFaceSamples = []
            calibrationShoulderSamples = []
            calibrationProgress = 1
            isCalibrating = false
            phase = .top
            proximityPercent = 100
            status = "Hazır · aşağı in"
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return
        }

        guard let baselineFaceScale, let baselineShoulderWidth,
              baselineFaceScale > 0, baselineShoulderWidth > 0 else {
            phase = .calibrating
            isCalibrating = true
            calibrationFaceSamples = []
            calibrationShoulderSamples = []
            calibrationProgress = 0
            status = "Başlangıç mesafesi yeniden ayarlanıyor"
            return
        }

        let faceRatio = faceScale / baselineFaceScale
        let shoulderRatio = shoulderWidth / baselineShoulderWidth
        proximityPercent = Int((faceRatio * 100).rounded())

        switch phase {
        case .top:
            isAtBottom = false
            if faceRatio >= 1.16 && shoulderRatio >= 1.07 {
                nearFrameCount += 1
                if nearFrameCount >= 3 {
                    phase = .bottom
                    isAtBottom = true
                    nearFrameCount = 0
                    farFrameCount = 0
                    status = "Aşağı tamam · şimdi yüksel"
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } else {
                    status = "Biraz daha aşağı"
                }
            } else {
                nearFrameCount = 0
                status = faceRatio >= 1.16 ? "Omuzlarınla birlikte aşağı in" : "Aşağı in"
                if faceRatio > 0.92 && faceRatio < 1.07 && shoulderRatio > 0.94 && shoulderRatio < 1.05 {
                    self.baselineFaceScale = baselineFaceScale * 0.997 + faceScale * 0.003
                    self.baselineShoulderWidth = baselineShoulderWidth * 0.997 + shoulderWidth * 0.003
                }
            }

        case .bottom:
            isAtBottom = true
            if faceRatio <= 1.10 && shoulderRatio <= 1.045 {
                farFrameCount += 1
                if farFrameCount >= 3 && Date().timeIntervalSince(lastRepAt) > 0.65 {
                    count += 1
                    phase = .top
                    isAtBottom = false
                    farFrameCount = 0
                    nearFrameCount = 0
                    lastRepAt = Date()
                    status = "Güzel tekrar · tekrar aşağı"
                    if count > bestSession {
                        bestSession = count
                        defaults.set(count, forKey: "tempo.pushup.best")
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            } else {
                farFrameCount = 0
                status = "Şimdi yüksel"
            }

        case .idle:
            status = "Yüz ve omuz takibi hazır"

        case .calibrating:
            break
        }
    }

    private static func shoulderWidth(from observation: VNHumanBodyPoseObservation) -> Double? {
        guard let points = try? observation.recognizedPoints(.all),
              let left = points[.leftShoulder],
              let right = points[.rightShoulder],
              left.confidence > 0.18,
              right.confidence > 0.18 else { return nil }
        return Double(hypot(
            left.location.x - right.location.x,
            left.location.y - right.location.y
        ))
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        if sorted.count.isMultiple(of: 2) {
            let middle = sorted.count / 2
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[sorted.count / 2]
    }
}

private extension Calendar {
    func isDateInCurrentWeek(_ date: Date) -> Bool {
        isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
    }
}