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

struct `Polling Confirmation Tests` {
  struct `with PollingStopCondition.firstPass` {
    let stop = PollingStopCondition.firstPass

    @available(_clockAPI, *)
    @Test func `simple passing expressions`() async throws {
      try await confirmation(until: stop) { true }

      let value = try await confirmation(until: stop) { 1 }

      #expect(value == 1)
    }

    @available(_clockAPI, *)
    @Test func `simple failing expressions`() async throws {
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
    @Test
    func `returning false in a closure returning Optional<Bool> is considered a pass`() async throws {
      try await confirmation(until: stop) { () -> Bool? in
        return false
      }
    }

    @available(_clockAPI, *)
    @Test
    func `When the value changes from false to true during execution`() async throws {
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
    @Test func `Thrown errors are treated as returning false`() async throws {
      let issues = await runTest {
        try await confirmation(until: stop) {
          throw PollingTestSampleError.ohNo
        }
      }
      #expect(issues.count == 1)
    }

    @available(_clockAPI, *)
    @Test
    func `Calculates how many times to poll based on the duration & interval`() async {
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
      .pollingConfirmationDefaults(
        until: .firstPass,
        within: .milliseconds(100)
      )
    )
    struct `Configuration traits` {
      let stop = PollingStopCondition.firstPass

      @available(_clockAPI, *)
      @Test
      func `When no test or callsite configuration provided, uses the suite configuration`() async {
        let incrementor = Incrementor()
        var test = Test {
          try await confirmation(until: stop, pollingEvery: .milliseconds(1)) {
            await incrementor.increment() == 0
          }
        }
        test.traits = Test.current?.traits ?? []
        await runTest(test: test)
        #expect(await incrementor.count == 100)
      }

      @available(_clockAPI, *)
      @Test(
        .pollingConfirmationDefaults(
          until: .stopsPassing,
          within: .milliseconds(
            500
          )
        )
      )
      func `Ignore trait configurations that don't match the stop condition`() async {
        let incrementor = Incrementor()
        var test = Test {
          try await confirmation(until: stop, pollingEvery: .milliseconds(1)) {
            await incrementor.increment() == 0
          }
        }
        test.traits = Test.current?.traits ?? []
        await runTest(test: test)
        #expect(await incrementor.count == 100)
      }

      @available(_clockAPI, *)
      @Test(
        .pollingConfirmationDefaults(
          until: .firstPass,
          within: .milliseconds(10)
        )
      )
      func `When test configuration provided, uses the test configuration`() async {
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
        .pollingConfirmationDefaults(
          until: .firstPass,
          within: .milliseconds(10)
        )
      )
      func `When callsite configuration provided, uses that`() async {
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

      @available(_clockAPI, *)
      @Test func `Allows duration to be equal to interval`() async throws {
        let incrementor = Incrementor()
        try await confirmation(
          until: stop,
          within: .milliseconds(100),
          pollingEvery: .milliseconds(100)
        ) {
          _ = await incrementor.increment()
          return true
        }

        #expect(await incrementor.count == 1)
      }

#if !SWT_NO_EXIT_TESTS
      @available(_clockAPI, *)
      @Test
      func `Requires duration be greater than or equal to interval`() async {
        await #expect(processExitsWith: .failure) {
          try await confirmation(
            until: .firstPass,
            within: .seconds(1),
            pollingEvery: .milliseconds(1100)
          ) { true }
        }
      }

      @available(_clockAPI, *)
      @Test func `Requires interval be greater than 0`() async {
        await #expect(processExitsWith: .failure) {
          try await confirmation(
            until: .firstPass,
            pollingEvery: .seconds(0)
          ) { true }
        }
      }

      @available(_clockAPI, *)
      @Test func `Handles extremely large polling iterations`() async throws {
        await #expect(processExitsWith: .success) {
          try await confirmation(
            until: .firstPass,
            within: .seconds(Int.max),
            pollingEvery: .nanoseconds(1)
          ) { true }
        }
      }
#endif
    }
  }

  struct `with PollingStopCondition.stopsPassing` {
    let stop = PollingStopCondition.stopsPassing
    @available(_clockAPI, *)
    @Test func `Simple passing expressions`() async throws {
      try await confirmation(until: stop) { true }
      let value = try await confirmation(until: stop) { 1 }

      #expect(value == 1)
    }

    @available(_clockAPI, *)
    @Test func `Simple failing expressions`() async {
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
    @Test
    func `returning false in a closure returning Optional<Bool> is considered a pass`() async throws {
      try await confirmation(until: stop) { () -> Bool? in
        return false
      }
    }

    @available(_clockAPI, *)
    @Test func `if the closure starts off as true, but becomes false`() async {
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
    @Test func `if the closure continues to pass`() async throws {
      let incrementor = Incrementor()

      try await confirmation(until: stop) {
        _ = await incrementor.increment()
        return true
      }

      #expect(await incrementor.count > 1)
    }

    @available(_clockAPI, *)
    @Test func `Thrown errors will automatically exit & fail`() async {
      let issues = await runTest {
        try await confirmation(until: stop) {
          throw PollingTestSampleError.ohNo
        }
      }
      #expect(issues.count == 1)
    }

    @available(_clockAPI, *)
    @Test
    func `Calculates how many times to poll based on the duration & interval`() async throws {
      let incrementor = Incrementor()
      try await confirmation(until: stop, pollingEvery: .milliseconds(1)) {
        await incrementor.increment() != 0
      }
      #expect(await incrementor.count == 1000)
    }

    @Suite(
      .pollingConfirmationDefaults(
        until: .stopsPassing,
        within: .milliseconds(100)
      )
    )
    struct `Configuration traits` {
      let stop = PollingStopCondition.stopsPassing

      @available(_clockAPI, *)
      @Test
      func `"When no test/callsite configuration, it uses the suite configuration"`() async throws {
        let incrementor = Incrementor()
        try await confirmation(until: stop, pollingEvery: .milliseconds(1)) {
          await incrementor.increment() != 0
        }
        let count = await incrementor.count
        #expect(count == 100)
      }

      @available(_clockAPI, *)
      @Test(
        .pollingConfirmationDefaults(
          until: .firstPass,
          within: .milliseconds(
            500
          )
        )
      )
      func `Ignore trait configurations that don't match the stop condition`() async throws {
        let incrementor = Incrementor()
        try await confirmation(until: stop, pollingEvery: .milliseconds(1)) {
          await incrementor.increment() != 0
        }
        let count = await incrementor.count
        #expect(count == 100)
      }

      @available(_clockAPI, *)
      @Test(
        .pollingConfirmationDefaults(
          until: .stopsPassing,
          within: .milliseconds(10)
        )
      )
      func `When test configuration provided, uses the test configuration`() async throws  {
        let incrementor = Incrementor()
        try await confirmation(until: stop, pollingEvery: .milliseconds(1)) {
          await incrementor.increment() != 0
        }
        let count = await incrementor.count
        #expect(await count == 10)
      }

      @available(_clockAPI, *)
      @Test(
        .pollingConfirmationDefaults(
          until: .stopsPassing,
          within: .milliseconds(10)
        )
      )
      func `When callsite configuration provided, uses that`() async throws {
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

      @available(_clockAPI, *)
      @Test func `Allows duration to be equal to interval`() async throws {
        let incrementor = Incrementor()
        try await confirmation(
          until: stop,
          within: .milliseconds(100),
          pollingEvery: .milliseconds(100)
        ) {
          _ = await incrementor.increment()
          return true
        }

        #expect(await incrementor.count == 1)
      }

#if !SWT_NO_EXIT_TESTS
      @available(_clockAPI, *)
      @Test
      func `Requires duration be greater than or equal to interval`() async {
        await #expect(processExitsWith: .failure) {
          try await confirmation(
            until: .stopsPassing,
            within: .seconds(1),
            pollingEvery: .milliseconds(1100)
          ) { true }
        }
      }

      @available(_clockAPI, *)
      @Test func `Requires duration be greater than 0`() async {
        await #expect(processExitsWith: .failure) {
          try await confirmation(
            until: .stopsPassing,
            within: .seconds(0)
          ) { true }
        }
      }

      @available(_clockAPI, *)
      @Test func `Requires interval be greater than 0`() async {
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

  @Suite(.disabled("time-sensitive"))
  struct `Duration Tests` {
    struct `with PollingStopCondition.firstPass` {
      let stop = PollingStopCondition.firstPass
      let delta = Duration.milliseconds(100)

      @available(_clockAPI, *)
      @Test func `Simple passing expressions`() async throws {
        let duration = try await Test.Clock().measure {
          try await confirmation(until: stop) { true }
        }
        #expect(duration.isCloseTo(other: .zero, within: delta))
      }

      @available(_clockAPI, *)
      @Test func `Simple failing expressions`() async {
        let duration = await Test.Clock().measure {
          let issues = await runTest {
            try await confirmation(until: stop) { false }
          }
          #expect(issues.count == 1)
        }
        #expect(duration.isCloseTo(other: .seconds(2), within: delta))
      }

      @available(_clockAPI, *)
      @Test
      func `When the value changes from false to true during execution`() async throws {
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
      @Test func `Doesn't wait after the last iteration`() async {
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

    struct `with PollingStopCondition.stopsPassing` {
      let stop = PollingStopCondition.stopsPassing
      let delta = Duration.milliseconds(100)

      @available(_clockAPI, *)
      @Test func `Simple passing expressions`() async throws {
        let duration = try await Test.Clock().measure {
          try await confirmation(until: stop) { true }
        }
        #expect(duration.isCloseTo(other: .seconds(2), within: delta))
      }

      @available(_clockAPI, *)
      @Test func `Simple failing expressions`() async {
        let duration = await Test.Clock().measure {
          _ = await runTest {
            try await confirmation(until: stop) { false }
          }
        }
        #expect(duration.isCloseTo(other: .zero, within: delta))
      }

      @available(_clockAPI, *)
      @Test
      func `Doesn't wait after the last iteration`() async throws {
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
