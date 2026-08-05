// SPDX-License-Identifier: MIT

import Testing

@testable import SwimWorkoutKit

@Suite("SwimText palette")
struct SwimTextPaletteTests {

    // MARK: - Section classification

    @Test("Warmup headings, in the spellings coaches actually use", arguments: [
        "Warmup", "Warm-up", "Warm Up", "WARMUP", "Loosen", "Loosen Up",
        "Pre-set", "Preset", "warmup: 600",
    ])
    func warmupHeadings(name: String) {
        #expect(SwimTextPalette.sectionRole(for: name) == .sectionWarmup)
    }

    @Test("Cool-down headings", arguments: [
        "Cool Down", "Cooldown", "COOL DOWN", "cool-down", "Warm Down", "Warmdown",
    ])
    func cooldownHeadings(name: String) {
        #expect(SwimTextPalette.sectionRole(for: name) == .sectionCooldown)
    }

    /// "Warm down" is a cool-down — it is what most swimmers call one. The
    /// substring check for "warm" used to claim it first, so a section headed
    /// *Warm Down* was drawn in the warmup colour at the bottom of the sheet.
    /// The down-check now wins, which is the whole reason these two live in one
    /// function rather than two independent `contains` passes.
    @Test("A warm-down is a cool-down, not a warmup")
    func warmDownIsCooldown() {
        #expect(SwimTextPalette.sectionRole(for: "Warm Down") == .sectionCooldown)
        #expect(SwimTextPalette.sectionRole(for: "Warm-down") == .sectionCooldown)
        // …and a plain warmup is still a warmup.
        #expect(SwimTextPalette.sectionRole(for: "Warmup") == .sectionWarmup)
    }

    @Test("Everything else is the default section", arguments: [
        "Main Set", "Main", "Kick Set", "Sprint Set", "Pull", "Threshold",
    ])
    func defaultHeadings(name: String) {
        #expect(SwimTextPalette.sectionRole(for: name) == .sectionDefault)
    }

    // MARK: - Tokens

    @Test("Every token kind resolves to a role")
    func everyTokenKindHasARole() {
        let kinds: [SwimTextTokenKind] = [
            .title, .section(name: "Warmup"), .metadataKey, .metadataValue,
            .repsDistance, .stroke(.free), .activity(.kick), .effortLevel(.sprint),
            .effortShape(.build), .percent, .equipment(.fins), .sendoff, .rest,
            .time, .note, .structure,
        ]
        for kind in kinds {
            // Resolution is total: no token may fall through to a default the
            // renderer would draw as plain text.
            _ = SwimTextPalette.role(for: kind)
        }
        #expect(SwimTextPalette.role(for: .title) == .title)
        #expect(SwimTextPalette.role(for: .stroke(.fly)) == .stroke(.fly))
        // A section token carries its name, and the role follows the name.
        #expect(SwimTextPalette.role(for: .section(name: "Cool Down")) == .sectionCooldown)
    }

    @Test("The four load-bearing tokens are emphasized")
    func emphasis() {
        #expect(SwimTextPalette.isEmphasized(.title))
        #expect(SwimTextPalette.isEmphasized(.section(name: "Main Set")))
        #expect(SwimTextPalette.isEmphasized(.repsDistance))
        #expect(SwimTextPalette.isEmphasized(.sendoff))

        #expect(!SwimTextPalette.isEmphasized(.note))
        #expect(!SwimTextPalette.isEmphasized(.stroke(.free)))
        #expect(!SwimTextPalette.isEmphasized(.percent))
    }

    // MARK: - Hues

    @Test("Every stroke, activity and effort level has a hue")
    func everyAxisValueHasAHue() {
        for stroke in Stroke.allCases {
            _ = SwimTextRole.stroke(stroke).defaultHue
        }
        for activity in Activity.allCases {
            _ = SwimTextRole.activity(activity).defaultHue
        }
        for level in EffortLevel.allCases {
            _ = SwimTextRole.effortLevel(level).defaultHue
        }
    }

    /// The ramp readers already know. Effort is the one axis where the hue
    /// ordering carries meaning rather than just distinguishing values.
    @Test("Effort runs green → yellow → red")
    func effortRamp() {
        #expect(SwimTextRole.effortLevel(.easy).defaultHue == .green)
        #expect(SwimTextRole.effortLevel(.smooth).defaultHue == .green)
        #expect(SwimTextRole.effortLevel(.moderate).defaultHue == .yellow)
        #expect(SwimTextRole.effortLevel(.strong).defaultHue == .yellow)
        #expect(SwimTextRole.effortLevel(.fast).defaultHue == .red)
        #expect(SwimTextRole.effortLevel(.max).defaultHue == .red)
    }

    @Test("The IM family shares one hue")
    func imFamilyMatches() {
        let im = SwimTextRole.stroke(.im).defaultHue
        #expect(SwimTextRole.stroke(.imo).defaultHue == im)
        #expect(SwimTextRole.stroke(.rimo).defaultHue == im)
    }

    // MARK: - Wire form

    /// These strings are read by code that is not compiled with this package —
    /// the Android renderer maps them to its own colours — so a rename is a
    /// breaking change and this test is where that gets noticed.
    @Test("Wire names are stable and unique")
    func wireNames() {
        #expect(SwimTextRole.plain.wireName == "plain")
        #expect(SwimTextRole.sectionWarmup.wireName == "sectionWarmup")
        #expect(SwimTextRole.stroke(.free).wireName == "stroke.free")
        #expect(SwimTextRole.activity(.kick).wireName == "activity.kick")
        #expect(SwimTextRole.effortLevel(.sprint).wireName == "effort.sprint")

        var seen = Set<String>()
        var roles: [SwimTextRole] = [
            .plain, .title, .repsDistance, .sendoff, .rest, .time, .note, .structure,
            .metadataKey, .metadataValue, .effortShape, .percent, .equipment,
            .sectionWarmup, .sectionCooldown, .sectionDefault,
        ]
        roles += Stroke.allCases.map(SwimTextRole.stroke)
        roles += Activity.allCases.map(SwimTextRole.activity)
        roles += EffortLevel.allCases.map(SwimTextRole.effortLevel)

        for role in roles {
            #expect(seen.insert(role.wireName).inserted, "duplicate wire name: \(role.wireName)")
        }
    }
}
