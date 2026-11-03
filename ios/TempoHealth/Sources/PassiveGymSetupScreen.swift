import CoreLocation
import SwiftUI
import UIKit

struct PassiveGymSetupScreen: View {
    @ObservedObject private var gym = TempoPassiveGym.shared
    @ObservedObject private var detector = TempoWorkoutDetection.shared
    @State private var name = ""
    @State private var routines: [Int: String] = [:]
    @State private var notice = ""
    private let weekdays = [2, 3, 4, 5, 6, 7, 1]
    private var coordinate: CLLocationCoordinate2D? {
        gym.location ?? gym.configuration.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }
    var body: some View {
        TempoPage {
            PageTitle(title: "passive.gym.title", subtitle: "passive.gym.subtitle")
            TempoCard {
                VStack(alignment: .leading, spacing: 18) {
                    TempoIconBadge(symbol: "mappin.and.ellipse", color: TempoTheme.green, size: 54)
                    Text("passive.gym.setupHint".tempoLocalized).font(.subheadline).foregroundStyle(TempoTheme.secondary)
                    TextField("passive.gym.name".tempoLocalized, text: $name).textFieldStyle(.roundedBorder)
                    Button { gym.useCurrentLocation() } label: {
                        Label(gym.locating ? "passive.gym.locating".tempoLocalized : "passive.gym.useHere".tempoLocalized, systemImage: "location.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(TempoSecondaryButtonStyle()).disabled(gym.locating)
                    if let coordinate {
                        Text("\(coordinate.latitude.formatted(.number.precision(.fractionLength(4)))), \(coordinate.longitude.formatted(.number.precision(.fractionLength(4))))")
                            .font(.caption.monospacedDigit()).foregroundStyle(TempoTheme.secondary)
                    }
                    Text("passive.gym.evidence".tempoLocalized).font(.footnote).foregroundStyle(TempoTheme.secondary)
                }
            }
            TempoDisclosureSection(title: "passive.gym.routine", icon: "calendar") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("passive.gym.routineHint".tempoLocalized).font(.footnote).foregroundStyle(TempoTheme.secondary)
                    ForEach(weekdays, id: \.self) { day in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(Calendar.current.weekdaySymbols[day - 1]).font(.caption.weight(.medium))
                            TextField("passive.gym.program".tempoLocalized, text: Binding(get: { routines[day] ?? "" }, set: { routines[day] = String($0.prefix(64)) }))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }
            TempoCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("passive.gym.privacy".tempoLocalized).font(.footnote).foregroundStyle(TempoTheme.secondary)
                    if gym.enabled {
                        Label((gym.authorization == .authorizedAlways && detector.enabled ? "passive.gym.enabled" : "passive.gym.needsAlways").tempoLocalized, systemImage: "location.circle")
                            .font(.subheadline.weight(.medium)).foregroundStyle(TempoTheme.green)
                    }
                    Button {
                        guard let coordinate else { return }
                        do {
                            try gym.save(PassiveGymConfiguration(name: name.trimmingCharacters(in: .whitespacesAndNewlines), latitude: coordinate.latitude, longitude: coordinate.longitude, routines: routines))
                            notice = "passive.gym.saved".tempoLocalized
                        } catch { notice = error.localizedDescription }
                    } label: { Text("passive.gym.save".tempoLocalized).frame(maxWidth: .infinity) }
                        .buttonStyle(TempoPrimaryButtonStyle()).disabled(coordinate == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 64)
                    if gym.enabled {
                        Button("passive.gym.disable".tempoLocalized, role: .destructive) { gym.disable() }.frame(minHeight: 44)
                    }
                    if gym.authorization != .authorizedAlways {
                        Button("permissions.settings".tempoLocalized) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }.frame(minHeight: 44)
                    }
                }
            }
            if !gym.message.isEmpty { Text(gym.message).font(.footnote).foregroundStyle(TempoTheme.orange) }
            if !notice.isEmpty { Text(notice).font(.footnote).foregroundStyle(TempoTheme.secondary) }
        }.navigationTitle("passive.gym.title".tempoLocalized).navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
            .onAppear { if let config = gym.configuration { name = config.name; routines = config.routines } }
    }
}
