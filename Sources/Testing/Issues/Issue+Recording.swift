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
  /// The known issue matcher, as set by `withKnownIssue()`, associated with the
  /// current task.
  ///
  /// If there is no call to `withKnownIssue()` executing on the current task,
  /// the value of this property is `nil`.
  @TaskLocal
  static var currentKnownIssueMatcher: KnownIssueMatcher?

  /// Record a new issue with the specified properties.
  ///
  /// - Parameters:
  ///   - kind: The kind of issue.
  ///   - comments: An array of comments describing the issue. This array may be
  ///     empty.
  ///   - backtrace: The backtrace of the issue, if available. This value is
  ///     used to construct an instance of ``SourceContext``.
  ///   - sourceLocation: The source location of the issue. This value is used
  ///     to construct an instance of ``SourceContext``.
  ///   - configuration: The test configuration to use when recording the issue.
  ///     The default value is ``Configuration/current``.
  ///
  /// - Returns: The issue that was recorded.
  @discardableResult
  static func record(_ kind: Kind, comments: [Comment], backtrace: Backtrace?, sourceLocation: SourceLocation, configuration: Configuration? = nil) -> Self {
    let sourceContext = SourceContext(backtrace: backtrace, sourceLocation: sourceLocation)
    return record(kind, comments: comments, sourceContext: sourceContext, configuration: configuration)
  }

  /// Record a new issue with the specified properties.
  ///
  /// - Parameters:
  ///   - kind: The kind of issue.
  ///   - comments: An array of comments describing the issue. This array may be
  ///     empty.
  ///   - sourceContext: The source context of the issue.
  ///   - configuration: The test configuration to use when recording the issue.
  ///     The default value is ``Configuration/current``.
  ///
  /// - Returns: The issue that was recorded.
  @discardableResult
  static func record(_ kind: Kind, comments: [Comment], sourceContext: SourceContext, configuration: Configuration? = nil) -> Self {
    let issue = Issue(kind: kind, comments: comments, sourceContext: sourceContext)
    return issue.record(configuration: configuration)
  }

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
    // If this issue is a caught error of kind SystemError, reinterpret it as a
    // testing system issue instead (per the documentation for SystemError.)
    if case let .errorCaught(error) = kind, let error = error as? SystemError {
      var selfCopy = self
      selfCopy.kind = .system
      selfCopy.comments.append(Comment(rawValue: String(describing: error)))
      return selfCopy.record(configuration: configuration)
    }

    // If this issue matches via the known issue matcher, set a copy of it to be
    // known and record the copy instead.
    if !isKnown, let issueMatcher = Self.currentKnownIssueMatcher, issueMatcher(self) {
      var selfCopy = self
      selfCopy.isKnown = true
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

  /// Record an issue when a running test fails unexpectedly.
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
  @discardableResult public static func record(
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
  ) -> Self {
    let sourceContext = SourceContext(backtrace: .current(), sourceLocation: sourceLocation)
    let issue = Issue(kind: .unconditional, comments: Array(comment), sourceContext: sourceContext)
    return issue.record()
  }

  /// Record an issue on behalf of a tool or library.
  ///
  /// - Parameters:
  ///   - comment: A comment describing the expectation.
  ///   - toolContext: Any tool-specific context about the issue including the
  ///     name of the tool that recorded it.
  ///   - sourceLocation: The source location to which the issue should be
  ///     attributed.
  ///
  /// - Returns: The issue that was recorded.
  ///
  /// Test authors do not generally need to use this function. Rather, a tool
  /// or library based on the testing library can use it to record a
  /// domain-specific issue and to propagatre additional information about that
  /// issue to other layers of the testing library's infrastructure.
  @_spi(Experimental)
  @discardableResult public static func record(
    _ comment: Comment? = nil,
    context toolContext: some Issue.Kind.ToolContext,
    sourceLocation: SourceLocation = #_sourceLocation
  ) -> Self {
    let sourceContext = SourceContext(backtrace: .current(), sourceLocation: sourceLocation)
    let issue = Issue(kind: .recordedByTool(toolContext), comments: Array(comment), sourceContext: sourceContext)
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
    let backtrace = Backtrace(forFirstThrowOf: error) ?? Backtrace.current()
    let sourceContext = SourceContext(backtrace: backtrace, sourceLocation: sourceLocation)
    let issue = Issue(kind: .errorCaught(error), comments: Array(comment), sourceContext: sourceContext)
    return issue.record()
  }

  /// Catch any error thrown from a closure and record it as an issue instead of
  /// allowing it to propagate to the caller.
  ///
  /// - Parameters:
  ///   - sourceLocation: The source location to attribute any caught error to.
  ///   - configuration: The test configuration to use when recording an issue.
  ///     The default value is ``Configuration/current``.
  ///   - body: A closure that might throw an error.
  ///
  /// - Returns: The issue representing the caught error, if any error was
  ///   caught, otherwise `nil`.
  @discardableResult
  static func withErrorRecording(
    at sourceLocation: SourceLocation,
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
    } catch {
      Issue.record(
        .errorCaught(error),
        comments: [],
        backtrace: Backtrace(forFirstThrowOf: error),
        sourceLocation: sourceLocation,
        configuration: configuration
      )
      return error
    }

    return nil
  }

  /// Catch any error thrown from an asynchronous closure and record it as an
  /// issue instead of allowing it to propagate to the caller.
  ///
  /// - Parameters:
  ///   - sourceLocation: The source location to attribute any caught error to.
  ///   - configuration: The test configuration to use when recording an issue.
  ///     The default value is ``Configuration/current``.
  ///   - body: An asynchronous closure that might throw an error.
  ///
  /// - Returns: The issue representing the caught error, if any error was
  ///   caught, otherwise `nil`.
  @discardableResult
  static func withErrorRecording(
    at sourceLocation: SourceLocation,
    configuration: Configuration? = nil,
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
    } catch {
      Issue.record(
        .errorCaught(error),
        comments: [],
        backtrace: Backtrace(forFirstThrowOf: error),
        sourceLocation: sourceLocation,
        configuration: configuration
      )
      return error
    }

    return nil
  }
}

// MARK: - Debugging failures

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
@inline(never) @_optimize(none)
@usableFromInline
func failureBreakpoint() {
  // This function's body cannot be completely empty or else linker symbol
  // de-duplication will cause its symbol to be consolidated with that of
  // another, arbitrarily chosen empty function in this module. This linker
  // behavior can be disabled by passing the `-no_deduplicate` flag described in
  // ld(1), but that would disable it module-wide and sacrifice optimization
  // opportunities elsewhere. Instead, this function performs a trivial
  // function call, passing it a sufficiently unique value to avoid
  // de-duplication.
  struct NoOp {
    nonisolated(unsafe) static var ignored: Int = 0
    static func perform(_: inout Int) {}
  }
  NoOp.perform(&NoOp.ignored)
}
