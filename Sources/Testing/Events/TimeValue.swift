//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

// `internal` because `TimeValue.init(_ timespec:)` below is internal and
// references a type (`timespec`) which comes from this import.
internal import _TestingInternals

/// A container type representing a time value that is suitable for storage,
/// conversion, encoding, and decoding.
///
/// This type models time values as durations. When representing a timestamp, an
/// instance of this type represents that timestamp as an offset from an epoch
/// such as the January 1, 1970 POSIX epoch or the system's boot time; which
/// epoch depends on the calling code.
///
/// This type is not part of the public interface of the testing library. Time
/// values exposed to clients of the testing library should generally be
/// represented as instances of ``Test/Clock/Instant`` or a type from the Swift
/// standard library like ``Duration``.
struct TimeValue: Sendable {
  /// The number of whole seconds represented by this instance.
  var seconds: Int64

  /// The number of attoseconds (that is, the subsecond part) represented by
  /// this instance.
  var attoseconds: Int64

  /// The amount of time represented by this instance as a tuple.
  var components: (seconds: Int64, attoseconds: Int64) {
    (seconds, attoseconds)
  }

  init(_ components: (seconds: Int64, attoseconds: Int64)) {
    (seconds, attoseconds) = components
  }

#if !SWT_NO_TIMESPEC
  init(_ timespec: timespec) {
    self.init((Int64(timespec.tv_sec), Int64(timespec.tv_nsec) * 1_000_000_000))
  }
#endif

  @available(_clockAPI, *)
  init(_ duration: Duration) {
    self.init(duration.components)
  }

  @available(_clockAPI, *)
  init(_ instant: SuspendingClock.Instant) {
#if compiler(>=6.2)
    self.init(SuspendingClock().systemEpoch.duration(to: instant))
#else
    self.init(unsafeBitCast(instant, to: Duration.self))
#endif
  }
}

// MARK: - Equatable, Hashable, Comparable

extension TimeValue: Equatable, Hashable, Comparable {
  static func <(lhs: Self, rhs: Self) -> Bool {
    if lhs.seconds != rhs.seconds {
      return lhs.seconds < rhs.seconds
    }
    return lhs.attoseconds < rhs.attoseconds
  }
}

// MARK: - Codable

extension TimeValue: Codable {}

// MARK: - CustomStringConvertible

extension TimeValue: CustomStringConvertible {
  var description: String {
#if os(WASI)
    // BUG: https://github.com/swiftlang/swift/issues/72398
    return String(describing: Duration(self))
#else
    let (secondsFromAttoseconds, attosecondsRemaining) = attoseconds.quotientAndRemainder(dividingBy: 1_000_000_000_000_000_000)
    let seconds = seconds + secondsFromAttoseconds
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
#endif
  }
}

// MARK: -

@available(_clockAPI, *)
extension Duration {
  init(_ timeValue: TimeValue) {
    self.init(secondsComponent: timeValue.seconds, attosecondsComponent: timeValue.attoseconds)
  }
}

@available(_clockAPI, *)
extension SuspendingClock.Instant {
  init(_ timeValue: TimeValue) {
#if compiler(>=6.2)
    self = SuspendingClock().systemEpoch.advanced(by: Duration(timeValue))
#else
    self = unsafeBitCast(Duration(timeValue), to: SuspendingClock.Instant.self)
#endif
  }
}

#if !SWT_NO_TIMESPEC
extension timespec {
  init(_ timeValue: TimeValue) {
    self.init(tv_sec: .init(timeValue.seconds), tv_nsec: .init(timeValue.attoseconds / 1_000_000_000))
  }
}
#endif

extension FloatingPoint {
  /// Initialize this floating-point value with the total number of seconds
  /// (including the subsecond part) represented by an instance of
  /// ``TimeValue``.
  ///
  /// - Parameters:
  ///   - timeValue: The instance of ``TimeValue`` to convert.
  ///
  /// The resulting value may have less precision than `timeValue` as most
  /// floating-point types are unable to represent a time value's
  /// ``TimeValue/attoseconds`` property exactly.
  init(_ timeValue: TimeValue) {
    self = Self(timeValue.seconds) + (Self(timeValue.attoseconds) / (1_000_000_000_000_000_000 as Self))
  }
}
