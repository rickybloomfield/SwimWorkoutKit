// SPDX-License-Identifier: MIT

import Testing
@testable import SwimWorkoutKit

@Suite("Set line parsing")
struct SetLineParserTests {

    private func parseSet(_ line: String, groups: [SpeedGroup] = []) -> SwimSet? {
        SetLineParser.parse(line, groups: groups)
    }

    @Test("Basic reps x distance with stroke and activity")
    func basic() throws {
        let set = try #require(parseSet("4x50 kick choice"))
        #expect(set.reps == 4)
        #expect(set.distance == 50)
        #expect(set.activity == .kick)
        #expect(set.stroke == .choice)
    }

    @Test("Bare distance means one rep")
    func bareDistance() throws {
        let set = try #require(parseSet("300 free"))
        #expect(set.reps == 1)
        #expect(set.distance == 300)
        #expect(set.stroke == .free)
    }

    @Test("Multi-group send-offs map to groups in order")
    func multiGroupSendoffs() throws {
        let set = try #require(parseSet("100 free sprint @1:30/1:45/2:00 (~:15 rest)"))
        let interval = try #require(set.interval)
        #expect(interval.mode == .sendoff)
        #expect(interval.sendoffs?["A"] == SwimTime(seconds: 90))
        #expect(interval.sendoffs?["B"] == SwimTime(seconds: 105))
        #expect(interval.sendoffs?["C"] == SwimTime(seconds: 120))
        #expect(interval.targetRest == SwimTime(seconds: 15))
        #expect(set.effort?.level == .sprint)
    }

    @Test("Open-ended send-off list")
    func openEnded() throws {
        let set = try #require(parseSet("5x100 free 80% be4-5 @1:15/1:20/1:25+"))
        #expect(set.interval?.openEnded == true)
        #expect(set.effort?.percent == 80)
        #expect(set.breath?.pattern == "4-5")
    }

    @Test("Send-off offset notation expands cumulatively")
    func sendoffOffsets() throws {
        let set = try #require(parseSet("4x100 free descend 1-4 @1:30 (+1:00)"))
        #expect(set.interval?.sendoffs?["A"] == SwimTime(seconds: 90))
        #expect(set.interval?.sendoffs?["B"] == SwimTime(seconds: 150))
        #expect(set.effort?.shape == .descend)
        #expect(set.effort?.detail == "1-4")
    }

    @Test("Rest-based interval")
    func restInterval() throws {
        let set = try #require(parseSet("200 kick easy r1:00 | flutter on back"))
        #expect(set.interval?.mode == .rest)
        #expect(set.interval?.rest == SwimTime(seconds: 60))
        #expect(set.effort?.level == .easy)
        #expect(set.note == "flutter on back")
    }

    @Test("Rest alongside a send-off becomes the designed rest")
    func restWithSendoff() throws {
        let set = try #require(parseSet("4x75 imo @1:30 r:20"))
        #expect(set.interval?.mode == .sendoff)
        #expect(set.interval?.targetRest == SwimTime(seconds: 20))
    }

    @Test("Explicit segments with distances")
    func segments() throws {
        let set = try #require(parseSet("4x75 breast (25 drill/25 build/25 fast) @1:30/1:45/2:00"))
        let segments = try #require(set.segments)
        #expect(segments.count == 3)
        #expect(segments[0].activity == .drill)
        #expect(segments[2].effortLevel == .fast)
        #expect(set.stroke == .breast)
    }

    @Test("as-clause with count == reps becomes perRep")
    func asClausePerRep() throws {
        let set = try #require(parseSet("3x100 as swim/kick/pull"))
        let perRep = try #require(set.perRep)
        #expect(perRep.count == 3)
        #expect(perRep[0].activity == .swim)
        #expect(perRep[1].activity == .kick)
        #expect(perRep[2].activity == .pull)
        #expect(set.activity == .mixed)
    }

    @Test("as-clause dividing the distance becomes segments")
    func asClauseSegments() throws {
        let set = try #require(parseSet("4x75 imo as kick/drill/swim r:20"))
        let segments = try #require(set.segments)
        #expect(segments.count == 3)
        #expect(segments.allSatisfy { $0.distance == 25 })
        #expect(set.interval?.rest == SwimTime(seconds: 20))
    }

    @Test("Percent ranges, max rest hints, equipment")
    func percentAndHints() throws {
        let set = try #require(parseSet("8x25 fly w/fins 75-80% @:30 (max :40 rest)"))
        #expect(set.effort?.percent == 75)
        #expect(set.effort?.percentMax == 80)
        #expect(set.equipment == [.fins])
        #expect(set.interval?.maxRest == SwimTime(seconds: 40))
    }

    @Test("descend to N% captures target percent")
    func descendTo() throws {
        let set = try #require(parseSet("3x300 free descend to 80% @4:40/4:50/5:00"))
        #expect(set.effort?.shape == .descend)
        #expect(set.effort?.percent == 80)
    }

    @Test("all out maps to max")
    func allOut() throws {
        let set = try #require(parseSet("100 im all out r2:00"))
        #expect(set.effort?.level == .max)
        #expect(set.stroke == .im)
    }

    @Test("Unknown words are preserved as a note")
    func unknownWords() throws {
        let set = try #require(parseSet("300 free | every 3rd length something different"))
        #expect(set.note == "every 3rd length something different")
        #expect(set.sourceText == "300 free | every 3rd length something different")
    }

    @Test("@Lane is preserved as a send-off note")
    func atLane() throws {
        let set = try #require(parseSet("3x200 @Lane as loosen/im/free"))
        #expect(set.interval?.mode == .sendoff)
        #expect(set.interval?.note == "send-off by lane")
        #expect(set.perRep?.count == 3)
    }

    @Test("Lines without a leading distance are rejected")
    func rejectsNonSet() {
        #expect(parseSet("every 3rd length fast") == nil)
        #expect(parseSet("REPEAT") == nil)
    }
}
