import SwiftUI
import UIKit

struct WorkoutDetectionHomeCard: View {
    @ObservedObject private var detector = TempoWorkoutDetection.shared
    var body: some View {
        NavigationLink(destination: WorkoutDetectionScreen()) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.path").font(.title2.weight(.semibold))
                        .frame(width: 52, height: 52).background(TempoTheme.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("detection.title".tempoLocalized).font(.headline)
                        Text((detector.enabled ? "detection.enabled" : "detection.optional").tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.caption.bold())
                }
                Text((detector.pending.isEmpty ? "detection.homeHint" : "detection.pendingCount").tempoFormatted(detector.pending.count))
                    .font(.subheadline).foregroundStyle(TempoTheme.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Label("detection.phone".tempoLocalized, systemImage: "iphone")
                    Text("·")
                    Label("detection.watch".tempoLocalized, systemImage: "applewatch")
                    Spacer()
                    if detector.scanning { ProgressView().tint(TempoTheme.green) }
                    else if !detector.pending.isEmpty { Text(detector.pending.count.formatted()).font(.subheadline.bold()).padding(8).background(TempoTheme.green.opacity(0.14), in: Circle()) }
                }.font(.caption.weight(.medium))
            }.foregroundStyle(TempoTheme.green).padding(20)
                .background(LinearGradient(colors: [TempoTheme.card, TempoTheme.green.opacity(0.07)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
                .overlay(RoundedRectangle(cornerRadius: 26).stroke(TempoTheme.green.opacity(0.20), lineWidth: 1))
        }.buttonStyle(.plain).accessibilityIdentifier("activity.detection")
    }
}

struct WorkoutDetectionScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    @ObservedObject private var detector = TempoWorkoutDetection.shared
    @State private var selected: DetectedWorkout?
    @State private var enabling = false
    @State private var showDisableConfirmation = false
    var body: some View {
        TempoPage {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "waveform.path.ecg").font(.system(size: 36, weight: .light)).foregroundStyle(TempoTheme.green)
                Text("detection.introTitle".tempoLocalized).font(.largeTitle.bold())
                Text("detection.intro".tempoLocalized).font(.body).foregroundStyle(TempoTheme.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(.vertical, 12)
            TempoCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label((detector.enabled ? "detection.enabled" : "detection.optional").tempoLocalized, systemImage: detector.enabled ? "checkmark.circle.fill" : "pause.circle")
                            .font(.headline).foregroundStyle(TempoTheme.green)
                        Spacer()
                        if detector.scanning || enabling { ProgressView().tint(TempoTheme.green) }
                    }
                    if !detector.enabled {
                        Text("detection.consent".tempoLocalized).font(.subheadline).foregroundStyle(TempoTheme.secondary)
                        Button {
                            enabling = true
                            Task { await detector.enable(); enabling = false }
                        } label: { Text("detection.enable".tempoLocalized).frame(maxWidth: .infinity) }
                            .buttonStyle(TempoPrimaryButtonStyle()).disabled(enabling)
                    } else {
                        if let last = detector.lastScan {
                            Text("detection.lastChecked".tempoFormatted(last.formatted(date: .abbreviated, time: .shortened))).font(.caption).foregroundStyle(TempoTheme.secondary)
                        }
                        Button { Task { await detector.scan(force: true) } } label: {
                            Label("detection.scan".tempoLocalized, systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                        }.buttonStyle(TempoSecondaryButtonStyle()).disabled(detector.scanning)
                        Button("detection.notifications".tempoLocalized) { Task { await detector.requestNotifications() } }.font(.subheadline)
                    }
                    if !detector.message.isEmpty { Text(detector.message).font(.footnote).foregroundStyle(TempoTheme.orange).accessibilityIdentifier("detection.status") }
                }
            }
            if detector.enabled {
                Text("detection.review".tempoLocalized).font(.title3.bold())
                if detector.pending.isEmpty {
                    TempoCard {
                        VStack(spacing: 12) {
                            Image(systemName: "figure.walk.motion").font(.largeTitle).foregroundStyle(TempoTheme.green)
                            Text("detection.emptyTitle".tempoLocalized).font(.headline)
                            Text("detection.empty".tempoLocalized).font(.subheadline).foregroundStyle(TempoTheme.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(.vertical, 18)
                    }
                }
                ForEach(detector.pending) { candidate in
                    TempoCard {
                        VStack(alignment: .leading, spacing: 16) {
                            DetectedWorkoutEvidence(candidate: candidate)
                            Button { selected = candidate } label: {
                                Label("detection.reviewAction".tempoLocalized, systemImage: "checkmark.circle").frame(maxWidth: .infinity)
                            }.buttonStyle(TempoPrimaryButtonStyle())
                            Button("detection.dismiss".tempoLocalized) { detector.decide(candidate, accepted: false) }
                                .font(.subheadline).foregroundStyle(TempoTheme.secondary).frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                }
            }
            TempoDisclosureSection(title: "detection.how", icon: "info.circle") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("detection.phoneDetail".tempoLocalized)
                    Text("detection.healthDetail".tempoLocalized)
                    Text("detection.limits".tempoLocalized)
                    Text("detection.privacy".tempoLocalized)
                }.font(.footnote).foregroundStyle(TempoTheme.secondary)
            }
            if !model.healthSyncEnabled {
                NavigationLink(destination: HealthScreen()) {
                    Label("detection.connectHealth".tempoLocalized, systemImage: "heart.fill").frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(TempoSecondaryButtonStyle())
            }
            if detector.enabled {
                Button("detection.disable".tempoLocalized, role: .destructive) { showDisableConfirmation = true }.frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .navigationTitle("detection.title".tempoLocalized).navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
        .sheet(item: $selected) { candidate in DetectedWorkoutReview(candidate: candidate) }
        .confirmationDialog("detection.disable".tempoLocalized, isPresented: $showDisableConfirmation) {
            Button("detection.disable".tempoLocalized, role: .destructive) { detector.disable() }
            Button("Vazgeç".tempoLocalized, role: .cancel) { }
        } message: { Text("detection.disableDetail".tempoLocalized) }
        .task { await detector.scan() }
        .refreshable { await detector.scan(force: true) }
    }
}

private struct DetectedWorkoutEvidence: View {
    let candidate: DetectedWorkout
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: candidate.origin == .phone ? "figure.walk.motion" : "heart.text.square.fill")
                    .font(.title2).foregroundStyle(TempoTheme.green)
                    .frame(width: 48, height: 48).background(TempoTheme.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text("detection.possible".tempoLocalized).font(.headline)
                    Text(candidate.start.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(TempoTheme.secondary)
                }
            }
            TempoMetricGrid(columns: 2) {
                MetricCard(value: TempoFormat.duration(candidate.seconds), label: "Süre", icon: "clock", color: TempoTheme.blue)
                if let steps = candidate.steps, steps > 0 {
                    MetricCard(value: steps.formatted(), label: "detection.steps", icon: "shoeprints.fill", color: TempoTheme.green)
                }
                if let rate = candidate.averageHeartRate {
                    MetricCard(value: "\(Int(rate.rounded())) bpm", label: "detection.averageHR", icon: "heart.fill", color: .pink)
                }
                if let energy = candidate.activeEnergy {
                    MetricCard(value: "\(Int(energy.rounded())) kcal", label: "detection.energy", icon: "flame.fill", color: TempoTheme.orange)
                }
            }
            Text((candidate.origin == .phone ? "detection.phoneEvidence" : "detection.healthEvidence").tempoLocalized)
                .font(.caption).foregroundStyle(TempoTheme.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct DetectedWorkoutReview: View {
    let candidate: DetectedWorkout
    @EnvironmentObject private var model: TempoAppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var detector = TempoWorkoutDetection.shared
    @State private var sportID = ""
    @State private var error = ""
    @State private var saving = false
    @State private var sessionID: UUID?
    var body: some View {
        NavigationStack {
            TempoPage {
                TempoCard { DetectedWorkoutEvidence(candidate: candidate) }
                TempoCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("detection.whichSport".tempoLocalized).font(.headline)
                        Text("detection.confirmHint".tempoLocalized).font(.subheadline).foregroundStyle(TempoTheme.secondary)
                        Picker("detection.whichSport".tempoLocalized, selection: $sportID) {
                            Text("detection.chooseSport".tempoLocalized).tag("")
                            ForEach(TempoSportChoice.allCases) { sport in Text(sport.title).tag(sport.rawValue) }
                        }.pickerStyle(.menu).tint(TempoTheme.green)
                    }
                }
                if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(TempoTheme.orange) }
                Button {
                    guard sessionID == model.activitySessionID, !saving else { return }; saving = true; error = ""
                    Task {
                        await detector.scan(force: true)
                        do {
                            try model.addDetectedWorkout(candidate, sportID: sportID)
                            dismiss()
                        } catch { self.error = error.localizedDescription.tempoLocalized }
                        saving = false
                    }
                } label: {
                    HStack { if saving { ProgressView() }; Label("detection.confirm".tempoLocalized, systemImage: "checkmark") }.frame(maxWidth: .infinity)
                }.buttonStyle(TempoPrimaryButtonStyle()).disabled(sportID.isEmpty || saving || detector.scanning)
                Text("detection.recordNote".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
            }
            .navigationTitle("detection.reviewAction".tempoLocalized).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç".tempoLocalized) { dismiss() }.disabled(saving) } }
            .interactiveDismissDisabled(saving)
            .onAppear { sessionID = model.activitySessionID; if candidate.origin == .phone { sportID = candidate.suggestedSport } }
            .onChange(of: model.activitySessionID) { _, _ in dismiss() }
        }
    }
}

/// Telefonda sensör sinyali bulunmayan sabit egzersizler için geçmişe dönük elle giriş yerine canlı süre kaydı.
struct TempoLiveSessionScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var sportID = "fitness"
    @State private var startedAt: Date?
    @State private var runningSince: Date?
    @State private var completedSeconds = 0.0
    @State private var error = ""
    @State private var confirmDiscard = false
    @State private var saving = false
    @State private var sessionID: UUID?
    private func seconds(at date: Date) -> Double { completedSeconds + (runningSince.map { max(0, date.timeIntervalSince($0)) } ?? 0) }
    var body: some View {
        NavigationStack {
            TempoPage {
                TempoCard {
                    VStack(spacing: 24) {
                        Image(systemName: TempoSportChoice(rawValue: sportID)?.symbol ?? "timer").font(.system(size: 48, weight: .light)).foregroundStyle(TempoTheme.green)
                        Picker("detection.whichSport".tempoLocalized, selection: $sportID) { ForEach(TempoSportChoice.allCases) { Text($0.title).tag($0.rawValue) } }
                            .disabled(startedAt != nil)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(TempoFormat.duration(seconds(at: context.date))).font(.system(.largeTitle, design: .rounded).monospacedDigit()).contentTransition(.numericText())
                        }
                        Text("detection.timerHint".tempoLocalized).font(.subheadline).foregroundStyle(TempoTheme.secondary).multilineTextAlignment(.center)
                        Button {
                            if let runningSince { completedSeconds += Date().timeIntervalSince(runningSince); self.runningSince = nil }
                            else { if startedAt == nil { startedAt = Date() }; runningSince = Date() }
                        } label: {
                            Label((runningSince != nil ? "detection.pause" : "detection.start").tempoLocalized, systemImage: runningSince != nil ? "pause.fill" : "play.fill").frame(maxWidth: .infinity)
                        }.buttonStyle(TempoPrimaryButtonStyle()).disabled(saving)
                        if startedAt != nil {
                            Button("detection.finish".tempoLocalized) { save() }.buttonStyle(TempoSecondaryButtonStyle()).disabled(saving)
                        }
                    }.frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(TempoTheme.orange) }
            }.navigationTitle("detection.liveSession".tempoLocalized).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat".tempoLocalized) { if startedAt == nil { dismiss() } else { confirmDiscard = true } }.accessibilityIdentifier("activity.live.close") } }
                .interactiveDismissDisabled(startedAt != nil)
                .onAppear { sessionID = model.activitySessionID }
                .onChange(of: model.activitySessionID) { _, _ in dismiss() }
                .onChange(of: startedAt) { _, start in TempoWorkoutDetection.shared.setLiveRecording(start: start) }
                .onDisappear { TempoWorkoutDetection.shared.setLiveRecording(start: nil) }
                .confirmationDialog("detection.discardTitle".tempoLocalized, isPresented: $confirmDiscard) {
                    Button("detection.discard".tempoLocalized, role: .destructive) { dismiss() }
                    Button("Vazgeç".tempoLocalized, role: .cancel) { }
                }
        }.accessibilityIdentifier("activity.live.form")
    }
    private func save() {
        guard sessionID == model.activitySessionID, let startedAt, let sport = TempoSportChoice(rawValue: sportID), !saving else { return }
        let duration = seconds(at: Date())
        guard duration >= 60 else { error = "detection.tooShort".tempoLocalized; return }
        saving = true
        do {
            try model.addPhoneTrackedWorkout(sportId: sportID, sportTitle: sport.title, startedAt: startedAt, durationSeconds: Int(duration), distanceKm: 0, routeCoordinates: [])
            dismiss()
        } catch { self.error = error.localizedDescription.tempoLocalized; saving = false }
    }
}
