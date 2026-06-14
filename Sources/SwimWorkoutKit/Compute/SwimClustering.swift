// SPDX-License-Identifier: MIT

import Foundation

/// A swim as recorded by any source (Apple Watch, FORM goggles, manual…).
/// Neutral on purpose: HealthKit types stay in the app; clustering logic
/// stays testable here. Codable so the app can cache imports between runs.
public struct RecordedSwim: Sendable, Equatable, Identifiable, Codable {
    public var id: UUID
    public var start: Date
    public var end: Date
    /// Meters, when the source recorded distance.
    public var distanceMeters: Double?
    public var activeEnergyKcal: Double?
    public var sourceBundleID: String
    public var sourceName: String

    public init(
        id: UUID, start: Date, end: Date,
        distanceMeters: Double? = nil, activeEnergyKcal: Double? = nil,
        sourceBundleID: String, sourceName: String
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.distanceMeters = distanceMeters
        self.activeEnergyKcal = activeEnergyKcal
        self.sourceBundleID = sourceBundleID
        self.sourceName = sourceName
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// One real-world swim: every record of it, plus the chosen representative.
public struct SwimEvent: Sendable, Equatable, Identifiable {
    /// Stable across refreshes: derived from the member swim UUIDs.
    public var id: String
    public var swims: [RecordedSwim]
    public var representativeID: UUID
    /// Earliest member start — stored, not derived, so sorting events stays
    /// cheap over decade-sized histories.
    public var start: Date

    init(id: String, swims: [RecordedSwim], representativeID: UUID) {
        self.id = id
        self.swims = swims
        self.representativeID = representativeID
        self.start = swims.map { $0.start }.min() ?? .distantPast
    }

    public var representative: RecordedSwim {
        swims.first { $0.id == representativeID } ?? swims[0]
    }

    public var hasDuplicates: Bool { swims.count > 1 }
}

/// HealthKit does not deduplicate across sources: a Watch and FORM goggles
/// both wearing through one swim produce two full workouts. This clusters
/// them into events and picks one representative per event.
public enum SwimClustering {

    /// Two swims are the same event when their intervals overlap by more
    /// than half the shorter one, or they start within 10 minutes of each
    /// other and overlap at all.
    public static func belongTogether(_ a: RecordedSwim, _ b: RecordedSwim) -> Bool {
        let overlapStart = max(a.start, b.start)
        let overlapEnd = min(a.end, b.end)
        let overlap = overlapEnd.timeIntervalSince(overlapStart)
        guard overlap > 0 else { return false }
        let shorter = min(a.duration, b.duration)
        if shorter > 0, overlap / shorter > 0.5 { return true }
        return abs(a.start.timeIntervalSince(b.start)) < 600
    }

    /// Clusters swims into events.
    ///
    /// - Parameters:
    ///   - sourcePriority: bundle ids, most preferred first. Sources not
    ///     listed rank after listed ones.
    ///   - overrides: event id → swim id, the user's explicit picks.
    public static func events(
        from swims: [RecordedSwim],
        sourcePriority: [String],
        overrides: [String: UUID] = [:]
    ) -> [SwimEvent] {
        let sorted = swims.sorted { $0.start < $1.start }
        var clusters: [[RecordedSwim]] = []

        for swim in sorted {
            if var last = clusters.last, last.contains(where: { belongTogether($0, swim) }) {
                last.append(swim)
                clusters[clusters.count - 1] = last
            } else {
                clusters.append([swim])
            }
        }

        return clusters.map { members in
            let id = eventID(for: members)
            let representative = pickRepresentative(
                members, sourcePriority: sourcePriority, override: overrides[id]
            )
            return SwimEvent(id: id, swims: members, representativeID: representative)
        }
        .sorted { $0.start > $1.start }
    }

    /// Stable event identity: the lexicographically smallest member UUID.
    /// Adding a *new* source to an existing event can change the key only if
    /// the new UUID sorts first — the override is then simply re-asked.
    static func eventID(for swims: [RecordedSwim]) -> String {
        swims.map { $0.id.uuidString }.sorted().first ?? "empty"
    }

    static func pickRepresentative(
        _ swims: [RecordedSwim],
        sourcePriority: [String],
        override: UUID?
    ) -> UUID {
        if let override, swims.contains(where: { $0.id == override }) {
            return override
        }
        func rank(_ swim: RecordedSwim) -> (Int, Double, String) {
            let priorityIndex = sourcePriority.firstIndex(of: swim.sourceBundleID) ?? sourcePriority.count
            // Tie-break: richer record (longer distance) wins, then stable id.
            return (priorityIndex, -(swim.distanceMeters ?? 0), swim.id.uuidString)
        }
        return swims.min { rank($0) < rank($1) }?.id ?? swims[0].id
    }
}
