//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

/// A protocol describing cancellable tests and test cases.
///
/// This protocol is used to abstract away the common implementation of test and
/// test case cancellation.
protocol TestCancellable: Sendable {
  /// Make an instance of ``Event/Kind`` appropriate for an instance of this
  /// type.
  ///
  /// - Parameters:
  ///   - skipInfo: The ``SkipInfo`` structure describing the cancellation.
  ///
  /// - Returns: An instance of ``Event/Kind`` that describes the cancellation.
  static func makeCancelledEventKind(with skipInfo: SkipInfo) -> Event.Kind
}

// MARK: - Tracking the current task

/// A structure describing a reference to a task that is associated with some
/// ``TestCancellable`` value.
private struct _TaskReference: Sendable {
  /// The unsafe underlying reference to the associated task.
  private nonisolated(unsafe) var _unsafeCurrentTask = Locked<UnsafeCurrentTask?>()

  init() {
    // WARNING! Normally, allowing an instance of `UnsafeCurrentTask` to escape
    // its scope is dangerous because it could be used unsafely after the task
    // ends. However, because we take care not to allow the task object to
    // escape the task (by only storing it in a task-local value), we can ensure
    // these unsafe scenarios won't occur.
    //
    // TODO: when our deployment targets allow, we should switch to calling the
    // `async` overload of `withUnsafeCurrentTask()` from the body of
    // `withCancellationHandling(_:)`. That will allow us to use the task object
    // in a safely scoped fashion.
    _unsafeCurrentTask = withUnsafeCurrentTask { Locked(rawValue: $0) }
  }

  /// Take this instance's reference to its associated task.
  ///
  /// - Returns: An `UnsafeCurrentTask` instance, or `nil` if it was already
  ///   taken or if it was never available.
  ///
  /// This function consumes the reference to the task. After the first call,
  /// subsequent calls on the same instance return `nil`.
  func takeUnsafeCurrentTask() -> UnsafeCurrentTask? {
    _unsafeCurrentTask.withLock { unsafeCurrentTask in
      let result = unsafeCurrentTask
      unsafeCurrentTask = nil
      return result
    }
  }
}

/// A dictionary of tracked tasks, keyed by types that conform to
/// ``TestCancellable``.
@TaskLocal private var _currentTaskReferences = [ObjectIdentifier: _TaskReference]()

/// The instance of ``SkipInfo`` to propagate to children of the current task.
///
/// We set this value while calling `UnsafeCurrentTask.cancel()` so that its
/// value is available in tracked child tasks when their cancellation handlers
/// are called (in ``TestCancellable/withCancellationHandling(_:)`` below).
@TaskLocal private var _currentSkipInfo: SkipInfo?

extension TestCancellable {
  /// Call a function while the ``unsafeCurrentTask`` property of this instance
  /// is set to the current task.
  ///
  /// - Parameters:
  ///   - body: The function to invoke.
  ///
  /// - Returns: Whatever is returned by `body`.
  ///
  /// - Throws: Whatever is thrown by `body`.
  ///
  /// This function sets up a task cancellation handler and calls `body`. If
  /// the current task, test, or test case is cancelled, it records a
  /// corresponding cancellation event.
  func withCancellationHandling<R>(_ body: () async throws -> R) async rethrows -> R {
    var currentTaskReferences = _currentTaskReferences
    currentTaskReferences[ObjectIdentifier(Self.self)] = _TaskReference()
    return try await $_currentTaskReferences.withValue(currentTaskReferences) {
      try await withTaskCancellationHandler {
        try await body()
      } onCancel: {
        // The current task was cancelled, so cancel the test case or test
        // associated with it.
        let skipInfo = _currentSkipInfo ?? SkipInfo(sourceContext: SourceContext(backtrace: .current(), sourceLocation: nil))
        _ = try? Test.cancel(with: skipInfo)
      }
    }
  }
}

// MARK: -

/// The common implementation of cancellation for ``Test`` and ``Test/Case``.
///
/// - Parameters:
///   - cancellableValue: The test or test case to cancel, or `nil` if neither
///     is set and we need fallback handling.
///   - testAndTestCase: The test and test case to use when posting an event.
///   - skipInfo: Information about the cancellation event.
private func _cancel<T>(_ cancellableValue: T?, for testAndTestCase: (Test?, Test.Case?), skipInfo: SkipInfo) where T: TestCancellable {
  if cancellableValue != nil {
    // If the current test case is still running, take its task property (which
    // signals to subsequent callers that it has been cancelled.)
    let task = _currentTaskReferences[ObjectIdentifier(T.self)]?.takeUnsafeCurrentTask()

    // If we just cancelled the current test case's task, post a corresponding
    // event with the relevant skip info.
    if let task {
      $_currentSkipInfo.withValue(skipInfo) {
        task.cancel()
      }
      Event.post(T.makeCancelledEventKind(with: skipInfo), for: testAndTestCase)
    }
  } else {
    // The current task isn't associated with a test/case, so just cancel the
    // task.
    withUnsafeCurrentTask { task in
      task?.cancel()
    }

    var inExitTest = false
#if !SWT_NO_EXIT_TESTS
    inExitTest = (ExitTest.current != nil)
#endif
    if Bool(inExitTest) {
      // This code is running in an exit test. We don't have a "current test" or
      // "current test case" in the child process, so we'll let the parent
      // process sort that out.
      Event.post(T.makeCancelledEventKind(with: skipInfo), for: (nil, nil))
    } else {
      // Record an API misuse issue for trying to cancel the current test/case
      // outside of any useful context.
      let issue = Issue(
        kind: .apiMisused,
        comments: [
          "Attempted to cancel the current test or test case, but one is not associated with the current task.",
          skipInfo.comment,
        ].compactMap(\.self),
        sourceContext: skipInfo.sourceContext
      )
      issue.record()
    }
  }
}

// MARK: - Test cancellation

extension Test: TestCancellable {
  /// Cancel the current test or test case.
  ///
  /// - Parameters:
  ///   - comment: A comment describing why you are cancelling the test or test
  ///     case.
  ///   - sourceLocation: The source location to which the testing library will
  ///     attribute the cancellation.
  ///
  /// - Throws: An error indicating that the current test or test case has been
  ///   cancelled.
  ///
  /// The testing library runs each test and each test case in its own task.
  /// When you call this function, the testing library cancels the task
  /// associated with the current test:
  ///
  /// ```swift
  /// @Test func `Food truck is well-stocked`() throws {
  ///   guard businessHours.contains(.now) else {
  ///     try Test.cancel("We're off the clock.")
  ///   }
  ///   // ...
  /// }
  /// ```
  ///
  /// If the current test is a parameterized test function, this function
  /// instead cancels the current test case. Other test cases in the test
  /// function are not affected.
  ///
  /// If the current test is a suite, the testing library cancels all of its
  /// pending and running tests.
  ///
  /// If you have already cancelled the current test or if it has already
  /// finished running, this function throws an error to indicate that the
  /// current test has been cancelled, but does not attempt to cancel the test a
  /// second time.
  ///
  /// @Comment {
  ///   TODO: Document the interaction between an exit test and test
  ///   cancellation. In particular, the error thrown by this function isn't
  ///   thrown into the parent process and task cancellation doesn't propagate
  ///   (because the exit test _de facto_ runs in a detached task.)
  /// }
  ///
  /// - Important: If the current task is not associated with a test (for
  ///   example, because it was created with [`Task.detached(name:priority:operation:)`](https://developer.apple.com/documentation/swift/task/detached(name:priority:operation:)-795w1))
  ///   this function records an issue and cancels the current task.
  @_spi(Experimental)
  public static func cancel(_ comment: Comment? = nil, sourceLocation: SourceLocation = #_sourceLocation) throws -> Never {
    let skipInfo = SkipInfo(comment: comment, sourceContext: SourceContext(backtrace: nil, sourceLocation: sourceLocation))
    try Self.cancel(with: skipInfo)
  }

  /// Cancel the current test or test case.
  ///
  /// - Parameters:
  ///   - skipInfo: Information about the cancellation event.
  ///
  /// - Throws: An error indicating that the current test or test case has been
  ///   cancelled.
  ///
  /// Note that the public ``Test/cancel(_:sourceLocation:)`` function has a
  /// different signature and accepts a source location rather than an instance
  /// of ``SkipInfo``.
  static func cancel(with skipInfo: SkipInfo) throws -> Never {
    let test = Test.current
    let testCase = Test.Case.current

    if let testCase {
      // Cancel the current test case.
      _cancel(testCase, for: (test, testCase), skipInfo: skipInfo)
    }

    if let test {
      if !test.isParameterized {
        // The current test is not parameterized, so cancel the whole test too.
        _cancel(test, for: (test, nil), skipInfo: skipInfo)
      }
    } else {
      // There is no current test (this is the API misuse path.)
      _cancel(test, for: (test, nil), skipInfo: skipInfo)
    }

    throw skipInfo
  }

  static func makeCancelledEventKind(with skipInfo: SkipInfo) -> Event.Kind {
    .testCancelled(skipInfo)
  }
}

// MARK: - Test case cancellation

extension Test.Case: TestCancellable {
  static func makeCancelledEventKind(with skipInfo: SkipInfo) -> Event.Kind {
    .testCaseCancelled(skipInfo)
  }
}
