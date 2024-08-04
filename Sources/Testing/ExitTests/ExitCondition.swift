//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

private import _TestingInternals

/// An enumeration describing possible conditions under which an exit test will
/// succeed or fail.
///
/// Values of this type can be passed to
/// ``expect(exitsWith:_:sourceLocation:performing:)`` or
/// ``require(exitsWith:_:sourceLocation:performing:)`` to configure which exit
/// statuses should be considered successful.
@_spi(Experimental)
#if SWT_NO_EXIT_TESTS
@available(*, unavailable, message: "Exit tests are not available on this platform.")
#endif
public enum ExitCondition: Sendable {
  /// The process terminated successfully with status `EXIT_SUCCESS`.
  public static var success: Self { .exitCode(EXIT_SUCCESS) }

  /// The process terminated abnormally with any status other than
  /// `EXIT_SUCCESS` or with any signal.
  case failure

  /// The process terminated with the given exit code.
  ///
  /// - Parameters:
  ///   - exitCode: The exit code yielded by the process.
  ///
  /// The C programming language defines two [standard exit codes](https://en.cppreference.com/w/c/program/EXIT_status),
  /// `EXIT_SUCCESS` and `EXIT_FAILURE`. Platforms may additionally define their
  /// own non-standard exit codes:
  ///
  /// | Platform | Header |
  /// |-|-|
  /// | macOS | [`<stdlib.h>`](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/_Exit.3.html), [`<sysexits.h>`](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/sysexits.3.html) |
  /// | Linux | `<stdlib.h>`, `<sysexits.h>` |
  /// | Windows | [`<stdlib.h>`](https://learn.microsoft.com/en-us/cpp/c-runtime-library/exit-success-exit-failure) |
  ///
  /// On POSIX-like systems including macOS and Linux, only the low unsigned 8
  /// bits (0&ndash;255) of the exit code are reliably preserved and reported to
  /// a parent process.
  case exitCode(_ exitCode: CInt)

  /// The process terminated with the given signal.
  ///
  /// - Parameters:
  ///   - signal: The signal that terminated the process.
  ///
  /// The C programming language defines a number of [standard signals](https://en.cppreference.com/w/c/program/SIG_types).
  /// Platforms may additionally define their own non-standard signal codes:
  ///
  /// | Platform | Header |
  /// |-|-|
  /// | macOS | [`<signal.h>`](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/signal.3.html) |
  /// | Linux | `<signal.h>` |
  /// | Windows | [`<signal.h>`](https://learn.microsoft.com/en-us/cpp/c-runtime-library/signal-constants) |
  ///
  /// On Windows, by default, the C runtime will terminate a process with exit
  /// code `-3` if a raised signal is not handled, exactly as if `exit(-3)` were
  /// called. As a result, this case is unavailable on that platform. Developers
  /// should use ``failure`` instead when testing signal handling on Windows.
#if os(Windows)
  @available(*, unavailable, message: "On Windows, use .failure instead.")
#endif
  case signal(_ signal: CInt)
}

// MARK: -

#if SWT_NO_EXIT_TESTS
@available(*, unavailable, message: "Exit tests are not available on this platform.")
#endif
extension ExitCondition {
  /// Check whether this instance matches another.
  ///
  /// - Parameters:
  ///   - other: The other instance to compare against.
  ///
  /// - Returns: Whether or not this instance is equal to, or at least covers,
  ///   the other instance.
  func matches(_ other: ExitCondition) -> Bool {
    return switch (self, other) {
    case (.failure, .failure):
      true
    case let (.failure, .exitCode(exitCode)), let (.exitCode(exitCode), .failure):
      exitCode != EXIT_SUCCESS
    case let (.exitCode(lhs), .exitCode(rhs)):
      lhs == rhs
#if !os(Windows)
    case let (.signal(lhs), .signal(rhs)):
      lhs == rhs
    case (.signal, .failure), (.failure, .signal):
      // All terminating signals are considered failures.
      true
    case (.signal, .exitCode), (.exitCode, .signal):
      // Signals do not match exit codes.
      false
#endif
    }
  }
}
