//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

/// A type describing a failure or warning which occurred during a test.
public struct Issue: Sendable {
  /// Kinds of issues which may be recorded.
  public enum Kind: Sendable {
    /// An issue which occurred unconditionally, for example by using
    /// ``Issue/record(_:severity:sourceLocation:)``.
    case unconditional

    /// An issue due to a failed expectation, such as those produced by
    /// ``expect(_:_:sourceLocation:)``.
    ///
    /// - Parameters:
    ///   - expectation: The expectation that failed.
    indirect case expectationFailed(_ expectation: Expectation)

    /// An issue due to a confirmation being confirmed the wrong number of
    /// times.
    ///
    /// - Parameters:
    ///   - actual: The number of times ``Confirmation/confirm(count:)`` was
    ///     actually called.
    ///   - expected: The expected number of times
    ///     ``Confirmation/confirm(count:)`` should have been called.
    ///
    /// This issue can occur when calling ``confirmation(_:expectedCount:isolation:sourceLocation:_:)-5mqz2``
    /// or ``confirmation(_:expectedCount:isolation:sourceLocation:_:)-l3il``
    /// when the confirmation passed to these functions' `body` closures is
    /// confirmed too few or too many times.
    indirect case confirmationMiscounted(actual: Int, expected: any RangeExpression & Sendable)

    /// An issue due to a polling confirmation having failed.
    ///
    /// This issue can occur when calling ``confirmation(_:until:within:pollingEvery:isolation:sourceLocation:_:)-455gr``
    /// or
    /// ``confirmation(_:until:within:pollingEvery:isolation:sourceLocation:_:)-5tnlk``
    /// whenever the polling fails, as described in ``PollingStopCondition``.
    @_spi(Experimental)
    case pollingConfirmationFailed

    /// An issue due to an `Error` being thrown by a test function and caught by
    /// the testing library.
    ///
    /// - Parameters:
    ///   - error: The error which was associated with this issue.
    indirect case errorCaught(_ error: any Error)

    /// An issue due to a test reaching its time limit and timing out.
    ///
    /// - Parameters:
    ///   - timeLimitComponents: The time limit reached by the test.
    ///
    /// @Comment {
    ///   - Bug: The associated value of this enumeration case should be an
    ///     instance of `Duration`, but the testing library's deployment target
    ///     predates the introduction of that type.
    /// }
    indirect case timeLimitExceeded(timeLimitComponents: (seconds: Int64, attoseconds: Int64))

    /// A known issue was expected, but was not recorded.
    case knownIssueNotRecorded

    /// An issue due to an `Error` being thrown while attempting to save an
    /// attachment to a test report or to disk.
    ///
    /// - Parameters:
    ///   - error: The error which was associated with this issue.
    case valueAttachmentFailed(_ error: any Error)

    /// An issue occurred due to misuse of the testing library.
    case apiMisused

    /// An issue due to a failure in the underlying system, not due to a failure
    /// within the tests being run.
    case system
  }

  /// The kind of issue this value represents.
  public var kind: Kind

  /// An enumeration representing the level of severity of a recorded issue.
  ///
  /// The supported levels, in increasing order of severity, are:
  ///
  /// - ``warning``
  /// - ``error``
  ///
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.3)
  /// }
  public enum Severity: Sendable {
    /// The severity level for an issue which should be noted but is not
    /// necessarily an error.
    ///
    /// An issue with warning severity does not cause the test it's associated
    /// with to be marked as a failure, but is noted in the results.
    ///
    /// @Metadata {
    ///   @Available(Swift, introduced: 6.3)
    /// }
    case warning

    /// The severity level for an issue which represents an error in a test.
    ///
    /// An issue with error severity causes the test it's associated with to be
    /// marked as a failure.
    ///
    /// @Metadata {
    ///   @Available(Swift, introduced: 6.3)
    /// }
    case error
  }

  /// The severity of this issue.
  ///
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.3)
  /// }
  public var severity: Severity
  
  /// Whether or not this issue should cause the test it's associated with to be
  /// considered a failure.
  ///
  /// The value of this property is `true` for issues which have a severity level of
  /// ``Issue/Severity/error`` or greater and are not known issues via
  /// ``withKnownIssue(_:isIntermittent:sourceLocation:_:when:matching:)``.
  /// Otherwise, the value of this property is `false.`
  ///
  /// Use this property to determine if an issue should be considered a failure, instead of
  /// directly comparing the value of the ``severity`` property.
  ///
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.3)
  /// }
  public var isFailure: Bool {
    return !self.isKnown && self.severity >= .error
  }

  /// Any comments provided by the developer and associated with this issue.
  ///
  /// If no comment was supplied when the issue occurred, the value of this
  /// property is the empty array.
  public var comments: [Comment]

  /// A ``SourceContext`` indicating where and how this issue occurred.
  @_spi(ForToolsIntegrationOnly)
  public var sourceContext: SourceContext

  /// A type representing a
  /// ``withKnownIssue(_:isIntermittent:sourceLocation:_:when:matching:)`` call
  /// that matched an issue.
  @_spi(ForToolsIntegrationOnly)
  public struct KnownIssueContext: Sendable {
    /// The comment that was passed to
    /// ``withKnownIssue(_:isIntermittent:sourceLocation:_:when:matching:)``.
    public var comment: Comment?
  }

  /// A ``KnownIssueContext-swift.struct`` representing the
  /// ``withKnownIssue(_:isIntermittent:sourceLocation:_:when:matching:)`` call
  /// that matched this issue, if any.
  @_spi(ForToolsIntegrationOnly)
  public var knownIssueContext: KnownIssueContext? = nil

  /// Whether or not this issue is known to occur.
  @_spi(ForToolsIntegrationOnly)
  public var isKnown: Bool {
    get { knownIssueContext != nil }
    @available(*, deprecated, message: "Setting this property has no effect.")
    set {}
  }

  /// Initialize an issue instance with the specified details.
  ///
  /// - Parameters:
  ///   - kind: The kind of issue this value represents.
  ///   - severity: The severity of this issue. The default value is
  ///     ``Severity-swift.enum/error``.
  ///   - comments: An array of comments describing the issue. This array may be
  ///     empty.
  ///   - sourceContext: A ``SourceContext`` indicating where and how this issue
  ///     occurred.
  init(
    kind: Kind,
    severity: Severity = .error,
    comments: [Comment],
    sourceContext: SourceContext
  ) {
    self.kind = kind
    self.severity = severity
    self.comments = comments
    self.sourceContext = sourceContext
  }

  /// Initialize an issue instance representing a caught error.
  ///
  /// - Parameters:
  ///   - error: The error which was caught which this issue is describing.
  ///   - sourceLocation: The source location of the issue. This value is used
  ///     to construct an instance of ``SourceContext``.
  ///
  /// The ``sourceContext`` property will have a ``SourceContext/backtrace``
  /// property whose value is the backtrace for the first throw of `error`.
  init(
    for error: any Error,
    sourceLocation: SourceLocation? = nil
  ) {
    let sourceContext = SourceContext(backtrace: Backtrace(forFirstThrowOf: error), sourceLocation: sourceLocation)
    self.init(
      kind: .errorCaught(error),
      comments: [],
      sourceContext: sourceContext
    )
  }

  /// The error which was associated with this issue, if any.
  ///
  /// The value of this property is non-`nil` when ``kind-swift.property`` is
  /// ``Kind-swift.enum/errorCaught(_:)``.
  public var error: (any Error)? {
    if case let .errorCaught(error) = kind {
      return error
    }
    return nil
  }

  /// The location in source where this issue occurred, if available.
  public var sourceLocation: SourceLocation? {
    get {
      sourceContext.sourceLocation
    }
    set {
      sourceContext.sourceLocation = newValue
    }
  }
}

extension Issue.Severity: Comparable {}

// MARK: - CustomStringConvertible, CustomDebugStringConvertible

extension Issue: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String {
    let joinedComments = if comments.isEmpty {
      ""
    } else {
      ": " + comments.lazy
        .map(\.rawValue)
        .joined(separator: "\n")
    }
    return "\(kind) (\(severity))\(joinedComments)"
  }

  public var debugDescription: String {
    let joinedComments = if comments.isEmpty {
      ""
    } else {
      ": " + comments.lazy
        .map(\.rawValue)
        .joined(separator: "\n")
    }
    return "\(kind)\(sourceLocation.map { " at \($0)" } ?? "") (\(severity))\(joinedComments)"
  }
}

/// An empty protocol defining a type that conforms to `RangeExpression<Int>`.
///
/// In the future, when our minimum deployment target supports casting a value
/// to a constrained existential type ([SE-0353](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0353-constrained-existential-types.md#effect-on-abi-stability)),
/// we can remove this protocol and cast to `RangeExpression<Int>` instead.
private protocol _RangeExpressionOverIntValues: RangeExpression & Sequence where Bound == Int, Element == Int {}
extension ClosedRange<Int>: _RangeExpressionOverIntValues {}
extension PartialRangeFrom<Int>: _RangeExpressionOverIntValues {}
extension Range<Int>: _RangeExpressionOverIntValues {}

extension Issue.Kind: CustomStringConvertible {
  public var description: String {
    switch self {
    case .unconditional:
      // Although the failure is unconditional at the point it is recorded, the
      // code that recorded the issue may not be unconditionally executing, so
      // we shouldn't describe it as unconditional (we just don't know!)
      return "Issue recorded"
    case let .expectationFailed(expectation):
      return if let mismatchedErrorDescription = expectation.mismatchedErrorDescription {
        "Expectation failed: \(mismatchedErrorDescription)"
      } else if let mismatchedExitConditionDescription = expectation.mismatchedExitConditionDescription {
        "Expectation failed: \(mismatchedExitConditionDescription)"
      } else {
        "Expectation failed: \(expectation.evaluatedExpression.expandedDescription())"
      }
    case let .confirmationMiscounted(actual: actual, expected: expected):
      if let expected = expected as? any _RangeExpressionOverIntValues {
        let lowerBound = expected.first { _ in true }
        if let lowerBound {
          // Not actually an upper bound, just "any value greater than the lower
          // bound." That's sufficient for us to determine if the range contains
          // a single value.
          let upperBound = expected.first { $0 > lowerBound }
          if upperBound == nil {
            return "Confirmation was confirmed \(actual.counting("time")), but expected to be confirmed \(lowerBound.counting("time"))"
          }
        }
      }
      return "Confirmation was confirmed \(actual.counting("time")), but expected to be confirmed \(String(describingForTest: expected)) time(s)"
    case .pollingConfirmationFailed:
      return "Polling confirmation failed"
    case let .errorCaught(error):
      return "Caught error: \(error)"
    case let .timeLimitExceeded(timeLimitComponents: timeLimitComponents):
      return "Time limit was exceeded: \(TimeValue(timeLimitComponents))"
    case .knownIssueNotRecorded:
      return "Known issue was not recorded"
    case let .valueAttachmentFailed(error):
      return "Caught error while saving attachment: \(error)"
    case .apiMisused:
      return "An API was misused"
    case .system:
      return "A system failure occurred"
    }
  }
}

extension Issue.Severity: CustomStringConvertible {
  public var description: String {
    switch self {
    case .warning:
      "warning"
    case .error:
      "error"
    }
  }
}

#if !SWT_NO_SNAPSHOT_TYPES
// MARK: - Snapshotting

extension Issue {
  /// A serializable type describing a failure or warning which occurred during a test.
  @_spi(ForToolsIntegrationOnly)
  public struct Snapshot: Sendable, Codable {
    /// The kind of issue this value represents.
    public var kind: Kind.Snapshot

    /// The severity of this issue.
    /// 
    /// @Metadata {
    ///   @Available(Swift, introduced: 6.3)
    /// }
    public var severity: Severity

    /// Any comments provided by the developer and associated with this issue.
    ///
    /// If no comment was supplied when the issue occurred, the value of this
    /// property is the empty array.
    public var comments: [Comment]

    /// A ``SourceContext`` indicating where and how this issue occurred.
    public var sourceContext: SourceContext

    /// Whether or not this issue is known to occur.
    public var isKnown: Bool = false

    /// Initialize an issue instance with the specified details.
    ///
    /// - Parameter issue: The original issue that gets snapshotted.
    public init(snapshotting issue: borrowing Issue) {
      if case .confirmationMiscounted = issue.kind {
        // Work around poor stringification of this issue kind in Xcode 16.
        self.kind = .unconditional
        self.comments = CollectionOfOne("\(issue.kind)") + issue.comments
      } else {
        self.kind = Issue.Kind.Snapshot(snapshotting: issue.kind)
        self.comments = issue.comments
      }
      self.severity = issue.severity
      self.sourceContext = issue.sourceContext
      self.isKnown = issue.isKnown
    }

    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      self.kind = try container.decode(Issue.Kind.Snapshot.self, forKey: .kind)
      self.comments = try container.decode([Comment].self, forKey: .comments)
      self.sourceContext = try container.decode(SourceContext.self, forKey: .sourceContext)
      self.isKnown = try container.decode(Bool.self, forKey: .isKnown)

      // Severity is a new field, so fall back to .error if it's not present.
      self.severity = try container.decodeIfPresent(Issue.Severity.self, forKey: .severity) ?? .error
    }

    /// The error which was associated with this issue, if any.
    ///
    /// The value of this property is non-`nil` when ``kind-swift.property`` is
    /// ``Kind-swift.enum/errorCaught(_:)``.
    public var error: (any Error)? {
      if case let .errorCaught(error) = kind {
        return error
      }
      return nil
    }

    /// The location in source where this issue occurred, if available.
    public var sourceLocation: SourceLocation? {
      get {
        sourceContext.sourceLocation
      }
      set {
        sourceContext.sourceLocation = newValue
      }
    }
  }
}

extension Issue.Severity: Codable {}

extension Issue.Kind {
  /// Serializable kinds of issues which may be recorded.
  @_spi(ForToolsIntegrationOnly)
  public enum Snapshot: Sendable, Codable {
    /// An issue which occurred unconditionally, for example by using
    /// ``Issue/record(_:severity:sourceLocation:)``.
    case unconditional

    /// An issue due to a failed expectation, such as those produced by
    /// ``expect(_:_:sourceLocation:)``.
    ///
    /// - Parameters:
    ///   - expectation: The expectation that failed.
    indirect case expectationFailed(_ expectation: Expectation.Snapshot)

    /// An issue due to a confirmation being confirmed the wrong number of
    /// times.
    ///
    /// - Parameters:
    ///   - actual: The number of times ``Confirmation/confirm(count:)`` was
    ///     actually called.
    ///   - expected: The expected number of times
    ///     ``Confirmation/confirm(count:)`` should have been called.
    ///
    /// This issue can occur when calling
    /// ``confirmation(_:expectedCount:isolation:sourceLocation:_:)-5mqz2`` when
    /// the confirmation passed to these functions' `body` closures is confirmed
    /// too few or too many times.
    indirect case confirmationMiscounted(actual: Int, expected: Int)

    /// An issue due to a polling confirmation having failed.
    ///
    /// This issue can occur when calling ``confirmation(_:until:within:pollingEvery:isolation:sourceLocation:_:)-455gr``
    /// or
    /// ``confirmation(_:until:within:pollingEvery:isolation:sourceLocation:_:)-5tnlk``
    /// whenever the polling fails, as described in ``PollingStopCondition``.
    @_spi(Experimental)
    case pollingConfirmationFailed

    /// An issue due to an `Error` being thrown by a test function and caught by
    /// the testing library.
    ///
    /// - Parameters:
    ///   - error: A snapshot of the underlying error which was associated with
    ///     this issue.
    indirect case errorCaught(_ error: ErrorSnapshot)

    /// An issue due to a test reaching its time limit and timing out.
    ///
    /// - Parameters:
    ///   - timeLimitComponents: The time limit reached by the test.
    ///
    /// @Comment {
    ///   - Bug: The associated value of this enumeration case should be an
    ///     instance of `Duration`, but the testing library's deployment target
    ///     predates the introduction of that type.
    /// }
    indirect case timeLimitExceeded(timeLimitComponents: (seconds: Int64, attoseconds: Int64))

    /// A known issue was expected, but was not recorded.
    case knownIssueNotRecorded

    /// An issue occurred due to misuse of the testing library.
    case apiMisused

    /// An issue due to a failure in the underlying system, not due to a failure
    /// within the tests being run.
    case system

    /// Initialize an instance of this type by snapshotting the specified issue
    /// kind.
    ///
    /// - Parameters:
    ///   - kind: The original issue kind to snapshot.
    public init(snapshotting kind: Issue.Kind) {
      self = switch kind {
      case .unconditional:
          .unconditional
      case let .expectationFailed(expectation):
          .expectationFailed(Expectation.Snapshot(snapshotting: expectation))
      case .confirmationMiscounted:
          .unconditional
      case .pollingConfirmationFailed:
          .pollingConfirmationFailed
      case let .errorCaught(error), let .valueAttachmentFailed(error):
          .errorCaught(ErrorSnapshot(snapshotting: error))
      case let .timeLimitExceeded(timeLimitComponents: timeLimitComponents):
          .timeLimitExceeded(timeLimitComponents: timeLimitComponents)
      case .knownIssueNotRecorded:
          .knownIssueNotRecorded
      case .apiMisused:
          .apiMisused
      case .system:
          .system
      }
    }

    /// The keys used to encode ``Issue.Kind``.
    private enum _CodingKeys: CodingKey {
      case unconditional
      case expectationFailed
      case confirmationMiscounted
      case pollingConfirmationFailed
      case errorCaught
      case timeLimitExceeded
      case knownIssueNotRecorded
      case apiMisused
      case system

      /// The keys used to encode ``Issue.Kind.expectationFailed``.
      enum _ExpectationFailedKeys: CodingKey {
        case expectation
      }

      /// The keys used to encode ``Issue.Kind.confirmationMiscount``.
      enum _ConfirmationMiscountedKeys: CodingKey {
        case actual
        case expected
      }

      /// The keys used to encode``Issue.Kind.errorCaught``.
      enum _ErrorCaughtKeys: CodingKey {
        case error
      }
    }

    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: _CodingKeys.self)
      if try container.decodeIfPresent(Bool.self, forKey: .unconditional) != nil {
        self = .unconditional
      } else if let expectationFailedContainer = try? container.nestedContainer(keyedBy: _CodingKeys._ExpectationFailedKeys.self,
                                                                                forKey: .expectationFailed) {
        self = .expectationFailed(try expectationFailedContainer.decode(Expectation.Snapshot.self, forKey: .expectation))
      } else if let confirmationMiscountedContainer = try? container.nestedContainer(keyedBy: _CodingKeys._ConfirmationMiscountedKeys.self,
                                                                                     forKey: .confirmationMiscounted) {
        self = .confirmationMiscounted(actual: try confirmationMiscountedContainer.decode(Int.self,
                                                                                          forKey: .actual),
                                       expected: try confirmationMiscountedContainer.decode(Int.self,
                                                                                            forKey: .expected))
      } else if let errorCaught = try? container.nestedContainer(keyedBy: _CodingKeys._ErrorCaughtKeys.self,
                                                                 forKey: .errorCaught) {
        self = .errorCaught(try errorCaught.decode(ErrorSnapshot.self, forKey: .error))
      } else if let timeLimit = try container.decodeIfPresent(TimeValue.self, forKey: .timeLimitExceeded) {
        self = .timeLimitExceeded(timeLimitComponents: timeLimit.components)
      } else if try container.decodeIfPresent(Bool.self, forKey: .knownIssueNotRecorded) != nil {
        self = .knownIssueNotRecorded
      } else if try container.decodeIfPresent(Bool.self, forKey: .apiMisused) != nil {
        self = .apiMisused
      } else if try container.decodeIfPresent(Bool.self, forKey: .system) != nil {
        self = .system
      } else {
        throw DecodingError.valueNotFound(
          Self.self,
          DecodingError.Context(
            codingPath: decoder.codingPath,
            debugDescription: "Value found did not match any of the existing cases for Issue.Kind."
          )
        )
      }
    }

    public func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: _CodingKeys.self)
      switch self {
      case .unconditional:
        try container.encode(true, forKey: .unconditional)
      case let .expectationFailed(expectation):
        var errorCaughtContainer = container.nestedContainer(keyedBy: _CodingKeys._ExpectationFailedKeys.self,
                                                             forKey: .expectationFailed)
        try errorCaughtContainer.encode(expectation, forKey: .expectation)
      case let .confirmationMiscounted(actual, expected):
        var confirmationMiscountedContainer = container.nestedContainer(keyedBy: _CodingKeys._ConfirmationMiscountedKeys.self,
                                                                        forKey: .confirmationMiscounted)
        try confirmationMiscountedContainer.encode(actual, forKey: .actual)
        try confirmationMiscountedContainer.encode(expected, forKey: .expected)
      case .pollingConfirmationFailed:
        try container.encode(true, forKey: .pollingConfirmationFailed)
      case let .errorCaught(error):
        var errorCaughtContainer = container.nestedContainer(keyedBy: _CodingKeys._ErrorCaughtKeys.self, forKey: .errorCaught)
        try errorCaughtContainer.encode(error, forKey: .error)
      case let .timeLimitExceeded(timeLimitComponents):
        try container.encode(TimeValue(timeLimitComponents), forKey: .timeLimitExceeded)
      case .knownIssueNotRecorded:
        try container.encode(true, forKey: .knownIssueNotRecorded)
      case .apiMisused:
        try container.encode(true, forKey: .apiMisused)
      case .system:
        try container.encode(true, forKey: .system)
      }
    }
  }
}

// MARK: - Snapshot CustomStringConvertible, CustomDebugStringConvertible

extension Issue.Snapshot: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String {
    let joinedComments = if comments.isEmpty {
      ""
    } else {
      ": " + comments.lazy
        .map(\.rawValue)
        .joined(separator: "\n")
    }
    return "\(kind) (\(severity))\(joinedComments)"
  }

  public var debugDescription: String {
    let joinedComments = if comments.isEmpty {
      ""
    } else {
      ": " + comments.lazy
        .map(\.rawValue)
        .joined(separator: "\n")
    }
    return "\(kind)\(sourceLocation.map { " at \($0)" } ?? "") (\(severity))\(joinedComments)"
  }
}

extension Issue.Kind.Snapshot: CustomStringConvertible {
  public var description: String {
    switch self {
    case .unconditional:
      "Issue recorded"
    case let .expectationFailed(expectation):
      if let mismatchedErrorDescription = expectation.mismatchedErrorDescription {
        "Expectation failed: \(mismatchedErrorDescription)"
      } else {
        "Expectation failed: \(expectation.evaluatedExpression.expandedDescription())"
      }
    case let .confirmationMiscounted(actual: actual, expected: expected):
      "Confirmation was confirmed \(actual.counting("time")), but expected to be confirmed \(expected.counting("time"))"
    case .pollingConfirmationFailed:
      "Polling confirmation failed"
    case let .errorCaught(error):
      "Caught error: \(error)"
    case let .timeLimitExceeded(timeLimitComponents: timeLimitComponents):
      "Time limit was exceeded: \(TimeValue(timeLimitComponents))"
    case .knownIssueNotRecorded:
      "Known issue was not recorded"
    case .apiMisused:
      "An API was misused"
    case .system:
      "A system failure occurred"
    }
  }
}
#endif
