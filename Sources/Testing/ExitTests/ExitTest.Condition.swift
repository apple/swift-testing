//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024–2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

private import _TestingInternals

#if SWT_NO_EXIT_TESTS
@_unavailableInEmbedded
@available(*, unavailable, message: "Exit tests are not available on this platform.")
#endif
extension ExitTest {
  /// The possible conditions under which an exit test will complete.
  ///
  /// Values of this type are used to describe the conditions under which an
  /// exit test is expected to pass or fail by passing them to
  /// ``expect(processExitsWith:observing:_:sourceLocation:performing:)`` or
  /// ``require(processExitsWith:observing:_:sourceLocation:performing:)``.
  ///
  /// ## Topics
  ///
  /// ### Successful exit conditions
  ///
  /// - ``success``
  ///
  /// ### Failing exit conditions
  ///
  /// - ``failure``
  /// - ``exitCode(_:)``
  /// - ``signal(_:)``
  ///
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.2)
  ///   @Available(Xcode, introduced: 26.0)
  /// }
  public struct Condition: Sendable {
    /// An enumeration describing the possible conditions for an exit test.
    private enum _Kind: Sendable, Equatable {
      /// The exit test must exit with a particular exit status.
      case exitStatus(ExitStatus)

      /// The exit test must exit successfully.
      case success

      /// The exit test must exit with any failure.
      case failure
    }

    /// The kind of condition.
    private var _kind: _Kind
  }
}

// MARK: -

#if SWT_NO_EXIT_TESTS
@_unavailableInEmbedded
@available(*, unavailable, message: "Exit tests are not available on this platform.")
#endif
extension ExitTest.Condition {
  /// A condition that matches when a process exits normally.
  ///
  /// This condition matches the exit code `EXIT_SUCCESS`.
  ///
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.2)
  ///   @Available(Xcode, introduced: 26.0)
  /// }
  public static var success: Self {
    Self(_kind: .success)
  }

  /// A condition that matches when a process exits abnormally
  ///
  /// This condition matches any exit code other than `EXIT_SUCCESS` or any
  /// signal that causes the process to exit.
  ///
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.2)
  ///   @Available(Xcode, introduced: 26.0)
  /// }
  public static var failure: Self {
    Self(_kind: .failure)
  }

  /// Initialize an instance of this type that matches the specified exit
  /// status.
  ///
  /// - Parameters:
  ///   - exitStatus: The particular exit status this condition should match.
  ///
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.2)
  ///   @Available(Xcode, introduced: 26.0)
  /// }
  public init(_ exitStatus: ExitStatus) {
    self.init(_kind: .exitStatus(exitStatus))
  }

  /// Creates a condition that matches when a process terminates with a given
  /// exit code.
  ///
  /// - Parameters:
  ///   - exitCode: The exit code reported by the process.
  ///
  /// The C programming language defines two standard exit codes, `EXIT_SUCCESS`
  /// and `EXIT_FAILURE`. Platforms may additionally define their own
  /// non-standard exit codes:
  ///
  /// | Platform | Header |
  /// |-|-|
  /// | macOS | [`<stdlib.h>`](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/_Exit.3.html), [`<sysexits.h>`](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/sysexits.3.html) |
  /// | Linux | [`<stdlib.h>`](https://www.kernel.org/doc/man-pages/online/pages/man3/exit.3.html), [`<sysexits.h>`](https://www.kernel.org/doc/man-pages/online/pages/man3/sysexits.h.3head.html) |
  /// | FreeBSD | [`<stdlib.h>`](https://man.freebsd.org/cgi/man.cgi?exit(3)), [`<sysexits.h>`](https://man.freebsd.org/cgi/man.cgi?sysexits(3)) |
  /// | OpenBSD | [`<stdlib.h>`](https://man.openbsd.org/exit.3), [`<sysexits.h>`](https://man.openbsd.org/sysexits.3) |
  /// | Windows | [`<stdlib.h>`](https://learn.microsoft.com/en-us/cpp/c-runtime-library/exit-success-exit-failure) |
  ///
  /// @Comment {
  ///   See https://en.cppreference.com/w/c/program/EXIT_status for more
  ///   information about exit codes defined by the C standard.
  /// }
  ///
  /// On macOS, FreeBSD, OpenBSD, and Windows, the full exit code reported by
  /// the process is reported to the parent process. Linux and other POSIX-like
  /// systems may only reliably report the low unsigned 8 bits (0&ndash;255) of
  /// the exit code.
  ///
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.2)
  ///   @Available(Xcode, introduced: 26.0)
  /// }
  public static func exitCode(_ exitCode: CInt) -> Self {
#if !SWT_NO_EXIT_TESTS
    Self(.exitCode(exitCode))
#else
    swt_unreachable()
#endif
  }

  /// Creates a condition that matches when a process exits with a given signal.
  ///
  /// - Parameters:
  ///   - signal: The signal that caused the process to exit.
  ///
  /// The C programming language defines a number of standard signals. Platforms
  /// may additionally define their own non-standard signal codes:
  ///
  /// | Platform | Header |
  /// |-|-|
  /// | macOS | [`<signal.h>`](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/signal.3.html) |
  /// | Linux | [`<signal.h>`](https://www.kernel.org/doc/man-pages/online/pages/man7/signal.7.html) |
  /// | FreeBSD | [`<signal.h>`](https://man.freebsd.org/cgi/man.cgi?signal(3)) |
  /// | OpenBSD | [`<signal.h>`](https://man.openbsd.org/signal.3) |
  /// | Windows | [`<signal.h>`](https://learn.microsoft.com/en-us/cpp/c-runtime-library/signal-constants) |
  ///
  /// @Comment {
  ///   See https://en.cppreference.com/w/c/program/SIG_types for more
  ///   information about signals defined by the C standard.
  /// }
  ///
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.2)
  ///   @Available(Xcode, introduced: 26.0)
  /// }
  public static func signal(_ signal: CInt) -> Self {
#if !SWT_NO_EXIT_TESTS
    Self(.signal(signal))
#else
    swt_unreachable()
#endif
  }
}

// MARK: - CustomStringConvertible

#if SWT_NO_EXIT_TESTS
@_unavailableInEmbedded
@available(*, unavailable, message: "Exit tests are not available on this platform.")
#endif
extension ExitTest.Condition: CustomStringConvertible {
  public var description: String {
#if !SWT_NO_EXIT_TESTS
    switch _kind {
    case .failure:
      ".failure"
    case .success:
      ".success"
    case let .exitStatus(exitStatus):
      String(describing: exitStatus)
    }
#else
    swt_unreachable()
#endif
  }
}

// MARK: - Comparison

#if SWT_NO_EXIT_TESTS
@_unavailableInEmbedded
@available(*, unavailable, message: "Exit tests are not available on this platform.")
#endif
extension ExitTest.Condition {
  /// Check whether or not an exit test condition matches a given exit status.
  ///
  /// - Parameters:
  ///   - exitStatus: An exit status to compare against.
  ///
  /// - Returns: Whether or not `self` and `exitStatus` represent the same exit
  ///   condition.
  ///
  /// Two exit test conditions can be compared; if either instance is equal to
  /// ``failure``, it will compare equal to any instance except ``success``.
  func isApproximatelyEqual(to exitStatus: ExitStatus) -> Bool {
    // Strictly speaking, the C standard treats 0 as a successful exit code and
    // potentially distinct from EXIT_SUCCESS. To my knowledge, no modern
    // operating system defines EXIT_SUCCESS to any value other than 0, so the
    // distinction is academic.
    return switch (self._kind, exitStatus) {
    case let (.success, .exitCode(exitCode)):
      exitCode == EXIT_SUCCESS
    case let (.failure, .exitCode(exitCode)):
      exitCode != EXIT_SUCCESS
    case (.failure, .signal):
      // All terminating signals are considered failures.
      true
    default:
      self._kind == .exitStatus(exitStatus)
    }
  }
}
