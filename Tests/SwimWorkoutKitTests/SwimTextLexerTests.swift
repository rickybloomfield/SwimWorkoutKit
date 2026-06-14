// SPDX-License-Identifier: MIT

import Testing
@testable import SwimWorkoutKit

@Suite("SwimText lexer")
struct SwimTextLexerTests {

    /// (substring, kind) pairs for every token, in order — convenient for asserts.
    private func lex(_ text: String) -> [(String, SwimTextTokenKind)] {
        SwimTextLexer.tokens(in: text).map { (String(text[$0.range]), $0.kind) }
    }

    @Test("Reps, distance, stroke, effort, and send-off")
    func setLine() {
        let tokens = lex("4x50 free fast @:40")
        #expect(tokens.contains { $0 == ("4x50", .repsDistance) })
        #expect(tokens.contains { $0 == ("free", .stroke(.free)) })
        #expect(tokens.contains { $0 == ("fast", .effortLevel(.fast)) })
        #expect(tokens.contains { $0 == ("@:40", .sendoff) })
    }

    @Test("Bare distance is reps×distance")
    func bareDistance() {
        #expect(lex("300 choice easy").first.map { ($0.0, $0.1) }! == ("300", .repsDistance))
    }

    @Test("Per-lane send-off stays one token")
    func sendoffList() {
        let tokens = lex("3x300 free descend to 80% @4:40/4:50/5:00")
        #expect(tokens.contains { $0 == ("@4:40/4:50/5:00", .sendoff) })
        #expect(tokens.contains { $0 == ("descend", .effortShape(.descend)) })
        #expect(tokens.contains { $0 == ("80%", .percent) })
    }

    @Test("Rest token, not the word race")
    func restToken() {
        #expect(lex("100 kick easy r1:00").contains { $0 == ("r1:00", .rest) })
        // "race" must classify as an effort level, never as a rest token.
        #expect(lex("50 free race").contains { $0 == ("race", .effortLevel(.race)) })
    }

    @Test("Title, section, and metadata")
    func structureLines() {
        #expect(lex("# Friday — Sprint").first!.1 == .title)
        #expect(lex("== Warmup: 300").first! == ("== Warmup: 300", .section(name: "Warmup")))
        let meta = lex("course: scy")
        #expect(meta.contains { $0 == ("course", .metadataKey) })
        #expect(meta.contains { $0 == ("scy", .metadataValue) })
    }

    @Test("Repeat block markers and notes")
    func repeats() {
        #expect(lex("2x {").first! == ("2x {", .structure))
        #expect(lex("4/3x {").first! == ("4/3x {", .structure))
        let close = lex("} | between sets")
        #expect(close.contains { $0 == ("}", .structure) })
        #expect(close.contains { $0 == ("| between sets", .note) })
        #expect(lex("round 2: back").contains { $0 == ("round 2:", .structure) })
    }

    @Test("Bare section header is highlighted as a section")
    func bareSection() {
        #expect(lex("Cool Down: 200").first! == ("Cool Down: 200", .section(name: "Cool Down")))
        #expect(lex("Warmup").first! == ("Warmup", .section(name: "Warmup")))
        // A non-section "key: value" line is not colored as a section.
        #expect(!lex("course: scy").contains { if case .section = $0.1 { return true } else { return false } })
    }

    @Test("Segments and equipment inside a set")
    func segmentsAndEquipment() {
        let tokens = lex("3x100 as swim/kick/pull w/fins")
        #expect(tokens.contains { $0 == ("swim", .activity(.swim)) })
        #expect(tokens.contains { $0 == ("kick", .activity(.kick)) })
        #expect(tokens.contains { $0 == ("pull", .activity(.pull)) })
        #expect(tokens.contains { $0 == ("fins", .equipment(.fins)) })
    }

    @Test("Ranges are valid and non-overlapping")
    func rangesWellFormed() {
        let text = """
        # Workout
        == Main Set: 800
        8x50 free sprint @:45 r:10 | strong finish
        """
        let tokens = SwimTextLexer.tokens(in: text)
        var previousEnd = text.startIndex
        for token in tokens {
            #expect(token.range.lowerBound >= previousEnd)
            #expect(token.range.lowerBound < token.range.upperBound)
            previousEnd = token.range.upperBound
        }
    }
}
