// SPDX-License-Identifier: MIT

import Testing
@testable import SwimWorkoutKit

@Suite("GenerationCritic")
struct GenerationCriticTests {

    @Test("Extracts stated totals from prompts")
    func targetExtraction() {
        #expect(GenerationCritic.targetDistance(in: "a 3,200 IM workout with fly emphasis") == 3200)
        #expect(GenerationCritic.targetDistance(in: "3000 yards of sprint work") == 3000)
        #expect(GenerationCritic.targetDistance(in: "about 2.5k easy") == 2500)
        // Rep distances must not be mistaken for totals.
        #expect(GenerationCritic.targetDistance(in: "descending 50s and easy 100s") == nil)
        #expect(GenerationCritic.targetDistance(in: "finish with sprint 25s") == nil)
        #expect(GenerationCritic.targetDistance(in: "a fun fly day") == nil)
    }

    @Test("Flags the monotonous wall-of-125s failure mode")
    func flagsMonotony() {
        // The real on-device failure: 10×125 of every stroke, no shapes.
        let monotone = Workout(
            course: .scy,
            sections: [
                WorkoutSection(name: "Main Set", items: [
                    .set(SwimSet(reps: 10, distance: 125, stroke: .fly,
                                 effort: Effort(level: .strong))),
                    .set(SwimSet(reps: 10, distance: 125, stroke: .back,
                                 effort: Effort(level: .strong))),
                    .set(SwimSet(reps: 10, distance: 125, stroke: .breast,
                                 effort: Effort(level: .strong))),
                ]),
            ]
        )
        let critique = GenerationCritic.critique(monotone)
        #expect(critique.isMonotonous)
        #expect(critique.complaint?.contains("repetitive") == true)
    }

    @Test("Passes a varied workout (real corpus fixture)")
    func passesVariety() {
        let text = """
        == Main Set
        3x300 free descend to 80% @4:40/4:50/5:00
        100 kick easy r1:00
        4x200 free descend to 90% @3:10/3:20/3:30
        100 kick easy r1:00
        5x100 choice descend to 95% @1:30/1:40/1:50
        6x50 choice descend to 100% @1:00/1:10
        """
        let workout = SwimTextParser.parse(text).document.workout
        let critique = GenerationCritic.critique(workout)
        #expect(!critique.isMonotonous, "\(critique)")
    }

    @Test("Extreme scale-down (the 20,000-yard hallucination) stays valid")
    func extremeScaleDown() {
        // Roughly the shape the on-device model produced unprompted.
        var sections: [WorkoutSection] = []
        sections.append(WorkoutSection(name: "Warmup", items: [
            .set(SwimSet(reps: 20, distance: 50, stroke: .fly, effort: Effort(level: .easy))),
            .repeatBlock(RepeatBlock(rounds: 2, items: [
                .set(SwimSet(reps: 20, distance: 50, stroke: .fly)),
                .set(SwimSet(reps: 10, distance: 25, stroke: .back)),
            ])),
        ]))
        sections.append(WorkoutSection(name: "Main Set", items: [
            .repeatBlock(RepeatBlock(rounds: 2, items: [
                .set(SwimSet(reps: 10, distance: 125, stroke: .fly)),
                .set(SwimSet(reps: 10, distance: 125, stroke: .back)),
                .set(SwimSet(reps: 10, distance: 125, stroke: .breast)),
            ])),
        ]))
        let bloated = Workout(course: .scy, sections: sections)
        let before = WorkoutCalculator.distance(of: bloated, group: nil)
        #expect(before > 10000)

        let scaled = WorkoutScaler.scale(bloated, toPrimaryTotal: 3000)
        let after = WorkoutCalculator.distance(of: scaled, group: nil)
        #expect(abs(after - 3000) <= 50, "Got \(after)")
        let errors = WorkoutValidator.validate(scaled).filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }
}
