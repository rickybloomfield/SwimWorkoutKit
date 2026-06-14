// SPDX-License-Identifier: MIT

import Testing
@testable import SwimWorkoutKit

@Suite("Document parsing")
struct DocumentParserTests {

    @Test("Metadata, sections, and stated distances")
    func metadataAndSections() throws {
        let text = """
        # Friday — Sprint
        date: 2026-06-05
        course: scy
        categories: sprint
        groups: A "Lanes 1-2" 1:15; B "Lanes 3-4" 1:25
        total: 2800

        == Warmup: 300
        3x100 as swim/kick/pull
        == Cool Down: 100
        100 choice easy
        """
        let result = SwimTextParser.parse(text)
        let workout = result.document.workout
        #expect(workout.title == "Friday — Sprint")
        #expect(workout.date == "2026-06-05")
        #expect(workout.course == .scy)
        #expect(workout.categories == ["sprint"])
        #expect(workout.statedTotal == 2800)
        #expect(workout.groups.count == 2)
        #expect(workout.groups[0].id == "A")
        #expect(workout.groups[0].label == "Lanes 1-2")
        #expect(workout.groups[0].basePace100 == SwimTime(seconds: 75))
        #expect(workout.sections.count == 2)
        #expect(workout.sections[0].statedDistance == 300)
        #expect(result.unparsedLines.isEmpty)
    }

    @Test("Trailing total is hoisted to metadata, not kept as a note")
    func trailingTotalNotANote() throws {
        // Matches the photo-read case: the model writes "total: NNNN" at the
        // very end (under the cool down), after content has been seen.
        let text = """
        == Warmup: 300
        100 choice easy
        == Cool Down: 200
        100 choice easy

        total: 3000
        """
        let result = SwimTextParser.parse(text)
        #expect(result.document.workout.statedTotal == 3000)
        #expect(result.unparsedLines.isEmpty)
        // The total must not have leaked into the cool-down section as a note.
        let cooldown = try #require(result.document.workout.sections.last)
        #expect(cooldown.items.allSatisfy { if case .note = $0 { return false } else { return true } })
    }

    @Test("Cool Down stated only as a header distance expands to a swim")
    func statedOnlyCoolDownExpands() throws {
        let text = """
        == Warmup: 300
        100 choice easy
        == Cool Down: 200
        total: 3000
        """
        let parsed = SwimTextParser.parse(text)
        let filled = OCRTextAssembler.fillEmptyStatedSections(parsed.document.workout)
        let cooldown = try #require(filled.sections.last)
        #expect(cooldown.statedDistance == 200)
        #expect(cooldown.items.count == 1)
        guard case .set(let set) = cooldown.items.first else {
            Issue.record("expected the cool down to expand into a swim set")
            return
        }
        #expect(set.distance == 200)
        // And the cool-down distance now counts toward the computed total
        // (100 warmup swim + 200 expanded cool down).
        let computed = WorkoutCalculator.totals(of: filled).first?.distance
        #expect(computed == 300)
    }

    @Test("Section header without == is recognized")
    func bareSectionHeaders() throws {
        let text = """
        Warmup: 300
        100 choice easy
        Cool Down: 200
        """
        let workout = SwimTextParser.parse(text).document.workout
        #expect(workout.sections.count == 2)
        #expect(workout.sections[0].name == "Warmup")
        #expect(workout.sections[0].statedDistance == 300)
        #expect(workout.sections[1].name == "Cool Down")
        #expect(workout.sections[1].statedDistance == 200)
        // Parser stays faithful — the deck-convention fill is a separate step.
        #expect(workout.sections[1].items.isEmpty)
    }

    @Test("A lone 'Cool down: 200' (no ==) counts its distance after fill")
    func bareStatedSectionCounts() throws {
        // The exact reported case: typed with nothing else after it.
        let parsed = SwimTextParser.parse("Cool down: 200")
        let filled = OCRTextAssembler.fillEmptyStatedSections(parsed.document.workout)
        #expect(WorkoutCalculator.distance(of: filled) == 200)
    }

    @Test("Bare 'key: value' metadata is not mistaken for a section")
    func bareHeaderDoesNotEatMetadata() throws {
        let text = """
        course: scy
        Warmup: 300
        100 free
        """
        let workout = SwimTextParser.parse(text).document.workout
        #expect(workout.course == .scy)
        #expect(workout.sections.count == 1)
        #expect(workout.sections[0].name == "Warmup")
    }

    @Test("Stated-empty section survives a SwimText print → parse → fill round-trip")
    func statedEmptyRoundTrip() throws {
        // Mirrors the workout editor's Swim Text mode: print the draft, edit as
        // text, parse back, fill stated-empty sections. The cool-down distance
        // must survive the toggle.
        let workout = Workout(
            sections: [
                WorkoutSection(name: "Main Set", statedDistance: 400, items: [
                    .set(SwimSet(reps: 4, distance: 100, stroke: .free)),
                ]),
                WorkoutSection(name: "Cool Down", statedDistance: 200),
            ]
        )
        let text = SwimTextPrinter.print(workout)
        let parsed = SwimTextParser.parse(text).document.workout
        let filled = OCRTextAssembler.fillEmptyStatedSections(parsed)
        #expect(WorkoutCalculator.distance(of: filled) == 600)
    }

    @Test("Metadata placeholders survive a print → parse → print round-trip")
    func metadataPlaceholdersPersist() {
        let workout = Workout(title: "New Workout", course: .scy, groups: [SpeedGroup(id: "A")])
        let text = SwimTextPrinter.print(workout, metadataPlaceholders: true)
        for key in ["date:", "author:", "team:", "categories:", "tags:"] {
            #expect(text.contains(key))
        }
        // After a round-trip (empty values parse to nil), placeholders persist
        // when reprinted with the flag — but are omitted by the default printer.
        let parsed = SwimTextParser.parse(text).document.workout
        #expect(SwimTextPrinter.print(parsed, metadataPlaceholders: true).contains("author:"))
        #expect(!SwimTextPrinter.print(parsed).contains("author:"))
    }

    @Test("Nested repeats with per-group rounds and per-round notes")
    func nestedRepeats() throws {
        let text = """
        == Main Set
        4/3x {
          round 2: back
          100 choice
          2x {
            50 drill
          }
        }
        """
        let result = SwimTextParser.parse(text)
        let section = try #require(result.document.workout.sections.first)
        guard case .repeatBlock(let block) = try #require(section.items.first) else {
            Issue.record("Expected repeat block")
            return
        }
        #expect(block.rounds == 4)
        #expect(block.roundsPerGroup?["A"] == 4)
        #expect(block.roundsPerGroup?["B"] == 3)
        #expect(block.perRound?.first?.selector == "2")
        #expect(block.perRound?.first?.stroke == .back)
        #expect(block.items.count == 2)
        guard case .repeatBlock(let inner) = block.items[1] else {
            Issue.record("Expected nested repeat block")
            return
        }
        #expect(inner.rounds == 2)
    }

    @Test("Groups are auto-created from send-off arity")
    func groupInference() throws {
        let text = """
        == Main
        5x100 choice @1:30/1:40/1:50
        """
        let workout = SwimTextParser.parse(text).document.workout
        #expect(workout.groups.map { $0.id } == ["A", "B", "C"])
    }

    @Test("Unparseable lines become notes and are reported")
    func unparsedFallback() throws {
        let text = """
        == Main
        100 free
        REPEAT EVERYTHING TWICE
        """
        let result = SwimTextParser.parse(text)
        #expect(result.unparsedLines.count == 1)
        #expect(result.unparsedLines.first?.text.contains("REPEAT") == true)
        let section = try #require(result.document.workout.sections.first)
        guard case .note(let note) = section.items.last else {
            Issue.record("Expected note fallback")
            return
        }
        #expect(note.text == "REPEAT EVERYTHING TWICE")
    }

    @Test("Standalone rest lines")
    func restLines() throws {
        let text = """
        == Main
        100 free
        rest 2:00 | between sets
        100 free
        """
        let section = try #require(SwimTextParser.parse(text).document.workout.sections.first)
        guard case .rest(let rest) = section.items[1] else {
            Issue.record("Expected rest item")
            return
        }
        #expect(rest.duration == SwimTime(seconds: 120))
        #expect(rest.note == "between sets")
    }
}
