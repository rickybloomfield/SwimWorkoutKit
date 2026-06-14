// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import SwimWorkoutKit

@Suite("SwimClustering")
struct SwimClusteringTests {

    private let base = Date(timeIntervalSince1970: 1_750_000_000)

    private func swim(
        _ id: String, startMinutes: Double, durationMinutes: Double,
        meters: Double? = nil, bundle: String, name: String? = nil
    ) -> RecordedSwim {
        RecordedSwim(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000\(id)")!,
            start: base.addingTimeInterval(startMinutes * 60),
            end: base.addingTimeInterval((startMinutes + durationMinutes) * 60),
            distanceMeters: meters,
            sourceBundleID: bundle,
            sourceName: name ?? bundle
        )
    }

    private let watch = "com.apple.health.workout"
    private let form = "com.formswim.app"

    @Test("Watch + FORM recording the same swim collapse to one event")
    func watchPlusForm() {
        let swims = [
            swim("01", startMinutes: 0, durationMinutes: 62, meters: 2750, bundle: watch, name: "Apple Watch"),
            swim("02", startMinutes: 1, durationMinutes: 60, meters: 2700, bundle: form, name: "FORM"),
            swim("03", startMinutes: 24 * 60, durationMinutes: 45, meters: 2000, bundle: watch),
        ]
        let events = SwimClustering.events(from: swims, sourcePriority: [form, watch])
        #expect(events.count == 2)
        let dupe = events.first { $0.hasDuplicates }
        #expect(dupe != nil)
        // FORM preferred per priority.
        #expect(dupe?.representative.sourceBundleID == form)
        // Newest first.
        #expect(events[0].start > events[1].start)
    }

    @Test("Priority order decides; override beats priority")
    func priorityAndOverride() {
        let swims = [
            swim("01", startMinutes: 0, durationMinutes: 60, meters: 2750, bundle: watch),
            swim("02", startMinutes: 2, durationMinutes: 58, meters: 2700, bundle: form),
        ]
        let watchFirst = SwimClustering.events(from: swims, sourcePriority: [watch, form])
        #expect(watchFirst[0].representative.sourceBundleID == watch)

        let id = watchFirst[0].id
        let overridden = SwimClustering.events(
            from: swims, sourcePriority: [watch, form],
            overrides: [id: swims[1].id]
        )
        #expect(overridden[0].representative.sourceBundleID == form)
    }

    @Test("Disjoint swims on the same day stay separate")
    func disjointStaySeparate() {
        let swims = [
            swim("01", startMinutes: 0, durationMinutes: 45, bundle: watch),
            swim("02", startMinutes: 240, durationMinutes: 45, bundle: watch),
        ]
        let events = SwimClustering.events(from: swims, sourcePriority: [])
        #expect(events.count == 2)
    }

    @Test("A split recording joins the long recording's event")
    func splitRecordingJoins() {
        let swims = [
            swim("01", startMinutes: 0, durationMinutes: 90, meters: 4000, bundle: watch),
            swim("02", startMinutes: 0, durationMinutes: 40, meters: 1800, bundle: form),
            swim("03", startMinutes: 50, durationMinutes: 40, meters: 1900, bundle: form),
        ]
        let events = SwimClustering.events(from: swims, sourcePriority: [watch])
        #expect(events.count == 1)
        #expect(events[0].swims.count == 3)
        #expect(events[0].representative.sourceBundleID == watch)
    }

    @Test("Unknown sources rank after listed ones; distance breaks ties")
    func unknownSourceRanking() {
        let swims = [
            swim("01", startMinutes: 0, durationMinutes: 60, meters: 2000, bundle: "com.garmin.connect"),
            swim("02", startMinutes: 1, durationMinutes: 59, meters: 2750, bundle: "com.other.app"),
        ]
        // Neither listed → longer distance wins.
        let events = SwimClustering.events(from: swims, sourcePriority: [watch, form])
        #expect(events[0].representative.distanceMeters == 2750)
    }

    @Test("Event ids are stable regardless of input order")
    func stableIDs() {
        let a = swim("01", startMinutes: 0, durationMinutes: 60, bundle: watch)
        let b = swim("02", startMinutes: 1, durationMinutes: 59, bundle: form)
        let id1 = SwimClustering.events(from: [a, b], sourcePriority: [])[0].id
        let id2 = SwimClustering.events(from: [b, a], sourcePriority: [])[0].id
        #expect(id1 == id2)
    }

    @Test("Brief accidental overlap below threshold does not merge")
    func briefOverlap() {
        // 45-minute swims overlapping by 4 minutes, starts 41 minutes apart.
        let swims = [
            swim("01", startMinutes: 0, durationMinutes: 45, bundle: watch),
            swim("02", startMinutes: 41, durationMinutes: 45, bundle: form),
        ]
        let events = SwimClustering.events(from: swims, sourcePriority: [])
        #expect(events.count == 2)
    }
}
