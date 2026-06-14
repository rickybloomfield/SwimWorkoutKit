// SPDX-License-Identifier: MIT

import Foundation

/// Distance/duration totals for one speed group.
public struct GroupTotals: Sendable, Equatable {
    public var groupID: String?
    public var distance: Int
    /// Estimated seconds. Present only when every timed component could be estimated.
    public var durationSeconds: Int?
    /// True when `durationSeconds` covers every item (no unknown components).
    public var durationIsComplete: Bool

    public init(groupID: String?, distance: Int, durationSeconds: Int?, durationIsComplete: Bool) {
        self.groupID = groupID
        self.distance = distance
        self.durationSeconds = durationSeconds
        self.durationIsComplete = durationIsComplete
    }
}

/// Pure functions over the model: per-group distances and duration estimates.
public enum WorkoutCalculator {

    // MARK: - Group resolution

    /// Resolves a sparse send-off map for `groupID` given the workout's group order:
    /// exact match, else nearest *faster* (earlier-listed) specified group, else nearest slower.
    public static func resolveSendoff(
        _ sendoffs: [String: SwimTime]?,
        groupID: String?,
        groups: [SpeedGroup]
    ) -> SwimTime? {
        guard let sendoffs, !sendoffs.isEmpty else { return nil }
        // Single-group workouts / unspecified group: take the only or first-listed value.
        guard let groupID else {
            if sendoffs.count == 1 { return sendoffs.values.first }
            for group in groups {
                if let time = sendoffs[group.id] { return time }
            }
            return sendoffs.values.first
        }
        if let exact = sendoffs[groupID] { return exact }
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else {
            return nil
        }
        // Walk toward faster groups, then slower.
        for i in stride(from: index - 1, through: 0, by: -1) {
            if let time = sendoffs[groups[i].id] { return time }
        }
        for i in (index + 1)..<groups.count {
            if let time = sendoffs[groups[i].id] { return time }
        }
        return nil
    }

    // MARK: - Distance

    public static func distance(of workout: Workout, group groupID: String? = nil) -> Int {
        workout.sections.reduce(0) { $0 + distance(of: $1, group: groupID, groups: workout.groups) }
    }

    public static func distance(of section: WorkoutSection, group groupID: String?, groups: [SpeedGroup]) -> Int {
        section.items.reduce(0) { $0 + distance(of: $1, group: groupID, groups: groups) }
    }

    public static func distance(of item: WorkoutItem, group groupID: String?, groups: [SpeedGroup]) -> Int {
        switch item {
        case .set(let set):
            guard appliesToGroup(set.groupFilter, groupID: groupID) else { return 0 }
            let override = groupID.flatMap { set.perGroup?[$0] }
            let reps = override?.reps ?? set.reps
            let distance = override?.distance ?? set.distance
            return reps * distance
        case .repeatBlock(let block):
            let rounds = roundCount(of: block, group: groupID, groups: groups)
            let inner = block.items.reduce(0) { $0 + distance(of: $1, group: groupID, groups: groups) }
            return rounds * inner
        case .rest, .note:
            return 0
        }
    }

    /// Round count for a group. Sparse `roundsPerGroup` maps resolve like
    /// send-offs: nearest faster (earlier-listed) specified group, then slower.
    public static func roundCount(of block: RepeatBlock, group groupID: String?, groups: [SpeedGroup]) -> Int {
        guard let perGroup = block.roundsPerGroup, !perGroup.isEmpty else {
            return block.rounds
        }
        guard let groupID else { return block.rounds }
        if let exact = perGroup[groupID] { return exact }
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else {
            return block.rounds
        }
        for i in stride(from: index - 1, through: 0, by: -1) {
            if let count = perGroup[groups[i].id] { return count }
        }
        for i in (index + 1)..<groups.count {
            if let count = perGroup[groups[i].id] { return count }
        }
        return block.rounds
    }

    public static func appliesToGroup(_ filter: [String]?, groupID: String?) -> Bool {
        guard let filter, !filter.isEmpty else { return true }
        guard let groupID else { return true }
        return filter.contains(groupID)
    }

    // MARK: - Duration

    /// Estimated duration in seconds for one group. `complete` is false when any
    /// component could not be estimated (its time contribution is omitted).
    public static func duration(
        of workout: Workout,
        group groupID: String? = nil,
        paceModel: PaceModel = .default
    ) -> (seconds: Int, complete: Bool) {
        let basePace = workout.groups.first(where: { $0.id == groupID })?.basePace100
            ?? workout.groups.first?.basePace100
        var total = 0
        var complete = true
        for section in workout.sections {
            for item in section.items {
                let result = duration(
                    of: item, group: groupID, groups: workout.groups,
                    basePace100: basePace, paceModel: paceModel
                )
                total += result.seconds
                complete = complete && result.complete
            }
        }
        return (total, complete)
    }

    static func duration(
        of item: WorkoutItem,
        group groupID: String?,
        groups: [SpeedGroup],
        basePace100: SwimTime?,
        paceModel: PaceModel
    ) -> (seconds: Int, complete: Bool) {
        switch item {
        case .set(let set):
            guard appliesToGroup(set.groupFilter, groupID: groupID) else { return (0, true) }
            let override = groupID.flatMap { set.perGroup?[$0] }
            let reps = override?.reps ?? set.reps
            let distance = override?.distance ?? set.distance
            let interval = set.interval

            if let sendoff = override?.sendoff
                ?? resolveSendoff(interval?.sendoffs, groupID: groupID, groups: groups),
                interval?.mode != .rest {
                return (reps * sendoff.seconds, true)
            }
            // Rest-based or open: estimate swim time from pace.
            let swim = paceModel.estimateSeconds(
                distance: distance, stroke: set.stroke, activity: set.activity,
                basePace100: basePace100
            )
            guard let swim else { return (0, false) }
            let rest = interval?.rest?.seconds ?? 0
            return (reps * (swim + rest), true)
        case .repeatBlock(let block):
            let rounds = roundCount(of: block, group: groupID, groups: groups)
            var inner = 0
            var complete = true
            for child in block.items {
                let result = duration(
                    of: child, group: groupID, groups: groups,
                    basePace100: basePace100, paceModel: paceModel
                )
                inner += result.seconds
                complete = complete && result.complete
            }
            return (rounds * inner, complete)
        case .rest(let rest):
            if let duration = rest.duration {
                return (duration.seconds, true)
            }
            return (0, false)
        case .note:
            return (0, true)
        }
    }

    // MARK: - Convenience

    /// Totals for every group (or a single unnamed entry when no groups are defined).
    public static func totals(of workout: Workout, paceModel: PaceModel = .default) -> [GroupTotals] {
        let groupIDs: [String?] = workout.groups.isEmpty ? [nil] : workout.groups.map { $0.id }
        return groupIDs.map { id in
            let dist = distance(of: workout, group: id)
            let dur = duration(of: workout, group: id, paceModel: paceModel)
            return GroupTotals(
                groupID: id,
                distance: dist,
                durationSeconds: dur.seconds > 0 ? dur.seconds : nil,
                durationIsComplete: dur.complete
            )
        }
    }
}
