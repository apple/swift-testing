//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

@testable @_spi(Experimental) @_spi(ForToolsIntegrationOnly) import Testing

@Suite("Parallelization Trait Tests", .tags(.traitRelated))
struct ParallelizationTraitTests {
  @Test(".serialized trait serializes parameterized test", arguments: await [
    Runner.Plan(selecting: OuterSuite.self),
    Runner.Plan(selecting: "globalParameterized(i:)"),
  ])
  func serializesParameterizedTestFunction(plan: Runner.Plan) async {
    var configuration = Configuration()
    configuration.isParallelizationEnabled = true

    let indicesRecorded = Locked<[Int]>()
    configuration.eventHandler = { event, _ in
      if case let .issueRecorded(issue) = event.kind,
         let comment = issue.comments.first,
         comment.rawValue.hasPrefix("PARAMETERIZED") {
        // Silly hack: only letters before the index, so just scrape off all
        // leading letters and what's left will be the index as a string. No
        // need for sscanf() or similar.
        if let index = Int(String(comment.rawValue.drop(while: \.isLetter))) {
          indicesRecorded.withLock { indicesRecorded in
            indicesRecorded.append(index)
          }
        }
      }
    }

    let runner = Runner(plan: plan, configuration: configuration)
    await runner.run()

    let indicesRecordedValue = indicesRecorded.rawValue
    #expect(indicesRecordedValue.count == 10_000)
    let isSorted = indicesRecordedValue == indicesRecordedValue.sorted()
    #expect(isSorted)
  }
}

// MARK: - Fixtures

@Suite(.hidden, .serialized)
private struct OuterSuite {
  /* This @Suite intentionally left blank */ struct IntermediateSuite {
    @Suite(.hidden)
    struct InnerSuite {
      @Test(.hidden) func example() {}

      @Test(.hidden, arguments: 0 ..< 10_000) func parameterized(i: Int) async throws {
        Issue.record("PARAMETERIZED\(i)")
      }
    }
  }
}

@Test(.hidden, .serialized, arguments: 0 ..< 10_000)
private func globalParameterized(i: Int) {
  Issue.record("PARAMETERIZED\(i)")
}
