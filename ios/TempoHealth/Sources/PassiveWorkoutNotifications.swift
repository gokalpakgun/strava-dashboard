import Foundation
import UserNotifications

enum PassiveWorkoutNotifications {
    static let workoutCategory = "tempo.passive.workout.v1"
    static let gymCategory = "tempo.passive.gym.v1"
    static let approve = "tempo.passive.approve"
    static let reject = "tempo.passive.reject"
    static let effort = "tempo.passive.rpe"

    static func register() {
        let yes = UNNotificationAction(identifier: approve, title: "passive.confirm".tempoLocalized, options: [.foreground, .authenticationRequired])
        let no = UNNotificationAction(identifier: reject, title: "passive.no".tempoLocalized, options: [.authenticationRequired])
        let rpe = UNTextInputNotificationAction(identifier: effort, title: "passive.rpe".tempoLocalized, options: [.foreground, .authenticationRequired], textInputButtonTitle: "passive.confirm".tempoLocalized, textInputPlaceholder: "1–10")
        let center = UNUserNotificationCenter.current()
        center.getNotificationCategories { existing in
            let retained = existing.filter { $0.identifier != workoutCategory && $0.identifier != gymCategory }
            center.setNotificationCategories(Set(retained).union([
                UNNotificationCategory(identifier: workoutCategory, actions: [yes, rpe, no], intentIdentifiers: [], options: []),
                UNNotificationCategory(identifier: gymCategory, actions: [yes, no], intentIdentifiers: [], options: [])
            ]))
        }
    }
    static func body(for candidate: DetectedWorkout) -> String {
        let minutes = Int(max(0, min(14_400, candidate.seconds)) / 60)
        if candidate.origin == .gym {
            return "passive.gym.notification".tempoFormatted(minutes, candidate.routineName ?? "passive.gym.session".tempoLocalized)
        }
        let type: String
        if candidate.healthWorkoutID != nil { type = candidate.primarySportIsKnown == false ? "passive.workout".tempoLocalized : (TempoSportChoice(rawValue: candidate.suggestedSport)?.title ?? "passive.workout".tempoLocalized) }
        else { type = patternTitle(candidate.loadEstimate?.pattern) }
        let load = candidate.loadEstimate?.strain.map { "\($0)/10" } ?? "passive.loadMissing".tempoLocalized
        return "passive.workout.notification".tempoFormatted(minutes, type, load)
    }
    static func patternTitle(_ pattern: PassiveActivityPattern?) -> String {
        switch pattern {
        case .intervals: "passive.pattern.intervals".tempoLocalized
        case .sustained: "passive.pattern.sustained".tempoLocalized
        case .mixed: "passive.pattern.mixed".tempoLocalized
        default: "passive.pattern.insufficient".tempoLocalized
        }
    }
    @MainActor static func handle(_ response: UNNotificationResponse, info: [String: String]?) -> Bool {
        guard [approve, reject, effort].contains(response.actionIdentifier) else { return false }
        guard [workoutCategory, gymCategory].contains(response.notification.request.content.categoryIdentifier), info?["destination"] == "detection" else { return true }
        let detector = TempoWorkoutDetection.shared
        guard let owner = info?["owner"], owner == detector.owner,
              let raw = info?["candidate"], let id = UUID(uuidString: raw),
              let candidate = detector.pending.first(where: { $0.id == id }) else { return true }
        if response.actionIdentifier == reject { detector.decide(candidate, accepted: false); return true }
        let rpe: Int?
        if response.actionIdentifier == effort {
            guard let text = response as? UNTextInputNotificationResponse, let value = PassiveWorkoutEngine.rpe(from: text.userText) else {
                detector.reportResponseError(); TempoNotifications.shared.open(destination: "detection"); return true
            }
            rpe = value
        } else { rpe = nil }
        detector.queueResponse(id: id, owner: owner, rpe: rpe)
        TempoNotifications.shared.open(destination: "detection")
        return true
    }
}
