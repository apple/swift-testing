//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if canImport(XCTest)
import XCTest
#endif
@testable @_spi(Experimental) @_spi(ForToolsIntegrationOnly) import Testing

struct MyError: Error, Equatable {
}

struct MyParameterizedError: Error, Equatable {
  var index: Int
}

struct MyDescriptiveError: Error, Equatable, CustomStringConvertible {
  var description: String
}

@Test(.hidden)
@Sendable func throwsError() async throws {
  throw MyError()
}

private let randomNumber = Int.random(in: 0 ..< .max)

@Test(.hidden, arguments: [randomNumber])
@Sendable func throwsErrorParameterized(i: Int) throws {
  throw MyParameterizedError(index: i)
}

private func getArguments() async throws -> [Int] {
  throw MyDescriptiveError(description: "boom")
}

@Test(.hidden, arguments: try await getArguments())
func parameterizedWithAsyncThrowingArgs(i: Int) {}

private func fatalArguments() -> [Int] {
  fatalError("Should never crash, since this should never be called by any test")
}

/// A test whose arguments always cause a `fatalError()` crash.
///
/// This test should always remain `.hidden` and never be selected to run. Its
/// purpose is to validate that the arguments of tests which are not run are
/// never evaluated.
@Test(.hidden, arguments: fatalArguments())
func parameterizedWithFatalArguments(i: Int) {}

#if canImport(XCTest)
@Suite(.hidden, .disabled())
struct NeverRunTests {
  private static var someCondition: Bool {
    XCTFail("Shouldn't be evaluated due to .disabled() on suite")
    return false
  }

  @Test(.hidden, .enabled(if: someCondition))
  func duelingConditions() {}
}

final class RunnerTests: XCTestCase {
  func testInitialTaskLocalState() {
    // These are expected to be `nil` since this is an XCTest.
    XCTAssertNil(Test.current)
    XCTAssertNil(Test.Case.current)
    XCTAssertNil(Configuration.current)
  }

  func testDefaultInit() async throws {
    let runner = await Runner()
    XCTAssertFalse(runner.tests.contains(where: \.isHidden))
  }

  func testTestsProperty() async throws {
    let tests = [
      Test(testFunction: freeSyncFunction),
      Test(testFunction: freeAsyncFunction),
    ]
    let runner = await Runner(testing: tests)
    XCTAssertEqual(runner.tests.count, 2)
    XCTAssertEqual(Set(tests), Set(runner.tests))
  }

  func testFreeFunction() async throws {
    let runner = await Runner(testing: [
      Test(testFunction: freeSyncFunction),
      Test(testFunction: freeAsyncFunction),
    ])
    await runner.run()
  }

  func testYieldingError() async throws {
    let errorObserved = expectation(description: "Error was thrown and caught")
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      if case let .issueRecorded(issue) = event.kind, issue.error is MyError {
        errorObserved.fulfill()
      }
    }
    let runner = await Runner(testing: [
      Test { @Sendable in
        throw MyError()
      },
    ], configuration: configuration)
    await runner.run()
    await fulfillment(of: [errorObserved], timeout: 0.0)
  }

  func testErrorThrownFromTest() async throws {
    let issueRecorded = expectation(description: "An issue was recorded")
    let otherTestEnded = expectation(description: "The other test (the one which didn't throw an error) ended")
    var configuration = Configuration()
    configuration.isParallelizationEnabled = false
    configuration.eventHandler = { event, context in
      if case let .issueRecorded(issue) = event.kind, issue.error is MyError {
        issueRecorded.fulfill()
      }
      if case .testEnded = event.kind, let test = context.test, test.name == "test2" {
        otherTestEnded.fulfill()
      }
    }
    let runner = await Runner(testing: [
      Test { throw MyError() },
      Test(name: "test2") {},
    ], configuration: configuration)
    await runner.run()
    await fulfillment(of: [issueRecorded, otherTestEnded], timeout: 0.0)
  }

  func testYieldsIssueWhenErrorThrownFromParallelizedTest() async throws {
    let errorObserved = expectation(description: "Error was thrown and caught")
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      if case let .issueRecorded(issue) = event.kind, issue.error is MyError {
        errorObserved.fulfill()
      }
    }
    await Runner(selecting: "throwsError()", configuration: configuration).run()
    await fulfillment(of: [errorObserved], timeout: 0.0)
  }

  func testYieldsIssueWhenErrorThrownFromTestCase() async throws {
    let errorObserved = expectation(description: "Error was thrown and caught")
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      if case let .issueRecorded(issue) = event.kind, let error = issue.error as? MyParameterizedError, error.index == randomNumber {
        errorObserved.fulfill()
      }
    }
    await Runner(selecting: "throwsErrorParameterized(i:)", configuration: configuration).run()
    await fulfillment(of: [errorObserved], timeout: 0.0)
  }

  func testTestIsSkippedWhenDisabled() async throws {
    let planStepStarted = expectation(description: "Plan step started")
    let testSkipped = expectation(description: "Test was skipped")
    let planStepEnded = expectation(description: "Plan step ended")
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      if case .planStepStarted = event.kind {
        planStepStarted.fulfill()
      } else if case let .testSkipped(skipInfo) = event.kind, skipInfo.comment == nil {
        XCTAssertEqual(skipInfo.sourceContext.sourceLocation?.line, 9999)
        testSkipped.fulfill()
      } else if case .planStepEnded = event.kind {
        planStepEnded.fulfill()
      }
    }
#sourceLocation(file: "blah.swift", line: 9999)
    let disabledTrait = ConditionTrait.disabled()
#sourceLocation()
    let test = Test(disabledTrait) {
      XCTFail("This should not be called since the test is disabled")
    }
    let runner = await Runner(testing: [test], configuration: configuration)
    await runner.run()
    await fulfillment(of: [planStepStarted, testSkipped, planStepEnded], timeout: 0.0, enforceOrder: true)
  }

  func testTestIsSkippedWhenDisabledWithComment() async throws {
    let testSkipped = expectation(description: "Test was skipped")
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      if case let .testSkipped(skipInfo) = event.kind, skipInfo.comment == "Some comment" {
        testSkipped.fulfill()
      }
    }
    let runner = await Runner(testing: [
      Test(.disabled("Some comment")) {},
    ], configuration: configuration)
    await runner.run()
    await fulfillment(of: [testSkipped], timeout: 0.0)
  }

  func testTestIsSkippedWithBlockingEnabledIfTrait() async throws {
    let testSkipped = expectation(description: "Test was skipped")
    testSkipped.expectedFulfillmentCount = 4
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      if case let .testSkipped(skipInfo) = event.kind, skipInfo.comment == "Some comment" {
        testSkipped.fulfill()
      }
    }

    do {
      let runner = await Runner(testing: [
        Test(.enabled(if: false, "Some comment")) {},
      ], configuration: configuration)
      await runner.run()
    }
    do {
      let runner = await Runner(testing: [
        Test(.enabled("Some comment") { false }) {},
      ], configuration: configuration)
      await runner.run()
    }
    do {
      let runner = await Runner(testing: [
        Test(.disabled(if: true, "Some comment")) {},
      ], configuration: configuration)
      await runner.run()
    }
    do {
      let runner = await Runner(testing: [
        Test(.disabled("Some comment") { true }) {},
      ], configuration: configuration)
      await runner.run()
    }

    await fulfillment(of: [testSkipped], timeout: 0.0)
  }

  func testTestIsNotSkippedWithPassingConditionTraits() async throws {
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      if case .testSkipped = event.kind {
        XCTFail("Test should not be skipped")
      }
    }

    do {
      let runner = await Runner(testing: [
        Test(.enabled(if: true, "Some comment")) {},
      ], configuration: configuration)
      await runner.run()
    }
    do {
      let runner = await Runner(testing: [
        Test(.enabled("Some comment") { true }) {},
      ], configuration: configuration)
      await runner.run()
    }
    do {
      let runner = await Runner(testing: [
        Test(.disabled(if: false, "Some comment")) {},
      ], configuration: configuration)
      await runner.run()
    }
    do {
      let runner = await Runner(testing: [
        Test(.disabled("Some comment") { false }) {},
      ], configuration: configuration)
      await runner.run()
    }
  }

  func testConditionTraitsAreEvaluatedOutermostToInnermost() async throws {
    let testSuite = try #require(await test(for: NeverRunTests.self))
    let testFunc = try #require(await testFunction(named: "duelingConditions()", in: NeverRunTests.self))

    var configuration = Configuration()
    let selection = [testSuite.id]
    configuration.setTestFilter(toInclude: selection, includeHiddenTests: true)

    let runner = await Runner(testing: [
      testSuite,
      testFunc,
    ], configuration: configuration)
    await runner.run()
  }

  func testTestActionIsRecordIssueDueToErrorThrownByConditionTrait() async throws {
    let testRecordedIssue = expectation(description: "Test recorded an issue")
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      if case let .issueRecorded(issue) = event.kind, case let .errorCaught(recordedError) = issue.kind {
        XCTAssert(recordedError is MyError)
        testRecordedIssue.fulfill()
      }
    }
    @Sendable func sketchyCondition() throws -> Bool {
      throw MyError()
    }
    let runner = await Runner(testing: [
      Test(.enabled(if: try sketchyCondition(), "Some comment")) {},
    ], configuration: configuration)
    await runner.run()
    await fulfillment(of: [testRecordedIssue], timeout: 0.0)
  }

  func testConditionTraitIsConstant() async throws {
    let test = Test(.disabled()) { }
    XCTAssertTrue(test.traits.compactMap { $0 as? ConditionTrait }.allSatisfy(\.isConstant))

    let test2 = Test(.disabled(if: Bool.random())) { }
    XCTAssertTrue(test2.traits.compactMap { $0 as? ConditionTrait }.allSatisfy { !$0.isConstant })
  }

  func testGeneratedPlan() async throws {
    let tests: [(Any.Type, String)] = [
      (SendableTests.self, "succeeds()"),
      (SendableTests.self, "succeedsAsync()"),
      (SendableTests.NestedSendableTests.self, "succeedsAsync()"),
      (SendableTests.self, "disabled()"),
    ]

    let selectedTestIDs = Set(tests.map {
      Test.ID(type: $0).child(named: $1)
    })
    XCTAssertFalse(selectedTestIDs.isEmpty)

    var configuration = Configuration()
    configuration.setTestFilter(toInclude: selectedTestIDs, includeHiddenTests: true)

    let runner = await Runner(configuration: configuration)
    let plan = runner.plan

    XCTAssertGreaterThanOrEqual(plan.steps.count, tests.count)
    let disabledStep = try XCTUnwrap(plan.steps.first(where: { $0.test.name == "disabled()" }))
    guard case let .skip(skipInfo) = disabledStep.action else {
      XCTFail("Disabled test was not marked skipped")
      return
    }
    XCTAssertEqual(skipInfo.comment, "Some comment")
  }

  func testErrorThrownWhileEvaluatingArguments() async throws {
    let errorObserved = expectation(description: "Error was thrown and caught")
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      if case .testStarted = event.kind {
        XCTFail("The test should not have started, since the evaluation of its arguments threw an Error")
      }
      if case let .issueRecorded(issue) = event.kind, let error = issue.error as? MyDescriptiveError, String(describing: error) == "boom" {
        errorObserved.fulfill()
      }
    }
    await Runner(selecting: "parameterizedWithAsyncThrowingArgs(i:)", configuration: configuration).run()
    await fulfillment(of: [errorObserved], timeout: 0.0)
  }

  @Suite(.hidden) struct S {
    @Test(.hidden) func f() {}
  }

  func testPlanExcludesHiddenTests() async throws {
    let selectedTestIDs: Set<Test.ID> = [
      Test.ID(type: S.self).child(named: "f()")
    ]

    var configuration1 = Configuration()
    configuration1.testFilter = Configuration.TestFilter(including: selectedTestIDs)

    var configuration2 = Configuration()
    configuration2.testFilter = Configuration.TestFilter(including: selectedTestIDs)

    for configuration in [configuration1, configuration2] {
      let runner = await Runner(configuration: configuration)
      let plan = runner.plan

      XCTAssertEqual(plan.steps.count, 0)
    }
  }

  func testHardCodedPlan() async throws {
    let tests = try await [
      testFunction(named: "succeeds()", in: SendableTests.self),
      testFunction(named: "succeedsAsync()", in: SendableTests.self),
      testFunction(named: "succeeds()", in: SendableTests.NestedSendableTests.self),
    ].map { try XCTUnwrap($0) }
    let steps: [Runner.Plan.Step] = tests
      .map { .init(test: $0, action: .skip()) }
    let plan = Runner.Plan(steps: steps)

    let testStarted = expectation(description: "Test was skipped")
    testStarted.isInverted = true
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      if case .testStarted = event.kind {
        testStarted.fulfill()
      }
    }

    let runner = Runner(plan: plan)
    await runner.run()
    await fulfillment(of: [testStarted], timeout: 0.0)
  }

  func testExpectationCheckedEventHandlingWhenDisabled() async {
    var configuration = Configuration()
    configuration.deliverExpectationCheckedEvents = false
    configuration.eventHandler = { event, _ in
      if case .expectationChecked = event.kind {
        XCTFail("Expectation checked event was posted unexpectedly")
      }
    }
    let runner = await Runner(testing: [
      Test {
        // Test the "normal" path.
        #expect(Bool(true))
        #expect(Bool(false))

#if !SWT_NO_UNSTRUCTURED_TASKS
        // Test the detached (no task-local configuration) path.
        await Task.detached {
          #expect(Bool(true))
          #expect(Bool(false))
        }.value
#endif
      },
    ], configuration: configuration)
    await runner.run()
  }

  func testExpectationCheckedEventHandlingWhenEnabled() async {
    let expectationCheckedAndPassed = expectation(description: "Expectation was checked (passed)")
    let expectationCheckedAndFailed = expectation(description: "Expectation was checked (failed)")
#if !SWT_NO_UNSTRUCTURED_TASKS
    expectationCheckedAndPassed.expectedFulfillmentCount = 2
    expectationCheckedAndFailed.expectedFulfillmentCount = 2
#endif

    var configuration = Configuration()
    configuration.deliverExpectationCheckedEvents = true
    configuration.eventHandler = { event, _ in
      guard case let .expectationChecked(expectation) = event.kind else {
        return
      }
      if expectation.isPassing {
        expectationCheckedAndPassed.fulfill()
      } else {
        expectationCheckedAndFailed.fulfill()
      }
    }

    let runner = await Runner(testing: [
      Test {
        // Test the "normal" path.
        #expect(Bool(true))
        #expect(Bool(false))

#if !SWT_NO_UNSTRUCTURED_TASKS
        // Test the detached (no task-local configuration) path.
        await Task.detached {
          #expect(Bool(true))
          #expect(Bool(false))
        }.value
#endif
      },
    ], configuration: configuration)
    await runner.run()

    await fulfillment(of: [expectationCheckedAndPassed, expectationCheckedAndFailed], timeout: 0.0)
  }

  @Suite(.hidden) struct PoundIfTrueTest {
#if true
    @Test(.hidden) func f() {}
    @Test(.hidden) func g() {}
#endif
    @Test(.hidden) func h() {}
  }

  func testPoundIfTrueTestFunctionRuns() async throws {
    let testStarted = expectation(description: "Test started")
    testStarted.expectedFulfillmentCount = 4
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      if case .testStarted = event.kind {
        testStarted.fulfill()
      }
    }
    await runTest(for: PoundIfTrueTest.self, configuration: configuration)
    await fulfillment(of: [testStarted], timeout: 0.0)
  }

  @Suite(.hidden) struct PoundIfFalseTest {
#if false
    @Test(.hidden) func f() {}
    @Test(.hidden) func g() {}
#endif
    @Test(.hidden) func h() {}
  }

  func testPoundIfFalseTestFunctionDoesNotRun() async throws {
    let testStarted = expectation(description: "Test started")
    testStarted.expectedFulfillmentCount = 2
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      if case .testStarted = event.kind {
        testStarted.fulfill()
      }
    }
    await runTest(for: PoundIfFalseTest.self, configuration: configuration)
    await fulfillment(of: [testStarted], timeout: 0.0)
  }

  @Suite(.hidden) struct PoundIfFalseElseTest {
#if false
#elseif false
#else
    @Test(.hidden) func f() {}
    @Test(.hidden) func g() {}
#endif
    @Test(.hidden) func h() {}
  }

  func testPoundIfFalseElseTestFunctionRuns() async throws {
    let testStarted = expectation(description: "Test started")
    testStarted.expectedFulfillmentCount = 4
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      if case .testStarted = event.kind {
        testStarted.fulfill()
      }
    }
    await runTest(for: PoundIfFalseElseTest.self, configuration: configuration)
    await fulfillment(of: [testStarted], timeout: 0.0)
  }

  @Suite(.hidden) struct PoundIfFalseElseIfTest {
#if false
#elseif false
#elseif true
    @Test(.hidden) func f() {}
    @Test(.hidden) func g() {}
#endif
    @Test(.hidden) func h() {}
  }

  func testPoundIfFalseElseIfTestFunctionRuns() async throws {
    let testStarted = expectation(description: "Test started")
    testStarted.expectedFulfillmentCount = 4
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      if case .testStarted = event.kind {
        testStarted.fulfill()
      }
    }
    await runTest(for: PoundIfFalseElseIfTest.self, configuration: configuration)
    await fulfillment(of: [testStarted], timeout: 0.0)
  }

  @Suite(.hidden) struct NoasyncTestsAreCallableTests {
    @Test(.hidden)
    @available(*, noasync)
    func noAsync() {}

    @Test(.hidden)
    @available(*, noasync)
    func noAsyncThrows() throws {}

    @Test(.hidden)
    @_unavailableFromAsync
    func unavailableFromAsync() {}

    @Test(.hidden)
    @_unavailableFromAsync(message: "")
    func unavailableFromAsyncWithMessage() {}

#if !SWT_NO_GLOBAL_ACTORS
    @Test(.hidden)
    @available(*, noasync) @MainActor
    func noAsyncThrowsMainActor() throws {}
#endif
  }

  func testNoasyncTestsAreCallable() async throws {
    let testStarted = expectation(description: "Test started")
#if !SWT_NO_GLOBAL_ACTORS
    testStarted.expectedFulfillmentCount = 6
#else
    testStarted.expectedFulfillmentCount = 5
#endif
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      if case .testStarted = event.kind {
        testStarted.fulfill()
      }
    }
    await runTest(for: NoasyncTestsAreCallableTests.self, configuration: configuration)
    await fulfillment(of: [testStarted], timeout: 0.0)
  }

  @Suite(.hidden) struct UnavailableTests {
    @Test(.hidden)
    @available(*, unavailable)
    func unavailable() {}

    @Suite(.hidden)
    struct T {
      @Test(.hidden)
      @available(*, unavailable)
      func f() {}
    }

#if SWT_TARGET_OS_APPLE
    @Test(.hidden)
    @available(macOS 999.0, iOS 999.0, watchOS 999.0, tvOS 999.0, visionOS 999.0, *)
    func futureAvailable() {}

    @Test(.hidden)
    @available(macOS, introduced: 999.0)
    @available(iOS, introduced: 999.0)
    @available(watchOS, introduced: 999.0)
    @available(tvOS, introduced: 999.0)
    @available(visionOS, introduced: 999.0)
    func futureAvailableLongForm() {}

    @Suite(.hidden)
    struct U {
      @Test(.hidden)
      @available(macOS 999.0, iOS 999.0, watchOS 999.0, tvOS 999.0, visionOS 999.0, *)
      func f() {}

      @Test(.hidden)
      @available(_distantFuture, *)
      func g() {}
    }

    @Suite(.hidden)
    struct V {
      @Test(.hidden)
      @available(macOS, introduced: 999.0)
      @available(iOS, introduced: 999.0)
      @available(watchOS, introduced: 999.0)
      @available(tvOS, introduced: 999.0)
      @available(visionOS, introduced: 999.0)
      func f() {}
    }
#endif
  }

  func testUnavailableTestsAreSkipped() async throws {
    let testStarted = expectation(description: "Test started")
    let testSkipped = expectation(description: "Test skipped")
#if SWT_TARGET_OS_APPLE
    testStarted.expectedFulfillmentCount = 4
    testSkipped.expectedFulfillmentCount = 7
#else
    testStarted.expectedFulfillmentCount = 2
    testSkipped.expectedFulfillmentCount = 2
#endif
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      if case .testStarted = event.kind {
        testStarted.fulfill()
      } else if case .testSkipped = event.kind {
        testSkipped.fulfill()
      }
    }
    await runTest(for: UnavailableTests.self, configuration: configuration)
    await fulfillment(of: [testStarted, testSkipped], timeout: 0.0)
  }

#if SWT_TARGET_OS_APPLE
  @Suite(.hidden) struct ObsoletedTests {
    @Test(.hidden)
    @available(macOS, introduced: 1.0, obsoleted: 999.0)
    @available(iOS, introduced: 1.0, obsoleted: 999.0)
    @available(watchOS, introduced: 1.0, obsoleted: 999.0)
    @available(tvOS, introduced: 1.0, obsoleted: 999.0)
    @available(visionOS, introduced: 1.0, obsoleted: 999.0)
    func obsoleted() {}
  }

  func testObsoletedTestFunctions() async throws {
    // It is not possible for the obsoleted argument to track the target
    // platform's deployment target, so we'll simply check that the traits were
    // emitted.
    let plan = await Runner.Plan(selecting: ObsoletedTests.self)
    for step in plan.steps where !step.test.isSuite {
      XCTAssertNotNil(step.test.comments(from: ConditionTrait.self).map(\.rawValue).first { $0.contains("999.0") })
    }
  }
#endif

  @Suite(.hidden) struct UnavailableWithMessageTests {
    @Test(.hidden)
    @available(*, unavailable, message: "Expected Message")
    func unavailable() {}

#if SWT_TARGET_OS_APPLE
    @Test(.hidden)
    @available(macOS, introduced: 999.0, message: "Expected Message")
    @available(iOS, introduced: 999.0, message: "Expected Message")
    @available(watchOS, introduced: 999.0, message: "Expected Message")
    @available(tvOS, introduced: 999.0, message: "Expected Message")
    @available(visionOS, introduced: 999.0, message: "Expected Message")
    func futureAvailableLongForm() {}
#endif
  }

  func testUnavailableTestMessageIsCaptured() async throws {
    let plan = await Runner.Plan(selecting: UnavailableWithMessageTests.self)
    for step in plan.steps where !step.test.isSuite {
      guard case let .skip(skipInfo) = step.action else {
        XCTFail("Test \(step.test) should be skipped, action is \(step.action)")
        continue
      }
      XCTAssertEqual(skipInfo.comment, "Expected Message")
    }
  }

  @Suite(.hidden) struct AvailableWithSwiftVersionTests {
    @Test(.hidden)
    @available(`swift` 1.0)
    func swift1() {}

    @Test(.hidden)
    @available(swift 999999.0)
    func swift999999() {}

    @Test(.hidden)
    @available(swift, introduced: 1.0, obsoleted: 2.0)
    func swiftIntroduced1Obsoleted2() {}

    @available(swift, introduced: 1.0, deprecated: 2.0)
    func swiftIntroduced1Deprecated2Callee() {}

    @Test(.hidden)
    @available(swift, introduced: 1.0, deprecated: 2.0)
    func swiftIntroduced1Deprecated2() {
      swiftIntroduced1Deprecated2Callee()
    }
  }

  func testAvailableWithSwiftVersion() async throws {
    let testStarted = expectation(description: "Test started")
    let testSkipped = expectation(description: "Test skipped")
    testStarted.expectedFulfillmentCount = 3
    testSkipped.expectedFulfillmentCount = 2
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      if case .testStarted = event.kind {
        testStarted.fulfill()
      } else if case .testSkipped = event.kind {
        testSkipped.fulfill()
      }
    }
    await runTest(for: AvailableWithSwiftVersionTests.self, configuration: configuration)
    await fulfillment(of: [testStarted, testSkipped], timeout: 0.0)
  }

  @Suite(.hidden) struct AvailableWithDefinedAvailabilityTests {
    @Test(.hidden)
    @available(_clockAPI, *)
    func clockAPI() {}
  }

  func testAvailableWithDefinedAvailability() async throws {
    guard #available(_clockAPI, *) else {
      throw XCTSkip("Test method is unavailable here.")
    }

    let testStarted = expectation(description: "Test started")
    testStarted.expectedFulfillmentCount = 2
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      if case .testStarted = event.kind {
        testStarted.fulfill()
      }
    }
    await runTest(for: AvailableWithDefinedAvailabilityTests.self, configuration: configuration)
    await fulfillment(of: [testStarted], timeout: 0.0)
  }

#if !SWT_NO_GLOBAL_ACTORS
  @TaskLocal static var isMainActorIsolationEnforced = false

  @Suite(.hidden) struct MainActorIsolationTests {
    @Test(.hidden) func mustRunOnMainActor() {
      XCTAssertEqual(Thread.isMainThread, isMainActorIsolationEnforced)
    }

    @Test(.hidden) @MainActor func definitelyRunsOnMainActor() {
      XCTAssertTrue(Thread.isMainThread)
    }

    @Test(.hidden) func neverRunsOnMainActor() async {
      XCTAssertFalse(Thread.isMainThread)
    }

    @Test(.hidden) @MainActor func asyncButRunsOnMainActor() async {
      XCTAssertTrue(Thread.isMainThread)
    }
  }

  func testSynchronousTestFunctionRunsOnMainActorWhenEnforced() async {
    var configuration = Configuration()
    configuration.isMainActorIsolationEnforced = true
    await Self.$isMainActorIsolationEnforced.withValue(true) {
      await runTest(for: MainActorIsolationTests.self, configuration: configuration)
    }

    configuration.isMainActorIsolationEnforced = false
    await Self.$isMainActorIsolationEnforced.withValue(false) {
      await runTest(for: MainActorIsolationTests.self, configuration: configuration)
    }
  }
#endif

  @Suite(.hidden) struct DeprecatedVersionTests {
    @available(*, deprecated)
    func deprecatedCallee() {}

    @Test(.hidden)
    @available(*, deprecated)
    func deprecated() {
      deprecatedCallee()
    }

    @available(*, deprecated, message: "I am deprecated")
    func deprecatedWithMessageCallee() {}

    @Test(.hidden)
    @available(*, deprecated, message: "I am deprecated")
    func deprecatedWithMessage() {
      deprecatedWithMessageCallee()
    }

#if SWT_TARGET_OS_APPLE
    @available(macOS, deprecated: 1.0)
    @available(iOS, deprecated: 1.0)
    @available(watchOS, deprecated: 1.0)
    @available(tvOS, deprecated: 1.0)
    @available(visionOS, deprecated: 1.0)
    func deprecatedAppleCallee() {}

    @Test(.hidden)
    @available(macOS, deprecated: 1.0)
    @available(iOS, deprecated: 1.0)
    @available(watchOS, deprecated: 1.0)
    @available(tvOS, deprecated: 1.0)
    @available(visionOS, deprecated: 1.0)
    func deprecatedApple() {
      deprecatedAppleCallee()
    }
#endif
  }

  func testDeprecated() async throws {
    let testStarted = expectation(description: "Test started")
    let testSkipped = expectation(description: "Test skipped")
#if SWT_TARGET_OS_APPLE
    testStarted.expectedFulfillmentCount = 4
#else
    testStarted.expectedFulfillmentCount = 3
#endif
    testSkipped.isInverted = true
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      if case .testStarted = event.kind {
        testStarted.fulfill()
      } else if case .testSkipped = event.kind {
        testSkipped.fulfill()
      }
    }
    await runTest(for: DeprecatedVersionTests.self, configuration: configuration)
    await fulfillment(of: [testStarted, testSkipped], timeout: 0.0)
  }

  func testTestIsRunning() async {
    // Only XCTest is running here.
    XCTAssertFalse(Test.isRunning)

    await Test {
      XCTAssertTrue(Test.isRunning)
    }.run(configuration: .init())
  }
}
#endif
