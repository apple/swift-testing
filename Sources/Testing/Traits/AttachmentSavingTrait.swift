//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

/// A type that defines a condition which must be satisfied for the testing
/// library to save attachments recorded by a test.
///
/// To add this trait to a test, use one of the following functions:
///
/// - ``Trait/savingAttachments(if:)``
///
/// By default, the testing library saves your attachments as soon as you call
/// ``Attachment/record(_:named:sourceLocation:)``. You can access saved
/// attachments after your tests finish running:
///
/// - When using Xcode, you can access attachments from the test report.
/// - When using Visual Studio Code, the testing library saves attachments to
///   `.build/attachments` by default. Visual Studio Code reports the paths to
///   individual attachments in its Tests Results panel.
/// - When using Swift Package Manager's `swift test` command, you can pass the
///   `--attachments-path` option. The testing library saves attachments to the
///   specified directory.
///
/// If you add an instance of this trait type to a test, any attachments that
/// test records are stored in memory until the test finishes running. The
/// testing library then evaluates the instance's condition and, if the
/// condition is met, saves the attachments.
@_spi(Experimental)
public struct AttachmentSavingTrait: TestTrait, SuiteTrait {
  /// A type that describes the conditions under which the testing library
  /// will save attachments.
  ///
  /// You can pass instances of this type to ``Trait/savingAttachments(if:)``.
  public struct Condition: Sendable {
    /// The testing library saves attachments if the test passes.
    public static var testPasses: Self {
      Self { !$0.hasFailed }
    }

    /// The testing library saves attachments if the test fails.
    public static var testFails: Self {
      Self { $0.hasFailed }
    }

    /// The testing library saves attachments if the test records a matching
    /// issue.
    ///
    /// - Parameters:
    ///   - issueMatcher: A function to invoke when an issue occurs that is used
    ///     to determine if the testing library should save attachments for the
    ///     current test.
    ///
    /// - Returns: An instance of ``AttachmentSavingTrait/Condition`` that
    ///   evaluates `issueMatcher`.
    public static func testRecordsIssue(
      matching issueMatcher: @escaping @Sendable (_ issue: Issue) async throws -> Bool
    ) -> Self {
      Self(inspectsIssues: true) { context in
        for issue in context.issues {
          if try await issueMatcher(issue) {
            return true
          }
        }
        return false
      }
    }

    /// Whether or not this condition needs to inspect individual issues (which
    /// implies a slower path.)
    fileprivate var inspectsIssues = false

    /// The condition function.
    fileprivate var body: @Sendable (borrowing Context) async throws -> Bool
  }

  /// This instance's condition.
  var condition: Condition

  /// The source location where this trait is specified.
  var sourceLocation: SourceLocation

  public var isRecursive: Bool {
    true
  }
}

// MARK: - TestScoping

extension AttachmentSavingTrait: TestScoping {
  /// A type representing the per-test-case context for this trait.
  ///
  /// An instance of this type is created for each scope this trait provides.
  /// When the scope ends, the context is then passed to the trait's condition
  /// function for evaluation.
  fileprivate struct Context: Sendable {
    /// The set of events that were deferred for later conditional handling.
    var deferredEvents = [Event]()

    /// Whether or not the current test case has recorded a failing issue.
    var hasFailed = false

    /// All issues recorded within the scope of the current test case.
    var issues = [Issue]()
  }

  public func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
    // This function should apply directly to test cases only. It doesn't make
    // sense to apply it to suites or test functions since they don't run their
    // own code.
    //
    // NOTE: this trait can't reliably affect attachments recorded when other
    // traits are evaluated (we may need a new scope in the TestScoping protocol
    // for that.)
    testCase != nil ? self : nil
  }

  public func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
    guard var configuration = Configuration.current else {
      throw SystemError(description: "There is no current Configuration when attempting to provide scope for test '\(test.name)'. Please file a bug report at https://github.com/swiftlang/swift-testing/issues/new")
    }
    let oldConfiguration = configuration

    let context = Locked(rawValue: Context())
    configuration.eventHandler = { event, eventContext in
      var eventDeferred = false
      defer {
        if !eventDeferred {
          oldConfiguration.eventHandler(event, eventContext)
        }
      }

      // Guard against events generated in unstructured tasks or outside a test
      // function body (where testCase shouldn't be nil).
      guard eventContext.test == test && eventContext.testCase != nil else {
        return
      }

      switch event.kind {
      case .valueAttached:
        // Defer this event until the current test or test case ends.
        eventDeferred = true
        context.withLock { context in
          context.deferredEvents.append(event)
        }

      case let .issueRecorded(issue):
        if condition.inspectsIssues {
          context.withLock { context in
            if issue.isFailure {
              context.hasFailed = true
            }
            context.issues.append(issue)
          }
        } else if issue.isFailure {
          context.withLock { context in
            context.hasFailed = true
          }
        }

      default:
        break
      }
    }

    // TODO: adopt async defer if/when we get it
    let result: Result<Void, any Error>
    do {
      result = try await .success(Configuration.withCurrent(configuration, perform: function))
    } catch {
      result = .failure(error)
    }
    await _handleDeferredEvents(in: context.rawValue, for: test, testCase: testCase, configuration: oldConfiguration)
    return try result.get()
  }

  /// Handle any deferred events for a given test and test case.
  ///
  /// - Parameters:
  ///   - context: A context structure containing the deferred events to handle.
  ///   - test: The test for which events were recorded.
  ///   - testCase The test case for which events were recorded, if any.
  ///   - configuration: The configuration to pass events to.
  private func _handleDeferredEvents(in context: consuming Context, for test: Test, testCase: Test.Case?, configuration: Configuration) async {
    if context.deferredEvents.isEmpty {
      // Never mind...
      return
    }

    await Issue.withErrorRecording(at: sourceLocation, configuration: configuration) {
      // Evaluate the condition.
      guard try await condition.body(context) else {
        return
      }

      // Finally issue the attachment-recorded events that we deferred.
      let eventContext = Event.Context(test: test, testCase: testCase, configuration: configuration)
      for event in context.deferredEvents {
#if DEBUG
        var event = event
        event.wasDeferred = true
#endif
        configuration.eventHandler(event, eventContext)
      }
    }
  }
}

// MARK: -

@_spi(Experimental)
extension Trait where Self == AttachmentSavingTrait {
  /// Constructs a trait that tells the testing library to only save attachments
  /// if a given condition is met.
  ///
  /// - Parameters:
  ///   - condition: A condition which, when met, means that the testing library
  ///     should save attachments that the current test has recorded. If the
  ///     condition is not met, the testing library discards the test's
  ///     attachments when the test ends.
  ///   - sourceLocation: The source location of the trait.
  ///
  /// - Returns: An instance of ``AttachmentSavingTrait`` that evaluates the
  ///   closure you provide.
  ///
  /// By default, the testing library saves your attachments as soon as you call
  /// ``Attachment/record(_:named:sourceLocation:)``. You can access saved
  /// attachments after your tests finish running:
  ///
  /// - When using Xcode, you can access attachments from the test report.
  /// - When using Visual Studio Code, the testing library saves attachments to
  ///   `.build/attachments` by default. Visual Studio Code reports the paths to
  ///   individual attachments in its Tests Results panel.
  /// - When using Swift Package Manager's `swift test` command, you can pass
  ///   the `--attachments-path` option. The testing library saves attachments
  ///   to the specified directory.
  ///
  /// If you add this trait to a test, any attachments that test records are
  /// stored in memory until the test finishes running. The testing library then
  /// evaluates `condition` and, if the condition is met, saves the attachments.
  public static func savingAttachments(
    if condition: Self.Condition,
    sourceLocation: SourceLocation = #_sourceLocation
  ) -> Self {
    Self(condition: condition, sourceLocation: sourceLocation)
  }

  /// Constructs a trait that tells the testing library to only save attachments
  /// if a given condition is met.
  ///
  /// - Parameters:
  ///   - condition: A closure that contains the trait's custom condition logic.
  ///     If this closure returns `true`, the trait tells the testing library to
  ///     save attachments that the current test has recorded. If this closure
  ///     returns `false`, the testing library discards the test's attachments
  ///     when the test ends. If this closure throws an error, the testing
  ///     library records that error as an issue and discards the test's
  ///     attachments.
  ///   - sourceLocation: The source location of the trait.
  ///
  /// - Returns: An instance of ``AttachmentSavingTrait`` that evaluates the
  ///   closure you provide.
  ///
  /// By default, the testing library saves your attachments as soon as you call
  /// ``Attachment/record(_:named:sourceLocation:)``. You can access saved
  /// attachments after your tests finish running:
  ///
  /// - When using Xcode, you can access attachments from the test report.
  /// - When using Visual Studio Code, the testing library saves attachments
  ///   to `.build/attachments` by default. Visual Studio Code reports the paths
  ///   to individual attachments in its Tests Results panel.
  /// - When using Swift Package Manager's `swift test` command, you can pass
  ///   the `--attachments-path` option. The testing library saves attachments
  ///   to the specified directory.
  ///
  /// If you add this trait to a test, any attachments that test records are
  /// stored in memory until the test finishes running. The testing library then
  /// evaluates `condition` and, if the condition is met, saves the attachments.
  public static func savingAttachments(
    if condition: @autoclosure @escaping @Sendable () throws -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
  ) -> Self {
    let condition = Self.Condition { _ in try condition() }
    return savingAttachments(if: condition, sourceLocation: sourceLocation)
  }

  /// Constructs a trait that tells the testing library to only save attachments
  /// if a given condition is met.
  ///
  /// - Parameters:
  ///   - condition: A closure that contains the trait's custom condition logic.
  ///     If this closure returns `true`, the trait tells the testing library to
  ///     save attachments that the current test has recorded. If this closure
  ///     returns `false`, the testing library discards the test's attachments
  ///     when the test ends. If this closure throws an error, the testing
  ///     library records that error as an issue and discards the test's
  ///     attachments.
  ///   - sourceLocation: The source location of the trait.
  ///
  /// - Returns: An instance of ``AttachmentSavingTrait`` that evaluates the
  ///   closure you provide.
  ///
  /// By default, the testing library saves your attachments as soon as you call
  /// ``Attachment/record(_:named:sourceLocation:)``. You can access saved
  /// attachments after your tests finish running:
  ///
  /// - When using Xcode, you can access attachments from the test report.
  /// - When using Visual Studio Code, the testing library saves attachments
  ///   to `.build/attachments` by default. Visual Studio Code reports the paths
  ///   to individual attachments in its Tests Results panel.
  /// - When using Swift Package Manager's `swift test` command, you can pass
  ///   the `--attachments-path` option. The testing library saves attachments
  ///   to the specified directory.
  ///
  /// If you add this trait to a test, any attachments that test records are
  /// stored in memory until the test finishes running. The testing library then
  /// evaluates `condition` and, if the condition is met, saves the attachments.
  ///
  /// @Comment {
  ///   - Bug: `condition` cannot be `async` without making this function
  ///     `async` even though `condition` is not evaluated locally.
  ///     ([103037177](rdar://103037177))
  /// }
  public static func savingAttachments(
    if condition: @escaping @Sendable () async throws -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
  ) -> Self {
    let condition = Self.Condition { _ in try await condition() }
    return savingAttachments(if: condition, sourceLocation: sourceLocation)
  }
}
