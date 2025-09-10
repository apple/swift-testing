//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

private import _TestingInternals

/// A type that defines a time limit to apply to a test.
///
/// To add this trait to a test, use ``Trait/timeLimit(_:)-4kzjp``.
@available(_clockAPI, *)
public struct TimeLimitTrait: TestTrait, SuiteTrait {
  /// A type representing the duration of a time limit applied to a test.
  ///
  /// Use this type to specify a test timeout with ``TimeLimitTrait``.
  /// `TimeLimitTrait` uses this type instead of Swift's built-in `Duration`
  /// type because the testing library doesn't support high-precision,
  /// arbitrarily short durations for test timeouts. The smallest unit of time
  /// you can specify in a `Duration` is minutes.
  public struct Duration: Sendable {
    /// The underlying Swift `Duration` which this time limit duration
    /// represents.
    var underlyingDuration: Swift.Duration

    /// Construct a time limit duration given a number of minutes.
    ///
    /// - Parameters:
    ///   - minutes: The length of the duration in minutes.
    ///
    /// - Returns: A duration representing the specified number of minutes.
    public static func minutes(_ minutes: some BinaryInteger) -> Self {
      Self(underlyingDuration: .seconds(60) * minutes)
    }
  }

  /// The maximum amount of time a test may run for before timing out.
  public var timeLimit: Swift.Duration

  public var isRecursive: Bool {
    // Since test functions cannot be nested inside other test functions,
    // inheriting time limits from a parent test implies inheriting them from
    // parent test suite types. Types do not take any time to execute on their
    // own (other than some testing library overhead.)
    true
  }
}

// MARK: -

@available(_clockAPI, *)
extension Trait where Self == TimeLimitTrait {
  /// Construct a time limit trait that causes a test to time out if it runs for
  /// too long.
  ///
  /// - Parameters:
  ///   - timeLimit: The maximum amount of time the test may run for.
  ///
  /// - Returns: An instance of ``TimeLimitTrait``.
  ///
  /// Test timeouts do not support high-precision, arbitrarily short durations
  /// due to variability in testing environments. The time limit must be at
  /// least one minute, and can only be expressed in increments of one minute.
  ///
  /// When this trait is associated with a test, that test must complete within
  /// a time limit of, at most, `timeLimit`. If the test runs longer, an issue
  /// of kind ``Issue/Kind/timeLimitExceeded(timeLimitComponents:)`` is
  /// recorded. This timeout is treated as a test failure.
  ///
  /// The time limit amount specified by `timeLimit` may be reduced if the
  /// testing library is configured to enforce a maximum per-test limit. When
  /// such a maximum is set, the effective time limit of the test this trait is
  /// applied to will be the lesser of `timeLimit` and that maximum. This is a
  /// policy which may be configured on a global basis by the tool responsible
  /// for launching the test process. Refer to that tool's documentation for
  /// more details.
  ///
  /// If a test is parameterized, this time limit is applied to each of its
  /// test cases individually. If a test has more than one time limit associated
  /// with it, the shortest one is used. A test run may also be configured with
  /// a maximum time limit per test case.
  ///
  /// If you apply this trait to a test suite, then it sets the time limit for
  /// each test in the suite, or each test case in parameterized tests in the
  /// suite.
  /// For example, if a suite contains five tests and you apply a time limit trait
  /// with a duration of one minute, then each test in the suite may run for up to
  /// one minute.
  @_spi(Experimental)
  public static func timeLimit(_ timeLimit: Duration) -> Self {
    return Self(timeLimit: timeLimit)
  }

  /// Construct a time limit trait that causes a test to time out if it runs for
  /// too long.
  ///
  /// - Parameters:
  ///   - timeLimit: The maximum amount of time the test may run for.
  ///
  /// - Returns: An instance of ``TimeLimitTrait``.
  ///
  /// Test timeouts do not support high-precision, arbitrarily short durations
  /// due to variability in testing environments. You express the duration in
  /// minutes, with a minimum duration of one minute.
  ///
  /// When you associate this trait with a test, that test must complete within
  /// a time limit of, at most, `timeLimit`. If the test runs longer, the
  /// testing library records a
  /// ``Issue/Kind/timeLimitExceeded(timeLimitComponents:)`` issue, which it
  /// treats as a test failure.
  ///
  /// The testing library can use a shorter time limit than that specified by
  /// `timeLimit` if you configure it to enforce a maximum per-test limit. When
  /// you configure a maximum per-test limit, the time limit of the test this
  /// trait is applied to is the shorter of `timeLimit` and the maximum per-test
  /// limit. For information on configuring maximum per-test limits, consult the
  /// documentation for the tool you use to run your tests.
  ///
  /// If a test is parameterized, this time limit is applied to each of its
  /// test cases individually. If a test has more than one time limit associated
  /// with it, the testing library uses the shortest time limit.
  ///
  /// If you apply this trait to a test suite, then it sets the time limit for
  /// each test in the suite, or each test case in parameterized tests in the
  /// suite.
  /// For example, if a suite contains five tests and you apply a time limit trait
  /// with a duration of one minute, then each test in the suite may run for up to
  /// one minute.
  public static func timeLimit(_ timeLimit: Self.Duration) -> Self {
    return Self(timeLimit: timeLimit.underlyingDuration)
  }
}

@available(_clockAPI, *)
extension TimeLimitTrait.Duration {
  /// Construct a time limit duration given a number of seconds.
  ///
  /// This function is unavailable and is provided for diagnostic purposes only.
  @available(*, unavailable, message: "Time limit must be specified in minutes")
  public static func seconds(_ seconds: some BinaryInteger) -> Self {
    swt_unreachable()
  }

  /// Construct a time limit duration given a number of seconds.
  ///
  /// This function is unavailable and is provided for diagnostic purposes only.
  @available(*, unavailable, message: "Time limit must be specified in minutes")
  public static func seconds(_ seconds: Double) -> Self {
    swt_unreachable()
  }

  /// Construct a time limit duration given a number of milliseconds.
  ///
  /// This function is unavailable and is provided for diagnostic purposes only.
  @available(*, unavailable, message: "Time limit must be specified in minutes")
  public static func milliseconds(_ milliseconds: some BinaryInteger) -> Self {
    swt_unreachable()
  }

  /// Construct a time limit duration given a number of milliseconds.
  ///
  /// This function is unavailable and is provided for diagnostic purposes only.
  @available(*, unavailable, message: "Time limit must be specified in minutes")
  public static func milliseconds(_ milliseconds: Double) -> Self {
    swt_unreachable()
  }

  /// Construct a time limit duration given a number of microseconds.
  ///
  /// This function is unavailable and is provided for diagnostic purposes only.
  @available(*, unavailable, message: "Time limit must be specified in minutes")
  public static func microseconds(_ microseconds: some BinaryInteger) -> Self {
    swt_unreachable()
  }

  /// Construct a time limit duration given a number of microseconds.
  ///
  /// This function is unavailable and is provided for diagnostic purposes only.
  @available(*, unavailable, message: "Time limit must be specified in minutes")
  public static func microseconds(_ microseconds: Double) -> Self {
    swt_unreachable()
  }

  /// Construct a time limit duration given a number of nanoseconds.
  ///
  /// This function is unavailable and is provided for diagnostic purposes only.
  @available(*, unavailable, message: "Time limit must be specified in minutes")
  public static func nanoseconds(_ nanoseconds: some BinaryInteger) -> Self {
    swt_unreachable()
  }
}

// MARK: -

@available(_clockAPI, *)
extension Test {
  /// The maximum amount of time this test's cases may run for.
  ///
  /// Associate a time limit with tests by using ``Trait/timeLimit(_:)-4kzjp``.
  ///
  /// If a test has more than one time limit associated with it, the value of
  /// this property is the shortest one. If a test has no time limits associated
  /// with it, the value of this property is `nil`.
  public var timeLimit: Duration? {
    traits.lazy
      .compactMap { $0 as? TimeLimitTrait }
      .map(\.timeLimit)
      .min()
  }

  /// Get the maximum amount of time the cases of this test may run for, taking
  /// the current configuration and any library-imposed rules into account.
  ///
  /// - Parameters:
  ///   - configuration: The current configuration.
  ///
  /// - Returns: The maximum amount of time the cases of this test may run for,
  ///   or `nil` if the test may run indefinitely.
  @_spi(ForToolsIntegrationOnly)
  public func adjustedTimeLimit(configuration: Configuration) -> Duration? {
    // If this instance doesn't have a time limit configured, use the default
    // specified by the configuration.
    var timeLimit = timeLimit ?? configuration.defaultTestTimeLimit

    // Round the time limit.
    timeLimit = timeLimit.map { timeLimit in
      let granularity = configuration.testTimeLimitGranularity
      return granularity * (timeLimit / granularity).rounded(.awayFromZero)
    }

    // Do not exceed the maximum time limit specified by the configuration.
    // Perform this step after rounding to avoid exceeding the maximum (which
    // could occur if it is not a multiple of the granularity value.)
    if let maximumTestTimeLimit = configuration.maximumTestTimeLimit {
      timeLimit = timeLimit.map { timeLimit in
        min(timeLimit, maximumTestTimeLimit)
      } ?? maximumTestTimeLimit
    }

    return timeLimit
  }
}

// MARK: -

/// An error that is reported when a test times out.
///
/// This type is not part of the public interface of the testing library.
struct TimeoutError: Error, CustomStringConvertible {
  /// The time limit exceeded by the test that timed out.
  var timeLimit: TimeValue

  var description: String {
    "Timed out after \(timeLimit) seconds."
  }
}

#if !SWT_NO_UNSTRUCTURED_TASKS
/// Invoke a function with a timeout.
///
/// - Parameters:
///   - timeLimit: The amount of time until the closure times out.
///   - taskName: The name of the child task that runs `body`, if any.
///   - body: The function to invoke.
///   - timeoutHandler: A function to invoke if `body` times out.
///
/// - Throws: Any error thrown by `body`.
///
/// If `body` does not return or throw before `timeLimit` is reached,
/// `timeoutHandler` is called and given the opportunity to handle the timeout
/// and `body` is cancelled.
///
/// This function is not part of the public interface of the testing library.
@available(_clockAPI, *)
func withTimeLimit(
  _ timeLimit: Duration,
  taskName: String? = nil,
  _ body: @escaping @Sendable () async throws -> Void,
  timeoutHandler: @escaping @Sendable () -> Void
) async throws {
  try await withThrowingTaskGroup { group in
    group.addTask(name: decorateTaskName(taskName, withAction: "waiting for timeout")) {
      // If sleep() returns instead of throwing a CancellationError, that means
      // the timeout was reached before this task could be cancelled, so call
      // the timeout handler.
      try await Test.Clock.sleep(for: timeLimit)
      timeoutHandler()
    }
    group.addTask(name: decorateTaskName(taskName, withAction: "running"), operation: body)

    defer {
      group.cancelAll()
    }
    try await group.next()!
  }
}
#endif

/// Invoke a closure with a time limit derived from an instance of ``Test``.
///
/// - Parameters:
///   - test: The test that may time out.
///   - configuration: The current configuration.
///   - body: The function to invoke.
///   - timeoutHandler: A function to invoke if `body` times out. The time limit
///     applied to `body` is passed to this function.
///
/// - Throws: Any error thrown by `body`.
///
/// This function is provided as a cross-platform convenience wrapper around
/// ``withTimeLimit(_:_:timeoutHandler:)``. If the current platform does not
/// support time limits or the Swift clock API, this function invokes `body`
/// with no time limit.
///
/// This function is not part of the public interface of the testing library.
func withTimeLimit(
  for test: Test,
  configuration: Configuration,
  _ body: @escaping @Sendable () async throws -> Void,
  timeoutHandler: @escaping @Sendable (_ timeLimit: (seconds: Int64, attoseconds: Int64)) -> Void
) async throws {
  if #available(_clockAPI, *),
     let timeLimit = test.adjustedTimeLimit(configuration: configuration) {
#if SWT_NO_UNSTRUCTURED_TASKS
    // This environment may not support full concurrency, so check if the body
    // closure timed out after it returns. This won't help us catch hangs, but
    // it will at least report tests that run longer than expected.
    let start = Test.Clock.Instant.now
    defer {
      if start.duration(to: .now) > timeLimit {
        timeoutHandler(timeLimit.components)
      }
    }
    try await body()
#else
    return try await withTimeLimit(timeLimit) {
      try await body()
    } timeoutHandler: {
      timeoutHandler(timeLimit.components)
    }
#endif
  }

  try await body()
}
