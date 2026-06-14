// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import SwimWorkoutKit

@Suite("Validator")
struct ValidatorTests {

    @Test("Total mismatch produces a warning; matching any group passes")
    func totalReconciliation() {
        var workout = Workout(
            groups: [SpeedGroup(id: "A"), SpeedGroup(id: "B")],
            sections: [
                WorkoutSection(name: "Main", items: [
                    .set(SwimSet(reps: 4, distance: 100, perGroup: ["B": GroupOverride(reps: 3)]))
                ])
            ],
            statedTotal: 300
        )
        // B computes 300 → no warning even though A is 400.
        #expect(!WorkoutValidator.validate(workout).contains { $0.code == "workout-total-mismatch" })
        workout.statedTotal = 500
        #expect(WorkoutValidator.validate(workout).contains { $0.code == "workout-total-mismatch" })
    }

    @Test("Segment sums must equal the rep distance")
    func segmentSum() {
        let workout = Workout(sections: [
            WorkoutSection(name: "Main", items: [
                .set(SwimSet(reps: 1, distance: 100, segments: [
                    Segment(distance: 25), Segment(distance: 25),
                ]))
            ])
        ])
        #expect(WorkoutValidator.validate(workout).contains { $0.code == "segment-sum-mismatch" })
    }

    @Test("Unknown group references are errors")
    func unknownGroup() {
        let workout = Workout(
            groups: [SpeedGroup(id: "A")],
            sections: [
                WorkoutSection(name: "Main", items: [
                    .set(SwimSet(reps: 1, distance: 100,
                                 interval: Interval(mode: .sendoff, sendoffs: ["Z": SwimTime(seconds: 90)])))
                ])
            ]
        )
        #expect(WorkoutValidator.validate(workout).contains { $0.code == "unknown-group" })
    }

    @Test("Distances that don't fit the course produce a warning")
    func courseMismatch() {
        let workout = Workout(
            course: .lcm,
            sections: [
                WorkoutSection(name: "Main", items: [.set(SwimSet(reps: 4, distance: 75))])
            ]
        )
        #expect(WorkoutValidator.validate(workout).contains { $0.code == "distance-course-mismatch" })
    }
}

@Suite("Codable")
struct CodableTests {

    @Test("JSON round-trip preserves the document")
    func jsonRoundTrip() throws {
        let original = SwimWorkoutDocument(workout: Workout(
            title: "Test",
            course: .scy,
            categories: ["sprint"],
            groups: [SpeedGroup(id: "A", label: "Fast", basePace100: SwimTime(seconds: 75))],
            sections: [
                WorkoutSection(name: "Main", statedDistance: 600, items: [
                    .set(SwimSet(
                        reps: 4, distance: 100, stroke: .free,
                        effort: Effort(shape: .descend, percent: 90),
                        interval: Interval(mode: .sendoff, sendoffs: ["A": SwimTime(seconds: 90)],
                                           targetRest: SwimTime(seconds: 15))
                    )),
                    .repeatBlock(RepeatBlock(rounds: 2, items: [
                        .set(SwimSet(reps: 2, distance: 50, activity: .kick)),
                        .rest(RestItem(duration: SwimTime(seconds: 30))),
                    ])),
                    .note(NoteItem(text: "rest extra after the last one")),
                ])
            ],
            statedTotal: 800
        ))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SwimWorkoutDocument.self, from: data)
        #expect(decoded == original)
    }

    @Test("Location round-trips with and without coordinates")
    func locationRoundTrip() throws {
        let mapped = SwimWorkoutDocument(workout: Workout(
            title: "At the pool",
            location: WorkoutLocation(
                name: "Community Aquatic Center",
                latitude: 0.0, longitude: 0.0,
                address: "123 Main St, Anytown"
            )
        ))
        let mappedDecoded = try JSONDecoder().decode(
            SwimWorkoutDocument.self, from: JSONEncoder().encode(mapped))
        #expect(mappedDecoded == mapped)

        let nameOnly = SwimWorkoutDocument(workout: Workout(
            location: WorkoutLocation(name: "Backyard pool")))
        let nameOnlyDecoded = try JSONDecoder().decode(
            SwimWorkoutDocument.self, from: JSONEncoder().encode(nameOnly))
        #expect(nameOnlyDecoded == nameOnly)
        #expect(nameOnlyDecoded.workout.location?.hasCoordinates == false)
    }

    @Test("A pre-location 0.1 document still decodes")
    func backwardCompatibleWithoutLocation() throws {
        let legacy = #"{"format":"open-swim-workout","version":"0.1","workout":{"course":{"length":25,"unit":"yd"},"categories":[],"tags":[],"groups":[],"sections":[]}}"#
        let decoded = try JSONDecoder().decode(SwimWorkoutDocument.self, from: Data(legacy.utf8))
        #expect(decoded.workout.location == nil)
    }

    @Test("Discriminators encode as set/repeat/rest/note")
    func discriminators() throws {
        let document = SwimWorkoutDocument(workout: Workout(sections: [
            WorkoutSection(name: "Main", items: [
                .set(SwimSet(reps: 1, distance: 100)),
                .repeatBlock(RepeatBlock(rounds: 2, items: [])),
                .rest(RestItem(duration: SwimTime(seconds: 60))),
                .note(NoteItem(text: "hi")),
            ])
        ]))
        let data = try JSONEncoder().encode(document)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains(#""type":"set""#))
        #expect(json.contains(#""type":"repeat""#))
        #expect(json.contains(#""type":"rest""#))
        #expect(json.contains(#""type":"note""#))
    }

    @Test("Unknown format or major version is rejected")
    func versionGate() throws {
        let bad = #"{"format":"other-format","version":"0.1","workout":{"course":{"length":25,"unit":"yd"},"categories":[],"tags":[],"groups":[],"sections":[]}}"#
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(SwimWorkoutDocument.self, from: Data(bad.utf8))
        }
        let futureMajor = #"{"format":"open-swim-workout","version":"1.0","workout":{"course":{"length":25,"unit":"yd"},"categories":[],"tags":[],"groups":[],"sections":[]}}"#
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(SwimWorkoutDocument.self, from: Data(futureMajor.utf8))
        }
    }
}
