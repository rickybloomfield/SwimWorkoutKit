// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import SwimWorkoutKit

/// The JSON wire format remote providers (Claude API) decode into, and the
/// schema they constrain generation with. The on-device path has its own
/// `@Generable` mirror of the same shape.
@Suite("AIDraftWire")
struct AIDraftWireTests {

    /// A representative model reply: optional fields sometimes present,
    /// sometimes absent — exactly what schema-constrained output produces.
    private let sampleJSON = """
    {
      "title": "Fly Focus Friday",
      "sections": [
        {
          "name": "Warmup",
          "blocks": [
            {"rounds": 1, "sets": [
              {"reps": 1, "distance": 300, "stroke": "free", "effort": "easy"},
              {"reps": 4, "distance": 50, "activity": "kick", "restSeconds": 15}
            ]}
          ]
        },
        {
          "name": "Main Set",
          "blocks": [
            {"rounds": 2, "sets": [
              {"reps": 4, "distance": 100, "stroke": "fly", "activity": "swim",
               "effort": "strong", "shape": "descend", "restSeconds": 20,
               "note": "last one fast"}
            ]}
          ]
        },
        {
          "name": "Cool Down",
          "blocks": [
            {"rounds": 1, "sets": [{"reps": 1, "distance": 200, "stroke": "choice", "effort": "easy"}]}
          ]
        }
      ]
    }
    """

    @Test func decodesModelJSONIntoDraft() throws {
        let draft = try AIDraftWire.decodeDraft(fromJSON: Data(sampleJSON.utf8))

        #expect(draft.title == "Fly Focus Friday")
        #expect(draft.sections.count == 3)
        #expect(draft.sections[1].blocks[0].rounds == 2)

        let mainSet = draft.sections[1].blocks[0].sets[0]
        #expect(mainSet.reps == 4)
        #expect(mainSet.distance == 100)
        #expect(mainSet.stroke == "fly")
        #expect(mainSet.shape == "descend")
        #expect(mainSet.restSeconds == 20)
        #expect(mainSet.note == "last one fast")

        // Omitted optionals decode as nil, not as a failure.
        let warmupSwim = draft.sections[0].blocks[0].sets[0]
        #expect(warmupSwim.activity == nil)
        #expect(warmupSwim.restSeconds == nil)
    }

    @Test func decodedDraftConvertsToARealWorkout() throws {
        let draft = try AIDraftWire.decodeDraft(fromJSON: Data(sampleJSON.utf8))
        let groups = [
            SpeedGroup(id: "A", label: "Lane 1", basePace100: SwimTime(parsing: "1:20")),
            SpeedGroup(id: "B", label: "Lane 2", basePace100: SwimTime(parsing: "1:40")),
        ]
        let workout = AIDraftConverter.workout(
            from: draft, course: .scy, groups: groups, targetDistance: 2000
        )
        // The scaler lands near the target within structural 25s — exactness
        // is the scaler's own tests' job; here we care that decode → convert
        // yields a real workout.
        let distance = WorkoutCalculator.distance(of: workout, group: "A")
        #expect((1600...2400).contains(distance))
        #expect(workout.title == "Fly Focus Friday")
    }

    @Test func schemaIsValidJSONAndLocksDownEveryObject() throws {
        let data = Data(AIDraftWire.jsonSchemaString.utf8)
        let root = try JSONSerialization.jsonObject(with: data)
        let rootObject = try #require(root as? [String: Any])

        // Hosted structured outputs require additionalProperties: false and
        // an explicit required list on every object node — walk the tree.
        var objectCount = 0
        func check(_ node: Any) throws {
            if let object = node as? [String: Any] {
                if object["type"] as? String == "object" {
                    objectCount += 1
                    #expect(object["additionalProperties"] as? Bool == false)
                    #expect(object["required"] as? [String] != nil)
                    // No unsupported numeric constraints anywhere.
                    #expect(object["minimum"] == nil && object["maximum"] == nil)
                }
                for value in object.values { try check(value) }
            } else if let array = node as? [Any] {
                for value in array { try check(value) }
            }
        }
        try check(rootObject)
        #expect(objectCount == 4) // workout, section, block, set
    }

    @Test func schemaFieldsMatchTheWireFormat() throws {
        // Decoding a value generated *from* the schema's property names must
        // round-trip; guard against schema/Codable drift.
        let data = Data(AIDraftWire.jsonSchemaString.utf8)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        func properties(_ node: [String: Any], path: [String]) -> [String: Any]? {
            var current = node
            for key in path {
                guard let next = current[key] as? [String: Any] else { return nil }
                current = next
            }
            return current["properties"] as? [String: Any]
        }

        let setProperties = try #require(properties(
            root,
            path: ["properties", "sections", "items", "properties", "blocks",
                   "items", "properties", "sets", "items"]
        ))
        #expect(Set(setProperties.keys) == [
            "reps", "distance", "stroke", "activity", "effort", "shape",
            "restSeconds", "note",
        ])
    }
}
