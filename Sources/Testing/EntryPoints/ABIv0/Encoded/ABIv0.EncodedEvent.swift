//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

extension ABIv0 {
  /// A type implementing the JSON encoding of ``Event`` for the ABI entry point
  /// and event stream output.
  ///
  /// This type is not part of the public interface of the testing library. It
  /// assists in converting values to JSON; clients that consume this JSON are
  /// expected to write their own decoders.
  struct EncodedEvent: Sendable {
    /// An enumeration describing the various kinds of event.
    ///
    /// Note that the set of encodable events is a subset of all events
    /// generated at runtime by the testing library.
    ///
    /// For descriptions of individual cases, see ``Event/Kind``.
    enum Kind: String, Sendable {
      case runStarted
      case testStarted
      case testCaseStarted
      case issueRecorded
      case knownIssueRecorded
      case testCaseEnded
      case testEnded
      case testSkipped
      case runEnded
    }

    /// The kind of event.
    var kind: Kind

    /// The source location of the event, if applicable.
    var sourceLocation: SourceLocation?

    /// The instant at which the event occurred on the current system's
    /// suspending clock.
    var timestamp: Double

    /// The instant at which the event occurred on the wall clock.
    var timestampSince1970: Double

    /// Human-readable messages associated with this event that can be presented
    /// to the user.
    var messages: [EncodedMessage]

    /// The ID of the test associated with this event, if any.
    var testID: EncodedTest.ID?

    /// The ID of the test case associated with this event, if any.
    ///
    /// - Warning: Test cases are not yet part of the JSON schema.
    var _testCase: EncodedTestCase?

    init?(encoding event: borrowing Event, in eventContext: borrowing Event.Context, messages: borrowing [Event.HumanReadableOutputRecorder.Message]) {
      if let test = eventContext.test {
        sourceLocation = test.sourceLocation
      }
      switch event.kind {
      case .runStarted:
        kind = .runStarted
      case .testStarted:
        kind = .testStarted
      case .testCaseStarted:
        kind = .testCaseStarted
      case let .issueRecorded(issue):
        if issue.isKnown {
          kind = .knownIssueRecorded
        } else {
          kind = .issueRecorded
        }
        sourceLocation = issue.sourceLocation
      case .testCaseEnded:
        kind = .testCaseEnded
      case .testEnded:
        kind = .testEnded
      case .testSkipped:
        kind = .testSkipped
      case .runEnded:
        kind = .runEnded
      default:
        return nil
      }
      timestamp = Double(event.instant.suspending)
      timestampSince1970 = Double(event.instant.wall)
      self.messages = messages.map(EncodedMessage.init)
      testID = event.testID.map(EncodedTest.ID.init)
      _testCase = eventContext.testCase.map(EncodedTestCase.init)
    }
  }
}

// MARK: - Codable

extension ABIv0.EncodedEvent: Codable {}
extension ABIv0.EncodedEvent.Kind: Codable {}
