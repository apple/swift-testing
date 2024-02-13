//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

@testable @_spi(ExperimentalTestRunning) @_spi(ExperimentalEventHandling) import Testing

@Suite("Serial Trait Tests", .tags("trait"))
struct SerialTraitTests {
  @Test(".serial trait is recursively applied")
  func serialTrait() async {
    var configuration = Configuration()
    configuration.isParallelizationEnabled = true
    let plan = await Runner.Plan(selecting: OuterSuite.self, configuration: configuration)
    for step in plan.steps {
      #expect(step.action.isParallelizationEnabled == false, "Step \(step) should have had parallelization disabled")
    }
  }

  @Test(".serial trait serializes parameterized test")
  func serializesParameterizedTestFunction() async {
    var configuration = Configuration()
    configuration.isParallelizationEnabled = true

    let indicesRecorded = Locked<[Int]>(rawValue: [])
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

    let plan = await Runner.Plan(selecting: OuterSuite.self, configuration: configuration)
    let runner = Runner(plan: plan, configuration: configuration)
    await runner.run()

    let indicesRecordedValue = indicesRecorded.rawValue
    #expect(indicesRecordedValue.count == 10_000)
    let isSorted = indicesRecordedValue == indicesRecordedValue.sorted()
    #expect(isSorted)
  }
}

// MARK: - Fixtures

@Suite(.hidden, .serial)
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
