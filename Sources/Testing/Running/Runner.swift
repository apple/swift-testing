//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

/// A type that runs tests according to a given configuration.
@_spi(ForToolsIntegrationOnly)
public struct Runner: Sendable {
  /// The plan to follow when running the associated tests.
  public var plan: Plan

  /// The set of tests this runner will run.
  public var tests: [Test] { plan.steps.map(\.test) }

  /// The runner's configuration.
  public var configuration: Configuration

  /// Initialize an instance of this type that runs the specified series of
  /// tests.
  ///
  /// - Parameters:
  ///   - tests: The tests to run.
  ///   - configuration: The configuration to use for running.
  public init(testing tests: [Test], configuration: Configuration = .init()) async {
    let plan = await Plan(tests: tests, configuration: configuration)
    self.init(plan: plan, configuration: configuration)
  }

  /// Initialize an instance of this type that runs the tests in the specified
  /// plan.
  ///
  /// - Parameters:
  ///   - plan: A previously constructed plan.
  ///   - configuration: The configuration to use for running.
  public init(plan: Plan, configuration: Configuration = .init()) {
    self.plan = plan
    self.configuration = configuration
  }

  /// Initialize an instance of this type that runs all tests found in the
  /// current process.
  ///
  /// - Parameters:
  ///   - configuration: The configuration to use for running.
  public init(configuration: Configuration = .init()) async {
    let plan = await Plan(configuration: configuration)
    self.init(plan: plan, configuration: configuration)
  }
}

// MARK: - Running tests

extension Runner {
  /// The current configuration _while_ running.
  ///
  /// This should be used from the functions in this extension which access the
  /// current configuration. This is important since individual tests or suites
  /// may have traits which customize the execution scope of their children,
  /// including potentially modifying the current configuration.
  private static var _configuration: Configuration {
    .current ?? .init()
  }

  /// Apply the custom scope for any test scope providers of the traits
  /// associated with a specified test by calling their
  /// ``TestScoping/provideScope(for:testCase:performing:)`` function.
  ///
  /// - Parameters:
  ///   - test: The test being run, for which to provide custom scope.
  ///   - testCase: The test case, if applicable, for which to provide custom
  ///     scope.
  ///   - body: A function to execute from within the
  ///     ``TestScoping/provideScope(for:testCase:performing:)`` function of
  ///     each non-`nil` scope provider of the traits applied to `test`.
  ///
  /// - Throws: Whatever is thrown by `body` or by any of the
  ///   ``TestScoping/provideScope(for:testCase:performing:)`` function calls.
  private static func _applyScopingTraits(
    for test: Test,
    testCase: Test.Case?,
    _ body: @escaping @Sendable () async throws -> Void
  ) async throws {
    // If the test does not have any traits, exit early to avoid unnecessary
    // heap allocations below.
    if test.traits.isEmpty {
      return try await body()
    }

    // Construct a recursive function that invokes each scope provider's
    // `provideScope(for:testCase:performing:)` function. The order of the
    // sequence is reversed so that the last trait is the one that invokes body,
    // then the second-to-last invokes the last, etc. and ultimately the first
    // trait is the first one to be invoked.
    let executeAllTraits = test.traits.lazy
      .reversed()
      .compactMap { $0.scopeProvider(for: test, testCase: testCase) }
      .map { $0.provideScope(for:testCase:performing:) }
      .reduce(body) { executeAllTraits, provideScope in
        {
          try await provideScope(test, testCase, executeAllTraits)
        }
      }

    try await executeAllTraits()
  }

  /// Apply the custom scope from any issue handling traits for the specified
  /// test.
  ///
  /// - Parameters:
  ///   - test: The test being run, for which to apply its issue handling traits.
  ///   - body: A function to execute within the scope provided by the test's
  ///     issue handling traits.
  ///
  /// - Throws: Whatever is thrown by `body` or by any of the traits' provide
  ///   scope function calls.
  private static func _applyIssueHandlingTraits(for test: Test, _ body: @escaping @Sendable () async throws -> Void) async throws {
    // If the test does not have any traits, exit early to avoid unnecessary
    // heap allocations below.
    if test.traits.isEmpty {
      return try await body()
    }

    // Construct a recursive function that invokes each issue handling trait's
    // `provideScope(performing:)` function. The order of the sequence is
    // reversed so that the last trait is the one that invokes body, then the
    // second-to-last invokes the last, etc. and ultimately the first trait is
    // the first one to be invoked.
    let executeAllTraits = test.traits.lazy
      .compactMap { $0 as? IssueHandlingTrait }
      .reversed()
      .map { $0.provideScope(performing:) }
      .reduce(body) { executeAllTraits, provideScope in
        {
          try await provideScope(executeAllTraits)
        }
      }

    try await executeAllTraits()
  }

  /// Enumerate the elements of a sequence, parallelizing enumeration in a task
  /// group if a given plan step has parallelization enabled.
  ///
  /// - Parameters:
  ///   - sequence: The sequence to enumerate.
  ///   - taskNamer: A function to invoke for each element in `sequence`. The
  ///     result of this function is used to name each child task.
  ///   - body: The function to invoke.
  ///
  /// - Throws: Whatever is thrown by `body`.
  private static func _forEach<E>(
    in sequence: some Sequence<E>,
    namingTasksWith taskNamer: (borrowing E) -> (taskName: String, action: String?)?,
    _ body: @Sendable @escaping (borrowing E) async throws -> Void
  ) async rethrows where E: Sendable {
    try await withThrowingTaskGroup { taskGroup in
      for element in sequence {
        // Each element gets its own subtask to run in.
        let taskName = taskNamer(element)
        taskGroup.addTask(name: decorateTaskName(taskName?.taskName, withAction: taskName?.action)) {
          try await body(element)
        }

        // If not parallelizing, wait after each task.
        if !_configuration.isParallelizationEnabled {
          try await taskGroup.waitForAll()
        }
      }
    }
  }

  /// Run this test.
  ///
  /// - Parameters:
  ///   - stepGraph: The subgraph whose root value, a step, is to be run.
  ///
  /// - Throws: Whatever is thrown from the test body. Thrown errors are
  ///   normally reported as test failures.
  ///
  /// This function sets ``Test/current``, then runs the test's content.
  ///
  /// The caller is responsible for configuring a task group for the test to run
  /// in if it should be parallelized. If `step.test` is parameterized and
  /// parallelization is supported and enabled, its test cases will be run in a
  /// nested task group.
  ///
  /// ## See Also
  ///
  /// - ``Runner/run()``
  private static func _runStep(atRootOf stepGraph: Graph<String, Plan.Step?>) async throws {
    // Whether to send a `.testEnded` event at the end of running this step.
    // Some steps' actions may not require a final event to be sent — for
    // example, a skip event only sends `.testSkipped`.
    let shouldSendTestEnded: Bool

    let configuration = _configuration

    // Determine what action to take for this step.
    if let step = stepGraph.value {
      Event.post(.planStepStarted(step), for: (step.test, nil), configuration: configuration)

      // Determine what kind of event to send for this step based on its action.
      switch step.action {
      case .run:
        Event.post(.testStarted, for: (step.test, nil), configuration: configuration)
        shouldSendTestEnded = true
      case let .skip(skipInfo):
        Event.post(.testSkipped(skipInfo), for: (step.test, nil), configuration: configuration)
        shouldSendTestEnded = false
      case let .recordIssue(issue):
        // Scope posting the issue recorded event such that issue handling
        // traits have the opportunity to handle it. This ensures that if a test
        // has an issue handling trait _and_ some other trait which caused an
        // issue to be recorded, the issue handling trait can process the issue
        // even though it wasn't recorded by the test function.
        try await Test.withCurrent(step.test) {
          try await _applyIssueHandlingTraits(for: step.test) {
            // Don't specify `configuration` when posting this issue so that
            // traits can provide scope and potentially customize the
            // configuration.
            Event.post(.issueRecorded(issue), for: (step.test, nil))
          }
        }
        shouldSendTestEnded = false
      }
    } else {
      shouldSendTestEnded = false
    }
    defer {
      if let step = stepGraph.value {
        if shouldSendTestEnded {
          Event.post(.testEnded, for: (step.test, nil), configuration: configuration)
        }
        Event.post(.planStepEnded(step), for: (step.test, nil), configuration: configuration)
      }
    }

    if let step = stepGraph.value, case .run = step.action {
      await Test.withCurrent(step.test) {
        _ = await Issue.withErrorRecording(at: step.test.sourceLocation, configuration: configuration) {
          // Exit early if the task has already been cancelled.
          try Task.checkCancellation()

          try await _applyScopingTraits(for: step.test, testCase: nil) {
            // Run the test function at this step (if one is present.)
            if let testCases = step.test.testCases {
              await _runTestCases(testCases, within: step)
            }

            // Run the children of this test (i.e. the tests in this suite.)
            try await _runChildren(of: stepGraph)
          }
        }
      }
    } else {
      // There is no test at this node in the graph, so just skip down to the
      // child nodes.
      try await _runChildren(of: stepGraph)
    }
  }

  /// Get the source location corresponding to the root of a plan step graph.
  ///
  /// - Parameters:
  ///   - stepGraph: The plan step graph whose root node is of interest.
  ///
  /// - Returns: The source location of the root node of `stepGraph`, or of the
  ///   first descendant node thereof (sorted by source location.)
  private static func _sourceLocation(of stepGraph: Graph<String, Plan.Step?>) -> SourceLocation? {
    if let result = stepGraph.value?.test.sourceLocation {
      return result
    }
    return stepGraph.children.lazy
      .compactMap { _sourceLocation(of: $0.value) }
      .min()
  }

  /// Recursively run the tests that are children of a given plan step.
  ///
  /// - Parameters:
  ///   - stepGraph: The subgraph whose root value, a step, will be used to
  ///     find children to run.
  ///
  /// - Throws: Whatever is thrown from the test body. Thrown errors are
  ///   normally reported as test failures.
  private static func _runChildren(of stepGraph: Graph<String, Plan.Step?>) async throws {
    let childGraphs = if _configuration.isParallelizationEnabled {
      // Explicitly shuffle the steps to help detect accidental dependencies
      // between tests due to their ordering.
      Array(stepGraph.children)
    } else {
      // Sort the children by source order. If a child node is empty but has
      // descendants, the lowest-ordered child node is used. If a child node is
      // empty and has no descendant nodes with source location information,
      // then we sort it before nodes with source location information (though
      // it won't end up doing anything in the test run.)
      //
      // FIXME: this operation is likely O(n log n) or worse when amortized
      // across the entire test plan; Graph should adopt OrderedDictionary if
      // possible so it can pre-sort its nodes once.
      stepGraph.children.sorted { lhs, rhs in
        switch (_sourceLocation(of: lhs.value), _sourceLocation(of: rhs.value)) {
        case let (.some(lhs), .some(rhs)):
          lhs < rhs
        case (.some, _):
          false // x < nil == false
        case (_, .some):
          true // nil < x == true
        default:
          false // stable ordering
        }
      }
    }

    // Figure out how to name child tasks.
    func taskNamer(_ childGraph: Graph<String, Plan.Step?>) -> (String, String?)? {
      childGraph.value.map { step in
        let testName = step.test.humanReadableName()
        if step.test.isSuite {
          return ("suite \(testName)", "running")
        }
        return ("test \(testName)", nil) // test cases have " - running" suffix
      }
    }

    // Run the child nodes.
    try await _forEach(in: childGraphs.lazy.map(\.value), namingTasksWith: taskNamer) { childGraph in
      try await _runStep(atRootOf: childGraph)
    }
  }

  /// Run a sequence of test cases.
  ///
  /// - Parameters:
  ///   - testCases: The test cases to be run.
  ///   - step: The runner plan step associated with this test case.
  ///
  /// If parallelization is supported and enabled, the generated test cases will
  /// be run in parallel using a task group.
  private static func _runTestCases(_ testCases: some Sequence<Test.Case>, within step: Plan.Step) async {
    // Apply the configuration's test case filter.
    let testCaseFilter = _configuration.testCaseFilter
    let testCases = testCases.lazy.filter { testCase in
      testCaseFilter(testCase, step.test)
    }

    // Figure out how to name child tasks.
    let testName = "test \(step.test.humanReadableName())"
    let taskNamer: (Int, Test.Case) -> (String, String?)? = if step.test.isParameterized {
      { i, _ in (testName, "running test case #\(i + 1)") }
    } else {
      { _, _ in (testName, "running") }
    }

    await _forEach(in: testCases.enumerated(), namingTasksWith: taskNamer) { _, testCase in
      await _runTestCase(testCase, within: step)
    }
  }

  /// Run a test case.
  ///
  /// - Parameters:
  ///   - testCase: The test case to run.
  ///   - step: The runner plan step associated with this test case.
  ///
  /// This function sets ``Test/Case/current``, then invokes the test case's
  /// body closure.
  private static func _runTestCase(_ testCase: Test.Case, within step: Plan.Step) async {
    let configuration = _configuration

    Event.post(.testCaseStarted, for: (step.test, testCase), configuration: configuration)
    defer {
      Event.post(.testCaseEnded, for: (step.test, testCase), configuration: configuration)
    }

    await Test.Case.withCurrent(testCase) {
      let sourceLocation = step.test.sourceLocation
      await Issue.withErrorRecording(at: sourceLocation, configuration: configuration) {
        // Exit early if the task has already been cancelled.
        try Task.checkCancellation()

        try await withTimeLimit(for: step.test, configuration: configuration) {
          try await _applyScopingTraits(for: step.test, testCase: testCase) {
            try await testCase.body()
          }
        } timeoutHandler: { timeLimit in
          let issue = Issue(
            kind: .timeLimitExceeded(timeLimitComponents: timeLimit),
            comments: [],
            sourceContext: .init(backtrace: .current(), sourceLocation: sourceLocation)
          )
          issue.record(configuration: configuration)
        }
      }
    }
  }

  /// Run the tests in this runner's plan.
  public func run() async {
    await Self._run(self)
  }

  /// Run the tests in a runner's plan with a given configuration.
  ///
  /// - Parameters:
  ///   - runner: The runner to run.
  ///
  /// This function is `static` so that it cannot accidentally reference `self`
  /// or `self.configuration` when it should use a modified copy of either.
  private static func _run(_ runner: Self) async {
    var runner = runner
    runner.configureEventHandlerRuntimeState()

    // Track whether or not any issues were recorded across the entire run.
    let issueRecorded = Locked(rawValue: false)
    runner.configuration.eventHandler = { [eventHandler = runner.configuration.eventHandler] event, context in
      if case let .issueRecorded(issue) = event.kind, !issue.isKnown {
        issueRecorded.withLock { issueRecorded in
          issueRecorded = true
        }
      }
      eventHandler(event, context)
    }

    await Configuration.withCurrent(runner.configuration) {
      // Post an event for every test in the test plan being run. These events
      // are turned into JSON objects if JSON output is enabled.
      for test in runner.plan.steps.lazy.map(\.test) {
        Event.post(.testDiscovered, for: (test, nil), configuration: runner.configuration)
      }

      Event.post(.runStarted, for: (nil, nil), configuration: runner.configuration)
      defer {
        Event.post(.runEnded, for: (nil, nil), configuration: runner.configuration)
      }

      let repetitionPolicy = runner.configuration.repetitionPolicy
      let iterationCount = repetitionPolicy.maximumIterationCount
      for iterationIndex in 0 ..< iterationCount {
        Event.post(.iterationStarted(iterationIndex), for: (nil, nil), configuration: runner.configuration)
        defer {
          Event.post(.iterationEnded(iterationIndex), for: (nil, nil), configuration: runner.configuration)
        }

        await withTaskGroup { [runner] taskGroup in
          var taskAction: String?
          if iterationCount > 1 {
            taskAction = "running iteration #\(iterationIndex + 1)"
          }
          _ = taskGroup.addTaskUnlessCancelled(name: decorateTaskName("test run", withAction: taskAction)) {
            try? await _runStep(atRootOf: runner.plan.stepGraph)
          }
          await taskGroup.waitForAll()
        }

        // Determine if the test plan should iterate again. (The iteration count
        // is handled by the outer for-loop.)
        let shouldContinue = switch repetitionPolicy.continuationCondition {
        case nil:
          true
        case .untilIssueRecorded:
          !issueRecorded.rawValue
        case .whileIssueRecorded:
          issueRecorded.rawValue
        }
        guard shouldContinue else {
          break
        }

        // Reset the run-wide "issue was recorded" flag for this iteration.
        issueRecorded.withLock { issueRecorded in
          issueRecorded = false
        }
      }
    }
  }
}
