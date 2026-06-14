// SPDX-License-Identifier: MIT

import Testing
@testable import SwimWorkoutKit

@Suite("SwimText field resolver")
struct SwimTextFieldResolverTests {

    private func index(of needle: String, in text: String) -> String.Index {
        text.range(of: needle)!.lowerBound
    }

    // MARK: - Body tokens

    @Test("Caret on a stroke resolves a stroke field")
    func strokeField() {
        let text = "4x50 free fast @:40"
        let field = SwimTextFieldResolver.field(in: text, at: index(of: "free", in: text))
        #expect(field?.kind == .stroke)
        #expect(field.map { String(text[$0.range]) } == "free")
    }

    @Test("Caret on an effort word resolves an effort-level field")
    func effortField() {
        let text = "4x50 free fast @:40"
        #expect(SwimTextFieldResolver.field(in: text, at: index(of: "fast", in: text))?.kind == .effortLevel)
    }

    @Test("Reps/distance and send-off are not swappable")
    func nonSwappable() {
        let text = "4x50 free fast @:40"
        #expect(SwimTextFieldResolver.field(in: text, at: index(of: "4x50", in: text)) == nil)
        #expect(SwimTextFieldResolver.field(in: text, at: index(of: "@:40", in: text)) == nil)
    }

    @Test("Every body axis on a line is found")
    func lineFields() {
        let text = "3x100 kick build r:15 w/fins"
        let kinds = SwimTextFieldResolver.fields(in: text).map(\.kind)
        #expect(kinds.contains(.activity))    // kick
        #expect(kinds.contains(.effortShape)) // build
        #expect(kinds.contains(.equipment))   // fins
    }

    // MARK: - Metadata

    @Test("Course / categories / date values resolve to metadata fields")
    func metadataFields() {
        let text = """
        # Test
        date: 2026-06-10
        course: scy
        categories: sprint, distance
        author: coach
        """
        let course = SwimTextFieldResolver.field(in: text, at: index(of: "scy", in: text))
        #expect(course?.kind == .course)
        #expect(course?.currentRaw == "scy")

        let date = SwimTextFieldResolver.field(in: text, at: index(of: "2026-06-10", in: text))
        #expect(date?.kind == .date)

        let cats = SwimTextFieldResolver.field(in: text, at: index(of: "sprint", in: text))
        #expect(cats?.kind == .categories)
        #expect(cats?.currentRaw == "sprint, distance")

        // A non-picker metadata key stays plain text.
        #expect(SwimTextFieldResolver.field(in: text, at: index(of: "coach", in: text)) == nil)
    }

    @Test("An empty metadata placeholder resolves with an empty range")
    func emptyPlaceholder() {
        let text = "date:\ncourse: scy"
        // Caret right after "date:"
        let caret = text.index(text.startIndex, offsetBy: 5)
        let field = SwimTextFieldResolver.field(in: text, at: caret)
        #expect(field?.kind == .date)
        #expect(field?.range.isEmpty == true)
        #expect(field?.currentRaw == "")
    }

    @Test("Line scoping returns only the caret line's fields")
    func lineScoping() {
        let text = "course: scy\n4x50 free fast"
        let onCourse = SwimTextFieldResolver.fields(in: text, onLineContaining: index(of: "scy", in: text))
        #expect(onCourse.map(\.kind) == [.course])

        let onSet = SwimTextFieldResolver.fields(in: text, onLineContaining: index(of: "free", in: text))
        #expect(Set(onSet.map(\.kind)) == [.stroke, .effortLevel])
    }

    // MARK: - Options

    @Test("Raw options match printer tokens")
    func rawOptions() {
        // Shapes use the abbreviations the printer emits, not the enum raw values.
        let shapes = SwimTextFieldResolver.rawOptions(for: .effortShape)
        #expect(shapes.contains("ns"))
        #expect(shapes.contains("vs"))
        #expect(!shapes.contains("negative-split"))
        #expect(Set(SwimTextFieldResolver.rawOptions(for: .course)) == ["scy", "scm", "lcm"])
        #expect(SwimTextFieldResolver.rawOptions(for: .date).isEmpty)
    }

    @Test("Every option list is alphabetical")
    func optionsAlphabetical() {
        let kinds: [SwimTextField.Kind] = [
            .stroke, .activity, .equipment, .effortLevel, .effortShape, .course, .categories,
        ]
        for kind in kinds {
            let options = SwimTextFieldResolver.rawOptions(for: kind)
            #expect(options == options.sorted(), "\(kind) options not alphabetical: \(options)")
        }
    }

    // MARK: - Swap round-trips

    @Test("Swapping a stroke token edits the text and re-parses")
    func swapRoundTrips() {
        let text = "4x50 free fast @:40"
        let field = SwimTextFieldResolver.field(in: text, at: index(of: "free", in: text))!
        var swapped = text
        swapped.replaceSubrange(field.range, with: "back")
        #expect(swapped == "4x50 back fast @:40")
        #expect(SwimTextLine.parseSet(swapped, groups: [])?.stroke == .back)
    }

    /// Every offered option, dropped into a bare set line, must survive a
    /// print→parse→print cycle — so a swap never silently vanishes. (A bare
    /// `100 swim` has no stroke, so the strokeless swim is preserved too.)
    @Test("Every body option survives a print round-trip")
    func optionsRoundTrip() {
        let bodyKinds: [SwimTextField.Kind] = [.stroke, .activity, .equipment, .effortLevel, .effortShape]
        for kind in bodyKinds {
            for raw in SwimTextFieldResolver.rawOptions(for: kind) {
                let line = "100 \(raw)"
                guard let set = SwimTextLine.parseSet(line, groups: []) else {
                    Issue.record("\(kind) option '\(raw)' did not parse as a set line")
                    continue
                }
                let printed = SwimTextLine.printSet(set)
                #expect(printed.contains(raw),
                        "\(kind) option '\(raw)' was lost — printed as '\(printed)'")
            }
        }
    }

    @Test("An explicit strokeless swim persists; swim with a stroke stays implicit")
    func swimPersistence() {
        #expect(SwimTextFieldResolver.rawOptions(for: .activity).contains("swim"))
        // A strokeless "swim" the user typed survives a reprint…
        let bare = SwimTextLine.parseSet("100 swim", groups: [])!
        #expect(bare.activity == .swim)
        #expect(bare.significantActivity == .swim)
        #expect(SwimTextLine.printSet(bare).contains("swim"))
        // …but "free swim" is redundant — swim alongside a stroke stays implicit.
        let withStroke = SwimTextLine.parseSet("100 free swim", groups: [])!
        #expect(withStroke.activity == .swim)
        #expect(withStroke.significantActivity == nil)
        #expect(!SwimTextLine.printSet(withStroke).contains("swim"))
    }
}

@Suite("Adding modifiers")
struct AddModifierTests {

    private func index(of needle: String, in text: String) -> String.Index {
        text.range(of: needle)!.lowerBound
    }

    private func applying(_ insertion: (index: String.Index, replacement: String)?, to text: String) -> String {
        guard let insertion else { return text }
        var out = text
        out.replaceSubrange(insertion.index..<insertion.index, with: insertion.replacement)
        return out
    }

    @Test("Addable modifiers exclude those already present")
    func addable() {
        let text = "4x100 free @1:30"
        let kinds = SwimTextFieldResolver.addableModifiers(in: text, onLineContaining: index(of: "free", in: text))
        #expect(!kinds.contains(.stroke))   // free is already there
        #expect(Set(kinds) == [.activity, .equipment, .effortShape, .effortLevel])
    }

    @Test("Non-set lines offer nothing to add")
    func nonSetLine() {
        let text = "course: scy"
        let caret = index(of: "scy", in: text)
        #expect(SwimTextFieldResolver.addableModifiers(in: text, onLineContaining: caret).isEmpty)
        #expect(SwimTextFieldResolver.modifierInsertion(of: "kick", in: text, onLineContaining: caret) == nil)
        #expect(SwimTextFieldResolver.commentInsertion(in: text, onLineContaining: caret) == nil)
    }

    @Test("A modifier inserts before the send-off and re-parses")
    func beforeSendoff() {
        let text = "4x100 free @1:30"
        let out = applying(
            SwimTextFieldResolver.modifierInsertion(of: "kick", in: text, onLineContaining: text.startIndex),
            to: text)
        #expect(out == "4x100 free kick @1:30")
        #expect(SwimTextLine.parseSet(out, groups: [])?.activity == .kick)
    }

    @Test("A modifier appends to a bare set line")
    func atEnd() {
        let text = "4x100 free"
        let out = applying(
            SwimTextFieldResolver.modifierInsertion(of: "fast", in: text, onLineContaining: text.endIndex),
            to: text)
        #expect(out == "4x100 free fast")
        #expect(SwimTextLine.parseSet(out, groups: [])?.effort?.level == .fast)
    }

    @Test("A modifier inserts before an existing note, not into it")
    func beforeNote() {
        let text = "4x100 free | strong finish"
        let out = applying(
            SwimTextFieldResolver.modifierInsertion(of: "build", in: text, onLineContaining: text.startIndex),
            to: text)
        #expect(out == "4x100 free build | strong finish")
    }

    @Test("Insertion targets the caret's line in a multi-line doc")
    func multiLine() {
        let text = "4x100 free @1:30\n4x50 kick"
        let out = applying(
            SwimTextFieldResolver.modifierInsertion(of: "fast", in: text, onLineContaining: index(of: "kick", in: text)),
            to: text)
        #expect(out == "4x100 free @1:30\n4x50 kick fast")
    }

    @Test("Comment inserts a pipe; skips lines that already have one")
    func comment() {
        let text = "4x100 free"
        let out = applying(
            SwimTextFieldResolver.commentInsertion(in: text, onLineContaining: text.endIndex),
            to: text)
        #expect(out == "4x100 free | ")
        // Parses cleanly (empty note is dropped).
        #expect(SwimTextLine.parseSet(out, groups: [])?.distance == 100)

        let noted = "4x100 free | hard"
        #expect(SwimTextFieldResolver.commentInsertion(in: noted, onLineContaining: noted.startIndex) == nil)
    }
}

@Suite("Equipment round-trip")
struct EquipmentRoundTripTests {

    @Test("Attached equipment parses for every kind, not just fins")
    func attachedEquipment() {
        #expect(SwimTextLine.parseSet("100 free w/fins", groups: [])?.equipment == [.fins])
        #expect(SwimTextLine.parseSet("100 free w/paddles", groups: [])?.equipment == [.paddles])
        #expect(SwimTextLine.parseSet("100 free w/buoy", groups: [])?.equipment == [.buoy])
    }

    @Test("A printed set with paddles round-trips through the parser")
    func paddlesRoundTrip() {
        var set = SwimSet(reps: 4, distance: 50, stroke: .free)
        set.equipment = [.paddles]
        let line = SwimTextLine.printSet(set)
        #expect(SwimTextLine.parseSet(line, groups: [])?.equipment == [.paddles])
    }
}
