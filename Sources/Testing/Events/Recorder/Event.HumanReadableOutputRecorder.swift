//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

extension Event {
  /// A type which handles ``Event`` instances and outputs representations of
  /// them as human-readable messages.
  ///
  /// This type can be used compositionally to produce output in other
  /// human-readable formats such as rich text or HTML.
  ///
  /// The format of the output is not meant to be machine-readable and is
  /// subject to change. For machine-readable output, use ``JUnitXMLRecorder``.
  @_spi(ForToolsIntegrationOnly)
  public struct HumanReadableOutputRecorder: Sendable/*, ~Copyable*/ {
    /// A type describing a human-readable message produced by an instance of
    /// ``Event/HumanReadableOutputRecorder``.
    public struct Message: Sendable {
      /// The symbol associated with this message, if any.
      var symbol: Symbol?

      /// The human-readable message.
      var stringValue: String

      /// A concise version of ``stringValue``, if available.
      ///
      /// Not all messages include a concise string.
      var conciseStringValue: String?
    }

    /// A type that contains mutable context for
    /// ``Event/ConsoleOutputRecorder``.
    fileprivate struct Context {
      /// The instant at which the run started.
      var runStartInstant: Test.Clock.Instant?

      /// The instant at which the current iteration started.
      var iterationStartInstant: Test.Clock.Instant?

      /// The number of tests started or skipped during the run.
      ///
      /// This value does not include test suites.
      var testCount = 0

      /// The number of test suites started or skipped during the run.
      var suiteCount = 0

      /// An enumeration describing the various keys which can be used in a test
      /// data graph for an output recorder.
      enum TestDataKey: Hashable {
        /// A string key, typically containing one key from the key path
        /// representation of a ``Test/ID`` instance.
        case string(String)

        /// A test case ID.
        case testCaseID(Test.Case.ID)
      }

      /// A type describing data tracked on a per-test basis.
      struct TestData {
        /// The instant at which the test started.
        var startInstant: Test.Clock.Instant

        /// The number of issues recorded for the test, grouped by their
        /// level of severity.
        var issueCount: [Issue.Severity: Int] = [:]

        /// The number of known issues recorded for the test.
        var knownIssueCount = 0

        /// Information about the cancellation of this test or test case.
        var cancellationInfo: SkipInfo?
      }

      /// Data tracked on a per-test basis.
      var testData = Graph<TestDataKey, TestData?>()
    }

    /// This event recorder's mutable context about events it has received,
    /// which may be used to inform how subsequent events are written.
    private var _context = Locked(rawValue: Context())

    /// Initialize a new human-readable event recorder.
    ///
    /// Output from the testing library is converted to "messages" using the
    /// ``Event/HumanReadableOutputRecorder/record(_:in:verbosity:)`` function.
    /// The format of those messages is, as the type's name suggests, not meant
    /// to be machine-readable and is subject to change.
    public init() {}
  }
}

// MARK: -

extension Event.HumanReadableOutputRecorder {
  /// Get a string representing an array of comments, formatted for output.
  ///
  /// - Parameters:
  ///   - comments: The comments that should be formatted.
  ///
  /// - Returns: An array of formatted messages representing `comments`, or an
  ///   empty array if there are none.
  private func _formattedComments(_ comments: [Comment]) -> [Message] {
    comments.map(_formattedComment)
  }

  /// Get a string representing a single comment, formatted for output.
  ///
  /// - Parameters:
  ///   - comment: The comment that should be formatted.
  ///
  /// - Returns: A formatted message representing `comment`.
  private func _formattedComment(_ comment: Comment) -> Message {
    Message(symbol: .details, stringValue: comment.rawValue)
  }

  /// Get a string representing the comments attached to a test, formatted for
  /// output.
  ///
  /// - Parameters:
  ///   - test: The test whose comments should be formatted.
  ///
  /// - Returns: A formatted string representing the comments attached to `test`,
  ///   or `nil` if there are none.
  private func _formattedComments(for test: Test) -> [Message] {
    _formattedComments(test.comments(from: Comment.self))
  }

  /// Get the total number of issues recorded in a graph of test data
  /// structures.
  ///
  /// - Parameters:
  ///   - graph: The graph to walk while counting issues.
  ///
  /// - Returns: A tuple containing the number of issues recorded in `graph`.
  private func _issueCounts(
    in graph: Graph<Event.HumanReadableOutputRecorder.Context.TestDataKey, Event.HumanReadableOutputRecorder.Context.TestData?>?
  ) -> (errorIssueCount: Int, warningIssueCount: Int, knownIssueCount: Int, totalIssueCount: Int, description: String) {
    guard let graph else {
      return (0, 0, 0, 0, "")
    }
    let errorIssueCount = graph.compactMap { $0.value?.issueCount[.error] }.reduce(into: 0, +=)
    let warningIssueCount = graph.compactMap { $0.value?.issueCount[.warning] }.reduce(into: 0, +=)
    let knownIssueCount = graph.compactMap(\.value?.knownIssueCount).reduce(into: 0, +=)
    let totalIssueCount = errorIssueCount + warningIssueCount + knownIssueCount

    // Construct a string describing the issue counts.
    let description = switch (errorIssueCount > 0, warningIssueCount > 0, knownIssueCount > 0) {
    case (true, true, true):
      " with \(totalIssueCount.counting("issue")) (including \(warningIssueCount.counting("warning")) and \(knownIssueCount.counting("known issue")))"
    case (true, false, true):
      " with \(totalIssueCount.counting("issue")) (including \(knownIssueCount.counting("known issue")))"
    case (false, true, true):
      " with \(warningIssueCount.counting("warning")) and \(knownIssueCount.counting("known issue"))"
    case (false, false, true):
      " with \(knownIssueCount.counting("known issue"))"
    case (true, true, false):
      " with \(totalIssueCount.counting("issue")) (including \(warningIssueCount.counting("warning")))"
    case (true, false, false):
      " with \(totalIssueCount.counting("issue"))"
    case(false, true, false):
      " with \(warningIssueCount.counting("warning"))"
    case(false, false, false):
      ""
    }

    return (errorIssueCount, warningIssueCount, knownIssueCount, totalIssueCount,  description)
  }
}

/// Generate a title for the specified test (either "Test" or "Suite"),
/// capitalized and suitable for use as the leading word of a human-readable
/// message string.
///
/// - Parameters:
///   - test: The test to generate a description for, if any.
///
/// - Returns: A human-readable title for the specified test. Defaults to "Test"
///   if `test` is `nil`.
private func _capitalizedTitle(for test: Test?) -> String {
  test?.isSuite == true ? "Suite" : "Test"
}

extension Test {
  /// The name to use for this test in a human-readable context such as console
  /// output.
  ///
  /// - Parameters:
  ///   - verbosity: The verbosity with which to describe this test.
  ///
  /// - Returns: The name of this test, suitable for display to the user.
  func humanReadableName(withVerbosity verbosity: Int = 0) -> String {
    switch displayName {
    case let .some(displayName) where verbosity > 0:
      #""\#(displayName)" (aka '\#(name)')"#
    case let .some(displayName):
      #""\#(displayName)""#
    default:
      name
    }
  }
}

extension Test.Case {
  /// The arguments of this test case, formatted for presentation, prefixed by
  /// their corresponding parameter label when available.
  ///
  /// - Parameters:
  ///   - includeTypeNames: Whether the qualified type name of each argument's
  ///     runtime type should be included. Defaults to `false`.
  ///
  /// - Returns: A string containing the arguments of this test case formatted
  ///   for presentation, or an empty string if this test cases is
  ///   non-parameterized.
  fileprivate func labeledArguments(includingQualifiedTypeNames includeTypeNames: Bool = false) -> String {
    guard let arguments else { return "" }

    return arguments.lazy
      .map { argument in
        let valueDescription = String(describingForTest: argument.value)

        let label = argument.parameter.secondName ?? argument.parameter.firstName
        let labeledArgument = if label == "_" {
          valueDescription
        } else {
          "\(label) → \(valueDescription)"
        }

        if includeTypeNames {
          let typeInfo = TypeInfo(describingTypeOf: argument.value)
          return "\(labeledArgument) (\(typeInfo.fullyQualifiedName))"
        } else {
          return labeledArgument
        }
      }
      .joined(separator: ", ")
  }
}

// MARK: -

extension Event.HumanReadableOutputRecorder {
  /// Record the specified event by generating zero or more messages that
  /// describe it.
  ///
  /// - Parameters:
  ///   - event: The event to record.
  ///   - eventContext: The context associated with the event.
  ///   - verbosity: How verbose output should be. When the value of this
  ///     argument is greater than `0`, additional output is provided. When the
  ///     value of this argument is less than `0`, some output is suppressed.
  ///     If the value of this argument is `nil`, the value set for the current
  ///     configuration is used instead. The exact effects of this argument are
  ///     implementation-defined and subject to change.
  ///
  /// - Returns: An array of zero or more messages that can be displayed to the
  ///   user.
  @discardableResult public func record(
    _ event: borrowing Event,
    in eventContext: borrowing Event.Context,
    verbosity: Int? = nil
  ) -> [Message] {
    let verbosity: Int = if let verbosity {
      verbosity
    } else if let verbosity = eventContext.configuration?.verbosity {
      verbosity
    } else {
      0
    }
    let test = eventContext.test
    let testCase = eventContext.testCase
    let keyPath = eventContext.keyPath
    let testName = test?.humanReadableName(withVerbosity: verbosity) ?? "«unknown»"
    let instant = event.instant
    let iterationCount = eventContext.configuration?.repetitionPolicy.maximumIterationCount

    // First, make any updates to the context/state associated with this
    // recorder.
    let context = _context.withLock { context in
      switch event.kind {
      case .runStarted:
        context.runStartInstant = instant

      case .iterationStarted:
        if let iterationCount, iterationCount > 1 {
          context.iterationStartInstant = instant
        }

      case .testStarted:
        let test = test!
        context.testData[keyPath] = .init(startInstant: instant)
        if test.isSuite {
          context.suiteCount += 1
        } else {
          context.testCount += 1
        }

      case .testSkipped:
        let test = test!
        if test.isSuite {
          context.suiteCount += 1
        } else {
          context.testCount += 1
        }

      case let .issueRecorded(issue):
        var testData = context.testData[keyPath] ?? .init(startInstant: instant)
        if issue.isKnown {
          testData.knownIssueCount += 1
        } else {
          let issueCount = testData.issueCount[issue.severity] ?? 0
          testData.issueCount[issue.severity] = issueCount + 1
        }
        context.testData[keyPath] = testData
      
      case .testCaseStarted:
        context.testData[keyPath] = .init(startInstant: instant)

      case let .testCancelled(skipInfo), let .testCaseCancelled(skipInfo):
        context.testData[keyPath]?.cancellationInfo = skipInfo

      default:
        // These events do not manipulate the context structure.
        break
      }

      return context
    }

    // If in quiet mode, only produce messages for a subset of events we'd
    // otherwise log.
    if verbosity == .min {
      // Quietest mode: no messages at all.
      return []
    } else if verbosity < 0 {
      switch event.kind {
      case .runStarted, .issueRecorded, .runEnded:
        break
      default:
        return []
      }
    }

    // Finally, produce any messages for the event.
    switch event.kind {
    case .testDiscovered:
      // Suppress events of this kind from output as they are not generally
      // interesting in human-readable output.
      break

    case .runStarted:
      var comments = [Comment]()
      if verbosity > 0 {
        if let swiftStandardLibraryVersion {
          comments.append("Swift Standard Library Version: \(swiftStandardLibraryVersion)")
        }
        comments.append("Swift Compiler Version: \(swiftCompilerVersion)")
#if os(Linux) && canImport(Glibc)
        comments.append("GNU C Library Version: \(glibcVersion)")
#endif
      }
      comments.append("Testing Library Version: \(testingLibraryVersion)")
      if let targetTriple {
        comments.append("Target Platform: \(targetTriple)")
      }
      if verbosity > 0 {
#if targetEnvironment(simulator)
        comments.append("OS Version (Simulator): \(simulatorVersion)")
        comments.append("OS Version (Host): \(operatingSystemVersion)")
#else
        comments.append("OS Version: \(operatingSystemVersion)")
#endif
      }
      return CollectionOfOne(
        Message(
          symbol: .default,
          stringValue: "Test run started."
        )
      ) + _formattedComments(comments)

    case let .iterationStarted(index):
      if let iterationCount, iterationCount > 1 {
        return [
          Message(
            symbol: .default,
            stringValue: "Iteration \(index + 1) started."
          )
        ]
      }

    case .planStepStarted, .planStepEnded:
      // Suppress events of these kinds from output as they are not generally
      // interesting in human-readable output.
      break

    case .testStarted:
      let test = test!
      return [
        Message(
          symbol: .default,
          stringValue: "\(_capitalizedTitle(for: test)) \(testName) started."
        )
      ]

    case .testEnded:
      let test = test!
      let testDataGraph = context.testData.subgraph(at: keyPath)
      let testData = testDataGraph?.value ?? .init(startInstant: instant)
      let issues = _issueCounts(in: testDataGraph)
      let duration = testData.startInstant.descriptionOfDuration(to: instant)
      let testCasesCount = if test.isParameterized, let testDataGraph {
        " with \(testDataGraph.children.count.counting("test case"))"
      } else {
        ""
      }
      var cancellationComment = "."
      let (symbol, verbed): (Event.Symbol, String)
      if issues.errorIssueCount > 0 {
        (symbol, verbed) = (.fail, "failed")
      } else if !test.isParameterized, let cancellationInfo = testData.cancellationInfo {
        if let comment = cancellationInfo.comment {
          cancellationComment = ": \"\(comment.rawValue)\""
        }
        (symbol, verbed) = (.skip, "was cancelled")
      } else {
        (symbol, verbed) = (.pass(knownIssueCount: issues.knownIssueCount), "passed")
      }

      var result = [
        Message(
          symbol: symbol,
          stringValue: "\(_capitalizedTitle(for: test)) \(testName)\(testCasesCount) \(verbed) after \(duration)\(issues.description)\(cancellationComment)"
        )
      ]
      if issues.errorIssueCount > 0 {
        result += _formattedComments(for: test)
      }
      return result

    case let .testSkipped(skipInfo):
      let test = test!
      return if let comment = skipInfo.comment {
        [
          Message(symbol: .skip, stringValue: "\(_capitalizedTitle(for: test)) \(testName) skipped: \"\(comment.rawValue)\"")
        ]
      } else {
        [
          Message(symbol: .skip, stringValue: "\(_capitalizedTitle(for: test)) \(testName) skipped.")
        ]
      }

    case .expectationChecked:
      // Suppress events of this kind from output as they are not generally
      // interesting in human-readable output.
      break

    case let .issueRecorded(issue):
      let parameterCount = if let parameters = test?.parameters {
        parameters.count
      } else {
        0
      }
      let labeledArguments = if let testCase {
        testCase.labeledArguments()
      } else {
        ""
      }
      let symbol: Event.Symbol
      let subject: String
      if issue.isKnown {
        symbol = .pass(knownIssueCount: 1)
        subject = "a known issue"
      } else {
        switch issue.severity {
        case .warning:
          symbol = .passWithWarnings
          subject = "a warning"
        case .error:
          symbol = .fail
          subject = "an issue"
        }
      }

      var additionalMessages = [Message]()
      if case let .expectationFailed(expectation) = issue.kind, let differenceDescription = expectation.differenceDescription {
        additionalMessages.append(Message(symbol: .difference, stringValue: differenceDescription))
      }
      additionalMessages += _formattedComments(issue.comments)
      if let knownIssueComment = issue.knownIssueContext?.comment {
        additionalMessages.append(_formattedComment(knownIssueComment))
      }

      if verbosity > 0, case let .expectationFailed(expectation) = issue.kind {
        let expression = expectation.evaluatedExpression
        func addMessage(about expression: __Expression) {
          let description = expression.expandedDebugDescription()
          additionalMessages.append(Message(symbol: .details, stringValue: description))
        }
        let subexpressions = expression.subexpressions
        if subexpressions.isEmpty {
          addMessage(about: expression)
        } else {
          for subexpression in subexpressions {
            addMessage(about: subexpression)
          }
        }
      }

      let atSourceLocation = issue.sourceLocation.map { " at \($0)" } ?? ""
      let primaryMessage: Message = if parameterCount == 0 {
        Message(
          symbol: symbol,
          stringValue: "\(_capitalizedTitle(for: test)) \(testName) recorded \(subject)\(atSourceLocation): \(issue.kind)",
          conciseStringValue: String(describing: issue.kind)
        )
      } else {
        Message(
          symbol: symbol,
          stringValue: "\(_capitalizedTitle(for: test)) \(testName) recorded \(subject) with \(parameterCount.counting("argument")) \(labeledArguments)\(atSourceLocation): \(issue.kind)",
          conciseStringValue: String(describing: issue.kind)
        )
      }
      return CollectionOfOne(primaryMessage) + additionalMessages

    case let .valueAttached(attachment):
      var result = [
        Message(
          symbol: .attachment,
          stringValue: "Attached '\(attachment.preferredName)' to \(testName)."
        )
      ]
      if let path = attachment.fileSystemPath {
        result.append(
          Message(
            symbol: .details,
            stringValue: "Written to '\(path)'."
          )
        )
      }
      return result

    case .testCaseStarted:
      guard let testCase, testCase.isParameterized, let arguments = testCase.arguments else {
        break
      }

      return [
        Message(
          symbol: .default,
          stringValue: "Test case passing \(arguments.count.counting("argument")) \(testCase.labeledArguments(includingQualifiedTypeNames: verbosity > 0)) to \(testName) started."
        )
      ]

    case .testCaseEnded:
      guard verbosity > 0, let test, let testCase, testCase.isParameterized, let arguments = testCase.arguments else {
        break
      }

      let testDataGraph = context.testData.subgraph(at: keyPath)
      let testData = testDataGraph?.value ?? .init(startInstant: instant)
      let issues = _issueCounts(in: testDataGraph)
      let duration = testData.startInstant.descriptionOfDuration(to: instant)

      var cancellationComment = "."
      let (symbol, verbed): (Event.Symbol, String)
      if issues.errorIssueCount > 0 {
        (symbol, verbed) = (.fail, "failed")
      } else if !test.isParameterized, let cancellationInfo = testData.cancellationInfo {
        if let comment = cancellationInfo.comment {
          cancellationComment = ": \"\(comment.rawValue)\""
        }
        (symbol, verbed) = (.skip, "was cancelled")
      } else {
        (symbol, verbed) = (.pass(knownIssueCount: issues.knownIssueCount), "passed")
      }
      return [
        Message(
          symbol: symbol,
          stringValue: "Test case passing \(arguments.count.counting("argument")) \(testCase.labeledArguments(includingQualifiedTypeNames: verbosity > 0)) to \(testName) \(verbed) after \(duration)\(issues.description)\(cancellationComment)"
        )
      ]

    case .testCancelled, .testCaseCancelled:
      // Handled in .testEnded and .testCaseEnded
      break

    case let .iterationEnded(index):
      guard let iterationStartInstant = context.iterationStartInstant else {
        break
      }
      let duration = iterationStartInstant.descriptionOfDuration(to: instant)

      return [
        Message(
          symbol: .default,
          stringValue: "Iteration \(index + 1) ended after \(duration)."
        )
      ]

    case .runEnded:
      let testCount = context.testCount
      let suiteCount = context.suiteCount
      let issues = _issueCounts(in: context.testData)
      let runStartInstant = context.runStartInstant ?? instant
      let duration = runStartInstant.descriptionOfDuration(to: instant)

      return if issues.errorIssueCount > 0 {
        [
          Message(
            symbol: .fail,
            stringValue: "Test run with \(testCount.counting("test")) in \(suiteCount.counting("suite")) failed after \(duration)\(issues.description)."
          )
        ]
      } else {
        [
          Message(
            symbol: .pass(knownIssueCount: issues.knownIssueCount),
            stringValue: "Test run with \(testCount.counting("test")) in \(suiteCount.counting("suite")) passed after \(duration)\(issues.description)."
          )
        ]
      }
    }

    return []
  }
}

extension Test.ID {
  /// The key path in a test data graph representing this test ID.
  fileprivate var keyPath: some Collection<Event.HumanReadableOutputRecorder.Context.TestDataKey> {
    keyPathRepresentation.map { .string($0) }
  }
}

extension Event.Context {
  /// The key path in a test data graph representing this event this context is
  /// associated with, including its test and/or test case IDs.
  fileprivate var keyPath: some Collection<Event.HumanReadableOutputRecorder.Context.TestDataKey> {
    var keyPath = [Event.HumanReadableOutputRecorder.Context.TestDataKey]()

    if let test {
      keyPath.append(contentsOf: test.id.keyPath)

      if let testCase {
        keyPath.append(.testCaseID(testCase.id))
      }
    }

    return keyPath
  }
}

// MARK: - Codable

extension Event.HumanReadableOutputRecorder.Message: Codable {}
