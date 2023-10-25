//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

@_implementationOnly import TestingInternals

@_spi(ExperimentalEventHandling)
extension Test {
  /// A clock used to track time when events occur during testing.
  ///
  /// This clock tracks time using both the [suspending clock](https://developer.apple.com/documentation/swift/suspendingclock)
  /// and the wall clock. Only the suspending clock is used for comparing and
  /// calculating; the wall clock is used for presentation when needed.
  public struct Clock: Sendable {
    /// An instant on the testing clock.
    public struct Instant: Sendable {
      /// The corresponding suspending-clock time.
      ///
      /// The testing library's availability on Apple platforms is earlier than
      /// that of the Swift Clock API, so we don't use `SuspendingClock`
      /// directly on them and instead derive a value from platform API.
      fileprivate(set) var suspending: TimeValue = {
#if SWT_TARGET_OS_APPLE
        // SuspendingClock corresponds to CLOCK_UPTIME_RAW on Darwin.
        // SEE: https://github.com/apple/swift/blob/main/stdlib/public/Concurrency/Clock.cpp
        var uptime = timespec()
        _ = clock_gettime(CLOCK_UPTIME_RAW, &uptime)
        return TimeValue(uptime)
#else
        /// The corresponding suspending-clock time.
        TimeValue(SuspendingClock.Instant.now)
#endif
      }()

#if !SWT_NO_UTC_CLOCK
      /// The corresponding wall-clock time, in seconds and nanoseconds.
      ///
      /// This value is stored as an instance of `timespec` rather than an
      /// instance of `Duration` because the latter type requires that the Swift
      /// clocks API be available.
      fileprivate(set) var wall: TimeValue = {
        var wall = timespec()
        timespec_get(&wall, TIME_UTC)
        return TimeValue(wall)
      }()
#endif

      /// The current time according to the testing clock.
      public static var now: Self {
        Self()
      }
    }

    public init() {}
  }
}

// MARK: -

@_spi(ExperimentalEventHandling)
@available(_clockAPI, *)
extension SuspendingClock.Instant {
  /// Initialize this instant to the equivalent of the same instant on the
  /// testing library's clock.
  ///
  /// - Parameters:
  ///   - testClockInstant: The equivalent instant on ``Test/Clock``.
  public init(_ testClockInstant: Test.Clock.Instant) {
    self.init(testClockInstant.suspending)
  }
}

#if !SWT_NO_UTC_CLOCK
@_spi(ExperimentalEventHandling)
extension Test.Clock.Instant {
  /// The duration since 1970 represented by this instance as a tuple of seconds
  /// and attoseconds.
  ///
  /// The value of this property is the equivalent of `self` on the wall clock.
  /// It is suitable for display to the user, but not for fine timing
  /// calculations.
  public var timeComponentsSince1970: (seconds: Int64, attoseconds: Int64) {
    wall.components
  }

  /// The duration since 1970 represented by this instance.
  ///
  /// The value of this property is the equivalent of `self` on the wall clock.
  /// It is suitable for display to the user, but not for fine timing
  /// calculations.
  @available(_clockAPI, *)
  public var durationSince1970: Duration {
    Duration(wall)
  }
}
#endif

// MARK: - Sleeping

extension Test.Clock {
  /// Suspend the current task for the given duration.
  ///
  /// - Parameters:
  ///   - duration: How long to suspend for.
  ///
  /// - Throws: `CancellationError` if the current task was cancelled while it
  ///   was sleeping.
  ///
  /// This function is not part of the public interface of the testing library.
  /// It is primarily used by the testing library's own tests. External clients
  /// can use ``sleep(for:tolerance:)`` or ``sleep(until:tolerance:)`` instead.
  @available(_clockAPI, *)
  static func sleep(for duration: Duration) async throws {
#if SWT_NO_UNSTRUCTURED_TASKS
    var ts = timespec(duration)
    var tsRemaining = ts
    while 0 != nanosleep(&ts, &tsRemaining) {
      try Task.checkCancellation()
      ts = tsRemaining
    }
#else
    return try await SuspendingClock().sleep(for: duration)
#endif
  }
}

// MARK: - Clock

@_spi(ExperimentalEventHandling)
@available(_clockAPI, *)
extension Test.Clock: _Concurrency.Clock {
  public typealias Duration = SuspendingClock.Duration

  public var now: Instant {
    .now
  }

  public var minimumResolution: Duration {
#if SWT_TARGET_OS_APPLE
    var res = timespec()
    _ = clock_getres(CLOCK_UPTIME_RAW, &res)
    return Duration(res)
#else
    SuspendingClock().minimumResolution
#endif
  }

  public func sleep(until deadline: Instant, tolerance: Duration?) async throws {
    let duration = Instant.now.duration(to: deadline)
#if SWT_NO_UNSTRUCTURED_TASKS
    try await Self.sleep(for: duration)
#else
    try await SuspendingClock().sleep(for: duration, tolerance: tolerance)
#endif
  }
}

// MARK: - Equatable, Hashable, Comparable

@_spi(ExperimentalEventHandling)
extension Test.Clock.Instant: Equatable, Hashable, Comparable {
  public static func ==(lhs: Self, rhs: Self) -> Bool {
    lhs.suspending == rhs.suspending
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(suspending)
  }

  public static func <(lhs: Self, rhs: Self) -> Bool {
    lhs.suspending < rhs.suspending
  }
}

// MARK: - InstantProtocol

@_spi(ExperimentalEventHandling)
@available(_clockAPI, *)
extension Test.Clock.Instant: InstantProtocol {
  public typealias Duration = Swift.Duration

  public func advanced(by duration: Duration) -> Self {
    var result = self

    result.suspending = TimeValue(Duration(result.suspending) + duration)
#if !SWT_NO_UTC_CLOCK
    result.wall = TimeValue(Duration(result.wall) + duration)
#endif

    return result
  }

  public func duration(to other: Test.Clock.Instant) -> Duration {
    Duration(other.suspending) - Duration(suspending)
  }
}

// MARK: - Duration descriptions

/// Get a description of a duration represented as a tuple containing seconds
/// and attoseconds.
///
/// - Parameters:
///   - components: The duration.
///
/// - Returns: A string describing the specified duration, up to millisecond
///   accuracy.
func descriptionOfTimeComponents(_ components: (seconds: Int64, attoseconds: Int64)) -> String {
  let (secondsFromAttoseconds, attosecondsRemaining) = components.attoseconds.quotientAndRemainder(dividingBy: 1_000_000_000_000_000_000)
  let seconds = components.seconds + secondsFromAttoseconds
  var milliseconds = attosecondsRemaining / 1_000_000_000_000_000
  if seconds == 0 && milliseconds == 0 && attosecondsRemaining > 0 {
    milliseconds = 1
  }

  return withUnsafeTemporaryAllocation(of: CChar.self, capacity: 512) { buffer in
    withVaList([CLongLong(seconds), CInt(milliseconds)]) { args in
      _ = vsnprintf(buffer.baseAddress!, buffer.count, "%lld.%03d seconds", args)
    }
    return String(cString: buffer.baseAddress!)
  }
}

extension Test.Clock.Instant {
  /// Get a description of the duration between this instance and another.
  ///
  /// - Parameters:
  ///   - other: The later instant.
  ///
  /// - Returns: A string describing the duration between `self` and `other`,
  ///   up to millisecond accuracy.
  func descriptionOfDuration(to other: Test.Clock.Instant) -> String {
#if SWT_TARGET_OS_APPLE
    let otherNanoseconds = (other.suspending.seconds * 1_000_000_000) + (other.suspending.attoseconds / 1_000_000_000)
    let selfNanoseconds = (suspending.seconds * 1_000_000_000) + (suspending.attoseconds / 1_000_000_000)
    let (seconds, nanosecondsRemaining) = (otherNanoseconds - selfNanoseconds).quotientAndRemainder(dividingBy: 1_000_000_000)
    return descriptionOfTimeComponents((seconds, nanosecondsRemaining * 1_000_000_000))
#else
    return descriptionOfTimeComponents((Duration(other.suspending) - Duration(suspending)).components)
#endif
  }
}

// MARK: - Codable

extension Test.Clock.Instant: Codable {}
