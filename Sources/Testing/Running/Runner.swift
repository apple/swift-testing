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

    // Post an event for every test in the resulting test plan. These events are
    // turned into JSON objects if JSON output is enabled.
    for test in plan.steps.lazy.map(\.test) {
      Event.post(.testDiscovered, for: test, testCase: nil, configuration: configuration)
    }
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
  /// Execute the ``CustomExecutionTrait/execute(_:for:testCase:)`` functions
  /// associated with the test in a plan step.
  ///
  /// - Parameters:
  ///   - step: The step being performed.
  ///   - testCase: The test case, if applicable, for which to execute the
  ///     custom trait.
  ///   - body: A function to execute from within the
  ///     ``CustomExecutionTrait/execute(_:for:testCase:)`` functions of each
  ///     trait applied to `step.test`.
  ///
  /// - Throws: Whatever is thrown by `body` or by any of the
  ///   ``CustomExecutionTrait/execute(_:for:testCase:)`` functions.
  private func _executeTraits(
    for step: Plan.Step,
    testCase: Test.Case?,
    _ body: @escaping @Sendable () async throws -> Void
  ) async throws {
    // If the test does not have any traits, exit early to avoid unnecessary
    // heap allocations below.
    if step.test.traits.isEmpty {
      return try await body()
    }

    if case .skip = step.action {
      return try await body()
    }

    // Construct a recursive function that invokes each trait's ``execute(_:for:testCase:)``
    // function. The order of the sequence is reversed so that the last trait is
    // the one that invokes body, then the second-to-last invokes the last, etc.
    // and ultimately the first trait is the first one to be invoked.
    let executeAllTraits = step.test.traits.lazy
      .reversed()
      .compactMap { $0 as? any CustomExecutionTrait }
      .compactMap { $0.execute(_:for:testCase:) }
      .reduce(body) { executeAllTraits, traitExecutor in
        {
          try await traitExecutor(executeAllTraits, step.test, testCase)
        }
      }

    try await executeAllTraits()
  }

  /// Enumerate the elements of a sequence, parallelizing enumeration in a task
  /// group if a given plan step has parallelization enabled.
  ///
  /// - Parameters:
  ///   - sequence: The sequence to enumerate.
  ///   - step: The plan step that controls parallelization. If `nil`, or if its
  ///   ``Runner/Plan/Step/action`` property is not of case
  ///   ``Runner/Plan/Action/run(options:)``, the
  ///   ``Configuration/isParallelizationEnabled`` property of this runner's
  ///   ``configuration`` property is used instead to determine if
  ///   parallelization is enabled.
  ///   - body: The function to invoke.
  ///
  /// - Throws: Whatever is thrown by `body`.
  private func _forEach<E>(
    in sequence: some Sequence<E>,
    for step: Plan.Step?,
    _ body: @Sendable @escaping (E) async throws -> Void
  ) async throws where E: Sendable {
    let isParallelizationEnabled = step?.action.isParallelizationEnabled ?? configuration.isParallelizationEnabled
    if isParallelizationEnabled {
      // Each element gets its own subtask to run in.
      try await withThrowingTaskGroup(of: Void.self) { taskGroup in
        for element in sequence {
          _ = taskGroup.addTaskUnlessCancelled {
            try await body(element)
          }
        }
        try await taskGroup.waitForAll()
      }
    } else {
      // No task group or subtasks required as parallelization is not enabled.
      for element in sequence {
        try Task.checkCancellation()
        try await body(element)
      }
    }
  }

  /// Run this test.
  ///
  /// - Parameters:
  ///   - stepGraph: The subgraph whose root value, a step, is to be run.
  ///   - depth: How deep into the step graph this call is. The first call has a
  ///     depth of `0`.
  ///   - lastAncestorStep: The last-known ancestral step, if any, of the step
  ///     at the root of `stepGraph`. The options in this step (if its action is
  ///     of case ``Runner/Plan/Action/run(options:)``) inform the execution of
  ///     `stepGraph`.
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
  private func _runStep(atRootOf stepGraph: Graph<String, Plan.Step?>, depth: Int, lastAncestorStep: Plan.Step?) async throws {
    // Exit early if the task has already been cancelled.
    try Task.checkCancellation()

    // Whether to send a `.testEnded` event at the end of running this step.
    // Some steps' actions may not require a final event to be sent — for
    // example, a skip event only sends `.testSkipped`.
    let shouldSendTestEnded: Bool

    // Determine what action to take for this step.
    if let step = stepGraph.value {
      Event.post(.planStepStarted(step), for: step.test, configuration: configuration)

      // Determine what kind of event to send for this step based on its action.
      switch step.action {
      case .run:
        Event.post(.testStarted, for: step.test, configuration: configuration)
        shouldSendTestEnded = true
      case let .skip(skipInfo):
        Event.post(.testSkipped(skipInfo), for: step.test, configuration: configuration)
        shouldSendTestEnded = false
      case let .recordIssue(issue):
        Event.post(.issueRecorded(issue), for: step.test, configuration: configuration)
        shouldSendTestEnded = false
      }
    } else {
      shouldSendTestEnded = false
    }
    defer {
      if let step = stepGraph.value {
        if shouldSendTestEnded {
          Event.post(.testEnded, for: step.test, configuration: configuration)
        }
        Event.post(.planStepEnded(step), for: step.test, configuration: configuration)
      }
    }

    if let step = stepGraph.value, case .run = step.action {
      await Test.withCurrent(step.test) {
        _ = await Issue.withErrorRecording(at: step.test.sourceLocation, configuration: configuration) {
          try await _executeTraits(for: step, testCase: nil) {
            // Run the test function at this step (if one is present.)
            if let testCases = step.test.testCases {
              try await _runTestCases(testCases, within: step)
            }
          }
        }
      }
    }

    // Figure out the last-good step, either the one at the root of `stepGraph`
    // or, if it is nil, the one passed into this function. We need to track
    // this value in case we run into sparse sections of the graph so we don't
    // lose track of the recursive `isParallelizationEnabled` property in the
    // runnable steps' options.
    let stepOrAncestor = stepGraph.value ?? lastAncestorStep

    // Run the children of this step.
    let childGraphs = stepGraph.children.sorted { $0.key < $1.key }
    try await _forEach(in: childGraphs, for: stepOrAncestor) { _, childGraph in
      try await _runStep(atRootOf: childGraph, depth: depth + 1, lastAncestorStep: stepOrAncestor)
    }
  }

  /// Run a sequence of test cases.
  ///
  /// - Parameters:
  ///   - testCases: The test cases to be run.
  ///   - step: The runner plan step associated with this test case.
  ///
  /// - Throws: Whatever is thrown from a test case's body. Thrown errors are
  ///   normally reported as test failures.
  ///
  /// If parallelization is supported and enabled, the generated test cases will
  /// be run in parallel using a task group.
  private func _runTestCases(_ testCases: some Sequence<Test.Case>, within step: Plan.Step) async throws {
    // Apply the configuration's test case filter.
    let testCases = testCases.lazy.filter { testCase in
      configuration.testCaseFilter(testCase, step.test)
    }

    try await _forEach(in: testCases, for: step) { testCase in
      try await _runTestCase(testCase, within: step)
    }
  }

  /// Run a test case.
  ///
  /// - Parameters:
  ///   - testCase: The test case to run.
  ///   - step: The runner plan step associated with this test case.
  ///
  /// - Throws: Whatever is thrown from the test case's body. Thrown errors
  ///   are normally reported as test failures.
  ///
  /// This function sets ``Test/Case/current``, then invokes the test case's
  /// body closure.
  private func _runTestCase(_ testCase: Test.Case, within step: Plan.Step) async throws {
    // Exit early if the task has already been cancelled.
    try Task.checkCancellation()

    Event.post(.testCaseStarted, for: step.test, testCase: testCase, configuration: configuration)
    defer {
      Event.post(.testCaseEnded, for: step.test, testCase: testCase, configuration: configuration)
    }

    await Test.Case.withCurrent(testCase) {
      let sourceLocation = step.test.sourceLocation
      await Issue.withErrorRecording(at: sourceLocation, configuration: configuration) {
        try await withTimeLimit(for: step.test, configuration: configuration) {
          try await _executeTraits(for: step, testCase: testCase) {
            try await testCase.body()
          }
        } timeoutHandler: { timeLimit in
          Issue.record(
            .timeLimitExceeded(timeLimitComponents: timeLimit),
            comments: [],
            backtrace: .current(),
            sourceLocation: sourceLocation,
            configuration: configuration
          )
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
  ///   - configuration: The configuration to use for running. The value of this
  ///     argument temporarily replaces the value of `runner`'s
  ///     ``Runner/configuration`` property.
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
      Event.post(.runStarted, for: nil, testCase: nil, configuration: runner.configuration)
      defer {
        Event.post(.runEnded, for: nil, testCase: nil, configuration: runner.configuration)
      }

      let repetitionPolicy = runner.configuration.repetitionPolicy
      for iterationIndex in 0 ..< repetitionPolicy.maximumIterationCount {
        Event.post(.iterationStarted(iterationIndex), for: nil, testCase: nil, configuration: runner.configuration)
        defer {
          Event.post(.iterationEnded(iterationIndex), for: nil, testCase: nil, configuration: runner.configuration)
        }

        await withTaskGroup(of: Void.self) { [runner] taskGroup in
          _ = taskGroup.addTaskUnlessCancelled {
            try? await runner._runStep(atRootOf: runner.plan.stepGraph, depth: 0, lastAncestorStep: nil)
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
