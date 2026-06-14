// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import SwimWorkoutKit

/// Corpus tests over the transcribed example workouts in the bundled Fixtures directory.
///
/// Every fixture must: parse with no unparsed lines, validate with no errors,
/// reconcile its stated totals (the printed totals are our checksum), and be
/// stable under print → parse → print.
@Suite("Fixture corpus")
struct FixtureCorpusTests {

    static func fixtureURLs() throws -> [URL] {
        let directory = try #require(
            Bundle.module.url(forResource: "Fixtures", withExtension: nil),
            "Fixtures directory missing from test bundle"
        )
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )
        return files.filter { $0.pathExtension == "swimtext" }.sorted { $0.path < $1.path }
    }

    @Test("Corpus is present")
    func corpusPresent() throws {
        let urls = try Self.fixtureURLs()
        #expect(urls.count >= 12, "Expected the transcribed corpus, found \(urls.count) fixtures")
    }

    @Test("Every fixture parses completely", arguments: try fixtureURLs())
    func parsesCompletely(url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        let result = SwimTextParser.parse(text)
        #expect(
            result.unparsedLines.isEmpty,
            "\(url.lastPathComponent): unparsed lines \(result.unparsedLines.map { "\($0.lineNumber): \($0.text)" })"
        )
    }

    @Test("Every fixture validates without errors", arguments: try fixtureURLs())
    func validates(url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        let document = SwimTextParser.parse(text).document
        let issues = WorkoutValidator.validate(document)
        let errors = issues.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(url.lastPathComponent): \(errors)")
    }

    @Test("Stated totals reconcile", arguments: try fixtureURLs())
    func totalsReconcile(url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        let document = SwimTextParser.parse(text).document
        let issues = WorkoutValidator.validate(document)
        let mismatches = issues.filter {
            $0.code == "workout-total-mismatch" || $0.code == "section-total-mismatch"
        }
        #expect(mismatches.isEmpty, "\(url.lastPathComponent): \(mismatches)")
    }

    @Test("Print → parse → print is stable", arguments: try fixtureURLs())
    func printStability(url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        let first = SwimTextParser.parse(text).document
        let printed = SwimTextPrinter.print(first)
        let reparsed = SwimTextParser.parse(printed)
        #expect(
            reparsed.unparsedLines.isEmpty,
            "\(url.lastPathComponent): printer emitted unparseable lines \(reparsed.unparsedLines)"
        )
        let printedAgain = SwimTextPrinter.print(reparsed.document)
        #expect(printed == printedAgain, "\(url.lastPathComponent): print not stable")
    }

    @Test("JSON encoding round-trips for the corpus", arguments: try fixtureURLs())
    func jsonRoundTrip(url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        let document = SwimTextParser.parse(text).document
        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(SwimWorkoutDocument.self, from: data)
        #expect(decoded == document)
    }
}
