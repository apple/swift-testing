//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

extension Issue {
  /// Record this issue by wrapping it in an ``Event`` and passing it to the
  /// current event handler.
  ///
  /// - Parameters:
  ///   - configuration: The test configuration to use when recording the issue.
  ///     The default value is ``Configuration/current``.
  ///
  /// - Returns: The issue that was recorded (`self` or a modified copy of it.)
  @discardableResult
  func record(configuration: Configuration? = nil) -> Self {
    // If this issue is a caught error that has a custom issue representation,
    // perform that customization now.
    if case let .errorCaught(error) = kind {
      if let error = error as? any CustomIssueRepresentable {
        let selfCopy = error.customize(self)
        return selfCopy.record(configuration: configuration)
      }
    }

    // If this issue matches via the known issue matcher, set a copy of it to be
    // known and record the copy instead.
    if !isKnown, let context = KnownIssueScope.current?.matcher(self) {
      var selfCopy = self
      selfCopy.knownIssueContext = context
      return selfCopy.record(configuration: configuration)
    }

    Event.post(.issueRecorded(self), configuration: configuration)

    if !isKnown {
      // Since this is not a known issue, invoke the failure breakpoint.
      //
      // Do this after posting the event above, to allow the issue to be printed
      // to the console first (assuming the event handler does this), since that
      // can help explain the failure.
      failureBreakpoint()
    }

    return self
  }

  /// Records an issue that a test encounters while it's running.
  ///
  /// - Parameters:
  ///   - comment: A comment describing the expectation.
  ///   - sourceLocation: The source location to which the issue should be
  ///     attributed.
  ///
  /// - Returns: The issue that was recorded.
  ///
  /// Use this function if, while running a test, an issue occurs that cannot be
  /// represented as an expectation (using the ``expect(_:_:sourceLocation:)``
  /// or ``require(_:_:sourceLocation:)-5l63q`` macros.)
  @_disfavoredOverload
  @_documentation(visibility: private)
  @available(*, deprecated, message: "Use record(_:severity:sourceLocation:) instead.")
  @discardableResult public static func record(
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
  ) -> Self {
    record(comment, severity: .error, sourceLocation: sourceLocation)
  }

  /// Records an issue that a test encounters while it's running.
  ///
  /// - Parameters:
  ///   - comment: A comment describing the expectation.
  ///   - severity: The severity level of the issue.  The testing library marks the
  ///   test as failed if the severity is greater than ``Issue/Severity/warning``.
  ///   The default is ``Issue/Severity/error``.
  ///   - sourceLocation: The source location to which the issue should be
  ///     attributed.
  ///
  /// - Returns: The issue that was recorded.
  ///
  /// Use this function if, while running a test, an issue occurs that cannot be
  /// represented as an expectation (using the ``expect(_:_:sourceLocation:)``
  /// or ``require(_:_:sourceLocation:)-5l63q`` macros.)
  /// 
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.3)
  /// }
  @discardableResult public static func record(
    _ comment: Comment? = nil,
    severity: Severity = .error,
    sourceLocation: SourceLocation = #_sourceLocation
  ) -> Self {
    let sourceContext = SourceContext(backtrace: .current(), sourceLocation: sourceLocation)
    let issue = Issue(kind: .unconditional, severity: severity, comments: Array(comment), sourceContext: sourceContext)
    return issue.record()
  }
}

// MARK: - Recording issues for errors

extension Issue {
  /// Record a new issue when a running test unexpectedly catches an error.
  ///
  /// - Parameters:
  ///   - error: The error that caused the issue.
  ///   - comment: A comment describing the expectation.
  ///   - sourceLocation: The source location to which the issue should be
  ///     attributed.
  ///
  /// - Returns: The issue that was recorded.
  ///
  /// This function can be used if an unexpected error is caught while running a
  /// test and it should be treated as a test failure. If an error is thrown
  /// from a test function, it is automatically recorded as an issue and this
  /// function does not need to be used.
  @discardableResult public static func record(
    _ error: any Error,
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
  ) -> Self {
    record(error, comment, severity: .error, sourceLocation: sourceLocation)
  }
  
  /// Record a new issue when a running test unexpectedly catches an error.
  ///
  /// - Parameters:
  ///   - error: The error that caused the issue.
  ///   - comment: A comment describing the expectation.
  ///   - severity: The severity of the issue.
  ///   - sourceLocation: The source location to which the issue should be
  ///     attributed.
  ///
  /// - Returns: The issue that was recorded.
  ///
  /// This function can be used if an unexpected error is caught while running a
  /// test and it should be treated as a test failure. If an error is thrown
  /// from a test function, it is automatically recorded as an issue and this
  /// function does not need to be used.
  @_spi(Experimental)
  @discardableResult public static func record(
    _ error: any Error,
    _ comment: Comment? = nil,
    severity: Severity,
    sourceLocation: SourceLocation = #_sourceLocation
  ) -> Self {
    let backtrace = Backtrace(forFirstThrowOf: error) ?? Backtrace.current()
    let sourceContext = SourceContext(backtrace: backtrace, sourceLocation: sourceLocation)
    let issue = Issue(kind: .errorCaught(error), severity: severity, comments: Array(comment), sourceContext: sourceContext)
    return issue.record()
  }

  /// Catch any error thrown from a closure and record it as an issue instead of
  /// allowing it to propagate to the caller.
  ///
  /// - Parameters:
  ///   - sourceLocation: The source location to attribute any caught error to,
  ///     if available.
  ///   - configuration: The test configuration to use when recording an issue.
  ///     The default value is ``Configuration/current``.
  ///   - body: A closure that might throw an error.
  ///
  /// - Returns: The issue representing the caught error, if any error was
  ///   caught, otherwise `nil`.
  @discardableResult
  static func withErrorRecording(
    at sourceLocation: SourceLocation?,
    configuration: Configuration? = nil,
    _ body: () throws -> Void
  ) -> (any Error)? {
    // Ensure that we are capturing backtraces for errors before we start
    // expecting to see them.
    Backtrace.startCachingForThrownErrors()
    defer {
      Backtrace.flushThrownErrorCache()
    }

    do {
      try body()
    } catch is ExpectationFailedError {
      // This error is thrown by expectation checking functions to indicate a
      // condition evaluated to `false`. Those functions record their own issue,
      // so we don't need to record another one redundantly.
    } catch let error where SkipInfo(error) != nil {
      // This error represents control flow rather than an issue, so we suppress
      // it here.
    } catch {
      let issue = Issue(for: error, sourceLocation: sourceLocation)
      issue.record(configuration: configuration)
      return error
    }

    return nil
  }

  /// Catch any error thrown from an asynchronous closure and record it as an
  /// issue instead of allowing it to propagate to the caller.
  ///
  /// - Parameters:
  ///   - sourceLocation: The source location to attribute any caught error to,
  ///     if available.
  ///   - configuration: The test configuration to use when recording an issue.
  ///     The default value is ``Configuration/current``.
  ///   - isolation: The actor to which `body` is isolated, if any.
  ///   - body: An asynchronous closure that might throw an error.
  ///
  /// - Returns: The issue representing the caught error, if any error was
  ///   caught, otherwise `nil`.
  @discardableResult
  static func withErrorRecording(
    at sourceLocation: SourceLocation?,
    configuration: Configuration? = nil,
    isolation: isolated (any Actor)? = #isolation,
    _ body: () async throws -> Void
  ) async -> (any Error)? {
    // Ensure that we are capturing backtraces for errors before we start
    // expecting to see them.
    Backtrace.startCachingForThrownErrors()
    defer {
      Backtrace.flushThrownErrorCache()
    }

    do {
      try await body()
    } catch is ExpectationFailedError {
      // This error is thrown by expectation checking functions to indicate a
      // condition evaluated to `false`. Those functions record their own issue,
      // so we don't need to record another one redundantly.
    } catch let error where SkipInfo(error) != nil {
      // This error represents control flow rather than an issue, so we suppress
      // it here.
    } catch {
      let issue = Issue(for: error, sourceLocation: sourceLocation)
      issue.record(configuration: configuration)
      return error
    }

    return nil
  }
}

// MARK: - Debugging failures

/// A unique value used by ``failureBreakpoint()``.
#if !os(Windows) && !os(Android)
// Work around compiler bug by not specifying unchecked exclusivity on Windows/Android.
// SEE: https://github.com/swiftlang/swift/issues/76279
@exclusivity(unchecked)
#endif
@usableFromInline nonisolated(unsafe) var failureBreakpointValue = 0

/// A function called by the testing library when a failure occurs.
///
/// Whenever a test failure (specifically, a non-known ``Issue``) is recorded,
/// the testing library calls this function synchronously. This facilitates
/// interactive debugging of test failures: If you add a symbolic breakpoint
/// specifying the name of this function, the debugger will pause execution and
/// allow you to inspect the process state.
///
/// When creating a symbolic breakpoint for this function, it is recommended
/// that you constrain it to the `Testing` module to avoid collisions with
/// similarly-named functions in other modules. If you are using LLDB, you can
/// use the following command to create the breakpoint:
///
/// ```lldb
/// (lldb) breakpoint set -s Testing -n "failureBreakpoint()"
/// ```
///
/// This function performs no action of its own. It is not part of the public
/// interface of the testing library, but it is exported and its symbol name
/// must remain stable.
@inline(never)
@usableFromInline
func failureBreakpoint() {
  // This function's body cannot be completely empty or else linker symbol
  // de-duplication will cause its symbol to be consolidated with that of
  // another, arbitrarily chosen empty function in this module. This linker
  // behavior can be disabled by passing the `-no_deduplicate` flag described in
  // ld(1), but that would disable it module-wide and sacrifice optimization
  // opportunities elsewhere. Instead, this function performs a trivial
  // operation on a usable-from-inline value, which the compiler must assume
  // cannot be optimized away.
  failureBreakpointValue = 0
}
