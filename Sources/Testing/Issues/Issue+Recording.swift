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
  static func record(_ kind: Kind, comments: [Comment], backtrace: Backtrace?, sourceLocation: SourceLocation, configuration: Configuration? = nil) -> Issue {
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
  static func record(_ kind: Kind, comments: [Comment], sourceContext: SourceContext, configuration: Configuration? = nil) -> Issue {
    let issue = Issue(kind: kind, comments: comments, sourceContext: sourceContext)
    issue.record(configuration: configuration)
    return issue
  }

  /// Record this issue by wrapping it in an ``Event`` and passing it to the
  /// current event handler.
  ///
  /// - Parameters:
  ///   - configuration: The test configuration to use when recording the issue.
  ///     The default value is ``Configuration/current``.
  func record(configuration: Configuration? = nil) {
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
  }

  /// Record an issue when a running test fails unexpectedly.
  ///
  /// - Parameters:
  ///   - comment: A comment describing the expectation.
  ///
  /// - Returns: The issue that was recorded.
  ///
  /// Use this function if, while running a test, an issue occurs that cannot be
  /// represented as an expectation (using the ``expect(_:_:sourceLocation:)``
  /// or ``require(_:_:sourceLocation:)-5l63q`` macros.)
  @discardableResult public static func record(
    _ comment: Comment? = nil,
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column
  ) -> Self {
    let sourceLocation = SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column)
    let sourceContext = SourceContext(backtrace: .current(), sourceLocation: sourceLocation)
    let issue = Issue(kind: .unconditional, comments: Array(comment), sourceContext: sourceContext)
    issue.record()
    return issue
  }
}

// MARK: - Recording issues for errors

extension Issue {
  /// Record a new issue when a running test unexpectedly catches an error.
  ///
  /// - Parameters:
  ///   - error: The error that caused the issue.
  ///   - comment: A comment describing the expectation.
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
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column
  ) -> Self {
    let sourceLocation = SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column)
    let backtrace = Backtrace(forFirstThrowOf: error) ?? Backtrace.current()
    let sourceContext = SourceContext(backtrace: backtrace, sourceLocation: sourceLocation)
    let issue = Issue(kind: .errorCaught(error), comments: Array(comment), sourceContext: sourceContext)
    issue.record()
    return issue
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
  static func recordingErrors(
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
  static func recordingErrors(
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
  // Empty.
}
