import SwiftUI
import Combine

enum TempoWellnessKind: String, CaseIterable, Codable, Identifiable {
    case breathing, relaxation, movement, evening
    var id: String { rawValue }
    var title: String { ("wellness." + rawValue).tempoLocalized }
    var subtitle: String { ("wellness." + rawValue + ".subtitle").tempoLocalized }
    var symbol: String {
        switch self { case .breathing: return "wind"; case .relaxation: return "sparkles"; case .movement: return "figure.flexibility"; case .evening: return "moon.stars.fill" }
    }
    var color: Color {
        switch self { case .breathing: return TempoTheme.blue; case .relaxation: return TempoTheme.purple; case .movement: return TempoTheme.green; case .evening: return TempoTheme.purple }
    }
    var minutes: [Int] {
        switch self { case .breathing: return [1, 3, 5]; case .relaxation: return [5]; case .movement: return [2]; case .evening: return [3] }
    }
    var defaultMinutes: Int { self == .breathing ? 3 : minutes[0] }
    var steps: [String] {
        switch self {
        case .breathing: return ["wellness.breatheIn", "wellness.breatheOut"]
        case .relaxation: return ["wellness.relax.1", "wellness.relax.2", "wellness.relax.3", "wellness.relax.4", "wellness.relax.5"]
        case .movement: return ["wellness.move.1", "wellness.move.2", "wellness.move.3", "wellness.move.4"]
        case .evening: return ["wellness.night.1", "wellness.night.2", "wellness.night.3"]
        }
    }
}

struct TempoWellnessCompletion: Codable, Identifiable {
    var id = UUID()
    let kind: TempoWellnessKind
    let seconds: Int
    let date: Date
}

struct TempoWellnessCheckIn: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let energy: Int
    let mood: Int
    let tiredness: Int
    func conflicts(with balance: TempoBalanceScore?) -> Bool {
        Calendar.autoupdatingCurrent.isDateInToday(date) && TempoTrainingGuidance.checkInMismatch(readiness: balance?.value, energy: energy, mood: mood, tiredness: tiredness)
    }
}

struct TempoWellnessWaterEntry: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let amount: Int
    let healthID: UUID?
}

private struct TempoWellnessData: Codable {
    var favorites: [TempoWellnessKind] = []
    var completions: [TempoWellnessCompletion] = []
    var checkIns: [TempoWellnessCheckIn] = []
    var water: [TempoWellnessWaterEntry] = []
    var waterGoal = 2_000
}

@MainActor
final class TempoWellnessStore: ObservableObject {
    static let didChange = Notification.Name("tempo.wellness.didChange")
    @Published private var data = TempoWellnessData()
    @Published private(set) var ownerID: String?
    @Published private(set) var storageError: String?
    private static func key(_ owner: String) -> String { "tempo.wellness.v1." + owner }
    var isReady: Bool { ownerID != nil && storageError == nil }
    var favorites: [TempoWellnessKind] { data.favorites }
    var completions: [TempoWellnessCompletion] { data.completions }
    var checkIns: [TempoWellnessCheckIn] { data.checkIns }
    var waterGoal: Int { data.waterGoal }
    var todayCheckIn: TempoWellnessCheckIn? { checkIns.first { Calendar.autoupdatingCurrent.isDateInToday($0.date) } }
    var todayWater: [TempoWellnessWaterEntry] { data.water.filter { Calendar.autoupdatingCurrent.isDateInToday($0.date) } }
    var localWaterTotal: Int { todayWater.filter { $0.healthID == nil }.reduce(0) { $0 + $1.amount } }

    func bind(_ owner: String?) {
        data = TempoWellnessData(); storageError = nil; ownerID = owner
        guard let owner, let stored = UserDefaults.standard.data(forKey: Self.key(owner)) else { return }
        do {
            let restored = try JSONDecoder().decode(TempoWellnessData.self, from: stored)
            guard (250...6_000).contains(restored.waterGoal) else { throw CocoaError(.coderReadCorrupt) }
            data = restored
        } catch { storageError = "wellness.storageError".tempoLocalized }
    }

    func reload() { bind(ownerID) }

    static func removeData(for owner: String) { UserDefaults.standard.removeObject(forKey: key(owner)) }

    private func update(_ change: (inout TempoWellnessData) -> Void) {
        guard isReady, let ownerID else { return }
        var next = data; change(&next)
        guard let encoded = try? JSONEncoder().encode(next) else { return }
        UserDefaults.standard.set(encoded, forKey: Self.key(ownerID)); data = next
        NotificationCenter.default.post(name: Self.didChange, object: ownerID)
    }

    func toggleFavorite(_ kind: TempoWellnessKind) {
        update { if $0.favorites.contains(kind) { $0.favorites.removeAll { $0 == kind } } else { $0.favorites.append(kind) } }
    }
    func complete(_ kind: TempoWellnessKind, seconds: Int, owner: String) {
        guard ownerID == owner, seconds >= 60, seconds <= 300 else { return }
        update { $0.completions.insert(TempoWellnessCompletion(kind: kind, seconds: seconds, date: Date()), at: 0); $0.completions = Array($0.completions.prefix(100)) }
    }
    func saveCheckIn(energy: Int, mood: Int, tiredness: Int) {
        guard [energy, mood, tiredness].allSatisfy({ (1...5).contains($0) }) else { return }
        update {
            $0.checkIns.removeAll { Calendar.autoupdatingCurrent.isDateInToday($0.date) }
            $0.checkIns.insert(TempoWellnessCheckIn(date: Date(), energy: energy, mood: mood, tiredness: tiredness), at: 0)
            $0.checkIns = Array($0.checkIns.prefix(90))
        }
    }
    func setWaterGoal(_ value: Int) { guard (250...6_000).contains(value) else { return }; update { $0.waterGoal = value } }
    func addWater(_ amount: Int, healthID: UUID?, owner: String) {
        guard ownerID == owner, (1...2_000).contains(amount) else { return }
        update { $0.water.insert(TempoWellnessWaterEntry(date: Date(), amount: amount, healthID: healthID), at: 0); $0.water = Array($0.water.prefix(300)) }
    }
    func removeWater(_ entry: TempoWellnessWaterEntry, owner: String) {
        guard ownerID == owner else { return }; update { $0.water.removeAll { $0.id == entry.id } }
    }
}

struct TempoCheckInComparison: View {
    let entry: TempoWellnessCheckIn
    let balance: TempoBalanceScore?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("wellness.checkIn".tempoLocalized, systemImage: "person.crop.circle.badge.checkmark").font(.subheadline.weight(.medium))
            Text("wellness.checkIn.summary".tempoFormatted(entry.energy, entry.mood, entry.tiredness)).font(.caption).foregroundStyle(TempoTheme.secondary)
            if entry.conflicts(with: balance) {
                Label("progress.checkInWarning".tempoLocalized, systemImage: "info.circle.fill")
                    .font(.subheadline).foregroundStyle(TempoTheme.orange).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TempoWellnessTools: View {
    @ObservedObject var store: TempoWellnessStore
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "wellness.tools", caption: "wellness.offline", padding: false)
            if let error = store.storageError { Text(error).font(.footnote).foregroundStyle(TempoTheme.orange) }
            if !store.favorites.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(store.favorites) { kind in
                            NavigationLink(destination: TempoWellnessSessionScreen(kind: kind, store: store, autoStart: true)) {
                                Label(kind.title, systemImage: kind.symbol).font(.subheadline.weight(.semibold))
                                    .padding(12).background(kind.color.opacity(0.10), in: Capsule())
                            }.buttonStyle(.plain).foregroundStyle(kind.color)
                        }
                    }
                }.accessibilityLabel("wellness.favorites".tempoLocalized)
            }
            VStack(spacing: 10) {
                ForEach(TempoWellnessKind.allCases) { kind in
                    HStack(spacing: 4) {
                        NavigationLink(destination: TempoWellnessSessionScreen(kind: kind, store: store)) {
                            HStack(spacing: 12) {
                                Image(systemName: kind.symbol).font(.title3).foregroundStyle(kind.color)
                                    .frame(width: 44, height: 44).background(kind.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(kind.title).font(.subheadline.weight(.semibold)).foregroundStyle(TempoTheme.primary)
                                    Text(kind.subtitle).font(.caption).foregroundStyle(TempoTheme.secondary).fixedSize(horizontal: false, vertical: true)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(kind.color)
                            }.padding(14).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("wellness.tool.\(kind.rawValue)")
                        Button { store.toggleFavorite(kind) } label: {
                            Image(systemName: store.favorites.contains(kind) ? "star.fill" : "star").foregroundStyle(kind.color).frame(width: 44, height: 48)
                        }.buttonStyle(.plain).disabled(!store.isReady)
                            .accessibilityLabel((store.favorites.contains(kind) ? "wellness.unfavorite" : "wellness.favorite").tempoLocalized)
                    }.padding(.trailing, 6).background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 22))
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(kind.color.opacity(0.12), lineWidth: 1))
                }
            }
            NavigationLink(destination: TempoWellnessCheckInScreen(store: store)) {
                Label("wellness.checkIn".tempoLocalized, systemImage: "face.smiling").frame(maxWidth: .infinity)
            }.buttonStyle(TempoSecondaryButtonStyle())
            if !store.completions.isEmpty {
                TempoDisclosureSection(title: "wellness.history", icon: "clock.arrow.circlepath") {
                    VStack(spacing: 14) {
                        ForEach(store.completions.prefix(7)) { session in
                            HStack {
                                Label(session.kind.title, systemImage: session.kind.symbol).font(.subheadline)
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(TempoFormat.duration(Double(session.seconds))).font(.caption.monospacedDigit())
                                    Text(session.date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(TempoTheme.secondary)
                                }
                            }
                        }
                    }
                }
            }
            Text("wellness.localNote".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct TempoWellnessSessionScreen: View {
    let kind: TempoWellnessKind
    @ObservedObject var store: TempoWellnessStore
    var autoStart = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = 0
    @State private var accumulated: TimeInterval = 0
    @State private var startedAt: Date?
    @State private var now = Date()
    @State private var completed = false
    @State private var hasStarted = false
    @State private var haptics = false
    @State private var hapticTick = 0
    @State private var owner = ""
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    private var total: Int { max(1, minutes == 0 ? kind.defaultMinutes : minutes) * 60 }
    private var elapsed: TimeInterval { min(Double(total), max(0, accumulated + (startedAt.map { now.timeIntervalSince($0) } ?? 0))) }
    private var stepIndex: Int { kind == .breathing ? Int(elapsed / 4) % 2 : min(kind.steps.count - 1, Int(elapsed / Double(total) * Double(kind.steps.count))) }
    private var phase: String { kind.steps[stepIndex].tempoLocalized }
    private var phaseSymbol: String {
        if completed { return "checkmark" }
        if kind == .movement { return ["figure.cooldown", "hand.wave.fill", "figure.walk", "figure.mind.and.body"][stepIndex] }
        return kind.symbol
    }
    private var breatheScale: CGFloat { reduceMotion || kind != .breathing || !hasStarted ? 1 : (stepIndex == 0 ? 1.12 : 0.88) }

    var body: some View {
        TempoPage {
            PageTitle(title: kind.title, subtitle: kind.subtitle)
            TempoCard {
                VStack(spacing: 24) {
                    if !hasStarted, kind.minutes.count > 1 {
                        Picker("wellness.duration".tempoLocalized, selection: $minutes) {
                            ForEach(kind.minutes, id: \.self) { Text("wellness.minutes".tempoFormatted($0)).tag($0) }
                        }.pickerStyle(.segmented)
                    }
                    ZStack {
                        Circle().fill(kind.color.opacity(0.08)).scaleEffect(breatheScale)
                        Circle().stroke(kind.color.opacity(0.15), lineWidth: 10)
                        Circle().trim(from: 0, to: CGFloat(elapsed / Double(total)))
                            .stroke(kind.color, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90))
                        VStack(spacing: 14) {
                            Image(systemName: phaseSymbol).font(.system(size: 34, weight: .light)).foregroundStyle(kind.color)
                                .contentTransition(.opacity)
                            Text(String(format: "%02d:%02d", max(0, total - Int(elapsed)) / 60, max(0, total - Int(elapsed)) % 60))
                                .font(.system(size: 38, weight: .medium, design: .rounded).monospacedDigit())
                        }
                    }.frame(width: 218, height: 218).padding(.vertical, 16)
                        .animation(reduceMotion || startedAt == nil ? nil : .easeInOut(duration: 3.5), value: breatheScale)
                        .accessibilityElement(children: .ignore).accessibilityLabel(kind.title).accessibilityValue(TempoFormat.duration(Double(max(0, total - Int(elapsed)))))
                    Text(completed ? "wellness.completed".tempoLocalized : (hasStarted ? phase : "wellness.ready".tempoLocalized))
                        .font(.title3.weight(.medium)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 70)
                    if !completed {
                        Button {
                            if startedAt != nil { pause() }
                            else { now = Date(); startedAt = now; hasStarted = true }
                        } label: {
                            Label((startedAt != nil ? "wellness.pause" : (hasStarted ? "wellness.resume" : "wellness.start")).tempoLocalized, systemImage: startedAt != nil ? "pause.fill" : "play.fill").frame(maxWidth: .infinity)
                        }.buttonStyle(TempoPrimaryButtonStyle()).disabled(!store.isReady)
                        Toggle("wellness.haptics".tempoLocalized, isOn: $haptics).tint(kind.color).font(.subheadline)
                    } else {
                        Button("Bitti") { dismiss() }.buttonStyle(TempoPrimaryButtonStyle())
                    }
                }.padding(.vertical, 8)
            }
            Text("wellness.sessionNote".tempoLocalized).font(.footnote).foregroundStyle(TempoTheme.secondary).fixedSize(horizontal: false, vertical: true)
        }.navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
            .sensoryFeedback(.selection, trigger: hapticTick)
            .onAppear {
                if minutes == 0 { minutes = kind.defaultMinutes }
                if owner.isEmpty { owner = store.ownerID ?? "" }
                if autoStart, !hasStarted, store.isReady { now = Date(); startedAt = now; hasStarted = true }
            }
            .onReceive(timer) { date in
                guard startedAt != nil, !completed else { return }
                now = date
                if elapsed >= Double(total) {
                    accumulated = Double(total); startedAt = nil; completed = true
                    store.complete(kind, seconds: total, owner: owner)
                }
            }
            .onChange(of: stepIndex) { _, _ in if haptics, startedAt != nil { hapticTick += 1 } }
            .onChange(of: scenePhase) { _, value in if value != .active { pause() } }
            .onChange(of: store.ownerID) { _, value in
                if owner.isEmpty { owner = value ?? "" }
                else if value != owner { pause(); dismiss() }
            }
            .onDisappear { pause() }
    }
    private func pause() {
        guard let start = startedAt else { return }
        accumulated = min(Double(total), accumulated + max(0, Date().timeIntervalSince(start)))
        startedAt = nil; now = Date()
    }
}

struct TempoWellnessCheckInScreen: View {
    @ObservedObject var store: TempoWellnessStore
    @State private var energy = 3
    @State private var mood = 3
    @State private var tiredness = 3
    @State private var saved = false
    var body: some View {
        TempoPage {
            PageTitle(title: "wellness.checkIn", subtitle: "wellness.checkIn.subtitle")
            TempoCard {
                VStack(alignment: .leading, spacing: 24) {
                    rating("wellness.energy", value: $energy)
                    rating("wellness.mood", value: $mood)
                    rating("wellness.tiredness", value: $tiredness)
                    Text("wellness.ratingHelp".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
                    Button { store.saveCheckIn(energy: energy, mood: mood, tiredness: tiredness); saved = true } label: {
                        Label((saved ? "wellness.saved" : "wellness.saveCheckIn").tempoLocalized, systemImage: saved ? "checkmark.circle" : "square.and.pencil").frame(maxWidth: .infinity)
                    }.buttonStyle(TempoPrimaryButtonStyle()).disabled(!store.isReady)
                }
            }
            if !store.checkIns.isEmpty {
                SectionHeading(title: "wellness.checkIn.history", caption: "wellness.checkIn.recent", padding: false)
                ForEach(store.checkIns.prefix(7)) { entry in
                    TempoCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.date.formatted(date: .abbreviated, time: .omitted)).font(.subheadline.weight(.semibold))
                            Text("wellness.checkIn.summary".tempoFormatted(entry.energy, entry.mood, entry.tiredness)).font(.caption).foregroundStyle(TempoTheme.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Text("wellness.checkIn.note".tempoLocalized).font(.footnote).foregroundStyle(TempoTheme.secondary)
        }.navigationTitle("wellness.checkIn".tempoLocalized).navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
            .onAppear { if let entry = store.todayCheckIn { energy = entry.energy; mood = entry.mood; tiredness = entry.tiredness } }
    }
    private func rating(_ key: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(key.tempoLocalized).font(.headline)
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { number in
                    Button { value.wrappedValue = number; saved = false } label: {
                        Text(number.formatted()).font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(value.wrappedValue == number ? TempoTheme.onAccent : TempoTheme.primary)
                            .background(value.wrappedValue == number ? TempoTheme.green : TempoTheme.raised, in: RoundedRectangle(cornerRadius: 13))
                    }.buttonStyle(.plain).accessibilityLabel("\(key.tempoLocalized), \(number)/5")
                        .accessibilityAddTraits(value.wrappedValue == number ? .isSelected : [])
                }
            }
        }
    }
}

struct TempoWellnessWaterCard: View {
    @EnvironmentObject private var model: TempoAppModel
    @ObservedObject var store: TempoWellnessStore
    @State private var amount = 250
    @State private var working = false
    @State private var error = ""
    var total: Int { (model.healthSyncEnabled ? model.todayWaterMl : 0) + store.localWaterTotal }
    var body: some View {
        TempoCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("wellness.water".tempoLocalized, systemImage: "drop.fill").font(.headline).foregroundStyle(TempoTheme.blue)
                    Spacer()
                    Text("\(total.formatted()) / \(store.waterGoal.formatted()) ml").font(.subheadline.monospacedDigit())
                }
                ProgressView(value: min(Double(total) / Double(max(1, store.waterGoal)), 1)).tint(TempoTheme.blue)
                HStack(spacing: 8) {
                    ForEach([200, 250, 500], id: \.self) { value in
                        Button { Task { await add(value) } } label: { Text("+\(value) ml").frame(maxWidth: .infinity, minHeight: 48) }
                            .buttonStyle(TempoSecondaryButtonStyle()).disabled(working || !store.isReady || model.isBusy)
                    }
                }
                DisclosureGroup("wellness.water.options".tempoLocalized) {
                    VStack(alignment: .leading, spacing: 14) {
                        Stepper("wellness.water.amount".tempoFormatted(amount), value: $amount, in: 50...2_000, step: 50)
                        Button { Task { await add(amount) } } label: { Text("wellness.water.add".tempoLocalized).frame(maxWidth: .infinity) }
                            .buttonStyle(TempoPrimaryButtonStyle()).disabled(working || !store.isReady || model.isBusy)
                        Stepper("wellness.water.goal".tempoFormatted(store.waterGoal), value: Binding(get: { store.waterGoal }, set: { store.setWaterGoal($0) }), in: 250...6_000, step: 250)
                            .disabled(!store.isReady)
                    }.padding(.top, 14)
                }.font(.subheadline).tint(TempoTheme.blue)
                if let entry = store.todayWater.first {
                    Button { Task { await undo(entry) } } label: {
                        Label("wellness.water.undo".tempoFormatted(entry.amount), systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.buttonStyle(.plain).font(.subheadline).foregroundStyle(TempoTheme.blue).disabled(working || !store.isReady)
                }
                if working { ProgressView().tint(TempoTheme.blue) }
                if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(TempoTheme.orange) }
                Text((model.healthSyncEnabled ? "wellness.water.healthNote" : "wellness.water.localNote").tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
            }
        }
    }
    private func add(_ value: Int) async {
        guard !working, store.isReady, let owner = store.ownerID else { return }
        working = true; error = ""; defer { working = false }
        do {
            let healthID: UUID?
            if model.healthSyncEnabled { healthID = try await model.saveWellnessWater(value, for: owner) }
            else { healthID = nil }
            guard store.ownerID == owner else { return }
            store.addWater(value, healthID: healthID, owner: owner)
        } catch { if store.ownerID == owner, !(error is CancellationError) { self.error = error.localizedDescription.tempoLocalized } }
    }
    private func undo(_ entry: TempoWellnessWaterEntry) async {
        guard !working, store.isReady, let owner = store.ownerID else { return }
        working = true; error = ""; defer { working = false }
        do {
            if let healthID = entry.healthID { try await model.undoWellnessWater(healthID, for: owner) }
            guard store.ownerID == owner else { return }
            store.removeWater(entry, owner: owner)
        } catch { if store.ownerID == owner, !(error is CancellationError) { self.error = error.localizedDescription.tempoLocalized } }
    }
}
