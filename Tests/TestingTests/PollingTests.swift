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

@Suite("Polling Confirmation Tests")
struct PollingConfirmationTests {
  @Suite("with PollingStopCondition.firstPass")
  struct StopConditionFirstPass {
    let stop = PollingStopCondition.firstPass

    @available(_clockAPI, *)
    @Test("Simple passing expressions") func trivialHappyPath() async throws {
      try await confirmation(until: stop) { true }

      let value = try await confirmation(until: stop) { 1 }

      #expect(value == 1)
    }

    @available(_clockAPI, *)
    @Test("Simple failing expressions") func trivialSadPath() async throws {
      var issues = await runTest {
        try await confirmation(until: stop) { false }
      }
      issues += await runTest {
        _ = try await confirmation(until: stop) { Optional<Int>.none }
      }
      #expect(issues.count == 2)
      #expect(issues.allSatisfy {
        if case .pollingConfirmationFailed = $0.kind {
          return true
        } else {
          return false
        }
      })
    }

    @available(_clockAPI, *)
    @Test("When the value changes from false to true during execution")
    func changingFromFail() async throws {
      let incrementor = Incrementor()

      try await confirmation(until: stop) {
        await incrementor.increment() == 2
        // this will pass only on the second invocation
        // This checks that we really are only running the expression until
        // the first time it passes.
      }

      // and then we check the count just to double check.
      #expect(await incrementor.count == 2)
    }

    @available(_clockAPI, *)
    @Test("Thrown errors are treated as returning false")
    func errorsReported() async throws {
      let issues = await runTest {
        try await confirmation(until: stop) {
          throw PollingTestSampleError.ohNo
        }
      }
      #expect(issues.count == 1)
    }

    @available(_clockAPI, *)
    @Test("Calculates how many times to poll based on the duration & interval")
    func defaultPollingCount() async {
      let incrementor = Incrementor()
      _ = await runTest {
        // this test will intentionally fail.
        try await confirmation(until: stop, pollingEvery: .milliseconds(1)) {
          await incrementor.increment() == 0
        }
      }
      #expect(await incrementor.count == 1000)
    }

    @Suite(
      "Configuration traits",
      .pollingConfirmationDefaults(
        until: .firstPass,
        within: .milliseconds(100)
      )
    )
    struct WithConfigurationTraits {
      let stop = PollingStopCondition.firstPass

      @available(_clockAPI, *)
      @Test("When no test or callsite configuration provided, uses the suite configuration")
      func testUsesSuiteConfiguration() async {
        let incrementor = Incrementor()
        var test = Test {
          try await confirmation(until: stop, pollingEvery: .milliseconds(1)) {
            await incrementor.increment() == 0
          }
        }
        test.traits = Test.current?.traits ?? []
        await runTest(test: test)
        let count = await incrementor.count
        #expect(count == 100)
      }

      @available(_clockAPI, *)
      @Test(
        "Ignore trait configurations that don't match the stop condition",
        .pollingConfirmationDefaults(
          until: .stopsPassing,
          within: .milliseconds(
            500
          )
        )
      ) func testIgnoresTraitsWithNonmatchingStopConditions() async {
        let incrementor = Incrementor()
        var test = Test {
          try await confirmation(until: stop, pollingEvery: .milliseconds(1)) {
            await incrementor.increment() == 0
          }
        }
        test.traits = Test.current?.traits ?? []
        await runTest(test: test)
        let count = await incrementor.count
        #expect(count == 100)
      }

      @available(_clockAPI, *)
      @Test(
        "When test configuration provided, uses the test configuration",
        .pollingConfirmationDefaults(
          until: .firstPass,
          within: .milliseconds(10)
        )
      )
      func testUsesTestConfigurationOverSuiteConfiguration() async {
        let incrementor = Incrementor()
        var test = Test {
          // this test will intentionally fail.
          try await confirmation(until: stop, pollingEvery: .milliseconds(1)) {
            await incrementor.increment() == 0
          }
        }
        test.traits = Test.current?.traits ?? []
        await runTest(test: test)
        #expect(await incrementor.count == 10)
      }

      @available(_clockAPI, *)
      @Test(
        "When callsite configuration provided, uses that",
        .pollingConfirmationDefaults(
          until: .firstPass,
          within: .milliseconds(10)
        )
      )
      func testUsesCallsiteConfiguration() async {
        let incrementor = Incrementor()
        var test = Test {
          // this test will intentionally fail.
          try await confirmation(
            until: stop,
            within: .milliseconds(50),
            pollingEvery: .milliseconds(1)
          ) {
            await incrementor.increment() == 0
          }
        }
        test.traits = Test.current?.traits ?? []
        await runTest(test: test)
        #expect(await incrementor.count == 50)
      }

#if !SWT_NO_EXIT_TESTS
      @available(_clockAPI, *)
      @Test("Requires duration be greater than interval")
      func testRequiresDurationGreaterThanInterval() async {
        await #expect(processExitsWith: .failure) {
          try await confirmation(
            until: .stopsPassing,
            within: .seconds(1),
            pollingEvery: .milliseconds(1100)
          ) { true }
        }
      }

      @available(_clockAPI, *)
      @Test("Requires duration be greater than 0")
      func testRequiresDurationGreaterThan0() async {
        await #expect(processExitsWith: .failure) {
          try await confirmation(
            until: .stopsPassing,
            within: .seconds(0)
          ) { true }
        }
      }

      @available(_clockAPI, *)
      @Test("Requires interval be greater than 0")
      func testRequiresIntervalGreaterThan0() async {
        await #expect(processExitsWith: .failure) {
          try await confirmation(
            until: .stopsPassing,
            pollingEvery: .seconds(0)
          ) { true }
        }
      }
#endif
    }
  }

  @Suite("with PollingStopCondition.stopsPassing")
  struct StopConditionStopsPassing {
    let stop = PollingStopCondition.stopsPassing
    @available(_clockAPI, *)
    @Test("Simple passing expressions") func trivialHappyPath() async throws {
      try await confirmation(until: stop) { true }
      let value = try await confirmation(until: stop) { 1 }

      #expect(value == 1)
    }

    @available(_clockAPI, *)
    @Test("Simple failing expressions") func trivialSadPath() async {
      var issues = await runTest {
        try await confirmation(until: stop) { false }
      }
      issues += await runTest {
        _ = try await confirmation(until: stop) { Optional<Int>.none }
      }
      #expect(issues.count == 2)
      #expect(issues.allSatisfy {
        if case .pollingConfirmationFailed = $0.kind {
          return true
        } else {
          return false
        }
      })
    }

    @available(_clockAPI, *)
    @Test("if the closures starts off as true, but becomes false")
    func changingFromFail() async {
      let incrementor = Incrementor()
      let issues = await runTest {
        try await confirmation(until: stop) {
          await incrementor.increment() == 2
          // this will pass only on the first invocation
          // This checks that we fail the test if it starts failing later
          // during polling
        }
      }
      #expect(issues.count == 1)
    }

    @available(_clockAPI, *)
    @Test("if the closure continues to pass")
    func continuousCalling() async throws {
      let incrementor = Incrementor()

      try await confirmation(until: stop) {
        _ = await incrementor.increment()
        return true
      }

      #expect(await incrementor.count > 1)
    }

    @available(_clockAPI, *)
    @Test("Thrown errors will automatically exit & fail")
    func errorsReported() async {
      let issues = await runTest {
        try await confirmation(until: stop) {
          throw PollingTestSampleError.ohNo
        }
      }
      #expect(issues.count == 1)
    }

    @available(_clockAPI, *)
    @Test("Calculates how many times to poll based on the duration & interval")
    func defaultPollingCount() async throws {
      let incrementor = Incrementor()
      try await confirmation(until: stop, pollingEvery: .milliseconds(1)) {
        await incrementor.increment() != 0
      }
      #expect(await incrementor.count == 1000)
    }

    @Suite(
      "Configuration traits",
      .pollingConfirmationDefaults(
        until: .stopsPassing,
        within: .milliseconds(100)
      )
    )
    struct WithConfigurationTraits {
      let stop = PollingStopCondition.stopsPassing

      @available(_clockAPI, *)
      @Test(
        "When no test/callsite configuration, it uses the suite configuration"
      )
      func testUsesSuiteConfiguration() async throws {
        let incrementor = Incrementor()
        try await confirmation(until: stop, pollingEvery: .milliseconds(1)) {
          await incrementor.increment() != 0
        }
        let count = await incrementor.count
        #expect(count == 100)
      }

      @available(_clockAPI, *)
      @Test(
        "Ignore trait configurations that don't match the stop condition",
        .pollingConfirmationDefaults(
          until: .firstPass,
          within: .milliseconds(
            500
          )
        )
      ) func testIgnoresTraitsWithNonmatchingStopConditions() async throws {
        let incrementor = Incrementor()
        try await confirmation(until: stop, pollingEvery: .milliseconds(1)) {
          await incrementor.increment() != 0
        }
        let count = await incrementor.count
        #expect(count == 100)
      }

      @available(_clockAPI, *)
      @Test(
        "When test configuration porvided, uses the test configuration",
        .pollingConfirmationDefaults(
          until: .stopsPassing,
          within: .milliseconds(10)
        )
      )
      func testUsesTestConfigurationOverSuiteConfiguration() async throws  {
        let incrementor = Incrementor()
        try await confirmation(until: stop, pollingEvery: .milliseconds(1)) {
          await incrementor.increment() != 0
        }
        let count = await incrementor.count
        #expect(await count == 10)
      }

      @available(_clockAPI, *)
      @Test(
        "When callsite configuration provided, uses that",
        .pollingConfirmationDefaults(
          until: .stopsPassing,
          within: .milliseconds(10)
        )
      )
      func testUsesCallsiteConfiguration() async throws {
        let incrementor = Incrementor()
        try await confirmation(
          until: stop,
          within: .milliseconds(50),
          pollingEvery: .milliseconds(1)
        ) {
          await incrementor.increment() != 0
        }
        #expect(await incrementor.count == 50)
      }

#if !SWT_NO_EXIT_TESTS
      @available(_clockAPI, *)
      @Test("Requires duration be greater than interval")
      func testRequiresDurationGreaterThanInterval() async {
        await #expect(processExitsWith: .failure) {
          try await confirmation(
            until: .firstPass,
            within: .seconds(1),
            pollingEvery: .milliseconds(1100)
          ) { true }
        }
      }

      @available(_clockAPI, *)
      @Test("Requires duration be greater than 0")
      func testRequiresDurationGreaterThan0() async {
        await #expect(processExitsWith: .failure) {
          try await confirmation(
            until: .firstPass,
            within: .seconds(0)
          ) { true }
        }
      }

      @available(_clockAPI, *)
      @Test("Requires interval be greater than 0")
      func testRequiresIntervalGreaterThan0() async {
        await #expect(processExitsWith: .failure) {
          try await confirmation(
            until: .firstPass,
            pollingEvery: .seconds(0)
          ) { true }
        }
      }
#endif
    }
  }

  @Suite("Duration Tests", .disabled("time-sensitive"))
  struct DurationTests {
    @Suite("with PollingStopCondition.firstPass")
    struct StopConditionFirstPass {
      let stop = PollingStopCondition.firstPass
      let delta = Duration.milliseconds(100)

      @available(_clockAPI, *)
      @Test("Simple passing expressions") func trivialHappyPath() async throws {
        let duration = try await Test.Clock().measure {
          try await confirmation(until: stop) { true }
        }
        #expect(duration.isCloseTo(other: .zero, within: delta))
      }

      @available(_clockAPI, *)
      @Test("Simple failing expressions") func trivialSadPath() async {
        let duration = await Test.Clock().measure {
          let issues = await runTest {
            try await confirmation(until: stop) { false }
          }
          #expect(issues.count == 1)
        }
        #expect(duration.isCloseTo(other: .seconds(2), within: delta))
      }

      @available(_clockAPI, *)
      @Test("When the value changes from false to true during execution")
      func changingFromFail() async throws {
        let incrementor = Incrementor()

        let duration = try await Test.Clock().measure {
          try await confirmation(until: stop) {
            await incrementor.increment() == 2
            // this will pass only on the second invocation
            // This checks that we really are only running the expression until
            // the first time it passes.
          }
        }

        // and then we check the count just to double check.
        #expect(await incrementor.count == 2)
        #expect(duration.isCloseTo(other: .zero, within: delta))
      }

      @available(_clockAPI, *)
      @Test("Doesn't wait after the last iteration")
      func lastIteration() async {
        let duration = await Test.Clock().measure {
          let issues = await runTest {
            try await confirmation(
              until: stop,
              within: .seconds(10),
              pollingEvery: .seconds(1) // Wait a long time to handle jitter.
            ) { false }
          }
          #expect(issues.count == 1)
        }
        #expect(
          duration.isCloseTo(
            other: .seconds(9),
            within: .milliseconds(500)
          )
        )
      }
    }

    @Suite("with PollingStopCondition.stopsPassing")
    struct StopConditionStopsPassing {
      let stop = PollingStopCondition.stopsPassing
      let delta = Duration.milliseconds(100)

      @available(_clockAPI, *)
      @Test("Simple passing expressions") func trivialHappyPath() async throws {
        let duration = try await Test.Clock().measure {
          try await confirmation(until: stop) { true }
        }
        #expect(duration.isCloseTo(other: .seconds(2), within: delta))
      }

      @available(_clockAPI, *)
      @Test("Simple failing expressions") func trivialSadPath() async {
        let duration = await Test.Clock().measure {
          _ = await runTest {
            try await confirmation(until: stop) { false }
          }
        }
        #expect(duration.isCloseTo(other: .zero, within: delta))
      }

      @available(_clockAPI, *)
      @Test("Doesn't wait after the last iteration")
      func lastIteration() async throws {
        let duration = try await Test.Clock().measure {
          try await confirmation(
            until: stop,
            within: .seconds(10),
            pollingEvery: .seconds(1) // Wait a long time to handle jitter.
          ) { true }
        }
        #expect(
          duration.isCloseTo(
            other: .seconds(9),
            within: .milliseconds(500)
          )
        )
      }
    }
  }
}

private enum PollingTestSampleError: Error {
  case ohNo
  case secondCase
}

@available(_clockAPI, *)
extension DurationProtocol {
  fileprivate func isCloseTo(other: Self, within delta: Self) -> Bool {
    var distance = self - other
    if (distance < Self.zero) {
      distance *= -1
    }
    return distance <= delta
  }
}

private actor Incrementor {
  var count = 0
  func increment() -> Int {
    count += 1
    return count
  }
}
