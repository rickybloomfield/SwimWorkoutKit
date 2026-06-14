// SPDX-License-Identifier: MIT

import Foundation
import SwimWorkoutKit

/// Tiny CLI for the Open Swim Workout format.
///
///   swimtext to-json  <in.swimtext>   — SwimText → canonical JSON on stdout
///   swimtext to-text  <in.swimworkout> — JSON → SwimText on stdout
///   swimtext check    <file>           — parse + validate, print issues & totals

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    fail("usage: swimtext <to-json|to-text|check> <file>")
}
let command = arguments[1]
let url = URL(fileURLWithPath: arguments[2])
guard let raw = try? Data(contentsOf: url) else {
    fail("cannot read \(url.path)")
}

func parseAny() -> SwimWorkoutDocument {
    if url.pathExtension == "swimworkout" || url.pathExtension == "json" {
        do {
            return try JSONDecoder().decode(SwimWorkoutDocument.self, from: raw)
        } catch {
            fail("invalid JSON document: \(error)")
        }
    }
    guard let text = String(data: raw, encoding: .utf8) else {
        fail("not UTF-8 text")
    }
    return SwimTextParser.parse(text).document
}

switch command {
case "to-json":
    let document = parseAny()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try! encoder.encode(document)
    print(String(data: data, encoding: .utf8)!)

case "to-text":
    let document = parseAny()
    print(SwimTextPrinter.print(document), terminator: "")

case "check":
    let document = parseAny()
    if url.pathExtension == "swimtext" || url.pathExtension == "txt",
       let text = String(data: raw, encoding: .utf8) {
        let result = SwimTextParser.parse(text)
        for line in result.unparsedLines {
            print("unparsed line \(line.lineNumber): \(line.text)")
        }
    }
    let issues = WorkoutValidator.validate(document)
    for issue in issues {
        print(issue)
    }
    let workout = document.workout
    for totals in WorkoutCalculator.totals(of: workout) {
        let group = totals.groupID ?? "—"
        var line = "group \(group): \(totals.distance) \(workout.course.unit.rawValue)"
        if let duration = totals.durationSeconds {
            let mins = duration / 60
            line += String(format: ", ~%d:%02d%@", mins, duration % 60, totals.durationIsComplete ? "" : " (partial)")
        }
        print(line)
    }
    if issues.contains(where: { $0.severity == .error }) {
        exit(2)
    }

default:
    fail("unknown command: \(command)")
}
