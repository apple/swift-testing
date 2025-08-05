//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

/// A type containing settings for preparing and running tests.
@_spi(ForToolsIntegrationOnly)
public struct Configuration: Sendable {
  /// Initialize an instance of this type representing the default
  /// configuration.
  public init() {}

  // MARK: - Parallelization

  /// Whether or not to parallelize the execution of tests and test cases.
  public var isParallelizationEnabled: Bool = true

  /// How to symbolicate backtraces captured during a test run.
  ///
  /// If the value of this property is not `nil`, symbolication will be
  /// performed automatically when a backtrace is encoded into an event stream.
  ///
  /// The value of this property does not affect event handlers implemented in
  /// Swift in-process. When handling a backtrace in Swift, use its
  /// ``Backtrace/symbolicate(_:)`` function to symbolicate it.
  public var backtraceSymbolicationMode: Backtrace.SymbolicationMode?

  /// A type describing whether or not, and how, to iterate a test plan
  /// repeatedly.
  ///
  /// When a ``Runner`` is run, it will run all tests in its corresponding
  /// ``Runner/Plan`` according to the policy described by its
  /// ``Configuration/repetitionPolicy-swift.property`` property. For instance,
  /// if that property is set to:
  ///
  /// ```swift
  /// .repeating(.untilIssueRecorded, count: 10)
  /// ```
  ///
  /// The entire test plan will be run repeatedly, up to 10 times. If an issue
  /// is recorded, the current iteration will complete, but no further
  /// iterations will be attempted.
  ///
  /// If the value of an instance's ``maximumIterationCount`` property is `1`,
  /// the value of its ``continuationCondition-swift.property`` property has no
  /// effect.
  public struct RepetitionPolicy: Sendable {
    /// An enumeration describing the conditions under which test iterations
    /// should continue.
    public enum ContinuationCondition: Sendable {
      /// The test plan should continue iterating until an unknown issue is
      /// recorded.
      ///
      /// When this continuation condition is used and an issue is recorded, the
      /// current iteration will complete, but no further iterations will be
      /// attempted.
      case untilIssueRecorded

      /// The test plan should continue iterating until an iteration completes
      /// with no unknown issues recorded.
      case whileIssueRecorded
    }

    /// The conditions under which test iterations should continue.
    ///
    /// If the value of this property is `nil`, a test plan will be run
    /// ``maximumIterationCount`` times regardless of whether or not issues are
    /// encountered while running.
    public var continuationCondition: ContinuationCondition?

    /// The maximum number of times the test run should iterate.
    ///
    /// - Precondition: The value of this property must be greater than `0`.
    public var maximumIterationCount: Int {
      willSet {
        precondition(newValue > 0, "Test runs must iterate at least once (maximumIterationCount was \(newValue)).")
      }
    }

    /// Create an instance of this type.
    ///
    /// - Parameters:
    ///   - continuationCondition: The conditions under which test iterations
    ///     should continue. If `nil`, the iterations should continue
    ///     unconditionally `count` times.
    ///   - maximumIterationCount: The maximum number of times the test run
    ///     should iterate.
    public static func repeating(_ continuationCondition: ContinuationCondition? = nil, maximumIterationCount: Int) -> Self {
      Self(continuationCondition: continuationCondition, maximumIterationCount: maximumIterationCount)
    }

    /// An instance of this type representing a single iteration.
    public static var once: Self {
      repeating(maximumIterationCount: 1)
    }
  }

  /// Whether or not, and how, to iterate the test plan repeatedly.
  ///
  /// By default, the value of this property allows for a single iteration.
  public var repetitionPolicy: RepetitionPolicy = .once

  // MARK: - Isolation context for synchronous tests

  /// The isolation context to use for synchronous test functions.
  ///
  /// If the value of this property is `nil`, synchronous test functions run in
  /// an unspecified isolation context.
  public var defaultSynchronousIsolationContext: (any Actor)? = nil

  // MARK: - Time limits

  /// Storage for the ``defaultTestTimeLimit`` property.
  private var _defaultTestTimeLimit: (any Sendable)?

  /// The default amount of time a test may run for before timing out if it does
  /// not have an instance of ``TimeLimitTrait`` applied to it.
  ///
  /// If the value of this property is `nil`, individual test functions may run
  /// up to the limit specified by ``maximumTestTimeLimit``.
  ///
  /// To determine the actual time limit that applies to an instance of
  /// ``Test`` at runtime, use ``Test/adjustedTimeLimit(configuration:)``.
  @available(_clockAPI, *)
  public var defaultTestTimeLimit: Duration? {
    get {
      _defaultTestTimeLimit as? Duration
    }
    set {
      _defaultTestTimeLimit = newValue
    }
  }

  /// Storage for the ``maximumTestTimeLimit`` property.
  private var _maximumTestTimeLimit: (any Sendable)?

  /// The maximum amount of time a test may run for before timing out,
  /// regardless of the value of ``defaultTestTimeLimit`` or individual
  /// instances of ``TimeLimitTrait`` applied to it.
  ///
  /// If the value of this property is `nil`, individual test functions may run
  /// indefinitely.
  ///
  /// To determine the actual time limit that applies to an instance of
  /// ``Test`` at runtime, use ``Test/adjustedTimeLimit(configuration:)``.
  @available(_clockAPI, *)
  public var maximumTestTimeLimit: Duration? {
    get {
      _maximumTestTimeLimit as? Duration
    }
    set {
      _maximumTestTimeLimit = newValue
    }
  }

  /// Storage for the ``testTimeLimitGranularity`` property.
  private var _testTimeLimitGranularity: (any Sendable)?

  /// The granularity to enforce on test time limits.
  ///
  /// By default, test time limit granularity is limited to intervals of one
  /// minute (60 seconds.) If finer or coarser granularity is required, the
  /// value of this property can be adjusted.
  @available(_clockAPI, *)
  public var testTimeLimitGranularity: Duration {
    get {
      (_testTimeLimitGranularity as? Duration) ?? .seconds(60)
    }
    set {
      _testTimeLimitGranularity = newValue
    }
  }

  // MARK: - Event handling

  /// A type describing options to use when delivering events to this
  /// configuration's event handler
  public struct EventHandlingOptions: Sendable {
    /// Whether or not events of the kind ``Event/Kind-swift.enum/issueRecorded(_:)``
    /// containing issues with warning (or lower) severity should be delivered
    /// to the event handler of the configuration these options are applied to.
    public var isWarningIssueRecordedEventEnabled: Bool = true

    /// Whether or not events of the kind
    /// ``Event/Kind-swift.enum/expectationChecked(_:)`` should be delivered to
    /// the event handler of the configuration these options are applied to.
    ///
    /// By default, events of this kind are not delivered to event handlers
    /// because they occur frequently in a typical test run and can generate
    /// significant back-pressure on the event handler.
    public var isExpectationCheckedEventEnabled: Bool = false
  }

  /// The options to use when delivering events to this configuration's event
  /// handler.
  public var eventHandlingOptions: EventHandlingOptions = .init()

  /// The event handler to which events should be passed when they occur.
  public var eventHandler: Event.Handler = { _, _ in }

#if !SWT_NO_EXIT_TESTS
  /// A handler that is invoked when an exit test starts.
  ///
  /// For an explanation of how this property is used, see ``ExitTest/Handler``.
  ///
  /// When using the `swift test` command from Swift Package Manager, this
  /// property is pre-configured. Otherwise, the default value of this property
  /// records an issue indicating that it has not been configured.
  public var exitTestHandler: ExitTest.Handler = { exitTest in
    throw SystemError(description: "Exit test support has not been implemented by the current testing infrastructure.")
  }
#endif

#if !SWT_NO_FILE_IO
  /// Storage for ``attachmentsPath``.
  private var _attachmentsPath: String?

  /// The path to which attachments should be written.
  ///
  /// By default, attachments are not written to disk when they are created. If
  /// the value of this property is not `nil`, then when an attachment is
  /// created and attached to a test, it will automatically be written to a file
  /// in this directory.
  ///
  /// The value of this property must refer to a directory on the local file
  /// system that already exists and which the current user can write to. If it
  /// is a relative path, it is resolved to an absolute path automatically.
  public var attachmentsPath: String? {
    get {
      _attachmentsPath
    }
    set {
      _attachmentsPath = newValue.map { newValue in
        canonicalizePath(newValue) ?? newValue
      }
    }
  }
#endif

  /// How verbose human-readable output should be.
  ///
  /// When the value of this property is greater than `0`, additional output
  /// is provided. When the value of this property is less than `0`, some
  /// output is suppressed. The exact effects of this property are determined by
  /// the instance's event handler.
  public var verbosity: Int = 0

  // MARK: - Test selection

  /// The test filter to which tests should be filtered when run.
  public var testFilter: TestFilter = .unfiltered

  // MARK: - Test case selection

  /// A function that handles filtering test cases.
  ///
  /// - Parameters:
  ///   - testCase: The test case to be filtered.
  ///   - test: The test which `testCase` is associated with.
  ///
  /// - Returns: A Boolean value representing if the test case satisfied the
  ///   filter.
  public typealias TestCaseFilter = @Sendable (_ testCase: Test.Case, _ test: Test) -> Bool

  /// The test case filter to which test cases should be filtered when run.
  public var testCaseFilter: TestCaseFilter = { _, _ in true }

  // MARK: - Expectation value reflection

  /// The options to use when reflecting values in expressions checked by
  /// expectations, or `nil` if reflection is disabled.
  ///
  /// When the value of this property is a non-`nil` instance, values checked by
  /// expressions will be reflected using `Mirror` and the specified options
  /// will influence how that reflection is formed. Otherwise, when its value is
  /// `nil`, value reflection will not use `Mirror` and instead will use
  /// `String(describing:)`.
  ///
  /// The default value of this property is an instance of ``ValueReflectionOptions-swift.struct``
  /// with its properties initialized to their default values.
  public var valueReflectionOptions: ValueReflectionOptions? = .init()

  /// A type describing options to use when forming a reflection of a value
  /// checked by an expectation.
  public struct ValueReflectionOptions: Sendable {
    /// The maximum number of elements that can included in a single child
    /// collection when reflecting a value checked by an expectation.
    ///
    /// When ``Expression/Value/init(reflecting:)`` is reflecting a value and it
    /// encounters a child value which is a collection, it consults the value of
    /// this property and only includes the children of that collection up to
    /// this maximum count. After this maximum is reached, all subsequent
    /// elements are omitted and a single placeholder child is added indicating
    /// the number of elements which have been truncated.
    public var maximumCollectionCount: Int = 10

    /// The maximum depth of children that can be included in the reflection of
    /// a checked expectation value.
    ///
    /// When ``Expression/Value/init(reflecting:)`` is reflecting a value, it
    /// recursively reflects that value's children. Before doing so, it consults
    /// the value of this property to determine the maximum depth of the
    /// children to include. After this maximum depth is reached, all children
    /// at deeper levels are omitted and the ``Expression/Value/isTruncated``
    /// property is set to `true` to reflect that the reflection is incomplete.
    ///
    /// - Note: `Optional` values contribute twice towards this maximum, since
    ///   their mirror represents the wrapped value as a child of the optional.
    ///   Since optionals are common, the default value of this property is
    ///   somewhat larger than it otherwise would be in an attempt to make the
    ///   defaults useful for real-world tests.
    public var maximumChildDepth: Int = 10
  }
}

// MARK: - Deprecated

extension Configuration {
#if !SWT_NO_GLOBAL_ACTORS
  @available(*, deprecated, message: "Set defaultSynchronousIsolationContext instead.")
  public var isMainActorIsolationEnforced: Bool {
    get {
      defaultSynchronousIsolationContext === MainActor.shared
    }
    set {
      if newValue {
        defaultSynchronousIsolationContext = MainActor.shared
      } else {
        defaultSynchronousIsolationContext = nil
      }
    }
  }
#endif

  @available(*, deprecated, message: "Set eventHandlingOptions.isExpectationCheckedEventEnabled instead.")
  public var deliverExpectationCheckedEvents: Bool {
    get {
      eventHandlingOptions.isExpectationCheckedEventEnabled
    }
    set {
      eventHandlingOptions.isExpectationCheckedEventEnabled = newValue
    }
  }
}
