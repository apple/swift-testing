//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if !SWT_NO_ABI_JSON_SCHEMA
extension ABI {
  /// A type implementing the JSON encoding of ``Issue`` for the ABI entry point
  /// and event stream output.
  ///
  /// This type is not part of the public interface of the testing library. It
  /// assists in converting values to JSON; clients that consume this JSON are
  /// expected to write their own decoders.
  struct EncodedIssue<V>: Sendable where V: ABI.Version {
    /// An enumeration representing the level of severity of a recorded issue.
    ///
    /// For descriptions of individual cases, see ``Issue/Severity-swift.enum``.
    enum Severity: String, Sendable {
      case warning
      case error
    }

    /// The severity of this issue.
    ///
    /// Prior to 6.3, this is nil.
    ///
    /// @Metadata {
    ///   @Available(Swift, introduced: 6.3)
    ///   @Available(Xcode, introduced: 26.4)
    /// }
    var severity: Severity?

    /// If the issue is a failing issue.
    ///
    /// Prior to 6.3, this is nil.
    ///
    /// @Metadata {
    ///   @Available(Swift, introduced: 6.3)
    ///   @Available(Xcode, introduced: 26.4)
    /// }
    var isFailure: Bool?

    /// Whether or not this issue is known to occur.
    var isKnown: Bool

    /// A comment associated with the known issue, if any.
    ///
    /// - Warning: This property is not yet part of the JSON schema.
    var _knownIssueComment: String?

    /// The location in source where this issue occurred, if available.
    public var sourceLocation: EncodedSourceLocation<V>?

    /// The backtrace where this issue occurred, if available.
    ///
    /// - Warning: Backtraces are not yet part of the JSON schema.
    var _backtrace: EncodedBacktrace<V>?

    /// The error associated with this issue, if applicable.
    ///
    /// - Warning: Errors are not yet part of the JSON schema.
    var _error: EncodedError<V>?

    /// The expression associated with this issue, if applicable.
    ///
    /// - Warning: Expressions are not yet part of the JSON schema.
    var _expression: EncodedExpression<V>?

    init(encoding issue: borrowing Issue, in eventContext: borrowing Event.Context) {
      // >= v0
      isKnown = issue.isKnown
      sourceLocation = issue.sourceLocation.map { EncodedSourceLocation(encoding: $0) }

      // >= v6.3
      if V.versionNumber >= ABI.v6_3.versionNumber {
        severity = switch issue.severity {
        case .warning: .warning
        case .error: .error
        }
        isFailure = issue.isFailure
      }

      // Experimental fields
      if V.includesExperimentalFields {
        if let knownIssueContext = issue.knownIssueContext {
          _knownIssueComment = knownIssueContext.comment?.rawValue
        }
        if let backtrace = issue.sourceContext.backtrace {
          _backtrace = EncodedBacktrace(encoding: backtrace, in: eventContext)
        }
        _error = if let error = issue.error {
#if !hasFeature(Embedded)
          EncodedError(encoding: error)
#else
          EncodedError(encoding: error as any Error)
#endif
        } else {
          switch issue.kind {
          case .apiMisused:
            EncodedError(encoding: APIMisuseError(description: ""))
          case .system:
            EncodedError(encoding: SystemError(description: ""))
          default:
            nil
          }
        }
        if case let .expectationFailed(expectation) = issue.kind {
          _expression = EncodedExpression(encoding: expectation.evaluatedExpression)
        }
      }
    }
  }
}

#if !SWT_NO_CODABLE
// MARK: - Codable

extension ABI.EncodedIssue: Codable {}
extension ABI.EncodedIssue.Severity: Codable {}
#endif

// MARK: - Conversion to/from library types

extension Issue {
  /// Initialize an instance of this type from the given value.
  ///
  /// - Parameters:
  ///   - event: The encoded event to initialize this instance from.
  ///
  /// If `event` does not represent a recorded issue, the initializer returns
  /// `nil`.
  init?<V>(decoding event: ABI.EncodedEvent<V>) {
    guard let issue = event.issue else {
      return nil
    }
    self.init(decoding: issue)
    if let comments = event._comments {
      self.comments += comments.map(Comment.init(rawValue:))
    }
  }

  /// Initialize an instance of this type from the given value.
  ///
  /// - Parameters:
  ///   - issue: The encoded issue to initialize this instance from.
  ///
  /// - Note: For higher fidelity, initialize the issue with an encoded event
  ///   representing a recorded issue rather than just the encoded issue.
  init?<V>(decoding issue: ABI.EncodedIssue<V>) {
    let issueKind: Issue.Kind
    if let error = issue._error {
      switch error.domain {
      case APIMisuseError.domain:
        issueKind = .apiMisused
      case SystemError.domain:
        issueKind = .system
      default:
        issueKind = .errorCaught(error)
      }
    } else if let expression = issue._expression.flatMap(__Expression.init(decoding:)),
              let sourceLocation = issue.sourceLocation.flatMap(SourceLocation.init) {
      let expectation = Expectation(
        evaluatedExpression: expression,
        isPassing: false,
        isRequired: false,
        sourceLocation: sourceLocation
      )
      issueKind = .expectationFailed(expectation)
    } else {
      // TODO: improve fidelity of issue kind reporting (especially those without associated values)
      issueKind = .unconditional
    }
    let severity: Issue.Severity = switch issue.severity {
    case .warning:
        .warning
    case .error, nil:
      // Prior to 6.3, all Issues are errors
        .error
    }
#if !SWT_NO_BACKTRACE_SYMBOLICATION
    let backtrace = issue._backtrace.map { Backtrace(addresses: $0.symbolicatedAddresses.map { $0.address }) }
#else
    let backtrace = issue._backtrace.map { Backtrace(addresses: $0.addresses) }
#endif
    let sourceLocation = issue.sourceLocation.flatMap(SourceLocation.init)
    let sourceContext = SourceContext(backtrace: backtrace, sourceLocation: sourceLocation)
    self.init(
      kind: issueKind,
      severity: severity,
      comments: [],
      sourceContext: sourceContext
    )
    if issue.isKnown {
      let knownIssueComment = issue._knownIssueComment.map(Comment.init(rawValue:))
      self.knownIssueContext = Issue.KnownIssueContext(comment: knownIssueComment)
    }
  }
}
#endif
