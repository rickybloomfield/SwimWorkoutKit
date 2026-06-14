// SPDX-License-Identifier: MIT

import Testing
@testable import SwimWorkoutKit

@Suite("WorkoutFlattener")
struct FlattenerTests {

    @Test("Repeats unroll per round with context; notes are skipped")
    func unrollsRepeats() {
        let workout = SwimTextParser.parse("""
        == Main Set
        2x {
          round 2: back
          4x25 fly sprint
          100 im
        }
        > remember fins
        100 choice easy
        """).document.workout

        let steps = WorkoutFlattener.steps(for: workout, group: nil)
        // 2 rounds × 2 sets + trailing set; the note item vanishes.
        #expect(steps.count == 5)
        #expect(steps[0].round?.round == 1)
        #expect(steps[0].round?.totalRounds == 2)
        #expect(steps[0].round?.stroke == nil)
        #expect(steps[2].round?.round == 2)
        #expect(steps[2].round?.stroke == .back)
        #expect(steps[4].round == nil)
        #expect(steps.allSatisfy { $0.sectionName == "Main Set" })
    }

    @Test("Per-group round counts and group filters are honored")
    func perGroupExpansion() {
        var workout = SwimTextParser.parse("""
        == Warmup
        4/3x {
          100 choice
        }
        """).document.workout
        // Add a set only group A swims.
        workout.sections[0].items.append(
            .set(SwimSet(reps: 1, distance: 200, groupFilter: ["A"]))
        )

        let stepsA = WorkoutFlattener.steps(for: workout, group: "A")
        let stepsB = WorkoutFlattener.steps(for: workout, group: "B")
        #expect(stepsA.count == 5)  // 4 rounds + filtered set
        #expect(stepsB.count == 3)  // 3 rounds, no filtered set
    }

    @Test("Explicit rest items become steps")
    func restSteps() {
        let workout = SwimTextParser.parse("""
        == Main
        100 free
        rest 2:00
        100 free
        """).document.workout
        let steps = WorkoutFlattener.steps(for: workout, group: nil)
        #expect(steps.count == 3)
        guard case .rest(let rest) = steps[1].kind else {
            Issue.record("Expected rest step")
            return
        }
        #expect(rest.duration == SwimTime(seconds: 120))
    }

    @Test("Selector matching covers odd/even/exact/range")
    func selectors() {
        #expect(WorkoutFlattener.matches(selector: "odd", value: 3))
        #expect(!WorkoutFlattener.matches(selector: "odd", value: 2))
        #expect(WorkoutFlattener.matches(selector: "even", value: 2))
        #expect(WorkoutFlattener.matches(selector: "2", value: 2))
        #expect(!WorkoutFlattener.matches(selector: "2", value: 3))
        #expect(WorkoutFlattener.matches(selector: "1-3", value: 2))
        #expect(!WorkoutFlattener.matches(selector: "1-3", value: 4))
    }
}
