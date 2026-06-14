// SPDX-License-Identifier: MIT

import Testing
@testable import SwimWorkoutKit

@Suite("OCRTextAssembler")
struct OCRTextAssemblerTests {

    @Test("Typed-doc OCR lines assemble into parseable SwimText that reconciles")
    func typedDocument() {
        // Lines as Vision reads a typed-document photo (title shares the first row).
        let ocrLines = [
            "Warmup: 300 Friday- Sprint",
            "3 x 100 as swim, kick, pull",
            "Main Set: 2800",
            "3 x 300 free, descend to 80% effort @4:40/4:50/5:00 (ideally 40s rest)",
            "100 kick, easy; r1:00",
            "4 x 200 free, descend to 90% effort @3:10/3:20/3:30 (ideally 30s rest)",
            "100 kick, easy; r1:00",
            "5 x 100 choice, descend to 95% effort @1:30/1:40/1:50 (ideally 20s rest)",
            "100 kick, easy; r1:00",
            "6 x 50 choice, descend to 100% effort @1:00/1:10 (ideally 15s rest)",
            "Cool Down: 100 Total: 3200",
        ]
        let swimText = OCRTextAssembler.assembleSwimText(from: ocrLines)
        let result = SwimTextParser.parse(swimText)
        let workout = OCRTextAssembler.fillEmptyStatedSections(result.document.workout)

        #expect(workout.title == "Friday- Sprint")
        #expect(workout.statedTotal == 3200)
        #expect(workout.sections.count == 3)
        #expect(workout.sections[0].statedDistance == 300)
        let issues = WorkoutValidator.validate(workout)
        #expect(!issues.contains { $0.code == "workout-total-mismatch" }, "\(issues)")
        #expect(WorkoutCalculator.distance(of: workout, group: "A") == 3200)
    }

    @Test("Stated-but-empty sections fill with a choice swim")
    func emptySectionFill() {
        let workout = SwimTextParser.parse("== Cool Down: 200\n").document.workout
        let filled = OCRTextAssembler.fillEmptyStatedSections(workout)
        #expect(WorkoutCalculator.distance(of: filled, group: nil) == 200)
        guard case .set(let set) = filled.sections[0].items.first else {
            Issue.record("Expected filled set")
            return
        }
        #expect(set.stroke == .choice)
    }

    @Test("Section headers in many spellings")
    func sectionHeaders() {
        #expect(OCRTextAssembler.sectionHeader(from: "Warmup: 800") == "== Warmup: 800")
        #expect(OCRTextAssembler.sectionHeader(from: "warm up") == "== warm up")
        #expect(OCRTextAssembler.sectionHeader(from: "Main Set: 2,100") == "== Main Set: 2100")
        #expect(OCRTextAssembler.sectionHeader(from: "Warm Up (1000 yd, 20 min)") == "== Warm Up: 1000")
        #expect(OCRTextAssembler.sectionHeader(from: "Warmup: 600 or 800") == "== Warmup: 600")
        #expect(OCRTextAssembler.sectionHeader(from: "300 free") == nil)
        #expect(OCRTextAssembler.sectionHeader(from: "Stroke Work (2000 yd, 40 min)") == "== Stroke Work: 2000")
    }

    @Test("Total extraction, including shared lines")
    func totals() throws {
        let shared = try #require(OCRTextAssembler.extractTotal(from: "Cool Down: 100 Total: 2800"))
        #expect(shared.total == 2800)
        #expect(shared.before == "Cool Down: 100")
        let alone = try #require(OCRTextAssembler.extractTotal(from: "Total: 3,200"))
        #expect(alone.total == 3200)
        #expect(alone.before == nil)
        #expect(OCRTextAssembler.extractTotal(from: "100 choice easy") == nil)
    }

    @Test("Bare repeat markers open blocks that close at the next section")
    func repeatMarkers() {
        let lines = [
            "Main Set: 1800",
            "2x",
            "6 x 25 choice, sprint @:35",
            "6 x 25 kick, FAST @:40",
            "Cool Down: 200",
            "200 choice easy",
        ]
        let swimText = OCRTextAssembler.assembleSwimText(from: lines)
        #expect(swimText.contains("2x {"))
        let workout = SwimTextParser.parse(swimText).document.workout
        guard case .repeatBlock(let block) = workout.sections[0].items.first else {
            Issue.record("Expected repeat block, got \(workout.sections[0].items)")
            return
        }
        #expect(block.rounds == 2)
        #expect(block.items.count == 2)
        // The cool down landed outside the block.
        #expect(workout.sections.count == 2)
    }

    @Test("Title detection takes the first short letter line")
    func titles() {
        let lines = ["Wednesday- IM", "Warmup: 600", "3 x 200 as swim, kick, pull"]
        let swimText = OCRTextAssembler.assembleSwimText(from: lines)
        let workout = SwimTextParser.parse(swimText).document.workout
        #expect(workout.title == "Wednesday- IM")
    }

    @Test("Normalization fixes OCR artifacts")
    func normalization() {
        #expect(OCRTextAssembler.normalize("4 × 50  kick") == "4 x 50 kick")
        #expect(OCRTextAssembler.normalize("@ 1:30/1:45") == "@1:30/1:45")
        #expect(OCRTextAssembler.normalize("  100   free ") == "100 free")
    }
}
