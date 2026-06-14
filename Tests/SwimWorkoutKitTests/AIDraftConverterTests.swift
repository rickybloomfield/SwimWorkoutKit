// SPDX-License-Identifier: MIT

import Testing
@testable import SwimWorkoutKit

@Suite("AIDraftConverter")
struct AIDraftConverterTests {

    private let groups = [
        SpeedGroup(id: "A", basePace100: SwimTime(parsing: "1:20")),
        SpeedGroup(id: "B", basePace100: SwimTime(parsing: "1:40")),
    ]

    private func draft() -> AIDraft {
        AIDraft(title: "Test Sprint", sections: [
            .init(name: "Warmup", blocks: [
                .init(rounds: 1, sets: [
                    .init(reps: 1, distance: 300, stroke: "free", note: "loosen"),
                    .init(reps: 4, distance: 50, activity: "kick"),
                ]),
            ]),
            .init(name: "Main Set", blocks: [
                .init(rounds: 3, sets: [
                    .init(reps: 4, distance: 50, stroke: "choice", effort: "sprint",
                          shape: "descend", restSeconds: 20),
                    .init(reps: 1, distance: 100, stroke: "choice", effort: "easy", restSeconds: 60),
                ]),
            ]),
            .init(name: "Cool Down", blocks: [
                .init(rounds: 1, sets: [
                    .init(reps: 1, distance: 200, stroke: "choice", effort: "easy"),
                ]),
            ]),
        ])
    }

    @Test("Converts structure: repeats, enums, send-offs from paces")
    func conversion() throws {
        let workout = AIDraftConverter.workout(
            from: draft(), course: .scy, groups: groups, targetDistance: nil
        )
        #expect(workout.title == "Test Sprint")
        #expect(workout.sections.count == 3)
        guard case .repeatBlock(let block) = workout.sections[1].items.first else {
            Issue.record("Expected repeat block")
            return
        }
        #expect(block.rounds == 3)
        guard case .set(let sprintSet) = block.items.first else {
            Issue.record("Expected sprint set")
            return
        }
        #expect(sprintSet.effort?.level == .sprint)
        #expect(sprintSet.effort?.shape == .descend)
        // Work set with paces → computed send-offs, faster lane faster.
        let sendoffs = try #require(sprintSet.interval?.sendoffs)
        let a = try #require(sendoffs["A"])
        let b = try #require(sendoffs["B"])
        #expect(a.seconds < b.seconds)
        // Recovery set stays rest-based even with paces present.
        guard case .set(let easySet) = block.items.last else {
            Issue.record("Expected easy set")
            return
        }
        #expect(easySet.interval?.mode == .rest)
        #expect(easySet.interval?.rest == SwimTime(seconds: 60))
        // Stated total mirrors computed when no target given.
        #expect(workout.statedTotal == WorkoutCalculator.distance(of: workout, group: "A"))
    }

    @Test("Snaps distances to 25s and clamps junk values")
    func snapping() {
        let messy = AIDraft(title: "", sections: [
            .init(name: "Main", blocks: [
                .init(rounds: 1, sets: [
                    .init(reps: 0, distance: 60, stroke: "FREESTYLE??", effort: "bananas",
                          restSeconds: 999),
                ]),
            ]),
        ])
        let workout = AIDraftConverter.workout(
            from: messy, course: .scy, groups: [], targetDistance: nil
        )
        guard case .set(let set) = workout.sections[0].items.first else {
            Issue.record("Expected set")
            return
        }
        #expect(set.reps == 1)
        #expect(set.distance == 50)          // 60 → 50
        #expect(set.stroke == nil)           // unknown string → nil, never crash
        #expect(set.effort == nil)
        #expect(set.interval?.rest?.seconds == 180)  // clamped
        #expect(workout.title == "AI Workout")
    }

    @Test("Scales to an exact requested target with round section budgets")
    func scaling() {
        let workout = AIDraftConverter.workout(
            from: draft(), course: .scy, groups: groups, targetDistance: 2500
        )
        #expect(workout.statedTotal == 2500)
        let total = WorkoutCalculator.distance(of: workout, group: "A")
        #expect(total == 2500, "Got \(total)")
        // Warmup/cool down land on canonical round budgets, not 550/175.
        let warmup = WorkoutCalculator.distance(of: workout.sections[0], group: "A", groups: groups)
        let cool = WorkoutCalculator.distance(of: workout.sections[2], group: "A", groups: groups)
        #expect(warmup % 100 == 0 && (300...1000).contains(warmup), "warmup \(warmup)")
        #expect(cool % 100 == 0 && (100...300).contains(cool), "cool \(cool)")
        let errors = WorkoutValidator.validate(workout).filter { $0.severity == .error }
        #expect(errors.isEmpty)
    }

    @Test("Deck sense: no fly sprints in the warmup, calm cool downs")
    func deckSense() {
        let silly = AIDraft(title: "Fly Day", sections: [
            .init(name: "Warmup", blocks: [
                .init(rounds: 1, sets: [
                    .init(reps: 12, distance: 50, stroke: "fly", effort: "sprint", restSeconds: 15),
                ]),
            ]),
            .init(name: "Main Set", blocks: [
                .init(rounds: 1, sets: [
                    .init(reps: 8, distance: 50, stroke: "fly", effort: "sprint", restSeconds: 20),
                ]),
            ]),
            .init(name: "Cool Down", blocks: [
                .init(rounds: 1, sets: [
                    .init(reps: 4, distance: 50, stroke: "fly", effort: "fast", shape: "descend", restSeconds: 10),
                ]),
            ]),
        ])
        let workout = AIDraftConverter.workout(
            from: silly, course: .scy, groups: groups, targetDistance: 2000
        )
        guard case .set(let warmSet) = workout.sections[0].items.first,
              case .set(let mainSet) = workout.sections[1].items.first,
              case .set(let coolSet) = workout.sections[2].items.first
        else {
            Issue.record("Expected sets")
            return
        }
        #expect(warmSet.stroke != .fly)
        #expect(warmSet.effort?.level == .moderate)
        // The main set keeps the swimmer's actual request.
        #expect(mainSet.stroke == .fly)
        #expect(mainSet.effort?.level == .sprint)
        #expect(coolSet.stroke != .fly)
        #expect(coolSet.effort?.level == .easy)
        #expect(coolSet.effort?.shape == nil)
        #expect(WorkoutCalculator.distance(of: workout, group: "A") == 2000)
    }

    @Test("Empty sections and blocks are dropped")
    func emptyHandling() {
        let sparse = AIDraft(title: "Sparse", sections: [
            .init(name: "Ghost", blocks: []),
            .init(name: "Real", blocks: [
                .init(rounds: 1, sets: [.init(reps: 2, distance: 100)]),
            ]),
        ])
        let workout = AIDraftConverter.workout(
            from: sparse, course: .scy, groups: [], targetDistance: nil
        )
        #expect(workout.sections.count == 1)
        #expect(workout.sections[0].name == "Real")
    }
}
