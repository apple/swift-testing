//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

@testable @_spi(Experimental) @_spi(ForToolsIntegrationOnly) import Testing

@Suite("Confirmation Tests")
struct ConfirmationTests {
  @Test("Successful confirmations")
  func successfulConfirmations() async {
    await confirmation("Issue recorded", expectedCount: 0) { issueRecorded in
      var configuration = Configuration()
      configuration.eventHandler = { event, _ in
        if case .issueRecorded = event.kind {
          issueRecorded()
        }
      }
      let testPlan = await Runner.Plan(selecting: SuccessfulConfirmationTests.self)
      let runner = Runner(plan: testPlan, configuration: configuration)
      await runner.run()
    }
  }

  @Test("Unsuccessful confirmations")
  func unsuccessfulConfirmations() async {
    await confirmation("Miscount recorded", expectedCount: 3) { miscountRecorded in
      await confirmation("Unconditional issue recorded", expectedCount: 5) { unconditionalRecorded in
        var configuration = Configuration()
        configuration.eventHandler = { event, _ in
          if case let .issueRecorded(issue) = event.kind {
            switch issue.kind {
            case .confirmationMiscounted:
              miscountRecorded()
            case .unconditional:
              unconditionalRecorded()
            default:
              break
            }
          }
        }
        let testPlan = await Runner.Plan(selecting: UnsuccessfulConfirmationTests.self)
        let runner = Runner(plan: testPlan, configuration: configuration)
        await runner.run()
      }
    }
  }

#if !SWT_NO_EXIT_TESTS
  @Test("Confirmation requires positive count")
  func positiveCount() async {
    await #expect(exitsWith: .failure) {
      await confirmation { $0.confirm(count: 0) }
    }
    await #expect(exitsWith: .failure) {
      await confirmation { $0.confirm(count: -1) }
    }
  }
#endif
}

// MARK: - Fixtures

@Suite(.hidden)
struct SuccessfulConfirmationTests {
  @Test(.hidden)
  func basicConfirmation() async {
    await confirmation { (thingHappened) async in
      thingHappened()
    }
  }

  @Test(.hidden)
  func confirmed0Times() async {
    await confirmation(expectedCount: 0) { (_) async in }
  }

  @Test(.hidden)
  func confirmed3Times() async {
    await confirmation(expectedCount: 3) { (thingHappened) async in
      thingHappened(count: 3)
    }
  }
}

@Suite(.hidden)
struct UnsuccessfulConfirmationTests {
  @Test(.hidden)
  func basicConfirmation() async {
    await confirmation { (_) async in }
  }

  @Test(.hidden)
  func confirmedTooFewTimes() async {
    await confirmation(expectedCount: 3) { (thingHappened) async in
      thingHappened(count: 2)
    }
  }

  @Test(.hidden)
  func confirmedTooManyTimes() async {
    await confirmation(expectedCount: 3) { (thingHappened) async in
      thingHappened(count: 10)
    }
  }

  @Test(.hidden, arguments: [
    1 ... 2 as any RangeExpression<Int>,
    1 ..< 2,
    ..<2,
    ...2,
    999...,
  ])
  func confirmedOutOfRange(_ range: any RangeExpression<Int>) async {
    await confirmation(expectedCount: range) { (thingHappened) async in
      thingHappened(count: 3)
    }
  }
}
