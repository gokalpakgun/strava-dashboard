import Combine
import CoreLocation
import MapKit
import SwiftUI

@MainActor
private final class TempoLocationRecorder: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var route: [CLLocation] = []
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var isRecording = false
    @Published private(set) var isReadyToSave = false
    private var tracksLocation = true
    @Published var errorMessage: String?

    private let manager = CLLocationManager()
    private var startedAt: Date?
    private var segmentStartedAt: Date?
    private var accumulatedSeconds: TimeInterval = 0
    @Published private(set) var distanceMeters: Double = 0
    private var segmentLastLocation: CLLocation?
    private var segmentStartIndices = Set<Int>()
    private var timer: Timer?
    private var shouldStartAfterPermission = false

    var hasStarted: Bool { startedAt != nil }
    var sessionStartedAt: Date? { startedAt }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = false
    }

    var coordinates: [TempoCoordinate] {
        route.enumerated().map { index, location in
            TempoCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, startsNewSegment: segmentStartIndices.contains(index) ? true : nil)
        }
    }

    var canSave: Bool { elapsedSeconds > 0 }

    func report(_ message: String) { errorMessage = message }

    func startWithoutLocation() {
        shouldStartAfterPermission = false
        errorMessage = nil
        beginSegment(usingLocation: false)
    }

    func start() {
        errorMessage = nil
        if hasStarted && !tracksLocation { beginSegment(usingLocation: false); return }
        switch manager.authorizationStatus {
        case .notDetermined:
            shouldStartAfterPermission = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            beginSegment()
        case .denied, .restricted:
            errorMessage = "Rota kaydı için iPhone ayarlarından Tempo konum iznini aç."
        @unknown default:
            errorMessage = "Konum izni durumu okunamadı."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard shouldStartAfterPermission else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            shouldStartAfterPermission = false
            beginSegment()
        case .denied, .restricted:
            shouldStartAfterPermission = false
            errorMessage = "Rota kaydı için iPhone ayarlarından Tempo konum iznini aç."
        default:
            break
        }
    }

    func pause() {
        guard isRecording else { return }
        timer?.invalidate()
        timer = nil
        if let segmentStartedAt { accumulatedSeconds += max(0, Date().timeIntervalSince(segmentStartedAt)) }
        segmentStartedAt = nil
        elapsedSeconds = Int(accumulatedSeconds)
        manager.stopUpdatingLocation()
        isRecording = false
    }

    func finish() {
        pause()
        isReadyToSave = true
    }

    func cancel() {
        shouldStartAfterPermission = false
        timer?.invalidate()
        timer = nil
        manager.stopUpdatingLocation()
        route.removeAll()
        segmentLastLocation = nil
        segmentStartIndices.removeAll()
        distanceMeters = 0
        startedAt = nil
        segmentStartedAt = nil
        accumulatedSeconds = 0
        elapsedSeconds = 0
        isRecording = false
        isReadyToSave = false
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isRecording, tracksLocation else { return }
        for location in locations {
            guard CLLocationCoordinate2DIsValid(location.coordinate),
                  location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 35,
                  abs(location.timestamp.timeIntervalSinceNow) <= 15,
                  let segmentStartedAt, location.timestamp >= segmentStartedAt,
                  location.speed < 0 || location.speed <= 8 else { continue }
            var beginsSegment = segmentLastLocation == nil
            if let previous = segmentLastLocation {
                let interval = location.timestamp.timeIntervalSince(previous.timestamp)
                guard interval > 0 else { continue }
                let segment = previous.distance(from: location)
                if interval > 30 {
                    // A GPS gap has no measured path; resume without estimating it.
                    beginsSegment = true
                } else {
                    guard segment >= 2, segment <= 250, segment / interval <= 8 else { continue }
                    distanceMeters += segment
                }
            }
            if beginsSegment { segmentStartIndices.insert(route.count) }
            segmentLastLocation = location
            route.append(location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = "Konum alınamadı: %@".tempoFormatted(error.localizedDescription)
    }

    private func beginSegment(usingLocation: Bool = true) {
        guard !isRecording else { return }
        if startedAt == nil { startedAt = Date() }
        segmentStartedAt = Date()
        segmentLastLocation = nil
        isRecording = true
        isReadyToSave = false
        tracksLocation = usingLocation
        if usingLocation { manager.startUpdatingLocation() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let segmentStartedAt = self.segmentStartedAt else { return }
                self.elapsedSeconds = Int(self.accumulatedSeconds + max(0, Date().timeIntervalSince(segmentStartedAt)))
            }
        }
    }
}

struct TempoPhoneTrackerScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var recorder = TempoLocationRecorder()
    @State private var selectedSport = "run"
    @State private var notes = ""
    @State private var perceivedEffort: Int?
    @State private var enjoyment: Int?
    @State private var isSaving = false
    @State private var showCloseConfirmation = false
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39, longitude: 35),
        span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)
    ))

    private var routeCoordinates: [CLLocationCoordinate2D] { recorder.route.map(\.coordinate) }
    private var routeSegments: [[CLLocationCoordinate2D]] {
        TempoCoordinate.segments(recorder.coordinates).map { $0.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) } }
    }
    private var sportTitle: String { selectedSport == "run" ? "Koşu".tempoLocalized : "Yürüyüş".tempoLocalized }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    mapCard
                    sportPicker
                    metrics

                    Label("Konum izni yalnızca rotayı iPhone’da kaydetmek için kullanılır. Kayıt uygulama açıkken sürer ve Strava’ya gönderilmez.", systemImage: "hand.raised.fill")
                        .font(.caption2).foregroundStyle(TempoTheme.secondary).lineSpacing(3)

                    if let error = recorder.errorMessage {
                        Label(error.tempoLocalized, systemImage: "location.slash.fill")
                            .font(.caption).foregroundStyle(TempoTheme.orange)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(TempoTheme.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                    }

                    if recorder.isReadyToSave {
                        TextField("Nasıl geçti? Kısa not (isteğe bağlı)", text: $notes, axis: .vertical)
                            .lineLimit(2...4)
                            .padding(13).background(TempoTheme.raised, in: RoundedRectangle(cornerRadius: 15))
                        compactRatings
                        if recorder.route.count < 2 {
                            Text("GPS rotası yok; yalnızca süre kaydedilecek.").font(.caption).foregroundStyle(TempoTheme.secondary)
                        }
                        if !recorder.canSave {
                            Label("Kaydetmek için önce kısa bir kayıt başlat.", systemImage: "location.slash")
                                .font(.caption2).foregroundStyle(TempoTheme.secondary)
                        }
                    }

                    recorderControls.disabled(isSaving)
                }
                .padding(16)
                .padding(.bottom, TempoTheme.scrollBottomClearance)
            }
            .background(TempoTheme.background)
            .navigationTitle("Telefonla kayıt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Kapat") {
                        if recorder.hasStarted { showCloseConfirmation = true }
                        else { dismiss() }
                    }
                }
            }
            .confirmationDialog("Kayıt sürüyor", isPresented: $showCloseConfirmation, titleVisibility: .visible) {
                Button("Kaydı iptal et", role: .destructive) { recorder.cancel(); dismiss() }
                Button("Devam et", role: .cancel) {}
            } message: {
                Text("Çıkarsan bu rota kaydedilmeyecek.")
            }
            .interactiveDismissDisabled(recorder.hasStarted || isSaving)
            .onDisappear { recorder.cancel() }
            .onChange(of: recorder.route.count) { _, _ in updateRegion() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active && recorder.isRecording { recorder.pause() }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var mapCard: some View {
        ZStack(alignment: .topLeading) {
            Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
                if routeCoordinates.count >= 2 {
                    ForEach(routeSegments.indices, id: \.self) { index in
                        MapPolyline(coordinates: routeSegments[index]).stroke(TempoTheme.green, lineWidth: 5)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
            HStack(spacing: 8) {
                Circle().fill(recorder.isRecording ? TempoTheme.orange : TempoTheme.green).frame(width: 8, height: 8)
                Text((recorder.isRecording ? "KAYIT SÜRÜYOR" : (recorder.isReadyToSave ? "KAYIT HAZIR" : (recorder.hasStarted ? "KAYIT DURAKLATILDI" : "ROTA ÖNİZLEMESİ"))).tempoLocalized)
                    .font(.caption2.weight(.bold)).tracking(0.8)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule()).padding(12)
        }
        .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(.white.opacity(0.09)))
    }

    private var sportPicker: some View {
        HStack(spacing: 9) {
            sportButton("run", title: "Koşu", icon: "figure.run")
            sportButton("walking", title: "Yürüyüş", icon: "figure.walk")
        }
    }

    private func sportButton(_ id: String, title: String, icon: String) -> some View {
        Button { selectedSport = id } label: {
            Label(title.tempoLocalized, systemImage: icon)
                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 13)
                .foregroundStyle(selectedSport == id ? .black : .white.opacity(0.76))
                .background(selectedSport == id ? TempoTheme.green : TempoTheme.card, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(recorder.hasStarted || isSaving)
    }

    private var metrics: some View {
        HStack(spacing: 9) {
            trackerMetric(value: timeText, title: "Süre", icon: "timer")
            trackerMetric(value: TempoFormat.distance(recorder.distanceMeters / 1_000), title: "Mesafe", icon: "point.topleft.down.to.point.bottomright.curvepath")
            trackerMetric(value: "\(recorder.route.count)", title: "GPS noktası", icon: "location.fill")
        }
    }

    private func trackerMetric(value: String, title: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundStyle(TempoTheme.green)
            Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.75)
            Text(title.tempoLocalized).font(.caption2).foregroundStyle(TempoTheme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private var compactRatings: some View {
        VStack(alignment: .leading, spacing: 10) {
            ratingRow(title: "Zorluk", selection: $perceivedEffort)
            ratingRow(title: "Keyif", selection: $enjoyment)
        }
        .padding(14).background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private func ratingRow(title: String, selection: Binding<Int?>) -> some View {
        HStack {
            Text(title.tempoLocalized).font(.caption.weight(.semibold)).frame(width: 55, alignment: .leading)
            ForEach(1...5, id: \.self) { value in
                Button("\(value)") { selection.wrappedValue = selection.wrappedValue == value ? nil : value }
                    .font(.caption.bold()).frame(maxWidth: .infinity).padding(.vertical, 8)
                    .foregroundStyle(selection.wrappedValue == value ? .black : TempoTheme.secondary)
                    .background(selection.wrappedValue == value ? TempoTheme.green : TempoTheme.raised, in: Capsule())
                    .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var recorderControls: some View {
        if recorder.isRecording {
            HStack(spacing: 10) {
                Button { recorder.pause() } label: { Label("Duraklat", systemImage: "pause.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(TempoSecondaryButtonStyle())
                Button { recorder.finish() } label: { Label("Bitir", systemImage: "stop.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(TempoPrimaryButtonStyle())
            }
        } else if recorder.isReadyToSave {
            HStack(spacing: 10) {
                Button { recorder.start() } label: { Label("Sürdür", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(TempoSecondaryButtonStyle())
                Button { saveWorkout() } label: {
                    if isSaving { ProgressView().frame(maxWidth: .infinity) }
                    else { Label("Cihaza kaydet", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity) }
                }
                .buttonStyle(TempoPrimaryButtonStyle()).disabled(isSaving || !recorder.canSave)
            }
        } else {
            Button { recorder.start() } label: {
                Label((recorder.hasStarted ? "Sürdür" : "Kaydı başlat").tempoLocalized, systemImage: recorder.hasStarted ? "play.fill" : "location.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(TempoPrimaryButtonStyle())
            if !recorder.hasStarted {
                Button { recorder.startWithoutLocation() } label: {
                    Label("GPS olmadan süre kaydet", systemImage: "timer").frame(maxWidth: .infinity)
                }.buttonStyle(TempoSecondaryButtonStyle())
            }
        }
    }

    private var timeText: String {
        String(format: "%02d:%02d", recorder.elapsedSeconds / 60, recorder.elapsedSeconds % 60)
    }

    private func updateRegion() {
        guard !routeCoordinates.isEmpty else { return }
        let latitudes = routeCoordinates.map(\.latitude)
        let longitudes = routeCoordinates.map(\.longitude)
        cameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (latitudes.min()! + latitudes.max()!) / 2, longitude: (longitudes.min()! + longitudes.max()!) / 2),
            span: MKCoordinateSpan(latitudeDelta: max((latitudes.max()! - latitudes.min()!) * 1.6, 0.006), longitudeDelta: max((longitudes.max()! - longitudes.min()!) * 1.6, 0.006))
        ))
    }

    private func saveWorkout() {
        guard !isSaving, recorder.canSave, let startedAt = recorder.sessionStartedAt else { return }
        isSaving = true
        do {
            try model.addPhoneTrackedWorkout(
                sportId: selectedSport,
                sportTitle: sportTitle,
                startedAt: startedAt,
                durationSeconds: recorder.elapsedSeconds,
                distanceKm: recorder.distanceMeters / 1_000,
                routeCoordinates: recorder.coordinates,
                notes: notes,
                perceivedEffort: perceivedEffort,
                enjoyment: enjoyment
            )
            dismiss()
        } catch {
            isSaving = false
            recorder.report(error.localizedDescription.tempoLocalized)
        }
    }
}
