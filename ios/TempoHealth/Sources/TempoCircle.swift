import Combine
import CoreLocation
import Foundation
import HealthKit
import SwiftUI

struct CircleSnapshot: Decodable { let groups: [CircleGroup] }
struct CircleMember: Decodable, Identifiable { let id: String; let name: String; let accepted: Bool; let days: Int; let activity: String; let nudges: Bool }
struct CircleGhost: Decodable { let status: String; let expiresAt: Double }
struct CircleResult: Decodable { let id: String; let status: String; let leadPercent: Double? }
struct CircleGroup: Decodable, Identifiable {
    let id: String; let status: String; let startsAt: Double; let endsAt: Double; let finalizeAt: Double
    let goal: String; let target: Int; let stake: Int; let balance: Int; let locked: Int
    let myAccepted: Bool; let myGhosts: Bool; let myNudges: Bool
    let members: [CircleMember]; let ghost: CircleGhost?; let result: CircleResult?
    var editable: Bool { Date().timeIntervalSince1970 * 1000 < startsAt && !["void", "settled"].contains(status) }
}
struct CircleCommand: Encodable {
    var action: String; var consent: Bool? = nil; var ghosts: Bool? = nil
    var nudges: Bool? = nil; var recipient: String? = nil; var timeZone: String? = nil
}
struct CircleCreate: Encodable { let id: String; let friendIds: [String]; let goal: String; let target: Int; let stake: Int }
struct CirclePoint: Encodable { var value: Double?; var observedSeconds: Double }
struct CircleTrace: Encodable { let sport: String; let metric = "relativeEffort"; let points: [CirclePoint] }
struct CircleEvidence: Encodable {
    let id: String; let source: String; let manual = false; let start: Double; let end: Double
    let heartCoverage: Double; var trace: CircleTrace? = nil
}
struct CircleSync: Encodable { let sessions: [CircleEvidence]; let queryComplete: Bool; let venueComplete: Bool; var timeZone: String = TimeZone.current.identifier }
struct CircleEmpty: Encodable {}

@MainActor
final class TempoCircleStore: ObservableObject {
    static let shared = TempoCircleStore()
    @Published private(set) var groups: [CircleGroup] = []
    @Published private(set) var loading = false
    @Published private(set) var working = false
    @Published private(set) var message = ""
    private var owner: String?
    private var syncing = false
    private var lastSync: Date?
    func bind(_ next: String?) { if owner != next { owner = next; groups = []; message = ""; lastSync = nil } }
    func refresh(_ account: TempoAccountStore) async {
        let id = account.profile?.id; bind(id)
        guard id != nil, !loading else { return }; loading = true; defer { loading = false }
        do {
            let data = try await account.circleRequest(path: "/api/account/passive-social", method: "GET", body: Optional<CircleEmpty>.none)
            guard account.profile?.id == id, owner == id else { return }
            groups = try JSONDecoder().decode(CircleSnapshot.self, from: data).groups; message = ""
        } catch { if account.profile?.id == id { message = error.localizedDescription.tempoLocalized } }
    }
    func command(_ body: CircleCommand, group: CircleGroup, account: TempoAccountStore) async {
        guard !working else { return }; working = true; defer { working = false }
        let id = account.profile?.id
        do {
            _ = try await account.circleRequest(path: "/api/account/passive-social/groups/\(group.id)", method: "POST", body: body)
            guard account.profile?.id == id else { return }; lastSync = nil
            await refresh(account)
            if body.action == "nudge" { message = "circle.nudgeQueued".tempoLocalized }
        } catch { if account.profile?.id == id { message = error.localizedDescription.tempoLocalized } }
    }
    func create(friendIDs: [String], goal: String, account: TempoAccountStore) async -> Bool {
        guard !working else { return false }; working = true; defer { working = false }
        let id = account.profile?.id
        do {
            _ = try await account.circleRequest(path: "/api/account/passive-social/groups", method: "POST", body: CircleCreate(id: UUID().uuidString.lowercased(), friendIds: friendIDs, goal: goal, target: 3, stake: 20))
            guard account.profile?.id == id else { return false }; await refresh(account); return true
        } catch { if account.profile?.id == id { message = error.localizedDescription.tempoLocalized }; return false }
    }
    func sync(account: TempoAccountStore, model: TempoAppModel) async {
        let id = account.profile?.id; bind(id)
        guard id != nil, id == model.activityAccountID, account.isAuthenticated, !syncing else { return }
        if let lastSync, Date().timeIntervalSince(lastSync) < 120 { return }
        syncing = true; defer { syncing = false }
        await refresh(account)
        guard owner == id, groups.contains(where: \.myAccepted), !Task.isCancelled else { return }
        let ghostSharing = groups.contains { $0.myAccepted && $0.myGhosts }
        let now = Date()
        var evidence: [CircleEvidence] = []
        if model.healthSyncEnabled {
            for w in model.healthWorkouts.filter({ $0.sourceWasManuallyEntered == false && $0.startedAt > now.addingTimeInterval(-7 * 86400) }).prefix(16) {
                let end = w.sourceEndedAt ?? w.endedAt, seconds = end.timeIntervalSince(w.startedAt)
                guard (900...14400).contains(seconds), end <= now, let zone = w.sourceHeartRateZoneEvidence, zone.isValid, !zone.queryWasLimited else { continue }
                let coverage = min(1, zone.observedSeconds / seconds)
                guard coverage >= 0.7 else { continue }
                var record = CircleEvidence(id: w.id.uuidString.lowercased(), source: "healthkit", start: w.startedAt.timeIntervalSince1970 * 1000, end: end.timeIntervalSince1970 * 1000, heartCoverage: coverage)
                if ghostSharing { record.trace = await CircleEvidenceReader.trace(w, end: end, maximum: zone.maximumHeartRateBpm) }
                evidence.append(record)
                guard !Task.isCancelled, owner == id else { return }
            }
        }
        if groups.contains(where: { $0.myAccepted && $0.goal == "venueVisits" }) {
            for c in TempoWorkoutDetection.shared.candidates.filter({ $0.origin == .gym && $0.isValid && $0.end > now.addingTimeInterval(-7 * 86400) }).prefix(8) {
                evidence.append(CircleEvidence(id: c.id.uuidString.lowercased(), source: "corelocation", start: c.start.timeIntervalSince1970 * 1000, end: c.end.timeIntervalSince1970 * 1000, heartCoverage: 0))
            }
        }
        do {
            guard owner == id, account.profile?.id == id else { return }
            let queryComplete = model.healthSyncEnabled && model.healthWorkoutError == nil && model.healthWorkoutReadAt.map { now.timeIntervalSince($0) < 3600 } == true
            let gym = TempoPassiveGym.shared
            let venueComplete = gym.enabled && gym.authorization == .authorizedAlways && TempoWorkoutDetection.shared.enabled && TempoWorkoutDetection.shared.owner == id
            _ = try await account.circleRequest(path: "/api/account/passive-social/sync", method: "POST", body: CircleSync(sessions: evidence, queryComplete: queryComplete, venueComplete: venueComplete))
            guard owner == id else { return }; lastSync = Date(); await refresh(account)
        } catch { if owner == id { message = error.localizedDescription.tempoLocalized } }
    }
}

@MainActor private enum CircleEvidenceReader {
    static func trace(_ workout: TempoManualWorkout, end: Date, maximum: Double) async -> CircleTrace? {
        guard maximum.isFinite, maximum > 0 else { return nil }
        let store = HKHealthStore(), type = HKQuantityType(.heartRate)
        let gate = CircleReadGate(store: store)
        let samples: [HKQuantitySample] = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning: []); return }
                gate.continuation = continuation
                let query = HKSampleQuery(sampleType: type, predicate: HKQuery.predicateForSamples(withStart: workout.startedAt, end: end, options: .strictStartDate), limit: 5000, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, values, error in
                    let result = error == nil ? ((values as? [HKQuantitySample]) ?? []) : []
                    Task { @MainActor in gate.finish(result) }
                }
                gate.query = query; store.execute(query)
                gate.timeout = Task { [weak gate] in do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }; gate?.finish([]) }
            }
        } onCancel: { Task { @MainActor in gate.finish([]) } }
        guard !Task.isCancelled, samples.count >= 18, samples.count < 5000 else { return nil }
        let duration = end.timeIntervalSince(workout.startedAt), count = Int(ceil(duration / 60))
        guard (15...240).contains(count) else { return nil }
        var seconds = Array(repeating: 0.0, count: count), sums = seconds
        let unit = HKUnit.count().unitDivided(by: .minute())
        for index in samples.indices {
            let point = samples[index], bpm = point.quantity.doubleValue(for: unit)
            guard bpm.isFinite, (30...230).contains(bpm), (point.metadata?[HKMetadataKeyWasUserEntered] as? Bool) != true else { continue }
            let offset = max(0, point.startDate.timeIntervalSince(workout.startedAt))
            let next = index + 1 < samples.count ? samples[index + 1].startDate : min(end, point.startDate.addingTimeInterval(15))
            var remaining = max(0, min(30, min(end, next).timeIntervalSince(point.startDate))), cursor = offset
            while remaining > 0 {
                let bin = Int(cursor / 60); guard bin < count else { break }
                let span = min(remaining, Double(bin + 1) * 60 - cursor)
                guard span > 0 else { break }
                sums[bin] += min(100, max(0, bpm / maximum * 100)) * span; seconds[bin] += span
                cursor += span; remaining -= span
            }
        }
        let sport: String
        switch workout.sportId { case "run": sport = "running"; case "walking": sport = "walking"; default: sport = workout.sportId }
        return CircleTrace(sport: sport, points: seconds.indices.map { CirclePoint(value: seconds[$0] > 0 ? sums[$0] / seconds[$0] : nil, observedSeconds: min(60, seconds[$0])) })
    }
}

@MainActor private final class CircleReadGate {
    let store: HKHealthStore
    var continuation: CheckedContinuation<[HKQuantitySample], Never>?
    var query: HKQuery?
    var timeout: Task<Void, Never>?
    private var finished = false
    init(store: HKHealthStore) { self.store = store }
    func finish(_ values: [HKQuantitySample]) {
        guard !finished else { return }; finished = true
        if let query { store.stop(query) }; query = nil; timeout?.cancel(); timeout = nil
        let pending = continuation; continuation = nil; pending?.resume(returning: values)
    }
}

struct TempoCircleScreen: View {
    @EnvironmentObject private var account: TempoAccountStore
    @EnvironmentObject private var model: TempoAppModel
    @ObservedObject private var store = TempoCircleStore.shared
    @State private var friends: [TempoSocialProfile] = []
    @State private var selected: Set<String> = []
    @State private var showCreate = false
    @State private var goal = "sensorSessions"
    @State private var pendingAccept: CircleGroup?
    @State private var pendingWithdraw: CircleGroup?
    @State private var pendingLeave: CircleGroup?
    var body: some View {
        TempoPage {
            PageTitle(title: "circle.title", subtitle: "circle.subtitle")
            TempoCard { Text("circle.assurance".tempoLocalized).font(.footnote).foregroundStyle(TempoTheme.secondary).fixedSize(horizontal: false, vertical: true) }
            if !model.healthSyncEnabled { Button("circle.connectHealth".tempoLocalized) { model.connectAppleHealth() }.buttonStyle(TempoSecondaryButtonStyle()) }
            Button { showCreate = true } label: { Label("circle.create".tempoLocalized, systemImage: "person.3.fill").frame(maxWidth: .infinity) }.buttonStyle(TempoPrimaryButtonStyle())
            if store.loading && store.groups.isEmpty { ProgressView().frame(maxWidth: .infinity) }
            if !store.message.isEmpty { Text(store.message).font(.footnote).foregroundStyle(TempoTheme.orange).fixedSize(horizontal: false, vertical: true) }
            if !store.loading && store.groups.isEmpty { TempoCard { Label("circle.empty".tempoLocalized, systemImage: "circle.dotted").font(.subheadline).foregroundStyle(TempoTheme.secondary) } }
            ForEach(store.groups) { group in groupCard(group) }
        }.navigationTitle("circle.title".tempoLocalized).navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
            .refreshable { await store.refresh(account); await store.sync(account: account, model: model) }
            .task(id: account.profile?.id) { await store.refresh(account); friends = (try? await account.loadSocial().friends) ?? []; await store.sync(account: account, model: model) }
            .sheet(isPresented: $showCreate) { creator }
            .sheet(item: $pendingAccept) { group in acceptance(group) }
            .confirmationDialog("circle.withdraw".tempoLocalized, isPresented: Binding(get: { pendingWithdraw != nil }, set: { if !$0 { pendingWithdraw = nil } }), titleVisibility: .visible) {
                Button("circle.withdraw".tempoLocalized, role: .destructive) { if let g = pendingWithdraw { Task { await store.command(CircleCommand(action: "withdraw"), group: g, account: account); pendingWithdraw = nil } } }
            } message: { Text("circle.withdrawDetail".tempoLocalized) }
            .confirmationDialog("circle.leave".tempoLocalized, isPresented: Binding(get: { pendingLeave != nil }, set: { if !$0 { pendingLeave = nil } }), titleVisibility: .visible) {
                Button("circle.leave".tempoLocalized, role: .destructive) { if let g = pendingLeave { Task { await store.command(CircleCommand(action: "leave"), group: g, account: account); pendingLeave = nil } } }
            } message: { Text("circle.withdrawDetail".tempoLocalized) }
    }
    private func groupCard(_ g: CircleGroup) -> some View {
        TempoCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Label("circle.week".tempoLocalized, systemImage: "circle.hexagongrid.fill").font(.headline); Spacer(); Text("circle.status.\(g.status)".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary) }
                Text((g.goal == "venueVisits" ? "circle.venueGoal" : "circle.sensorGoal").tempoFormatted(g.target)).font(.title3.weight(.semibold))
                Text(Date(timeIntervalSince1970: g.startsAt / 1000).formatted(date: .abbreviated, time: .omitted) + " – " + Date(timeIntervalSince1970: g.endsAt / 1000).formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(TempoTheme.secondary)
                HStack { Label("circle.balance".tempoFormatted(g.balance), systemImage: "seal.fill"); Spacer(); Text("circle.locked".tempoFormatted(g.locked)) }.font(.caption.weight(.medium))
                ForEach(g.members) { m in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: m.activity == "active" ? "checkmark.circle.fill" : m.activity == "atRisk" ? "circle.lefthalf.filled" : "minus.circle")
                                .foregroundStyle(m.activity == "active" ? TempoTheme.green : TempoTheme.secondary)
                            VStack(alignment: .leading, spacing: 3) { Text(m.name).font(.subheadline.weight(.semibold)); Text((m.accepted ? "circle.activity.\(m.activity)" : "circle.invited").tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary) }
                            Spacer()
                            Text("\(m.days)/\(g.target)").font(.subheadline.monospacedDigit())
                            if m.id != account.profile?.id && m.activity == "atRisk" && g.myAccepted {
                                Button { Task { await store.command(CircleCommand(action: "nudge", recipient: m.id), group: g, account: account) } } label: { Image(systemName: "hand.wave.fill").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("circle.nudge".tempoLocalized).disabled(store.working || !m.nudges)
                            }
                        }
                        ProgressView(value: Double(min(m.days, g.target)), total: Double(g.target)).tint(TempoTheme.green).accessibilityLabel("\(m.name), \(m.days)/\(g.target)")
                    }
                }
                if let result = g.result {
                    Label("circle.ghostResult".tempoLocalized, systemImage: "flag.checkered").font(.subheadline.weight(.semibold))
                    Text(result.leadPercent.map { "circle.effortDifference".tempoFormatted($0) } ?? "circle.insufficient".tempoLocalized).font(.footnote).foregroundStyle(TempoTheme.secondary)
                } else if let ghost = g.ghost { Label("circle.ghostReady".tempoLocalized, systemImage: "figure.run.circle").font(.footnote).foregroundStyle(TempoTheme.green); Text(Date(timeIntervalSince1970: ghost.expiresAt / 1000), style: .relative).font(.caption).foregroundStyle(TempoTheme.secondary) }
                if !g.myAccepted && g.editable { Button("circle.accept".tempoLocalized) { pendingAccept = g }.buttonStyle(TempoPrimaryButtonStyle()) }
                if g.myAccepted {
                    Toggle("circle.ghostConsent".tempoLocalized, isOn: Binding(get: { g.myGhosts }, set: { value in Task { await store.command(CircleCommand(action: "preferences", ghosts: value, nudges: g.myNudges, timeZone: TimeZone.current.identifier), group: g, account: account) } })).disabled(store.working)
                    Toggle("circle.nudgeConsent".tempoLocalized, isOn: Binding(get: { g.myNudges }, set: { value in Task { await store.command(CircleCommand(action: "preferences", ghosts: g.myGhosts, nudges: value, timeZone: TimeZone.current.identifier), group: g, account: account) } })).disabled(store.working)
                    Button("circle.withdraw".tempoLocalized, role: .destructive) { pendingWithdraw = g }.font(.footnote).frame(minHeight: 44)
                }
                if ["settled", "void"].contains(g.status) { Button("circle.renew".tempoLocalized) { Task { await store.command(CircleCommand(action: "renew"), group: g, account: account) } }.buttonStyle(TempoSecondaryButtonStyle()).disabled(store.working) }
                Button("circle.leave".tempoLocalized, role: .destructive) { pendingLeave = g }.font(.footnote).frame(minHeight: 44).disabled(store.working)
            }
        }
    }
    private var creator: some View {
        NavigationStack { TempoPage {
            PageTitle(title: "circle.create", subtitle: "circle.createHint")
            Picker("circle.goal".tempoLocalized, selection: $goal) { Text("circle.sensorLabel".tempoLocalized).tag("sensorSessions"); Text("circle.venueLabel".tempoLocalized).tag("venueVisits") }.pickerStyle(.menu)
            ForEach(friends) { friend in Button { if selected.contains(friend.id) { selected.remove(friend.id) } else if selected.count < 5 { selected.insert(friend.id) } } label: { HStack { Text(friend.displayName); Spacer(); Image(systemName: selected.contains(friend.id) ? "checkmark.circle.fill" : "circle") }.frame(minHeight: 48) }.foregroundStyle(TempoTheme.primary) }
            if friends.count < 2 { Text("circle.membersRequired".tempoLocalized).font(.footnote).foregroundStyle(TempoTheme.secondary) }
            Button { Task { if await store.create(friendIDs: selected.sorted(), goal: goal, account: account) { showCreate = false; selected = [] } } } label: { Text("circle.create".tempoLocalized).frame(maxWidth: .infinity) }.buttonStyle(TempoPrimaryButtonStyle()).disabled(selected.count < 2 || store.working)
            if !store.message.isEmpty { Text(store.message).font(.footnote).foregroundStyle(TempoTheme.orange) }
        }.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç".tempoLocalized) { showCreate = false } } } }
    }
    private func acceptance(_ g: CircleGroup) -> some View {
        NavigationStack { TempoPage {
            PageTitle(title: "circle.accept", subtitle: "circle.consentTitle")
            TempoCard { Text("circle.consentDetail".tempoLocalized).font(.subheadline).fixedSize(horizontal: false, vertical: true) }
            Text("circle.stakeTerms".tempoFormatted(g.stake, g.target)).font(.headline)
            Button { Task { await store.command(CircleCommand(action: "accept", consent: true), group: g, account: account); if store.groups.first(where: { $0.id == g.id })?.myAccepted == true { pendingAccept = nil; await store.sync(account: account, model: model) } } } label: { Text("circle.acceptTerms".tempoLocalized).frame(maxWidth: .infinity) }.buttonStyle(TempoPrimaryButtonStyle()).disabled(store.working)
            if !store.message.isEmpty { Text(store.message).font(.footnote).foregroundStyle(TempoTheme.orange) }
        }.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç".tempoLocalized) { pendingAccept = nil } } } }
    }
}
