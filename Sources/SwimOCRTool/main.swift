// SPDX-License-Identifier: MIT

import Foundation
import SwimWorkoutKit
#if canImport(Vision)
import Vision
#endif
#if canImport(ImageIO)
import ImageIO
#endif

/// Headless OCR harness for the import pipeline:
///
///   swimocr <image> [--raw]
///
/// Prints assembled SwimText (or raw ordered OCR lines with --raw), then a
/// parse/validation report. Lets us tune the pipeline against a directory of
/// workout photos without a simulator.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

#if canImport(Vision) && canImport(ImageIO)

@available(macOS 15.0, *)
func run() async {
    let arguments = CommandLine.arguments
    guard arguments.count >= 2 else {
        fail("usage: swimocr <image> [--raw]")
    }
    let imageURL = URL(fileURLWithPath: arguments[1])
    let rawOnly = arguments.contains("--raw")

    guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCache: true
          ] as CFDictionary)
    else {
        fail("cannot read image: \(imageURL.path)")
    }

    var request = RecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true

    let observations: [RecognizedTextObservation]
    do {
        observations = try await request.perform(on: cgImage)
    } catch {
        fail("OCR failed: \(error)")
    }

    let fragments = observations.compactMap { observation -> OCRTextAssembler.Fragment? in
        guard let candidate = observation.topCandidates(1).first else { return nil }
        return OCRTextAssembler.Fragment(
            text: candidate.string,
            bounds: observation.boundingBox.cgRect
        )
    }

    let lines = OCRTextAssembler.orderLines(fragments)

    if rawOnly {
        for line in lines { print(line) }
        return
    }

    let swimText = OCRTextAssembler.assembleSwimText(from: lines)
    print("===== SwimText =====")
    print(swimText)

    let result = SwimTextParser.parse(swimText)
    let workout = OCRTextAssembler.fillEmptyStatedSections(result.document.workout)
    print("===== Report =====")
    print("title: \(workout.title ?? "—")")
    print("sections: \(workout.sections.count)")
    if let stated = workout.statedTotal {
        print("stated total: \(stated)")
    }
    for totals in WorkoutCalculator.totals(of: workout) {
        print("group \(totals.groupID ?? "—"): \(totals.distance)")
    }
    if !result.unparsedLines.isEmpty {
        print("unparsed lines (\(result.unparsedLines.count)):")
        for line in result.unparsedLines {
            print("  \(line.lineNumber): \(line.text)")
        }
    }
    let issues = WorkoutValidator.validate(workout)
    for issue in issues {
        print(issue)
    }
}

if #available(macOS 15.0, *) {
    await run()
} else {
    fail("swimocr requires macOS 15 or newer")
}

#else
fail("swimocr requires Vision (run on macOS)")
#endif
