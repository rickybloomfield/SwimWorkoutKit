// SPDX-License-Identifier: MIT

import Foundation

/// One thing to do at the pool, in order: a set or an explicit rest.
public struct FlatWorkoutStep: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case set(SwimSet)
        case rest(RestItem)
    }

    public struct RoundContext: Sendable, Equatable {
        public var round: Int
        public var totalRounds: Int
        /// Matching per-round annotation ("back and free"), if any.
        public var note: String?
        public var stroke: Stroke?

        public init(round: Int, totalRounds: Int, note: String? = nil, stroke: Stroke? = nil) {
            self.round = round
            self.totalRounds = totalRounds
            self.note = note
            self.stroke = stroke
        }
    }

    public var kind: Kind
    public var sectionName: String
    /// Innermost repeat context, when inside a repeat block.
    public var round: RoundContext?

    public init(kind: Kind, sectionName: String, round: RoundContext? = nil) {
        self.kind = kind
        self.sectionName = sectionName
        self.round = round
    }
}

/// Expands a workout into the ordered step sequence one group actually swims:
/// repeats unrolled round by round (per-group counts respected), group-filtered
/// items skipped, notes folded away (they ride along on the set itself).
public enum WorkoutFlattener {

    public static func steps(for workout: Workout, group groupID: String?) -> [FlatWorkoutStep] {
        var steps: [FlatWorkoutStep] = []
        for section in workout.sections {
            append(
                items: section.items, sectionName: section.name, round: nil,
                workout: workout, groupID: groupID, into: &steps
            )
        }
        return steps
    }

    private static func append(
        items: [WorkoutItem],
        sectionName: String,
        round: FlatWorkoutStep.RoundContext?,
        workout: Workout,
        groupID: String?,
        into steps: inout [FlatWorkoutStep]
    ) {
        for item in items {
            switch item {
            case .set(let set):
                guard WorkoutCalculator.appliesToGroup(set.groupFilter, groupID: groupID) else {
                    continue
                }
                steps.append(FlatWorkoutStep(kind: .set(set), sectionName: sectionName, round: round))
            case .rest(let rest):
                steps.append(FlatWorkoutStep(kind: .rest(rest), sectionName: sectionName, round: round))
            case .note:
                continue
            case .repeatBlock(let block):
                let rounds = WorkoutCalculator.roundCount(of: block, group: groupID, groups: workout.groups)
                for roundIndex in 1...max(rounds, 1) {
                    let annotation = perRoundAnnotation(block: block, round: roundIndex)
                    let context = FlatWorkoutStep.RoundContext(
                        round: roundIndex,
                        totalRounds: rounds,
                        note: annotation?.note,
                        stroke: annotation?.stroke
                    )
                    append(
                        items: block.items, sectionName: sectionName, round: context,
                        workout: workout, groupID: groupID, into: &steps
                    )
                }
            }
        }
    }

    private static func perRoundAnnotation(block: RepeatBlock, round: Int) -> PerRound? {
        block.perRound?.first { matches(selector: $0.selector, value: round) }
    }

    /// Selector grammar shared with PerRep: "odd", "even", "3", "1-4".
    static func matches(selector: String, value: Int) -> Bool {
        switch selector.lowercased() {
        case "odd": return value % 2 == 1
        case "even": return value % 2 == 0
        default:
            if let exact = Int(selector) {
                return exact == value
            }
            if let match = selector.firstMatch(of: /^(\d+)-(\d+)$/),
               let low = Int(match.1), let high = Int(match.2) {
                return (low...high).contains(value)
            }
            return false
        }
    }
}
