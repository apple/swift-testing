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

#if canImport(Foundation)
private import Foundation
#endif

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
    await confirmation("Miscount recorded", expectedCount: 7) { miscountRecorded in
      var configuration = Configuration()
      configuration.eventHandler = { event, _ in
        if case let .issueRecorded(issue) = event.kind {
          switch issue.kind {
          case .confirmationMiscounted:
            miscountRecorded()
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

  @Test func confirmationFailureCanBeDescribed() async {
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      if case let .issueRecorded(issue) = event.kind {
        #expect(String(describing: issue).contains("time(s)"))
      }
    }

    await Test {
      await confirmation(expectedCount: 1...) { _ in }
      await confirmation(expectedCount: 1...2) { _ in }
      await confirmation(expectedCount: 1..<3) { _ in }
    }.run(configuration: configuration)
  }

  @Test func confirmationFailureCanBeDescribedAsSingleValue() async {
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      if case let .issueRecorded(issue) = event.kind {
        #expect(!String(describing: issue).contains("time(s)"))
      }
    }

    await Test {
      await confirmation(expectedCount: 1...1) { _ in }
      await confirmation(expectedCount: 1..<2) { _ in }
      await confirmation(expectedCount: Int.max...Int.max) { _ in }
#if !SWT_NO_EXIT_TESTS
      await withKnownIssue("Crashes in Swift standard library (rdar://139568287)") {
        await #expect(processExitsWith: .success) {
          await confirmation(expectedCount: Int.max...) { _ in }
        }
      }
#endif
    }.run(configuration: configuration)
  }

#if !SWT_NO_EXIT_TESTS
  @Test("Confirmation requires positive count")
  func positiveCount() async {
    await #expect(processExitsWith: .failure) {
      await confirmation { $0.confirm(count: 0) }
    }
    await #expect(processExitsWith: .failure) {
      await confirmation { $0.confirm(count: -1) }
    }
  }
#endif

  @Test("Main actor isolation")
  @MainActor
  func mainActorIsolated() async {
    await confirmation { $0() }
  }
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
    1 ... 2 as any ExpectedCount,
    1 ..< 2,
    1 ..< 3,
    999...,
  ])
  func confirmedOutOfRange(_ range: any ExpectedCount) async {
    await confirmation(expectedCount: range) { (thingHappened) async in
      thingHappened(count: 3)
    }
  }
}

// MARK: -

/// Needed since we don't have generic test functions, so we need a concrete
/// argument type for `confirmedOutOfRange(_:)`. Although we can now write
/// `any RangeExpression<Int> & Sequence<Int> & Sendable` as of Swift 6.2
/// (per [swiftlang/swift#76705](https://github.com/swiftlang/swift/pull/76705)),
/// attempting to form an array of such values crashes at runtime. ([163980446](rdar://163980446))
protocol ExpectedCount: RangeExpression, Sequence, Sendable where Bound == Int, Element == Int {}
extension ClosedRange<Int>: ExpectedCount {}
extension PartialRangeFrom<Int>: ExpectedCount {}
extension Range<Int>: ExpectedCount {}
