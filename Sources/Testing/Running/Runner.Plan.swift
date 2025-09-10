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
  /// A type describing a runner plan.
  public struct Plan: Sendable {
    /// The action to perform for a test in this plan.
    public enum Action: Sendable {
      /// A type describing options to apply to actions of case
      /// ``Runner/Plan/Action/run(options:)`` when they are run.
      public struct RunOptions: Sendable {
        /// Whether or not this step should be run in parallel with other tests.
        ///
        /// By default, all steps in a runner plan are run in parallel if the
        /// ``Configuration/isParallelizationEnabled`` property of the
        /// configuration passed during initialization has a value of `true`.
        ///
        /// Traits such as ``Trait/serialized`` applied to individual tests may
        /// affect whether or not that test is parallelized.
        ///
        /// ## See Also
        ///
        /// - ``ParallelizationTrait``
        @available(*, deprecated, message: "The 'isParallelizationEnabled' property is deprecated and no longer used. Its value is always false.")
        public var isParallelizationEnabled: Bool {
          get {
            false
          }
          set {}
        }
      }

      /// The test should be run.
      ///
      /// - Parameters:
      ///   - options: Options to apply to this action when it is run.
      case run(options: RunOptions)

      /// The test should be skipped.
      ///
      /// - Parameters:
      ///   - skipInfo: A ``SkipInfo`` representing the details of this skip.
      indirect case skip(_ skipInfo: SkipInfo)

      /// The test should record an issue due to a failure during
      /// planning.
      ///
      /// - Parameters:
      ///   - issue: An issue representing the failure encountered during
      ///     planning.
      indirect case recordIssue(_ issue: Issue)

      /// Whether this action should be applied recursively to child tests or
      /// should only be applied to the test it is already associated with.
      var isRecursive: Bool {
        switch self {
        case .run:
          return false
        default:
          // Currently, all possible runner plan actions other than .run are
          // recursively applied. If a new action is added that should not be
          // recursively applied, be sure to update this function with the new
          // case.
          return true
        }
      }
    }

    /// A type describing a step in a runner plan.
    ///
    /// An instance of this type contains a test and the corresponding action an
    /// instance of ``Runner`` should perform for that test.
    public struct Step: Sendable {
      /// The test to be passed to an instance of ``Runner``.
      public var test: Test

      /// The action to perform with ``test``.
      public var action: Action
    }

    /// The graph of the steps in the runner plan.
    var stepGraph: Graph<String, Step?>

    /// The steps of the runner plan.
    public var steps: [Step] {
      stepGraph.compactMap(\.value).sorted { $0.test.sourceLocation < $1.test.sourceLocation }
    }

    /// Initialize an instance of this type with the specified graph of test
    /// plan steps.
    ///
    /// - Parameters:
    ///   - stepGraph: The steps of the runner plan.
    ///
    /// This is the designated initializer for this type.
    init(stepGraph: Graph<String, Step?>) {
      self.stepGraph = stepGraph
    }

    /// Initialize an instance of this type with the specified runner plan
    /// steps.
    ///
    /// - Parameters:
    ///   - steps: The steps of the runner plan.
    public init(steps: some Sequence<Step>) {
      var stepGraph = Graph<String, Step?>()
      for step in steps {
        let idComponents = step.test.id.keyPathRepresentation
        stepGraph.insertValue(step, at: idComponents)
      }
      self.init(stepGraph: stepGraph)
    }
  }
}

// MARK: - Constructing a new runner plan

extension Runner.Plan {
  /// Recursively apply eligible traits from a test suite to its children in a
  /// graph.
  ///
  /// - Parameters:
  ///   - parentTraits: The traits from the parent graph to recursively apply to
  ///     `testGraph`.
  ///   - testGraph: The graph of tests to modify.
  ///
  /// The traits in `testGraph.value?.traits` are added to each node in
  /// `testGraph`, and then this function is called recursively on each child
  /// node.
  private static func _recursivelyApplyTraits(_ parentTraits: [any SuiteTrait] = [], to testGraph: inout Graph<String, Test?>) {
    let traits: [any SuiteTrait] = parentTraits + (testGraph.value?.traits ?? []).lazy
      .compactMap { $0 as? any SuiteTrait }
      .filter(\.isRecursive)

    testGraph.children = testGraph.children.mapValues { child in
      var child = child
      _recursivelyApplyTraits(traits, to: &child)
      child.value?.traits.insert(contentsOf: traits, at: 0)
      return child
    }
  }

  /// Recursively synthesize test instances representing suites for all missing
  /// values in the specified test graph.
  ///
  /// - Parameters:
  ///   - graph: The graph in which suites should be synthesized.
  ///   - nameComponents: The name components of the suite to synthesize, based
  ///     on the key path from the root node of the test graph to `graph`.
  private static func _recursivelySynthesizeSuites(in graph: inout Graph<String, Test?>, nameComponents: [String] = []) {
    // The recursive function. This is a local function to simplify the initial
    // call which does not need to pass the `sourceLocation:` inout argument.
    func synthesizeSuites(in graph: inout Graph<String, Test?>, nameComponents: [String] = [], sourceLocation: inout SourceLocation?) {
      for (key, var childGraph) in graph.children {
        synthesizeSuites(in: &childGraph, nameComponents: nameComponents + [key], sourceLocation: &sourceLocation)
        graph.children[key] = childGraph
      }

      if let test = graph.value {
        sourceLocation = test.sourceLocation
      } else if let unqualifiedName = nameComponents.last, let sourceLocation {
        // Don't synthesize suites representing modules.
        if nameComponents.count <= 1 {
          return
        }

        // Don't synthesize suites for nodes in the graph which are the
        // immediate ancestor of a test function. That level of the hierarchy is
        // used to disambiguate test functions which have equal names but
        // different source locations.
        if let firstChildTest = graph.children.values.first?.value, !firstChildTest.isSuite {
          return
        }

        let typeInfo = TypeInfo(fullyQualifiedNameComponents: nameComponents, unqualifiedName: unqualifiedName)

        // Note: When a suite is synthesized, it does not have an accurate
        // source location, so we use the source location of a close descendant
        // test. We do this instead of falling back to some "unknown"
        // placeholder in an attempt to preserve the correct sort ordering.
        graph.value = Test(traits: [], sourceLocation: sourceLocation, containingTypeInfo: typeInfo, isSynthesized: true)
      }
    }

    var sourceLocation: SourceLocation?
    synthesizeSuites(in: &graph, sourceLocation: &sourceLocation)
  }

  /// The basic "run" action.
  private static let _runAction = Action.run(options: .init())

  /// Determine what action to perform for a given test by preparing its traits.
  ///
  /// - Parameters:
  ///   - test: The test whose action will be determined.
  ///
  /// - Returns:The action to take for `test`.
  private static func _determineAction(for test: inout Test) async -> Action {
    let result: Action

    // We use a task group here with a single child task so that, if the trait
    // code calls Test.cancel() we don't end up cancelling the entire test run.
    // We could also model this as an unstructured task except that they aren't
    // available in the "task-to-thread" concurrency model.
    //
    // FIXME: Parallelize this work. Calling `prepare(...)` on all traits and
    // evaluating all test arguments should be safely parallelizable.
    (test, result) = await withTaskGroup(returning: (Test, Action).self) { [test] taskGroup in
      let testName = test.humanReadableName()
      let (taskName, taskAction) = if test.isSuite {
        ("suite \(testName)", "evaluating traits")
      } else {
        // TODO: split the task group's single task into two serially-run subtasks
        ("test \(testName)", "evaluating traits and test cases")
      }
      taskGroup.addTask(name: decorateTaskName(taskName, withAction: taskAction)) {
        var test = test
        var action = _runAction

        await Test.withCurrent(test) {
          do {
            var firstCaughtError: (any Error)?

            for trait in test.traits {
              do {
                try await trait.prepare(for: test)
              } catch {
                if let skipInfo = SkipInfo(error) {
                  action = .skip(skipInfo)
                  break
                } else {
                  // Only preserve the first caught error
                  firstCaughtError = firstCaughtError ?? error
                }
              }
            }

            // If no trait specified that the test should be skipped, but one
            // did throw an error, then the action is to record an issue for
            // that error.
            if case .run = action, let error = firstCaughtError {
              action = .recordIssue(Issue(for: error))
            }
          }

          // If the test is still planned to run (i.e. nothing thus far has
          // caused it to be skipped), evaluate its test cases now.
          //
          // The argument expressions of each test are captured in closures so
          // they can be evaluated lazily only once it is determined that the
          // test will run, to avoid unnecessary work. But now is the
          // appropriate time to evaluate them.
          if case .run = action {
            do {
              try await test.evaluateTestCases()
            } catch {
              if let skipInfo = SkipInfo(error) {
                action = .skip(skipInfo)
              } else {
                action = .recordIssue(Issue(for: error))
              }
            }
          }
        }

        return (test, action)
      }

      return await taskGroup.first { _ in true }!
    }

    return result
  }

  /// Construct a graph of runner plan steps for the specified tests.
  ///
  /// - Parameters:
  ///   - tests: The tests for which a graph should be constructed.
  ///   - configuration: The configuration to use for planning.
  ///
  /// - Returns: A graph of the steps corresponding to `tests`.
  private static func _constructStepGraph(from tests: some Sequence<Test>, configuration: Configuration) async -> Graph<String, Step?> {
    // Ensure that we are capturing backtraces for errors before we start
    // expecting to see them.
    Backtrace.startCachingForThrownErrors()
    defer {
      Backtrace.flushThrownErrorCache()
    }

    // Convert the list of test into a graph of steps. The actions for these
    // steps will all be .run() *unless* an error was thrown while examining
    // them, in which case it will be .recordIssue().
    let runAction = _runAction
    var testGraph = Graph<String, Test?>()
    var actionGraph = Graph<String, Action>(value: runAction)
    for test in tests {
      let idComponents = test.id.keyPathRepresentation
      testGraph.insertValue(test, at: idComponents)
      actionGraph.insertValue(runAction, at: idComponents, intermediateValue: runAction)
    }

    // Remove any tests that should be filtered out per the runner's
    // configuration. The action graph is not modified here: actions that lose
    // their corresponding tests are effectively filtered out by the call to
    // zip() near the end of the function.
    do {
      testGraph = try configuration.testFilter.apply(to: testGraph)
    } catch {
      // FIXME: Handle this more gracefully, either by propagating the error
      // (which will ultimately require `Runner.init(...)` to be throwing:
      // rdar://126631222) or by recording a single `Issue` representing the
      // planning failure.
      //
      // For now, ignore the error and include all tests. As of this writing,
      // the only scenario where this will throw is when using regex filtering,
      // and that is already guarded earlier in the SwiftPM entry point.
    }

    // Synthesize suites for nodes in the test graph for which they are missing.
    _recursivelySynthesizeSuites(in: &testGraph)

    // Recursively apply all recursive suite traits to children.
    //
    // This must be done _before_ calling `prepare(for:)` on the traits below.
    // It is safe to do this _after_ filtering the test graph since filtering
    // internally propagates information about traits which are needed to
    // correctly evaluate the filter. It's also more efficient, since it avoids
    // needlessly applying non-filtering related traits to tests which might be
    // filtered out.
    _recursivelyApplyTraits(to: &testGraph)

    // For each test value, determine the appropriate action for it.
    testGraph = await testGraph.mapValues { keyPath, test in
      // Skip any nil test, which implies this node is just a placeholder and
      // not actual test content.
      guard var test else {
        return nil
      }

      // Walk all the traits and tell each to prepare to run the test.
      // If any throw a `SkipInfo` error at this stage, stop walking further.
      // But if any throw another kind of error, keep track of the first error
      // but continue walking, because if any subsequent traits throw a
      // `SkipInfo`, the error should not be recorded.
      var action = await _determineAction(for: &test)

      // If the test is parameterized but has no cases, mark it as skipped.
      if case .run = action, let testCases = test.testCases, testCases.first(where: { _ in true }) == nil {
        action = .skip(SkipInfo(comment: "No test cases found.", sourceContext: .init(backtrace: nil, sourceLocation: test.sourceLocation)))
      }

      actionGraph.updateValue(action, at: keyPath)

      return test
    }

    // Now that we have allowed all the traits to update their corresponding
    // actions, recursively apply those actions to child tests in the graph.
    actionGraph = actionGraph.mapValues { _, action in
      (action, recursivelyApply: action.isRecursive)
    }

    // Zip the tests and actions together and return them.
    return zip(testGraph, actionGraph).mapValues { _, pair in
      pair.0.map { Step(test: $0, action: pair.1) }
    }
  }

  /// Initialize an instance of this type with the specified tests and
  /// configuration.
  ///
  /// - Parameters:
  ///   - tests: The tests for which a runner plan should be constructed.
  ///   - configuration: The configuration to use for planning.
  ///
  /// This function produces a new runner plan for the provided tests.
  public init(tests: some Sequence<Test>, configuration: Configuration) async {
    let stepGraph = await Self._constructStepGraph(from: tests, configuration: configuration)
    self.init(stepGraph: stepGraph)
  }

  /// Initialize an instance of this type that will run all tests found in the
  /// current process.
  ///
  /// - Parameters:
  ///   - configuration: The configuration to use for planning.
  public init(configuration: Configuration) async {
    await self.init(tests: Test.all, configuration: configuration)
  }
}

extension Runner.Plan.Action.RunOptions: Codable {
  private enum CodingKeys: CodingKey {
    case isParallelizationEnabled
  }

  public init(from decoder: any Decoder) throws {
    // No-op. This initializer cannot be synthesized since `CodingKeys` includes
    // a case representing a non-stored property. See comment about the
    // `isParallelizationEnabled` property in `encode(to:)`.
    self.init()
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    // The `isParallelizationEnabled` property was removed after this type was
    // first introduced. Its value was never actually used in a meaningful way
    // by known clients, but its absence can cause decoding errors, so to avoid
    // such problems, continue encoding a hardcoded value.
    try container.encode(false, forKey: .isParallelizationEnabled)
  }
}

#if !SWT_NO_SNAPSHOT_TYPES
// MARK: - Snapshotting

extension Runner.Plan {
  /// A serializable snapshot of a ``Runner/Plan-swift.struct`` instance.
  @_spi(ForToolsIntegrationOnly)
  public struct Snapshot: Sendable {
    /// The graph of the steps in this runner plan.
    private var _stepGraph: Graph<String, Step.Snapshot?> = .init(value: nil)

    /// Initialize an instance of this type by snapshotting the specified plan.
    ///
    /// - Parameters:
    ///   - plan: The original plan to snapshot.
    public init(snapshotting plan: borrowing Runner.Plan) {
      plan.stepGraph.forEach { keyPath, step in
        let step = step.map(Step.Snapshot.init(snapshotting:))
        _stepGraph.insertValue(step, at: keyPath)
      }
    }

    /// The steps of this runner plan.
    public var steps: some Collection<Step.Snapshot> {
      _stepGraph.compactMap(\.value)
    }
  }
}

extension Runner.Plan.Snapshot: Codable {
  /// The coding keys used for serializing a
  /// ``Runner/Plan-swift.struct/Snapshot`` instance.
  private enum _CodingKeys: CodingKey {
    /// The tests contained by this plan, stored as an unkeyed container of
    /// ``Test/Snapshot`` instances.
    case tests
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: _CodingKeys.self)

    var testsContainer = try container.nestedUnkeyedContainer(forKey: .tests)

    // Decode elements incrementally, rather than all at once, to avoid needing
    // an array containing all tests.
    while !testsContainer.isAtEnd {
      let step = try testsContainer.decode(Runner.Plan.Step.Snapshot.self)
      let idComponents = step.test.id.keyPathRepresentation
      _stepGraph.insertValue(step, at: idComponents)
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: _CodingKeys.self)

    var testsContainer = container.nestedUnkeyedContainer(forKey: .tests)

    // Encode elements incrementally, rather than all at once, to avoid needing
    // an array containing all tests.
    try _stepGraph.forEach { _, step in
      guard let step else { return }
      try testsContainer.encode(step)
    }
  }
}

extension Runner.Plan.Step {
  /// A serializable snapshot of a ``Runner/Plan-swift.struct/Step`` instance.
  @_spi(ForToolsIntegrationOnly)
  public struct Snapshot: Sendable, Codable {
    /// The test referenced by this instance.
    public var test: Test.Snapshot

    /// The action to perform with ``test``.
    public var action: Runner.Plan.Action.Snapshot

    /// Initialize an instance of this type by snapshotting the specified step.
    ///
    /// - Parameters:
    ///   - step: The original step to snapshot.
    public init(snapshotting step: borrowing Runner.Plan.Step) {
      test = Test.Snapshot(snapshotting: step.test)
      action = Runner.Plan.Action.Snapshot(snapshotting: step.action)
    }
  }
}

extension Runner.Plan.Action {
  /// A serializable snapshot of a ``Runner/Plan-swift.struct/Action``
  /// instance.
  @_spi(ForToolsIntegrationOnly)
  public enum Snapshot: Sendable, Codable {
    /// The test should be run.
    ///
    /// - Parameters:
    ///   - options: Options to apply to this action when it is run.
    case run(options: RunOptions)

    /// The test should be skipped.
    ///
    /// - Parameters:
    ///   - skipInfo: A ``SkipInfo`` representing the details of this skip.
    case skip(_ skipInfo: SkipInfo)

    /// The test should record an issue due to a failure during
    /// planning.
    ///
    /// - Parameters:
    ///   - issue: A snapshot of the issue representing the failure encountered
    ///     during planning.
    case recordIssue(_ issue: Issue.Snapshot)

    /// Initialize an instance of this type by snapshotting the specified
    /// action.
    ///
    /// - Parameters:
    ///   - action: The original action to snapshot.
    public init(snapshotting action: Runner.Plan.Action) {
      self = switch action {
      case let .run(options):
        .run(options: options)
      case let .skip(skipInfo):
        .skip(skipInfo)
      case let .recordIssue(issue):
        .recordIssue(Issue.Snapshot(snapshotting: issue))
      }
    }
  }
}
#endif

// MARK: - Deprecated

extension Runner.Plan.Action {
  @available(*, deprecated, message: "Use .skip(_:) and pass a SkipInfo explicitly.")
  public static func skip() -> Self {
    .skip(SkipInfo())
  }
}
