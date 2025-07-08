//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

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
    /// - Warning: Severity is not yet part of the JSON schema.
    var _severity: Severity
    
    /// If the issue is a failing issue.
    ///
    /// - Warning: Non-failing issues are not yet part of the JSON schema.
    var _isFailure: Bool

    /// Whether or not this issue is known to occur.
    var isKnown: Bool

    /// The location in source where this issue occurred, if available.
    var sourceLocation: SourceLocation?

    /// The backtrace where this issue occurred, if available.
    ///
    /// - Warning: Backtraces are not yet part of the JSON schema.
    var _backtrace: EncodedBacktrace<V>?

    /// The error associated with this issue, if applicable.
    ///
    /// - Warning: Errors are not yet part of the JSON schema.
    var _error: EncodedError<V>?

    init(encoding issue: borrowing Issue, in eventContext: borrowing Event.Context) {
      _severity = switch issue.severity {
      case .warning: .warning
      case .error: .error
      }
      _isFailure = issue.isFailure
      isKnown = issue.isKnown
      sourceLocation = issue.sourceLocation
      if let backtrace = issue.sourceContext.backtrace {
        _backtrace = EncodedBacktrace(encoding: backtrace, in: eventContext)
      }
      if let error = issue.error {
        _error = EncodedError(encoding: error, in: eventContext)
      }
    }
  }
}

// MARK: - Codable

extension ABI.EncodedIssue: Codable {}
extension ABI.EncodedIssue.Severity: Codable {}
