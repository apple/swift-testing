//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

/// An event that occurred during testing.
@_spi(ForToolsIntegrationOnly)
public struct Event: Sendable {
  /// An enumeration describing the various kinds of event that can be observed.
  public enum Kind: Sendable {
    /// A test was discovered during test run planning.
    ///
    /// This event is recorded once per discovered test when an instance of
    /// ``Runner`` is initialized, _prior to_ ``Runner/run()`` being called. It
    /// does not indicate whether or not a test will run—only that the test was
    /// found by the testing library.
    case testDiscovered

    /// A test run started.
    ///
    /// This event is the first event posted after ``Runner/run()`` is called.
    case runStarted

    /// An iteration of the test run started.
    ///
    /// - Parameters:
    ///   - index: The index of the iteration. The first iteration has an index
    ///     of `0`.
    ///
    /// This event is posted at the start of each test plan iteration.
    ///
    /// By default, a test plan runs for one iteration, but the
    /// ``Configuration/repetitionPolicy-swift.property`` property can be set to
    /// allow for more iterations.
    indirect case iterationStarted(_ index: Int)

    /// A step in the runner plan started.
    ///
    /// - Parameters:
    ///   - step: The step in the runner plan which started.
    ///
    /// This event is posted when a ``Runner`` begins processing a
    /// ``Runner/Plan/Step``. Processing this step may result in its associated
    /// ``Test`` being run, skipped, or another action, so this event will only
    /// be followed by a ``testStarted`` event if the step's test is run.
    indirect case planStepStarted(_ step: Runner.Plan.Step)

    /// A test started.
    ///
    /// The test that started is contained in the ``Event/Context`` instance
    /// that was passed to the event handler along with this event. Its ID is
    /// available from this event's ``Event/testID`` property.
    case testStarted

    /// A test case started.
    ///
    /// The test case that started is contained in the ``Event/Context``
    /// instance that was passed to the event handler along with this event.
    case testCaseStarted

    /// A test case ended.
    ///
    /// The test case that ended is contained in the ``Event/Context`` instance
    /// that was passed to the event handler along with this event.
    case testCaseEnded

    /// An expectation was checked with `#expect()` or `#require()`.
    ///
    /// - Parameters:
    ///   - expectation: The expectation which was checked.
    ///
    /// By default, events of this kind are not generated because they occur
    /// frequently in a typical test run and can generate significant
    /// backpressure on the event handler.
    ///
    /// Failed expectations also, unless expected to fail, generate events of
    /// kind ``Event/Kind-swift.enum/issueRecorded(_:)``. Those events are
    /// always posted to the current event handler.
    ///
    /// To enable events of this kind, set
    /// ``Configuration/deliverExpectationCheckedEvents`` to `true` before
    /// running tests.
    indirect case expectationChecked(_ expectation: Expectation)

    /// An issue was recorded.
    ///
    /// - Parameters:
    ///   - issue: The issue which was recorded.
    indirect case issueRecorded(_ issue: Issue)

    /// A test ended.
    ///
    /// The test that ended is contained in the ``Event/Context`` instance that
    /// was passed to the event handler along with this event. Its ID is
    /// available from this event's ``Event/testID`` property.
    case testEnded

    /// A test was skipped.
    ///
    /// - Parameters:
    ///   - skipInfo: A ``SkipInfo`` containing details about this skipped test.
    ///
    /// The test that was skipped is contained in the ``Event/Context`` instance
    /// that was passed to the event handler along with this event. Its ID is
    /// available from this event's ``Event/testID`` property.
    indirect case testSkipped(_ skipInfo: SkipInfo)

    /// A step in the runner plan ended.
    ///
    /// - Parameters:
    ///   - step: The step in the runner plan which ended.
    ///
    /// This event is posted when a ``Runner`` finishes processing a
    /// ``Runner/Plan/Step``.
    indirect case planStepEnded(Runner.Plan.Step)

    /// An iteration of the test run ended.
    ///
    /// - Parameters:
    ///   - index: The index of the iteration. The first iteration has an index
    ///     of `0`.
    ///
    /// This event is posted at the end of each test plan iteration.
    ///
    /// By default, a test plan runs for one iteration, but the
    /// ``Configuration/repetitionPolicy-swift.property`` property can be set to
    /// allow for more iterations.
    indirect case iterationEnded(_ index: Int)

    /// A test run ended.
    ///
    /// This event is the last event posted before ``Runner/run()`` returns.
    case runEnded
  }

  /// The kind of event.
  public var kind: Kind

  /// The ID of the test for which this event occurred, if any.
  ///
  /// If an event occurred independently of any test, or if the running test
  /// cannot be determined, the value of this property is `nil`.
  public var testID: Test.ID?

  /// The ID of the test case for which this event occurred, if any.
  ///
  /// If an event occurred independently of any test case, or if the running
  /// test case cannot be determined, the value of this property is `nil`.
  public var testCaseID: Test.Case.ID?

  /// The instant at which the event occurred.
  public var instant: Test.Clock.Instant

  /// Initialize an instance of this type.
  ///
  /// - Parameters:
  ///   - kind: The kind of event that occurred.
  ///   - testID: The ID of the test for which the event occurred, if any.
  ///   - testCaseID: The ID of the test case for which the event occurred, if
  ///     any.
  ///   - instant: The instant at which the event occurred. The default value
  ///     of this argument is `.now`.
  ///
  /// When creating an event to be posted, use
  /// ``post(_:for:testCase:instant:configuration)`` instead since that ensures
  /// any task local-derived values in the associated ``Event/Context`` match
  /// the event.
  init(_ kind: Kind, testID: Test.ID?, testCaseID: Test.Case.ID?, instant: Test.Clock.Instant = .now) {
    self.kind = kind
    self.testID = testID
    self.testCaseID = testCaseID
    self.instant = instant
  }

  /// Post an ``Event`` with the specified values.
  ///
  /// - Parameters:
  ///   - kind: The kind of event that occurred.
  ///   - test: The test for which the event occurred, if any.
  ///   - testCase: The test case for which the event occurred, if any.
  ///   - instant: The instant at which the event occurred. The default value
  ///     of this argument is `.now`.
  ///   - configuration: The configuration whose event handler should handle
  ///     this event. If `nil` is passed, the current task's configuration is
  ///     used, if known.
  static func post(
    _ kind: Kind,
    for test: Test? = .current,
    testCase: Test.Case? = .current,
    instant: Test.Clock.Instant = .now,
    configuration: Configuration? = nil
  ) {
    // Create both the event and its associated context here at same point, to
    // ensure their task local-derived values are the same.
    let event = Event(kind, testID: test?.id, testCaseID: testCase?.id, instant: instant)
    let context = Event.Context(test: test, testCase: testCase)
    event._post(in: context, configuration: configuration)
  }
}

// MARK: - Event handling

extension Event {
  /// A function that handles events that occur while tests are running.
  ///
  /// - Parameters:
  ///   - event: An event that needs to be handled.
  ///   - context: The context associated with the event.
  public typealias Handler = @Sendable (_ event: borrowing Event, _ context: borrowing Context) -> Void

  /// A type which provides context about a posted ``Event``.
  ///
  /// An instance of this type is provided along with each ``Event`` that is
  /// passed to an ``Event/Handler``.
  public struct Context: Sendable {
    /// The test for which this instance's associated ``Event`` occurred, if
    /// any.
    ///
    /// If an event occurred independently of any test, or if the running test
    /// cannot be determined, the value of this property is `nil`.
    public var test: Test?

    /// The test case for which this instance's associated ``Event`` occurred,
    /// if any.
    ///
    /// The test case indicates which element in the iterated sequence is
    /// associated with this event. For non-parameterized tests, a single test
    /// case is synthesized. For test suite types (as opposed to test
    /// functions), the value of this property is `nil`.
    public var testCase: Test.Case?

    /// Initialize a new instance of this type.
    ///
    /// - Parameters:
    ///   - test: The test for which this instance's associated event occurred,
    ///     if any.
    ///   - testCase: The test case for which this instance's associated event
    ///     occurred, if any.
    init(test: Test? = .current, testCase: Test.Case? = .current) {
      self.test = test
      self.testCase = testCase
    }
  }

  /// Post this event to the currently-installed event handler.
  ///
  /// - Parameters:
  ///   - context: The context associated with this event.
  ///   - configuration: The configuration whose event handler should handle
  ///     this event. If `nil` is passed, the current task's configuration is
  ///     used, if known.
  ///
  /// Prefer using this function over invoking event handlers directly. If
  /// `configuration` is not `nil`, `self` is passed to its
  /// ``Configuration/eventHandler`` property. If `configuration` is `nil`, and
  /// ``Configuration/current`` is _not_ `nil`, its event handler is used
  /// instead. If there is no current configuration, the event is posted to
  /// the event handlers of all configurations set as current across all tasks
  /// in the process.
  private borrowing func _post(in context: borrowing Context, configuration: Configuration? = nil) {
    if let configuration = configuration ?? Configuration.current {
      // The caller specified a configuration, or the current task has an
      // associated configuration. Post to either configuration's event handler.
      switch kind {
      case .expectationChecked where !configuration.deliverExpectationCheckedEvents:
        break
      default:
        configuration.handleEvent(self, in: context)
      }
    } else {
      // The current task does NOT have an associated configuration. This event
      // will be lost! Post it to every registered event handler to avoid that.
      for configuration in Configuration.all {
        _post(in: context, configuration: configuration)
      }
    }
  }
}

// MARK: - Snapshotting

extension Event {
  /// A serializable event that occurred during testing.
  @_spi(ForToolsIntegrationOnly)
  public struct Snapshot: Sendable, Codable {

    /// The kind of event.
    public var kind: Kind.Snapshot

    /// The ID of the test for which this event occurred, if any.
    ///
    /// If an event occurred independently of any test, or if the running test
    /// cannot be determined, the value of this property is `nil`.
    public var testID: Test.ID?

    /// The ID of the test case for which this event occurred, if any.
    ///
    /// If an event occurred independently of any test case, or if the running
    /// test case cannot be determined, the value of this property is `nil`.
    public var testCaseID: Test.Case.ID?

    /// The instant at which the event occurred.
    public var instant: Test.Clock.Instant

    /// Snapshots an ``Event``.
    ///
    /// - Parameters:
    ///   - event: The original ``Event`` to snapshot.
    public init(snapshotting event: borrowing Event) {
      kind = Event.Kind.Snapshot(snapshotting: event.kind)
      testID = event.testID
      testCaseID = event.testCaseID
      instant = event.instant
    }
  }
}

extension Event.Kind {
  /// A serializable enumeration describing the various kinds of event that can be observed.
  public enum Snapshot: Sendable, Codable {
    /// A test was discovered during test run planning.
    ///
    /// This event is recorded once per discovered test when an instance of
    /// ``Runner`` is initialized, _prior to_ ``Runner/run()`` being called. It
    /// does not indicate whether or not a test will run—only that the test was
    /// found by the testing library.
    case testDiscovered

    /// A test run started.
    ///
    /// This is the first event posted after ``Runner/run()`` is called.
    case runStarted

    /// An iteration of the test run started.
    ///
    /// - Parameters:
    ///   - index: The index of the iteration. The first iteration has an index
    ///     of `0`.
    ///
    /// This event is posted at the start of each test plan iteration.
    ///
    /// By default, a test plan runs for one iteration, but the
    /// ``Configuration/repetitionPolicy-swift.property`` property can be set to
    /// allow for more iterations.
    indirect case iterationStarted(_ index: Int)

    /// A step in the runner plan started.
    ///
    /// - Parameters:
    ///   - step: The step in the runner plan which started.
    ///
    /// This is posted when a ``Runner`` begins processing a
    /// ``Runner/Plan/Step``. Processing this step may result in its associated
    /// ``Test`` being run, skipped, or another action, so this event will only
    /// be followed by a ``testStarted`` event if the step's test is run.
    case planStepStarted

    /// A test started.
    case testStarted

    /// A test case started.
    case testCaseStarted

    /// A test case ended.
    case testCaseEnded

    /// An expectation was checked with `#expect()` or `#require()`.
    ///
    /// - Parameters:
    ///   - expectation: The expectation which was checked.
    ///
    /// By default, events of this kind are not generated because they occur
    /// frequently in a typical test run and can generate significant
    /// backpressure on the event handler.
    ///
    /// Failed expectations also, unless expected to fail, generate events of
    /// kind ``Event/Kind-swift.enum/issueRecorded(_:)``. Those events are
    /// always posted to the current event handler.
    ///
    /// To enable events of this kind, set
    /// ``Configuration/deliverExpectationCheckedEvents`` to `true` before
    /// running tests.
    indirect case expectationChecked(_ expectation: Expectation.Snapshot)

    /// An issue was recorded.
    ///
    /// - Parameters:
    ///   - issue: The issue which was recorded.
    indirect case issueRecorded(_ issue: Issue.Snapshot)

    /// A test ended.
    case testEnded

    /// A test was skipped.
    ///
    /// - Parameters:
    ///   - skipInfo: A ``SkipInfo`` containing details about this skipped test.
    indirect case testSkipped(_ skipInfo: SkipInfo)

    /// A step in the runner plan ended.
    ///
    /// - Parameters:
    ///   - step: The step in the runner plan which ended.
    ///
    /// This is posted when a ``Runner`` finishes processing a
    /// ``Runner/Plan/Step``.
    case planStepEnded

    /// An iteration of the test run ended.
    ///
    /// - Parameters:
    ///   - index: The index of the iteration. The first iteration has an index
    ///     of `0`.
    ///
    /// This event is posted at the end of each test plan iteration.
    ///
    /// By default, a test plan runs for one iteration, but the
    /// ``Configuration/repetitionPolicy-swift.property`` property can be set to
    /// allow for more iterations.
    indirect case iterationEnded(_ index: Int)

    /// A test run ended.
    ///
    /// This is the last event posted before ``Runner/run()`` returns.
    case runEnded

    /// Snapshots an ``Event.Kind``.
    /// - Parameter kind: The original ``Event.Kind`` to snapshot.
    public init(snapshotting kind: Event.Kind) {
      switch kind {
      case .testDiscovered:
        self = .testDiscovered
      case .runStarted:
        self = .runStarted
      case let .iterationStarted(index):
        self = .iterationStarted(index)
      case .planStepStarted:
        self = .planStepStarted
      case .testStarted:
        self = .testStarted
      case .testCaseStarted:
        self = .testCaseStarted
      case .testCaseEnded:
        self = .testCaseEnded
      case let .expectationChecked(expectation):
        let expectationSnapshot = Expectation.Snapshot(snapshotting: expectation)
        self = Snapshot.expectationChecked(expectationSnapshot)
      case let .issueRecorded(issue):
        self = .issueRecorded(Issue.Snapshot(snapshotting: issue))
      case .testEnded:
        self = .testEnded
      case let .testSkipped(skipInfo):
        self = .testSkipped(skipInfo)
      case .planStepEnded:
        self = .planStepEnded
      case let .iterationEnded(index):
        self = .iterationEnded(index)
      case .runEnded:
        self = .runEnded
      }
    }
  }
}

extension Event.Context {

  /// A serializable type which provides context about a posted ``Event``.
  ///
  @_spi(ForToolsIntegrationOnly)
  public struct Snapshot: Sendable, Codable {
    /// A snapshot of the test for which this instance's associated ``Event``
    /// occurred, if any.
    ///
    /// If an event occurred independently of any test, or if the running test
    /// cannot be determined, the value of this property is `nil`.
    public var test: Test.Snapshot?

    /// A snapshot of the test case for which this instance's associated
    /// ``Event`` occurred, if any.
    ///
    /// The test case indicates which element in the iterated sequence is
    /// associated with this event. For non-parameterized tests, a single test
    /// case is synthesized. For test suite types (as opposed to test
    /// functions), the value of this property is `nil`.
    public var testCase: Test.Case.Snapshot?

    /// Initialize a new instance of this type.
    ///
    /// - Parameters:
    ///   - context: The context to snapshot.
    public init(snapshotting context: borrowing Event.Context) {
      test = context.test.map { Test.Snapshot(snapshotting: $0) }
      testCase = context.testCase.map { Test.Case.Snapshot(snapshotting: $0) }
    }
  }
}
