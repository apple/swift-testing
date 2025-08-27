//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

extension Runner {
  /// A type which collects the task-scoped runtime state for a running
  /// ``Runner`` instance, the tests it runs, and other objects it interacts
  /// with.
  ///
  /// This type is intended for use via the task-local
  /// ``Runner/RuntimeState/current`` property.
  fileprivate struct RuntimeState: Sendable {
    /// The configuration for the current task, if any.
    var configuration: Configuration?

    /// The test that is running on the current task, if any.
    var test: Test?

    /// The test case that is running on the current task, if any.
    var testCase: Test.Case?

    /// The runtime state related to the runner running on the current task,
    /// if any.
    @TaskLocal
    static var current: Self?
  }
}

extension Runner {
  /// Modify the event handler of this instance's ``Configuration`` to ensure it
  /// is invoked using the current ``RuntimeState`` value.
  ///
  /// This is meant to be called prior to running tests using this instance. It
  /// allows any events posted during the call to this instance's event handler
  /// to be directed to the previously-configured event handler, if any.
  ///
  /// In practice, the primary scenario where this is important is when running
  /// the testing library's own tests.
  mutating func configureEventHandlerRuntimeState() {
    guard let existingRuntimeState = RuntimeState.current else {
      return
    }

    configuration.eventHandler = { [eventHandler = configuration.eventHandler] event, context in
      RuntimeState.$current.withValue(existingRuntimeState) {
        eventHandler(event, context)
      }
    }
  }
}

// MARK: - Current configuration

extension Configuration {
  /// The configuration for the current task, if any.
  public static var current: Self? {
    Runner.RuntimeState.current?.configuration
  }

  /// Call a function while the value of ``Configuration/current`` is set.
  ///
  /// - Parameters:
  ///   - configuration: The new value to set for ``Configuration/current``.
  ///   - body: A function to call.
  ///
  /// - Returns: Whatever is returned by `body`.
  ///
  /// - Throws: Whatever is thrown by `body`.
  static func withCurrent<R>(_ configuration: Self, perform body: () throws -> R) rethrows -> R {
    let id = configuration._addToAll()
    defer {
      configuration._removeFromAll(identifiedBy: id)
    }

    var runtimeState = Runner.RuntimeState.current ?? .init()
    runtimeState.configuration = configuration
    return try Runner.RuntimeState.$current.withValue(runtimeState, operation: body)
  }

  /// Call an asynchronous function while the value of ``Configuration/current``
  /// is set.
  ///
  /// - Parameters:
  ///   - configuration: The new value to set for ``Configuration/current``.
  ///   - body: A function to call.
  ///
  /// - Returns: Whatever is returned by `body`.
  ///
  /// - Throws: Whatever is thrown by `body`.
  static func withCurrent<R>(_ configuration: Self, perform body: () async throws -> R) async rethrows -> R {
    let id = configuration._addToAll()
    defer {
      configuration._removeFromAll(identifiedBy: id)
    }

    var runtimeState = Runner.RuntimeState.current ?? .init()
    runtimeState.configuration = configuration
    return try await Runner.RuntimeState.$current.withValue(runtimeState, operation: body)
  }

  /// A type containing the mutable state tracked by ``Configuration/_all`` and,
  /// indirectly, by ``Configuration/all``.
  private struct _All: Sendable {
    /// All instances of ``Configuration`` set as current, keyed by their unique
    /// identifiers.
    var instances = [UInt64: Configuration]()

    /// The next available unique identifier for a configuration.
    var nextID: UInt64 = 0
  }

  /// Mutable storage for ``Configuration/all``.
  private static let _all = Locked(rawValue: _All())

  /// A collection containing all instances of this type that are currently set
  /// as the current configuration for a task.
  ///
  /// This property is used when an event is posted in a context where the value
  /// of ``Configuration/current`` is `nil`, such as from a detached task.
  static var all: some Collection<Self> {
    _all.rawValue.instances.values
  }

  /// Add this instance to ``Configuration/all``.
  ///
  /// - Returns: A unique number identifying `self` that can be
  ///   passed to `_removeFromAll(identifiedBy:)`` to unregister it.
  private func _addToAll() -> UInt64 {
    if eventHandlingOptions.isExpectationCheckedEventEnabled {
      Self._deliverExpectationCheckedEventsCount.increment()
    }
    return Self._all.withLock { all in
      let id = all.nextID
      all.nextID += 1
      all.instances[id] = self
      return id
    }
  }

  /// Remove this instance from ``Configuration/all``.
  ///
  /// - Parameters:
  ///   - id: The unique identifier of this instance, as previously returned by
  ///     `_addToAll()`.
  private func _removeFromAll(identifiedBy id: UInt64) {
    let configuration = Self._all.withLock { all in
      all.instances.removeValue(forKey: id)
    }
    if let configuration, configuration.eventHandlingOptions.isExpectationCheckedEventEnabled {
      Self._deliverExpectationCheckedEventsCount.decrement()
    }
  }

  /// An atomic counter that tracks the number of "current" configurations that
  /// have set ``EventHandlingOptions/isExpectationCheckedEventEnabled`` to
  /// `true`.
  private static let _deliverExpectationCheckedEventsCount = Locked(rawValue: 0)

  /// Whether or not events of the kind
  /// ``Event/Kind-swift.enum/expectationChecked(_:)`` should be delivered to
  /// the event handler of _any_ configuration set as current for a task in the
  /// current process.
  ///
  /// To determine if an individual instance of ``Configuration`` is listening
  /// for these events, consult the per-instance
  /// ``Configuration/EventHandlingOptions/isExpectationCheckedEventEnabled``
  /// property.
  static var deliverExpectationCheckedEvents: Bool {
    _deliverExpectationCheckedEventsCount.rawValue > 0
  }
}

// MARK: - Current test and test case

extension Test {
  /// The test that is running on the current task, if any.
  ///
  /// If the current task is running a test, or is a subtask of another task
  /// that is running a test, the value of this property describes that test. If
  /// no test is currently running, the value of this property is `nil`.
  ///
  /// If the current task is detached from a task that started running a test,
  /// or if the current thread was created without using Swift concurrency (e.g.
  /// by using [`Thread.detachNewThread(_:)`](https://developer.apple.com/documentation/foundation/thread/2088563-detachnewthread)
  /// or [`DispatchQueue.async(execute:)`](https://developer.apple.com/documentation/dispatch/dispatchqueue/2016103-async)),
  /// the value of this property may be `nil`.
  public static var current: Self? {
    Runner.RuntimeState.current?.test
  }

  /// Call a function while the value of ``Test/current`` is set.
  ///
  /// - Parameters:
  ///   - test: The new value to set for ``Test/current``.
  ///   - body: A function to call.
  ///
  /// - Returns: Whatever is returned by `body`.
  ///
  /// - Throws: Whatever is thrown by `body`.
  static func withCurrent<R>(_ test: Self, perform body: () async throws -> R) async rethrows -> R {
    var runtimeState = Runner.RuntimeState.current ?? .init()
    runtimeState.test = test
    return try await Runner.RuntimeState.$current.withValue(runtimeState) {
      try await test.withCancellationHandling(body)
    }
  }
}

extension Test.Case {
  /// The test case that is running on the current task, if any.
  ///
  /// If the current task is running a test, or is a subtask of another task
  /// that is running a test, the value of this property describes the test's
  /// currently-running case. If no test is currently running, the value of this
  /// property is `nil`.
  ///
  /// If the current task is detached from a task that started running a test,
  /// or if the current thread was created without using Swift concurrency (e.g.
  /// by using [`Thread.detachNewThread(_:)`](https://developer.apple.com/documentation/foundation/thread/2088563-detachnewthread)
  /// or [`DispatchQueue.async(execute:)`](https://developer.apple.com/documentation/dispatch/dispatchqueue/2016103-async)),
  /// the value of this property may be `nil`.
  public static var current: Self? {
    Runner.RuntimeState.current?.testCase
  }

  /// Call a function while the value of ``Test/Case/current`` is set.
  ///
  /// - Parameters:
  ///   - testCase: The new value to set for ``Test/Case/current``.
  ///   - body: A function to call.
  ///
  /// - Returns: Whatever is returned by `body`.
  ///
  /// - Throws: Whatever is thrown by `body`.
  static func withCurrent<R>(_ testCase: Self, perform body: () async throws -> R) async rethrows -> R {
    var runtimeState = Runner.RuntimeState.current ?? .init()
    runtimeState.testCase = testCase
    return try await Runner.RuntimeState.$current.withValue(runtimeState) {
      try await testCase.withCancellationHandling(body)
    }
  }
}

/// Get the current test and test case in a single operation.
///
/// - Returns: The current test and test case.
///
/// This function is more efficient than calling both ``Test/current`` and
/// ``Test/Case/current``.
func currentTestAndTestCase() -> (Test?, Test.Case?) {
  guard let state = Runner.RuntimeState.current else {
    return (nil, nil)
  }
  return (state.test, state.testCase)
}
