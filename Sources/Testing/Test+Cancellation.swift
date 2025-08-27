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
  /// Cancel the current instance of this type.
  ///
  /// - Parameters:
  ///   - comments: Comments describing why you are cancelling the test/case.
  ///   - sourceContext: The source context to which the testing library will
  ///     attribute the cancellation.
  ///
  /// - Throws: An error indicating that the current instance of this type has
  ///   been cancelled.
  ///
  /// Note that the public ``Test/cancel(_:sourceLocation:)`` function has a
  /// different signature and accepts a source location rather than a source
  /// context value.
  static func cancel(comments: [Comment], sourceContext: @autoclosure () -> SourceContext) throws -> Never

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
    let unsafeCurrentTask = withUnsafeCurrentTask { $0 }
    _unsafeCurrentTask = Locked(rawValue: unsafeCurrentTask)
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
@TaskLocal
private var _currentTaskReferences = [ObjectIdentifier: _TaskReference]()

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
        _ = try? Self.cancel(
          comments: [],
          sourceContext: SourceContext(backtrace: .current(), sourceLocation: nil)
        )
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
///   - comments: Comments describing why you are cancelling the test/case.
///   - sourceContext: The source context to which the testing library will
///     attribute the cancellation.
///
/// - Throws: An instance of ``SkipInfo`` describing the cancellation.
private func _cancel<T>(_ cancellableValue: T?, for testAndTestCase: (Test?, Test.Case?), comments: [Comment], sourceContext: @autoclosure () -> SourceContext) throws -> Never where T: TestCancellable {
  var skipInfo = SkipInfo(comment: comments.first, sourceContext: .init(backtrace: nil, sourceLocation: nil))

  if cancellableValue != nil {
    // If the current test case is still running, cancel its task and clear its
    // task property (which signals that it has been cancelled.)
    let task = _currentTaskReferences[ObjectIdentifier(T.self)]?.takeUnsafeCurrentTask()
    task?.cancel()

    // If we just cancelled the current test case's task, post a corresponding
    // event with the relevant skip info.
    if task != nil {
      skipInfo.sourceContext = sourceContext()
      Event.post(T.makeCancelledEventKind(with: skipInfo), for: testAndTestCase)
    }
  } else {
    // The current task isn't associated with a test/case, so just cancel the
    // task.
    withUnsafeCurrentTask { task in
      task?.cancel()
    }

    if ExitTest.current != nil {
      // This code is running in an exit test. We don't have a "current test" or
      // "current test case" in the child process, so we'll let the parent
      // process sort that out.
      skipInfo.sourceContext = sourceContext()
      Event.post(T.makeCancelledEventKind(with: skipInfo), for: (nil, nil))
    } else {
      // Record an API misuse issue for trying to cancel the current test/case
      // outside of any useful context.
      let comments = ["Attempted to cancel the current test or test case, but one is not associated with the current task."] + comments
      let issue = Issue(kind: .apiMisused, comments: comments, sourceContext: sourceContext())
      issue.record()
    }
  }

  throw skipInfo
}

// MARK: - Test cancellation

extension Test: TestCancellable {
  /// Cancel the current test.
  ///
  /// - Parameters:
  ///   - comment: A comment describing why you are cancelling the test.
  ///   - sourceLocation: The source location to which the testing library will
  ///     attribute the cancellation.
  ///
  /// - Throws: An error indicating that the current test case has been
  ///   cancelled.
  ///
  /// The testing library runs each test in its own task. When you call this
  /// function, the testing library cancels the task associated with the current
  /// test:
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
  /// If the current test is parameterized, all of its pending and running test
  /// cases are cancelled. If the current test is a suite, all of its pending
  /// and running tests are cancelled. If you have already cancelled the current
  /// test or if it has already finished running, this function throws an error
  /// but does not attempt to cancel the test a second time.
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
  ///
  /// To cancel the current test case but leave other test cases of the current
  /// test alone, call ``Test/Case/cancel(_:sourceLocation:)`` instead.
  @_spi(Experimental)
  public static func cancel(_ comment: Comment? = nil, sourceLocation: SourceLocation = #_sourceLocation) throws -> Never {
    try Self.cancel(
      comments: Array(comment),
      sourceContext: SourceContext(backtrace: .current(), sourceLocation: sourceLocation)
    )
  }

  static func cancel(comments: [Comment], sourceContext: @autoclosure () -> SourceContext) throws -> Never {
    let test = Test.current
    try _cancel(test, for: (test, nil), comments: comments, sourceContext: sourceContext())
  }

  static func makeCancelledEventKind(with skipInfo: SkipInfo) -> Event.Kind {
    .testCancelled(skipInfo)
  }
}

// MARK: - Test case cancellation

extension Test.Case: TestCancellable {
  /// Cancel the current test case.
  ///
  /// - Parameters:
  ///   - comment: A comment describing why you are cancelling the test case.
  ///   - sourceLocation: The source location to which the testing library will
  ///     attribute the cancellation.
  ///
  /// - Throws: An error indicating that the current test case has been
  ///   cancelled.
  ///
  /// The testing library runs each test case of a test in its own task. When
  /// you call this function, the testing library cancels the task associated
  /// with the current test case:
  ///
  /// ```swift
  /// @Test(arguments: [Food.burger, .fries, .iceCream])
  /// func `Food truck is well-stocked`(_ food: Food) throws {
  ///   if food == .iceCream && Season.current == .winter {
  ///     try Test.Case.cancel("It's too cold for ice cream.")
  ///   }
  ///   // ...
  /// }
  /// ```
  ///
  /// If the current test is parameterized, the test's other test cases continue
  /// running. If the current test case has already been cancelled, this
  /// function throws an error but does not attempt to cancel the test case a
  /// second time.
  ///
  /// @Comment {
  ///   TODO: Document the interaction between an exit test and test
  ///   cancellation. In particular, the error thrown by this function isn't
  ///   thrown into the parent process and task cancellation doesn't propagate
  ///   (because the exit test _de facto_ runs in a detached task.)
  /// }
  ///
  /// - Important: If the current task is not associated with a test case (for
  ///   example, because it was created with [`Task.detached(name:priority:operation:)`](https://developer.apple.com/documentation/swift/task/detached(name:priority:operation:)-795w1))
  ///   this function records an issue and cancels the current task.
  ///
  /// To cancel all test cases in the current test, call
  /// ``Test/cancel(_:sourceLocation:)`` instead.
  @_spi(Experimental)
  public static func cancel(_ comment: Comment? = nil, sourceLocation: SourceLocation = #_sourceLocation) throws -> Never {
    try Self.cancel(
      comments: Array(comment),
      sourceContext: SourceContext(backtrace: .current(), sourceLocation: sourceLocation)
    )
  }

  static func cancel(comments: [Comment], sourceContext: @autoclosure () -> SourceContext) throws -> Never {
    let test = Test.current
    let testCase = Test.Case.current
    let sourceContext = sourceContext() // evaluated twice, avoid laziness

    do {
      // Cancel the current test case (if it's nil, that's the API misuse path.)
      try _cancel(testCase, for: (test, testCase), comments: comments, sourceContext: sourceContext)
    } catch _ where test?.isParameterized == false {
      // The current test is not parameterized, so cancel the whole test too.
      try _cancel(test, for: (test, nil), comments: comments, sourceContext: sourceContext)
    }
  }

  static func makeCancelledEventKind(with skipInfo: SkipInfo) -> Event.Kind {
    .testCaseCancelled(skipInfo)
  }
}
