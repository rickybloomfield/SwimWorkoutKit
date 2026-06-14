// SPDX-License-Identifier: MIT

import Foundation

/// Model-neutral draft of an AI-designed workout: what an LLM decides
/// (structure, strokes, efforts, rest targets) before the deterministic
/// pass computes send-offs and scales to target. Keeping this in the kit
/// makes the whole conversion testable without any model.
public struct AIDraft: Sendable, Equatable {
    public struct DraftSet: Sendable, Equatable {
        public var reps: Int
        public var distance: Int
        public var stroke: String?
        public var activity: String?
        public var effort: String?
        public var shape: String?
        public var restSeconds: Int?
        public var note: String?

        public init(
            reps: Int, distance: Int,
            stroke: String? = nil, activity: String? = nil,
            effort: String? = nil, shape: String? = nil,
            restSeconds: Int? = nil, note: String? = nil
        ) {
            self.reps = reps
            self.distance = distance
            self.stroke = stroke
            self.activity = activity
            self.effort = effort
            self.shape = shape
            self.restSeconds = restSeconds
            self.note = note
        }
    }

    public struct DraftBlock: Sendable, Equatable {
        public var rounds: Int
        public var sets: [DraftSet]

        public init(rounds: Int, sets: [DraftSet]) {
            self.rounds = rounds
            self.sets = sets
        }
    }

    public struct DraftSection: Sendable, Equatable {
        public var name: String
        public var blocks: [DraftBlock]

        public init(name: String, blocks: [DraftBlock]) {
            self.name = name
            self.blocks = blocks
        }
    }

    public var title: String
    public var sections: [DraftSection]

    public init(title: String, sections: [DraftSection]) {
        self.title = title
        self.sections = sections
    }
}

public enum AIDraftConverter {

    /// Converts a draft into a real workout: enum mapping with safe
    /// fallbacks, distances snapped to 25s, send-offs computed from lane
    /// base paces (rest-based fallback), optional exact scaling.
    public static func workout(
        from draft: AIDraft,
        course: Course,
        groups: [SpeedGroup],
        targetDistance: Int?,
        paceModel: PaceModel = .default
    ) -> Workout {
        var sections: [WorkoutSection] = []
        for draftSection in draft.sections {
            var items: [WorkoutItem] = []
            for block in draftSection.blocks {
                let sets = block.sets.map {
                    makeSet($0, groups: groups, paceModel: paceModel)
                }
                guard !sets.isEmpty else { continue }
                if block.rounds > 1 {
                    items.append(.repeatBlock(RepeatBlock(rounds: block.rounds, items: sets)))
                } else {
                    items.append(contentsOf: sets)
                }
            }
            guard !items.isEmpty else { continue }
            sections.append(WorkoutSection(name: draftSection.name, items: items))
        }

        var workout = Workout(
            title: draft.title.isEmpty ? "AI Workout" : draft.title,
            course: course,
            categories: [],
            groups: groups,
            sections: sections,
            source: WorkoutSource(kind: .ai, attribution: "Apple Intelligence (on-device)")
        )

        tidyEnds(&workout)

        if let targetDistance {
            workout = rebudgeted(workout, target: targetDistance)
            workout.statedTotal = targetDistance
        } else {
            workout.statedTotal = WorkoutCalculator.distance(of: workout, group: groups.first?.id)
        }
        return workout
    }

    // MARK: - Deck sense

    /// Deterministic guardrails for warmups and cool downs — small models put
    /// 20×50 fly sprints in warmups; pools don't work that way.
    static func tidyEnds(_ workout: inout Workout) {
        for index in workout.sections.indices {
            let name = workout.sections[index].name.lowercased()
            let isWarm = name.contains("warm") || name.contains("pre")
            let isCool = name.contains("cool") || name.contains("down")
            guard isWarm || isCool else { continue }
            workout.sections[index].items = workout.sections[index].items.map { item in
                guard case .set(var set) = item else { return item }
                if set.stroke == .fly {
                    set.stroke = isWarm ? .free : .choice
                }
                if let level = set.effort?.level,
                   [.strong, .fast, .sprint, .max, .race].contains(level) {
                    set.effort?.level = isWarm ? .moderate : .easy
                }
                if isCool {
                    set.effort?.shape = nil
                    if set.effort?.isEmpty == true { set.effort = nil }
                }
                return .set(set)
            }
        }
    }

    // MARK: - Section rebudgeting

    /// Scales each section to a canonical share of the target — the same
    /// budget split the parametric generator uses — instead of scaling the
    /// whole workout uniformly. Section totals come out round (multiples of
    /// 100) and the workout lands exactly on target.
    static func rebudgeted(_ workout: Workout, target: Int) -> Workout {
        var result = workout
        let target = max(600, (target / 50) * 50)
        var warmupBudget = min(max((Int(0.18 * Double(target)) / 100) * 100, 300), 1000)
        var cooldownBudget = min(max((Int(0.07 * Double(target)) / 100) * 100, 100), 300)
        if target <= 1200 {
            warmupBudget = 200
            cooldownBudget = 100
        }

        var warmIndex: Int?
        var coolIndex: Int?
        for (index, section) in result.sections.enumerated() {
            let name = section.name.lowercased()
            if warmIndex == nil, name.contains("warm") || name.contains("pre") {
                warmIndex = index
            }
            if name.contains("cool") || name.contains("down") {
                coolIndex = index
            }
        }
        // No recognizable ends → uniform scaling is the best we can do.
        guard let warmIndex, let coolIndex, warmIndex != coolIndex else {
            return WorkoutScaler.scale(result, toPrimaryTotal: target)
        }

        let mainBudget = target - warmupBudget - cooldownBudget
        let primary = result.groups.first?.id
        let mainIndices = result.sections.indices.filter { $0 != warmIndex && $0 != coolIndex }
        let mainCurrent = mainIndices.reduce(0) {
            $0 + WorkoutCalculator.distance(of: result.sections[$1], group: primary, groups: result.groups)
        }

        scaleSection(&result, at: warmIndex, to: warmupBudget)
        scaleSection(&result, at: coolIndex, to: cooldownBudget)
        // Main sections share the main budget proportionally; the largest one
        // absorbs the rounding remainder.
        var allocated = 0
        var largest: (index: Int, size: Int)?
        for index in mainIndices {
            let current = WorkoutCalculator.distance(of: result.sections[index], group: primary, groups: result.groups)
            let share = mainCurrent > 0
                ? Int((Double(current) / Double(mainCurrent) * Double(mainBudget)) / 50) * 50
                : mainBudget / max(mainIndices.count, 1)
            scaleSection(&result, at: index, to: share)
            allocated += WorkoutCalculator.distance(of: result.sections[index], group: primary, groups: result.groups)
            if largest == nil || current > largest!.size {
                largest = (index, current)
            }
        }
        if let largest, allocated != mainBudget {
            let currentLargest = WorkoutCalculator.distance(
                of: result.sections[largest.index], group: primary, groups: result.groups
            )
            scaleSection(&result, at: largest.index, to: currentLargest + (mainBudget - allocated))
        }

        // Close any remaining gap exactly: 50s (plus at most one 25) appended
        // to the last main section — same trick the parametric generator uses.
        let total = WorkoutCalculator.distance(of: result, group: primary)
        let gap = target - total
        if gap >= 25, let lastMain = mainIndices.last {
            var items = result.sections[lastMain].items
            if gap >= 50 {
                items.append(.set(SwimSet(
                    reps: gap / 50, distance: 50, stroke: .choice,
                    effort: Effort(level: .easy), note: "shake it out"
                )))
            }
            if gap % 50 >= 25 {
                items.append(.set(SwimSet(reps: 1, distance: 25, stroke: .choice, effort: Effort(level: .easy))))
            }
            result.sections[lastMain].items = items
            if result.sections[lastMain].statedDistance != nil {
                result.sections[lastMain].statedDistance = WorkoutCalculator.distance(
                    of: result.sections[lastMain], group: primary, groups: result.groups
                )
            }
        }
        return result
    }

    /// Scales one section's items toward a target by reusing the workout
    /// scaler on a single-section stand-in.
    private static func scaleSection(_ workout: inout Workout, at index: Int, to target: Int) {
        guard target > 0 else { return }
        var standIn = Workout(
            course: workout.course,
            groups: workout.groups,
            sections: [workout.sections[index]]
        )
        standIn = WorkoutScaler.scale(standIn, toPrimaryTotal: target)
        workout.sections[index].items = standIn.sections[0].items
        if workout.sections[index].statedDistance != nil {
            workout.sections[index].statedDistance = WorkoutCalculator.distance(
                of: standIn.sections[0], group: workout.groups.first?.id, groups: workout.groups
            )
        }
    }

    private static func makeSet(
        _ draft: AIDraft.DraftSet,
        groups: [SpeedGroup],
        paceModel: PaceModel
    ) -> WorkoutItem {
        // Snap to the pool: multiples of 25, at least one length.
        let distance = max(25, ((draft.distance + 12) / 25) * 25)
        let reps = max(1, draft.reps)

        let stroke = draft.stroke.flatMap { Stroke(rawValue: $0.lowercased()) }
        let activity = draft.activity.flatMap { Activity(rawValue: $0.lowercased()) }
        let level = draft.effort.flatMap { EffortLevel(rawValue: $0.lowercased()) }
        let shape = draft.shape.flatMap { EffortShape(rawValue: $0.lowercased()) }

        var effort: Effort?
        if level != nil || (shape != nil && shape != .steady) {
            effort = Effort(shape: shape == .steady ? nil : shape, level: level)
        }

        var interval: Interval?
        if let restSeconds = draft.restSeconds {
            let clampedRest = min(max(restSeconds, 5), 180)
            let isRecovery = level == .easy || level == .smooth
            let hasPaces = groups.contains { $0.basePace100 != nil }
            if hasPaces && !isRecovery {
                var sendoffs: [String: SwimTime] = [:]
                for group in groups {
                    if let sendoff = paceModel.suggestedSendoff(
                        distance: distance, stroke: stroke, activity: activity,
                        basePace100: group.basePace100,
                        targetRest: SwimTime(seconds: clampedRest)
                    ) {
                        sendoffs[group.id] = sendoff
                    }
                }
                if !sendoffs.isEmpty {
                    interval = Interval(
                        mode: .sendoff, sendoffs: sendoffs,
                        targetRest: SwimTime(seconds: clampedRest)
                    )
                }
            }
            if interval == nil {
                interval = Interval(mode: .rest, rest: SwimTime(seconds: clampedRest))
            }
        }

        return .set(SwimSet(
            reps: reps, distance: distance,
            stroke: stroke, activity: activity,
            effort: effort, interval: interval,
            note: draft.note?.isEmpty == true ? nil : draft.note
        ))
    }
}
