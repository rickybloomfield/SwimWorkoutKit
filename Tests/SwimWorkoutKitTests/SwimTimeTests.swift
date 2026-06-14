// SPDX-License-Identifier: MIT

import Testing
@testable import SwimWorkoutKit

@Suite("SwimTime")
struct SwimTimeTests {

    @Test("Parses minute:second, leading-colon, and bare-second forms")
    func parsing() {
        #expect(SwimTime(parsing: "1:30")?.seconds == 90)
        #expect(SwimTime(parsing: ":35")?.seconds == 35)
        #expect(SwimTime(parsing: "35")?.seconds == 35)
        #expect(SwimTime(parsing: "12:00")?.seconds == 720)
        #expect(SwimTime(parsing: "0:05")?.seconds == 5)
        #expect(SwimTime(parsing: " 2:00 ")?.seconds == 120)
    }

    @Test("Rejects malformed input")
    func rejects() {
        #expect(SwimTime(parsing: "") == nil)
        #expect(SwimTime(parsing: "1:75") == nil)
        #expect(SwimTime(parsing: "abc") == nil)
        #expect(SwimTime(parsing: "1:2:3") == nil)
        #expect(SwimTime(parsing: "-10") == nil)
    }

    @Test("Canonical notation")
    func notation() {
        #expect(SwimTime(seconds: 90).notation == "1:30")
        #expect(SwimTime(seconds: 35).notation == ":35")
        #expect(SwimTime(seconds: 5).notation == ":05")
        #expect(SwimTime(seconds: 600).notation == "10:00")
    }

    @Test("Arithmetic and comparison")
    func arithmetic() {
        #expect(SwimTime(seconds: 60) + SwimTime(seconds: 30) == SwimTime(seconds: 90))
        #expect(SwimTime(seconds: 40) * 4 == SwimTime(seconds: 160))
        #expect(SwimTime(seconds: 59) < SwimTime(seconds: 60))
    }
}
