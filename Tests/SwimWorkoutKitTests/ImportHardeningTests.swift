// SPDX-License-Identifier: MIT

import Testing
@testable import SwimWorkoutKit

/// Regression tests for the photo-import hardening pass — each case mirrors a
/// real failure found auditing the Claude vision path against the 41
/// `Workout Examples` photos. See `Artifacts/claude-import-audit/`.
@Suite("Import hardening")
struct ImportHardeningTests {

    // MARK: #1 — markdown code fences

    @Test("Code fences are dropped, not kept as notes")
    func stripsCodeFences() {
        let text = """
        ```
        # Wednesday
        == Warmup: 100
        100 swim
        == Cool Down: 200
        ```
        """
        var result = SwimTextParser.parse(text)
        #expect(result.unparsedLines.isEmpty)
        // A trailing fence must not block the stated-only cool down from filling.
        result.document.workout = OCRTextAssembler.fillEmptyStatedSections(result.document.workout)
        #expect(WorkoutCalculator.distance(of: result.document.workout) == 300)
        #expect(result.document.workout.title == "Wednesday")
    }

    // MARK: #2 — stated-only sections with a stray note

    @Test("Stated-only section fills even when a stray note lands in it")
    func fillsStatedSectionWithStrayNote() {
        let text = """
        == Cool Down: 100
        choice
        """
        var result = SwimTextParser.parse(text)
        result.document.workout = OCRTextAssembler.fillEmptyStatedSections(result.document.workout)
        #expect(WorkoutCalculator.distance(of: result.document.workout) == 100)
        // The note survives alongside the filled swim.
        #expect(result.document.workout.sections.first?.items.count == 2)
    }

    // MARK: #3 — consensus lanes vs. per-rep interval ladders

    @Test("Send-off list with more reps than times declares real lanes (Friday-Sprint)")
    func laneSendoffsBecomeGroups() {
        // 3 times, 4 reps → three lanes each swimming 4×200, not a per-rep ladder.
        let text = """
        == Main: 1600
        4 x 200 free descend @3:10/3:20/3:30
        4 x 200 free descend @3:00/3:10/3:20
        """
        let workout = SwimTextParser.parse(text).document.workout
        #expect(workout.groups.count == 3)
    }

    @Test("A lone wide send-off list does not mint phantom lanes")
    func loneWideSendoffIsNotLanes() {
        let text = """
        == Main: 800
        100 free build @1:30
        200 free @2:50
        5 x 100 choice @1:40/1:45/1:50/1:55/2:00 | ascend
        """
        let workout = SwimTextParser.parse(text).document.workout
        #expect(workout.groups.isEmpty)
        // Distance is unaffected regardless of lane interpretation.
        #expect(WorkoutCalculator.distance(of: workout) == 800)
    }

    @Test("A wide per-rep ladder doesn't leave phantom group references")
    func wideLadderTrimsToLanes() {
        let text = """
        == Main: 1700
        3x {
        100 choice build @1:30/1:40/1:50
        5 x 100 choice @1:40/1:45/1:50/1:55/2:00 | ascend
        }
        """
        let workout = SwimTextParser.parse(text).document.workout
        // 3 lanes inferred from the 1-rep build set; the 5-wide ladder is not lanes.
        #expect(workout.groups.count == 3)
        let issues = WorkoutValidator.validate(workout)
        #expect(!issues.contains { $0.code == "unknown-group" })
    }

    // MARK: #4 — repeat-block round headers

    @Test("Fractional and alternative repeat headers parse")
    func fractionalAndAlternativeRounds() {
        // 3.5x → nearest whole round (4).
        let fractional = SwimTextParser.parse("3.5x {\n100 free\n}").document.workout
        #expect(WorkoutCalculator.distance(of: fractional) == 400)
        // "4 or 3x" → first stated count (4), and no bogus 4-yard set.
        let alternative = SwimTextParser.parse("4 or 3x {\n100 free\n}")
        #expect(WorkoutCalculator.distance(of: alternative.document.workout) == 400)
        #expect(alternative.unparsedLines.isEmpty)
    }

    @Test("Per-group repeat counts still work (4/3x)")
    func perGroupRoundsStillWork() {
        let text = """
        groups: A; B
        4/3x {
        100 free
        }
        """
        let workout = SwimTextParser.parse(text).document.workout
        #expect(WorkoutCalculator.distance(of: workout, group: "A") == 400)
        #expect(WorkoutCalculator.distance(of: workout, group: "B") == 300)
    }

    // MARK: #5 — rep ladders

    @Test("In-block rep ladder is per-round, not per-rep")
    func inBlockRepLadderIsPerRound() {
        // 6-4-2 across a 3-round block = 6+4+2 = 12 fifties total = 600.
        let text = """
        == Main: 600
        3x {
        6-4-2 x 50 stroke @:45-:50-:55
        }
        """
        let result = SwimTextParser.parse(text)
        #expect(result.unparsedLines.isEmpty)
        #expect(WorkoutCalculator.distance(of: result.document.workout) == 600)
    }

    @Test("Standalone rep ladder expands into sequential sets")
    func standaloneRepLadderExpands() {
        let text = """
        == Main: 600
        6-4-2 x 50 stroke
        """
        let result = SwimTextParser.parse(text)
        #expect(result.unparsedLines.isEmpty)
        #expect(WorkoutCalculator.distance(of: result.document.workout) == 600)
        #expect(result.document.workout.sections.first?.items.count == 3)
    }
}
