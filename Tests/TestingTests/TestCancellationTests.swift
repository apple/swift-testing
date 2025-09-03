//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

@testable @_spi(Experimental) @_spi(ForToolsIntegrationOnly) import Testing

@Suite(.serialized) struct `Test cancellation tests` {
  func testCancellation(
    testCancelled: Int = 0,
    testSkipped: Int = 0,
    testCaseCancelled: Int = 0,
    issueRecorded: Int = 0,
    _ body: @Sendable (Configuration) async -> Void,
    eventHandler: @escaping @Sendable (borrowing Event, borrowing Event.Context) -> Void = { _, _ in }
  ) async {
    await confirmation("Test cancelled", expectedCount: testCancelled) { testCancelled in
      await confirmation("Test skipped", expectedCount: testSkipped) { testSkipped in
        await confirmation("Test case cancelled", expectedCount: testCaseCancelled) { testCaseCancelled in
          await confirmation("Issue recorded", expectedCount: issueRecorded) { [issueRecordedCount = issueRecorded] issueRecorded in
            var configuration = Configuration()
            configuration.eventHandler = { event, eventContext in
              switch event.kind {
              case .testCancelled:
                testCancelled()
              case .testSkipped:
                testSkipped()
              case .testCaseCancelled:
                testCaseCancelled()
              case let .issueRecorded(issue):
                if issueRecordedCount == 0 {
                  issue.record()
                }
                issueRecorded()
              default:
                break
              }
              eventHandler(event, eventContext)
            }
#if !SWT_NO_EXIT_TESTS
            configuration.exitTestHandler = ExitTest.handlerForEntryPoint()
#endif
            await body(configuration)
          }
        }
      }
    }
  }

  @Test func `Cancelling a test`() async {
    await testCancellation(testCancelled: 1, testCaseCancelled: 1) { configuration in
      await Test {
        try Test.cancel("Cancelled test")
      }.run(configuration: configuration)
    }
  }

  @Test func `Cancelling a non-parameterized test via Test.Case.cancel()`() async {
    await testCancellation(testCancelled: 1, testCaseCancelled: 1) { configuration in
      await Test {
        try Test.Case.cancel("Cancelled test")
      }.run(configuration: configuration)
    }
  }

  @Test func `Cancelling a test case in a parameterized test`() async {
    await testCancellation(testCaseCancelled: 5, issueRecorded: 5) { configuration in
      await Test(arguments: 0 ..< 10) { i in
        if (i % 2) == 0 {
          try Test.Case.cancel("\(i) is even!")
        }
        Issue.record("\(i) records an issue!")
      }.run(configuration: configuration)
    }
  }

  @Test func `Cancelling an entire parameterized test`() async {
    await testCancellation(testCancelled: 1, testCaseCancelled: 10) { configuration in
      // .serialized to ensure that none of the cases complete before the first
      // one cancels the test.
      await Test(.serialized, arguments: 0 ..< 10) { i in
        if i == 0 {
          try Test.cancel("\(i) cancelled the test")
        }
        Issue.record("\(i) records an issue!")
      }.run(configuration: configuration)
    }
  }

  @Test func `Cancelling a test propagates its SkipInfo to its test cases`() async {
    let sourceLocation = #_sourceLocation
    await testCancellation(testCancelled: 1, testCaseCancelled: 1) { configuration in
      await Test {
        try Test.cancel("Cancelled test", sourceLocation: sourceLocation)
      }.run(configuration: configuration)
    } eventHandler: { event, _ in
      if case let .testCaseCancelled(skipInfo) = event.kind {
        #expect(skipInfo.comment?.rawValue == "Cancelled test")
        #expect(skipInfo.sourceContext.sourceLocation == sourceLocation)
      }
    }
  }

  @Test func `Cancelling a test by cancelling its task (throwing)`() async {
    await testCancellation(testCancelled: 1, testCaseCancelled: 1) { configuration in
      await Test {
        withUnsafeCurrentTask { $0?.cancel() }
        try Task.checkCancellation()
      }.run(configuration: configuration)
    }
  }

  @Test func `Cancelling a test by cancelling its task (returning)`() async {
    await testCancellation(testCancelled: 1, testCaseCancelled: 1) { configuration in
      await Test {
        withUnsafeCurrentTask { $0?.cancel() }
      }.run(configuration: configuration)
    }
  }

  @Test func `Throwing CancellationError without cancelling the test task`() async {
    await testCancellation(issueRecorded: 1) { configuration in
      await Test {
        throw CancellationError()
      }.run(configuration: configuration)
    }
  }

  @Test func `Throwing CancellationError while evaluating traits without cancelling the test task`() async {
    await testCancellation(issueRecorded: 1) { configuration in
      await Test(CancelledTrait(throwsWithoutCancelling: true)) {
      }.run(configuration: configuration)
    }
  }

  @Test func `Cancelling a test while evaluating traits skips the test`() async {
    await testCancellation(testSkipped: 1) { configuration in
      await Test(CancelledTrait()) {
        Issue.record("Recorded an issue!")
      }.run(configuration: configuration)
    }
  }

  @Test func `Cancelling the current task while evaluating traits skips the test`() async {
    await testCancellation(testSkipped: 1) { configuration in
      await Test(CancelledTrait(cancelsTask: true)) {
        Issue.record("Recorded an issue!")
      }.run(configuration: configuration)
    }
  }

  @Test func `Cancelling a test while evaluating test cases skips the test`() async {
    await testCancellation(testSkipped: 1) { configuration in
      await Test(arguments: { try await cancelledTestCases(cancelsTask: false) }) { _ in
        Issue.record("Recorded an issue!")
      }.run(configuration: configuration)
    }
  }

  @Test func `Cancelling the current task while evaluating test cases skips the test`() async {
    await testCancellation(testSkipped: 1) { configuration in
      await Test(arguments: { try await cancelledTestCases(cancelsTask: true) }) { _ in
        Issue.record("Recorded an issue!")
      }.run(configuration: configuration)
    }
  }

#if !SWT_NO_EXIT_TESTS
  @Test func `Cancelling the current test from within an exit test`() async {
    await testCancellation(testCancelled: 1, testCaseCancelled: 1) { configuration in
      await Test {
        await #expect(processExitsWith: .success) {
          try Test.cancel("Cancelled test")
        }
        #expect(Task.isCancelled)
        try Task.checkCancellation()
      }.run(configuration: configuration)
    }
  }

  @Test func `Cancelling the current test case from within an exit test`() async {
    await testCancellation(testCancelled: 1, testCaseCancelled: 1) { configuration in
      await Test {
        await #expect(processExitsWith: .success) {
          try Test.Case.cancel("Cancelled test")
        }
        #expect(Task.isCancelled)
        try Task.checkCancellation()
      }.run(configuration: configuration)
    }
  }

  @Test func `Cancelling the current task in an exit test doesn't cancel the test`() async {
    await testCancellation(testCancelled: 0, testCaseCancelled: 0) { configuration in
      await Test {
        await #expect(processExitsWith: .success) {
          withUnsafeCurrentTask { $0?.cancel() }
        }
        #expect(!Task.isCancelled)
        try Task.checkCancellation()
      }.run(configuration: configuration)
    }
  }
#endif
}

#if canImport(XCTest)
import XCTest

final class TestCancellationTests: XCTestCase {
  func testCancellationFromBackgroundTask() async {
    let testCancelled = expectation(description: "Test cancelled")
    testCancelled.isInverted = true

    let issueRecorded = expectation(description: "Issue recorded")

    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      if case .testCancelled = event.kind {
        testCancelled.fulfill()
      } else if case .issueRecorded = event.kind {
        issueRecorded.fulfill()
      }
    }

    await Test {
      await Task.detached {
        _ = try? Test.cancel("Cancelled test")
      }.value
    }.run(configuration: configuration)

    await fulfillment(of: [testCancelled, issueRecorded], timeout: 0.0)
  }
}
#endif

// MARK: - Fixtures

struct CancelledTrait: TestTrait {
  var throwsWithoutCancelling = false
  var cancelsTask = false

  func prepare(for test: Test) async throws {
    if throwsWithoutCancelling {
      throw CancellationError()
    }
    if cancelsTask {
      withUnsafeCurrentTask { $0?.cancel() }
      try Task.checkCancellation()
    }
    try Test.cancel("Cancelled from trait")
  }
}

func cancelledTestCases(cancelsTask: Bool) async throws -> EmptyCollection<Int> {
  if cancelsTask {
    withUnsafeCurrentTask { $0?.cancel() }
    try Task.checkCancellation()
  }
  try Test.cancel("Cancelled from trait")
}


#if !SWT_NO_SNAPSHOT_TYPES
struct `Shows as skipped in Xcode 16` {
  @Test func `Cancelled test`() throws {
    try Test.cancel("This test should appear cancelled/skipped")
  }
}
#endif
