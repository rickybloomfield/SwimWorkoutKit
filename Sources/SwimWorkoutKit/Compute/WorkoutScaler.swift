// SPDX-License-Identifier: MIT

import Foundation

/// Deterministically scales a workout toward a new primary-group total.
///
/// Strategy, in order, until within tolerance (one smallest-set distance):
/// 1. Scale repeat-block round counts proportionally (min 1).
/// 2. Scale set reps proportionally (min 1), largest sections first.
/// 3. Fine-tune by adding/removing single reps on main-set items, preferring
///    the set whose distance best fills the remaining gap.
///
/// Send-offs, strokes, and descriptors are preserved; per-group overrides are
/// scaled with the same factors. Stated totals are updated to the new
/// computed value (they would otherwise be stale).
public enum WorkoutScaler {

    public static func scale(_ workout: Workout, toPrimaryTotal target: Int) -> Workout {
        guard target > 0 else { return workout }
        let primary = workout.groups.first?.id
        let current = WorkoutCalculator.distance(of: workout, group: primary)
        guard current > 0, target != current else { return workout }

        var result = workout
        let factor = Double(target) / Double(current)

        // Pass 1: rounds.
        if abs(factor - 1) > 0.01 {
            for sectionIndex in result.sections.indices {
                scaleRounds(in: &result.sections[sectionIndex].items, factor: factor)
            }
        }

        // Pass 2: reps, only if still meaningfully off.
        var afterRounds = WorkoutCalculator.distance(of: result, group: primary)
        if afterRounds > 0, abs(Double(target) / Double(afterRounds) - 1) > 0.05 {
            let repFactor = Double(target) / Double(afterRounds)
            for sectionIndex in result.sections.indices {
                scaleReps(in: &result.sections[sectionIndex].items, factor: repFactor)
            }
            afterRounds = WorkoutCalculator.distance(of: result, group: primary)
        }

        // Pass 3: fine-tune one rep at a time (bounded).
        fineTune(&result, target: target, primary: primary)

        // Refresh stated totals to match the new reality.
        let newTotal = WorkoutCalculator.distance(of: result, group: primary)
        if result.statedTotal != nil {
            result.statedTotal = newTotal
        }
        for index in result.sections.indices {
            if result.sections[index].statedDistance != nil {
                result.sections[index].statedDistance = WorkoutCalculator.distance(
                    of: result.sections[index], group: primary, groups: result.groups
                )
            }
        }
        return result
    }

    // MARK: - Passes

    private static func scaleRounds(in items: inout [WorkoutItem], factor: Double) {
        for index in items.indices {
            if case .repeatBlock(var block) = items[index] {
                // Floor-biased: undershooting is repairable (fine-tune adds
                // reps; callers append fillers); overshooting often isn't,
                // because units inside a block are rounds × distance.
                block.rounds = max(1, Int((Double(block.rounds) * factor).rounded(.down)))
                if let perGroup = block.roundsPerGroup {
                    block.roundsPerGroup = perGroup.mapValues {
                        max(1, Int((Double($0) * factor).rounded(.down)))
                    }
                }
                scaleRounds(in: &block.items, factor: factor)
                items[index] = .repeatBlock(block)
            }
        }
    }

    private static func scaleReps(in items: inout [WorkoutItem], factor: Double) {
        for index in items.indices {
            switch items[index] {
            case .set(var set):
                // Single-rep "feature" swims (300 free) scale poorly by reps;
                // leave reps == 1 sets alone unless shrinking a lot.
                if set.reps > 1 || factor < 0.6 {
                    set.reps = max(1, Int((Double(set.reps) * factor).rounded()))
                }
                if let perGroup = set.perGroup {
                    set.perGroup = perGroup.mapValues { override in
                        var override = override
                        if let reps = override.reps {
                            override.reps = max(1, Int((Double(reps) * factor).rounded()))
                        }
                        return override
                    }
                }
                items[index] = .set(set)
            case .repeatBlock(var block):
                scaleReps(in: &block.items, factor: factor)
                items[index] = .repeatBlock(block)
            case .rest, .note:
                break
            }
        }
    }

    private static func fineTune(_ workout: inout Workout, target: Int, primary: String?) {
        let tolerance = smallestSetDistance(in: workout) ?? workout.course.length
        for _ in 0..<64 {
            let current = WorkoutCalculator.distance(of: workout, group: primary)
            let gap = target - current
            if abs(gap) < tolerance { return }
            if !adjustOneRep(&workout, gap: gap, primary: primary) { return }
        }
    }

    /// One rep on a set nested inside repeats moves the total by
    /// rounds × distance — its "unit". Fine-tuning picks the set, at any
    /// depth, whose unit best fills the gap.
    private struct RepCandidate {
        var section: Int
        var path: [Int]
        var unit: Int
        var reps: Int
    }

    private static func adjustOneRep(_ workout: inout Workout, gap: Int, primary: String?) -> Bool {
        var candidates: [RepCandidate] = []

        func collect(_ items: [WorkoutItem], section: Int, path: [Int], multiplier: Int) {
            for (index, item) in items.enumerated() {
                switch item {
                case .set(let set):
                    guard WorkoutCalculator.appliesToGroup(set.groupFilter, groupID: primary) else { continue }
                    candidates.append(RepCandidate(
                        section: section, path: path + [index],
                        unit: set.distance * multiplier, reps: set.reps
                    ))
                case .repeatBlock(let block):
                    let rounds = WorkoutCalculator.roundCount(of: block, group: primary, groups: workout.groups)
                    collect(block.items, section: section, path: path + [index], multiplier: multiplier * max(rounds, 1))
                case .rest, .note:
                    continue
                }
            }
        }
        for (sectionIndex, section) in workout.sections.enumerated() {
            collect(section.items, section: sectionIndex, path: [], multiplier: 1)
        }

        let fitting = candidates.filter { candidate in
            gap > 0 ? candidate.unit <= gap : (candidate.reps > 1 && candidate.unit <= -gap)
        }
        guard let best = fitting.max(by: { $0.unit < $1.unit }) else { return false }

        mutateSet(&workout.sections[best.section].items, path: best.path) { set in
            set.reps += gap > 0 ? 1 : -1
        }
        return true
    }

    private static func mutateSet(_ items: inout [WorkoutItem], path: [Int], _ change: (inout SwimSet) -> Void) {
        guard let index = path.first, items.indices.contains(index) else { return }
        if path.count == 1 {
            if case .set(var set) = items[index] {
                change(&set)
                items[index] = .set(set)
            }
            return
        }
        if case .repeatBlock(var block) = items[index] {
            mutateSet(&block.items, path: Array(path.dropFirst()), change)
            items[index] = .repeatBlock(block)
        }
    }

    private static func smallestSetDistance(in workout: Workout) -> Int? {
        var smallest: Int?
        func walk(_ items: [WorkoutItem]) {
            for item in items {
                switch item {
                case .set(let set):
                    smallest = smallest.map { min($0, set.distance) } ?? set.distance
                case .repeatBlock(let block):
                    walk(block.items)
                case .rest, .note:
                    break
                }
            }
        }
        for section in workout.sections { walk(section.items) }
        return smallest
    }
}
