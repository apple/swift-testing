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
  /// them as human-readable strings.
  ///
  /// The format of the output is not meant to be machine-readable and is
  /// subject to change.
  public struct Recorder: Sendable {
    /// An enumeration describing options to use when writing events to a
    /// stream.
    public enum Option: Sendable {
      /// Use [ANSI escape codes](https://en.wikipedia.org/wiki/ANSI_escape_code)
      /// to add color and other effects to the output.
      ///
      /// This option is useful when writing command-line output (for example,
      /// in Terminal.app on macOS.)
      ///
      /// As a general rule, standard output can be assumed to support ANSI
      /// escape codes on POSIX-like operating systems when the `"TERM"`
      /// environment variable is set _and_ `isatty(STDOUT_FILENO)` returns
      /// non-zero.
      ///
      /// On Windows, `GetFileType()` returns `FILE_TYPE_CHAR` for console file
      /// handles, and the [Console API](https://learn.microsoft.com/en-us/windows/console/)
      /// can be used to perform more complex console operations.
      case useANSIEscapeCodes

      /// Whether or not to use 256-color extended
      /// [ANSI escape codes](https://en.wikipedia.org/wiki/ANSI_escape_code) to
      /// add color to the output.
      ///
      /// This option is ignored unless ``useANSIEscapeCodes`` is also
      /// specified.
      case use256ColorANSIEscapeCodes

#if os(macOS) || (os(iOS) && targetEnvironment(macCatalyst))
      /// Use [SF&nbsp;Symbols](https://developer.apple.com/sf-symbols/) in the
      /// output.
      ///
      /// When this option is used, SF&nbsp;Symbols are assumed to be present in
      /// the font used for rendering within the Unicode Private Use Area. If
      /// the SF&nbsp;Symbols app is not installed on the system where the
      /// output is being rendered, the effect of this option is unspecified.
      case useSFSymbols
#endif
    }

    /// The options for this event recorder.
    var options: Set<Option>

    /// The write function for this event recorder.
    var write: @Sendable (String) -> Void

    /// A type that contains mutable context for
    /// ``Event/write(using:options:context:)``.
    fileprivate struct Context {
      /// The instant at which the run started.
      var runStartInstant: Test.Clock.Instant?

      /// The number of tests started or skipped during the run.
      ///
      /// This value does not include test suites.
      var testCount = 0

      /// The number of test suites started or skipped during the run.
      var suiteCount = 0

      /// A type describing data tracked on a per-test basis.
      struct TestData {
        /// The instant at which the test started.
        var startInstant: Test.Clock.Instant = .now

        /// The number of issues recorded for the test.
        var issueCount = 0

        /// The number of known issues recorded for the test.
        var knownIssueCount = 0
      }

      /// Data tracked on a per-test basis.
      var testData = Graph<String, TestData?>()
    }

    /// This event recorder's mutable context about events it has received,
    /// which may be used to inform how subsequent events are written.
    @Locked private var context = Context()

    /// Initialize a new event recorder.
    ///
    /// - Parameters:
    ///   - options: The options this event recorder should use when calling
    ///     `write`. Defaults to the empty array.
    ///   - write: A closure that writes output to its destination. The closure
    ///     may be invoked concurrently.
    ///
    /// Output from the testing library is written using `write`. The format of
    /// the output is not meant to be machine-readable and is subject to change.
    public init(options: [Option] = [], writingUsing write: @escaping @Sendable (String) -> Void) {
      self.options = Set(options)
      self.write = write
    }
  }
}

// MARK: -

/// The ANSI escape code prefix.
private let _ansiEscapeCodePrefix = "\u{001B}["

/// The ANSI escape code to reset text output to default settings.
private let _resetANSIEscapeCode = "\(_ansiEscapeCodePrefix)0m"

extension Event.Recorder {
  /// An enumeration describing the symbols used as prefixes when writing
  /// output.
  private enum _Symbol {
    /// The default symbol to use.
    case `default`

    /// The symbol to use when a test is skipped.
    case skip

    /// The symbol to use when a test passes.
    case pass(hasKnownIssues: Bool = false)

    /// The symbol to use when a test fails.
    case fail

    /// The symbol to use when an expectation includes a difference description.
    case difference

#if os(macOS) || (os(iOS) && targetEnvironment(macCatalyst))
    /// The SF Symbols character corresponding to this instance.
    private var _sfSymbolCharacter: Character {
      switch self {
      case .default:
        // SF Symbol: diamond
        return "\u{1007C8}"
      case .skip:
        // SF Symbol: arrow.triangle.turn.up.right.diamond.fill
        return "\u{10065F}"
      case let .pass(hasKnownIssues):
        if hasKnownIssues {
          // SF Symbol: xmark.diamond.fill
          return "\u{100884}"
        } else {
          // SF Symbol: checkmark.diamond.fill
          return "\u{10105B}"
        }
      case .fail:
        // SF Symbol: xmark.diamond.fill
        return "\u{100884}"
      case .difference:
        // SF Symbol: plus.forwardslash.minus
        return "\u{10017A}"
      }
    }
#endif

    /// The Unicode character corresponding to this instance.
    private var _unicodeCharacter: Character {
#if SWT_TARGET_OS_APPLE || os(Linux)
      switch self {
      case .default:
        // Unicode: WHITE DIAMOND
        return "\u{25C7}"
      case .skip:
        // Unicode: HEAVY BALLOT X
        return "\u{2718}"
      case let .pass(hasKnownIssues):
        if hasKnownIssues {
          // Unicode: HEAVY BALLOT X
          return "\u{2718}"
        } else {
          // Unicode: HEAVY CHECK MARK
          return "\u{2714}"
        }
      case .fail:
        // Unicode: HEAVY BALLOT X
        return "\u{2718}"
      case .difference:
        // Unicode: PLUS-MINUS SIGN
        return "\u{00B1}"
      }
#elseif os(Windows)
      // The default Windows console font (Consolas) has limited Unicode
      // support, so substitute some other characters that it does have.
      switch self {
      case .default:
        // Unicode: LOZENGE
        return "\u{25CA}"
      case .skip:
        // Unicode: MULTIPLICATION SIGN
        return "\u{00D7}"
      case let .pass(hasKnownIssues):
        if hasKnownIssues {
          // Unicode: MULTIPLICATION SIGN
          return "\u{00D7}"
        } else {
          // Unicode: SQUARE ROOT
          return "\u{221A}"
        }
      case .fail:
        // Unicode: MULTIPLICATION SIGN
        return "\u{00D7}"
      case .difference:
        // Unicode: PLUS-MINUS SIGN
        return "\u{00B1}"
      }
#else
#warning("Platform-specific implementation missing: Unicode characters unavailable")
      return " "
#endif
    }

    /// Get the string value for this symbol with the given write options.
    ///
    /// - Parameters:
    ///   - options: Options to use when writing this symbol.
    ///
    /// - Returns: A string representation of `self` appropriate for writing to
    ///   a stream.
    func stringValue(options: Set<Event.Recorder.Option>) -> String {
      var symbolCharacter = String(_unicodeCharacter)
#if os(macOS) || (os(iOS) && targetEnvironment(macCatalyst))
      if options.contains(.useSFSymbols) {
        symbolCharacter = String(_sfSymbolCharacter)
        if options.contains(.useANSIEscapeCodes) {
          symbolCharacter += " "
        }
      }
#endif

      if options.contains(.useANSIEscapeCodes) {
        switch self {
        case .default, .skip, .difference:
          return "\(_ansiEscapeCodePrefix)90m\(symbolCharacter)\(_resetANSIEscapeCode)"
        case let .pass(hasKnownIssues):
          if hasKnownIssues {
            return "\(_ansiEscapeCodePrefix)90m\(symbolCharacter)\(_resetANSIEscapeCode)"
          }
          return "\(_ansiEscapeCodePrefix)92m\(symbolCharacter)\(_resetANSIEscapeCode)"
        case .fail:
          return "\(_ansiEscapeCodePrefix)91m\(symbolCharacter)\(_resetANSIEscapeCode)"
        }
      }
      return "\(symbolCharacter)"
    }
  }

  /// Get a string representing an array of comments, formatted for output.
  ///
  /// - Parameters:
  ///   - comments: The comments that should be formatted.
  ///   - options: Options to use when writing the comments.
  ///
  /// - Returns: A formatted string representing `comments`, or `nil` if there
  ///   are none.
  private func _formattedComments(_ comments: [Comment], options: Set<Event.Recorder.Option>) -> String? {
    if comments.isEmpty {
      return nil
    }

    // Insert an arrow character at the start of each comment, then indent any
    // additional lines in the comment to align them with the arrow.
    var arrowCharacter = "\u{21B3}" // DOWNWARDS ARROW WITH TIP RIGHTWARDS
#if os(macOS) || (os(iOS) && targetEnvironment(macCatalyst))
    if options.contains(.useSFSymbols) {
      arrowCharacter = "\u{100135}" // arrow.turn.down.right
      if options.contains(.useANSIEscapeCodes) {
        arrowCharacter += " "
      }
    }
#endif
    let comments = comments.lazy
      .flatMap { comment in
        let lines = comment.rawValue.split(whereSeparator: \.isNewline)
        if let firstLine = lines.first {
          let remainingLines = lines.dropFirst()
          return CollectionOfOne("\(arrowCharacter) \(firstLine)") + remainingLines.map { "  \($0)" }
        }
        return []
      }.joined(separator: "\n")

    // If ANSI escape codes are enabled, dim the comments relative to the
    // primary test output.
    if options.contains(.useANSIEscapeCodes) {
      return "\(_ansiEscapeCodePrefix)90m\(comments)\(_resetANSIEscapeCode)"
    }

    return comments
  }

  /// Get a string representing the comments attached to a test, formatted for
  /// output.
  ///
  /// - Parameters:
  ///   - test: The test whose comments should be formatted.
  ///   - options: Options to use when writing the comments.
  ///
  /// - Returns: A formatted string representing the comments attached to `test`,
  ///   or `nil` if there are none.
  private func _formattedComments(for test: Test, options: Set<Event.Recorder.Option>) -> String? {
    _formattedComments(test.comments(from: Comment.self), options: options)
  }

  /// Get the total number of issues recorded in a graph of test data
  /// structures.
  ///
  /// - Parameters:
  ///   - graph: The graph to walk while counting issues.
  ///
  /// - Returns: A tuple containing the number of issues recorded in `graph`.
  private func _issueCounts(in graph: Graph<String, Event.Recorder.Context.TestData?>?) -> (issueCount: Int, knownIssueCount: Int, totalIssueCount: Int, description: String) {
    guard let graph else {
      return (0, 0, 0, "")
    }
    let issueCount = graph.compactMap(\.value?.issueCount).reduce(into: 0, +=)
    let knownIssueCount = graph.compactMap(\.value?.knownIssueCount).reduce(into: 0, +=)
    let totalIssueCount = issueCount + knownIssueCount

    // Construct a string describing the issue counts.
    let description = switch (issueCount > 0, knownIssueCount > 0) {
    case (true, true):
      " with \(totalIssueCount.counting("issue")) (including \(knownIssueCount.counting("known issue")))"
    case (false, true):
      " with \(knownIssueCount.counting("known issue"))"
    case (true, false):
      " with \(totalIssueCount.counting("issue"))"
    case(false, false):
      ""
    }

    return (issueCount, knownIssueCount, totalIssueCount,  description)
  }
}

// MARK: -

extension Difference {
  /// Get a description of this instance with the given recorder options.
  ///
  /// - Parameters:
  ///   - options: Options to use when writing the comments.
  ///
  /// - Returns: A formatted description of `self`.
  fileprivate func formattedDescription(options: Set<Event.Recorder.Option>) -> String {
    guard options.contains(.useANSIEscapeCodes) else {
      return String(describing: self)
    }

    return String(describing: self)
      .split(whereSeparator: \.isNewline)
      .map { line in
        switch line.first {
        case "+":
          "\(_ansiEscapeCodePrefix)32m\(line)\(_resetANSIEscapeCode)"
        case "-":
          "\(_ansiEscapeCodePrefix)31m\(line)\(_resetANSIEscapeCode)"
        default:
          String(line)
        }
      }.joined(separator: "\n")
  }
}

// MARK: -

extension Tag {
  /// Get an ANSI escape code that sets the foreground text color to this tag's
  /// corresponding color, if applicable.
  ///
  /// - Parameters:
  ///   - options: Options to use when writing this tag.
  ///
  /// - Returns: The corresponding ANSI escape code, or `nil` if `self` does not
  ///    represent a color.
  fileprivate func ansiEscapeCode(options: Set<Event.Recorder.Option>) -> String? {
    switch self {
    case .red:
      return "\(_ansiEscapeCodePrefix)91m"
    case .orange:
      if options.contains(.use256ColorANSIEscapeCodes) {
        return "\(_ansiEscapeCodePrefix)38;5;208m"
      }
      return "\(_ansiEscapeCodePrefix)33m"
    case .yellow:
      return "\(_ansiEscapeCodePrefix)93m"
    case .green:
      return "\(_ansiEscapeCodePrefix)92m"
    case .blue:
      return "\(_ansiEscapeCodePrefix)94m"
    case .purple:
      if options.contains(.use256ColorANSIEscapeCodes) {
        return "\(_ansiEscapeCodePrefix)38;5;128m"
      }
      return "\(_ansiEscapeCodePrefix)95m"
    default:
      return nil
    }
  }
}

extension Test.Case {
  /// The arguments of this test case, formatted for presentation, prefixed by
  /// their corresponding parameter label when available.
  ///
  /// - Parameters:
  ///   - parameters: The parameters to pair this test case's arguments with.
  ///
  /// - Returns: A string containing each argument prefixed with its
  ///   corresponding parameter label when available.
  fileprivate func labeledArguments(using parameters: [Test.ParameterInfo]) -> String {
    arguments(pairedWith: parameters).lazy
      .map { parameter, argument in
        let argumentDescription = String(describingForTest: argument)

        let label = parameter.secondName ?? parameter.firstName
        guard label != "_" else {
          return argumentDescription
        }
        return "\(label) → \(argumentDescription)"
      }
      .joined(separator: ", ")
  }
}

// MARK: -

extension Event.Recorder {
  /// Record the specified event by generating a representation of it as a
  /// human-readable string.
  ///
  /// - Parameters:
  ///   - event: The event to record.
  ///   - eventContext: The context associated with the event.
  ///
  /// - Returns: A string description of the event, or `nil` if there is nothing
  ///   useful to output for this event.
  func _record(_ event: borrowing Event, in eventContext: borrowing Event.Context) -> String? {
    let test = eventContext.test
    var testName: String
    if let displayName = test?.displayName {
      testName = "\"\(displayName)\""
    } else if let test {
      testName = test.name
    } else {
      testName = "«unknown»"
    }
    if options.contains(.useANSIEscapeCodes), let tags = test?.tags {
      let colorDots = tags
        .sorted(by: <)
        .compactMap { $0.ansiEscapeCode(options: options) }
        .map { "\($0)\u{25CF}" } // Unicode: BLACK CIRCLE
        .joined()
      if !colorDots.isEmpty {
        testName = "\(colorDots)\(_resetANSIEscapeCode) \(testName)"
      }
    }
    let instant = event.instant

    switch event.kind {
    case .runStarted:
      $context.withLock { context in
        context.runStartInstant = instant
      }
      let symbol = _Symbol.default.stringValue(options: options)
      var comments: [Comment] = [
        "Swift Version: \(swiftStandardLibraryVersion)",
        "Testing Library Version: \(testingLibraryVersion)",
      ]
#if targetEnvironment(simulator)
      comments.append("OS Version (Simulator): \(simulatorVersion)")
      comments.append("OS Version (Host): \(operatingSystemVersion)")
#else
      comments.append("OS Version: \(operatingSystemVersion)")
#endif
      if let comments = _formattedComments(comments, options: options) {
        return "\(symbol) Test run started.\n\(comments)\n"
      } else {
        return "\(symbol) Test run started.\n"
      }

    case .planStepStarted, .planStepEnded:
      // Suppress events of these kinds from output as they are not generally
      // interesting in human-readable output.
      break

    case .testStarted:
      let test = test!
      $context.withLock { context in
        context.testData.insertValue(.init(), at: test.id.keyPathRepresentation)
        if test.isSuite {
          context.suiteCount += 1
        } else {
          context.testCount += 1
        }
      }
      let symbol = _Symbol.default.stringValue(options: options)
      return "\(symbol) Test \(testName) started.\n"

    case .testEnded:
      let test = test!
      let id = test.id
      let testDataGraph = context.testData.subgraph(at: id.keyPathRepresentation)
      let testData = testDataGraph?.value ?? .init()
      let issues = _issueCounts(in: testDataGraph)
      let duration = testData.startInstant.descriptionOfDuration(to: instant)
      if issues.issueCount > 0 {
        let symbol = _Symbol.fail.stringValue(options: options)
        let comments = _formattedComments(for: test, options: options).map { "\($0)\n" } ?? ""
        return "\(symbol) Test \(testName) failed after \(duration)\(issues.description).\n\(comments)"
      } else {
        let symbol = _Symbol.pass(hasKnownIssues: issues.knownIssueCount > 0).stringValue(options: options)
        return "\(symbol) Test \(testName) passed after \(duration)\(issues.description).\n"
      }

    case let .testSkipped(skipInfo):
      let test = test!
      $context.withLock { context in
        if test.isSuite {
          context.suiteCount += 1
        } else {
          context.testCount += 1
        }
      }
      let symbol = _Symbol.skip.stringValue(options: options)
      if let comment = skipInfo.comment {
        return "\(symbol) Test \(testName) skipped: \"\(comment.rawValue)\"\n"
      } else {
        return "\(symbol) Test \(testName) skipped.\n"
      }

#if !SWIFT_PACKAGE
    case .testBypassed:
      // Deprecated, replaced by `.testSkipped` above.
      break
#endif

    case .expectationChecked:
      // Suppress events of this kind from output as they are not generally
      // interesting in human-readable output.
      break

    case let .issueRecorded(issue):
      if let test {
        let id = test.id.keyPathRepresentation
        $context.withLock { context in
          var testData = context.testData[id].flatMap { $0 } ?? .init()
          if issue.isKnown {
            testData.knownIssueCount += 1
          } else {
            testData.issueCount += 1
          }
          context.testData.insertValue(testData, at: id)
        }
      }
      let parameterCount = if let parameters = test?.parameters {
        parameters.count
      } else {
        0
      }
      let labeledArguments = if let testCase = eventContext.testCase, let parameters = test?.parameters {
        testCase.labeledArguments(using: parameters)
      } else {
        ""
      }
      let symbol: String
      let known: String
      if issue.isKnown {
        symbol = _Symbol.pass(hasKnownIssues: true).stringValue(options: options)
        known = " known"
      } else {
        symbol = _Symbol.fail.stringValue(options: options)
        known = "n"
      }

      var difference = ""
      if case let .expectationFailed(expectation) = issue.kind, let differenceValue = expectation.difference {
        let differenceSymbol = _Symbol.difference.stringValue(options: options)
        difference = "\n\(differenceSymbol) \(differenceValue.formattedDescription(options: options))"
      }

      var issueComments = ""
      if let formattedComments = _formattedComments(issue.comments, options: options) {
        issueComments = "\n\(formattedComments)"
      }

      let atSourceLocation = issue.sourceLocation.map { " at \($0)" } ?? ""
      if parameterCount == 0 {
        return "\(symbol) Test \(testName) recorded a\(known) issue\(atSourceLocation): \(issue.kind)\(difference)\(issueComments)\n"
      } else {
        return "\(symbol) Test \(testName) recorded a\(known) issue with \(parameterCount.counting("argument")) \(labeledArguments)\(atSourceLocation): \(issue.kind)\(difference)\(issueComments)\n"
      }

    case .testCaseStarted:
      guard let testCase = eventContext.testCase, testCase.isParameterized, let parameters = test?.parameters else {
        break
      }
      let symbol = _Symbol.default.stringValue(options: options)

      return "\(symbol) Passing \(parameters.count.counting("argument")) \(testCase.labeledArguments(using: parameters)) to \(testName)\n"

    case .testCaseEnded:
      break

    case .runEnded:
      let context = $context.wrappedValue

      let testCount = context.testCount
      let issues = _issueCounts(in: context.testData)
      let runStartInstant = context.runStartInstant ?? instant
      let duration = runStartInstant.descriptionOfDuration(to: instant)

      if issues.issueCount > 0 {
        let symbol = _Symbol.fail.stringValue(options: options)
        return "\(symbol) Test run with \(testCount.counting("test")) failed after \(duration)\(issues.description).\n"
      } else {
        let symbol = _Symbol.pass(hasKnownIssues: issues.knownIssueCount > 0).stringValue(options: options)
        return "\(symbol) Test run with \(testCount.counting("test")) passed after \(duration)\(issues.description).\n"
      }
    }

    return nil
  }

  /// Record the specified event by generating a representation of it as a
  /// human-readable string and writing it using this instance's write function.
  ///
  /// - Parameters:
  ///   - event: The event to record.
  ///   - context: The context associated with the event.
  ///
  /// - Returns: Whether any output was written using the recorder's write
  ///   function.
  @discardableResult public func record(_ event: borrowing Event, in context: borrowing Event.Context) -> Bool {
    if let output = _record(event, in: context) {
      write(output)
      return true
    }
    return false
  }
}
