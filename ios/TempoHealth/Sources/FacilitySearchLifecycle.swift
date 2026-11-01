import Foundation

/// İsteklerin yaşam döngüsü veriden ayrıdır: eski/geç callback yeni aramayı değiştiremez.
struct FacilitySearchLifecycle: Sendable {
    enum Provider: Hashable, Sendable { case appleMaps, openStreetMap }
    enum Outcome: Equatable, Sendable { case results, partialResults, empty, partialEmpty, unavailable }
    private(set) var generation = 0
    private(set) var active = false
    private(set) var pending: Set<Provider> = []
    private(set) var successful: Set<Provider> = []
    private(set) var hasResults = false
    var blocking: Bool { active && !hasResults }
    var complete: Bool { pending.isEmpty }

    mutating func begin(generation: Int) {
        self.generation = generation; active = true
        pending = [.appleMaps, .openStreetMap]; successful = []; hasResults = false
    }
    mutating func showResults(generation: Int) -> Bool {
        guard active, self.generation == generation else { return false }
        hasResults = true
        return true
    }
    mutating func receive(_ provider: Provider, succeeded: Bool, hasResults: Bool, generation: Int) -> Bool {
        guard active, self.generation == generation, pending.remove(provider) != nil else { return false }
        if succeeded { successful.insert(provider) }
        self.hasResults = self.hasResults || hasResults
        return true
    }
    mutating func finish(generation: Int) -> Outcome? {
        guard active, self.generation == generation else { return nil }
        active = false
        let allSucceeded = successful.count == 2
        pending = []
        if hasResults { return allSucceeded ? .results : .partialResults }
        if allSucceeded { return .empty }
        return successful.isEmpty ? .unavailable : .partialEmpty
    }
    mutating func cancel() { active = false; pending = [] }
}
