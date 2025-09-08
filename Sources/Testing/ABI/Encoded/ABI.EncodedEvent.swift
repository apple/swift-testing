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
  /// A type implementing the JSON encoding of ``Event`` for the ABI entry point
  /// and event stream output.
  ///
  /// This type is not part of the public interface of the testing library. It
  /// assists in converting values to JSON; clients that consume this JSON are
  /// expected to write their own decoders.
  struct EncodedEvent<V>: Sendable where V: ABI.Version {
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
      case valueAttached
      case testCaseEnded
      case testCaseCancelled = "_testCaseCancelled"
      case testEnded
      case testSkipped
      case testCancelled = "_testCancelled"
      case runEnded
    }

    /// The kind of event.
    var kind: Kind

    /// The instant at which the event occurred.
    var instant: EncodedInstant<V>

    /// The issue that occurred, if any.
    ///
    /// The value of this property is `nil` unless the value of the
    /// ``kind-swift.property`` property is ``Kind-swift.enum/issueRecorded``.
    var issue: EncodedIssue<V>?

    /// The value that was attached, if any.
    ///
    /// The value of this property is `nil` unless the value of the
    /// ``kind-swift.property`` property is ``Kind-swift.enum/valueAttached``.
    var attachment: EncodedAttachment<V>?

    /// Human-readable messages associated with this event that can be presented
    /// to the user.
    var messages: [EncodedMessage<V>]

    /// The ID of the test associated with this event, if any.
    var testID: EncodedTest<V>.ID?

    /// The ID of the test case associated with this event, if any.
    ///
    /// - Warning: Test cases are not yet part of the JSON schema.
    var _testCase: EncodedTestCase<V>?

    /// The comments the test author provided for this event, if any.
    ///
    /// The value of this property contains the comments related to the primary
    /// user action that caused this event to be generated.
    ///
    /// Some kinds of events have additional associated comments. For example,
    /// when using ``withKnownIssue(_:isIntermittent:sourceLocation:_:)``, there
    /// can be separate comments for the "underlying" issue versus the known
    /// issue matcher, and either can be `nil`. In such cases, the secondary
    /// comment(s) are represented via a distinct property depending on the kind
    /// of that event.
    ///
    /// - Warning: Comments at this level are not yet part of the JSON schema.
    var _comments: [String]?

    /// A source location associated with this event, if any.
    ///
    /// The value of this property represents the source location most closely
    /// related to the primary user action that caused this event to be
    /// generated.
    ///
    /// Some kinds of events have additional associated source locations. For
    /// example, when using ``withKnownIssue(_:isIntermittent:sourceLocation:_:)``,
    /// there can be separate source locations for the "underlying" issue versus
    /// the known issue matcher. In such cases, the secondary source location(s)
    /// are represented via a distinct property depending on the kind of that
    /// event.
    ///
    /// - Warning: Source locations at this level of the JSON schema are not yet
    ///   part of said JSON schema.
    var _sourceLocation: SourceLocation?

    init?(encoding event: borrowing Event, in eventContext: borrowing Event.Context, messages: borrowing [Event.HumanReadableOutputRecorder.Message]) {
      switch event.kind {
      case .runStarted:
        kind = .runStarted
      case .testStarted:
        kind = .testStarted
      case .testCaseStarted:
        if eventContext.test?.isParameterized == false {
          return nil
        }
        kind = .testCaseStarted
      case let .issueRecorded(recordedIssue):
        kind = .issueRecorded
        issue = EncodedIssue(encoding: recordedIssue, in: eventContext)
      case let .valueAttached(attachment):
        kind = .valueAttached
        self.attachment = EncodedAttachment(encoding: attachment, in: eventContext)
      case .testCaseEnded:
        if eventContext.test?.isParameterized == false {
          return nil
        }
        kind = .testCaseEnded
      case .testCaseCancelled:
        kind = .testCaseCancelled
      case .testEnded:
        kind = .testEnded
      case .testSkipped:
        kind = .testSkipped
      case .testCancelled:
        kind = .testCancelled
      case .runEnded:
        kind = .runEnded
      default:
        return nil
      }
      instant = EncodedInstant(encoding: event.instant)
      self.messages = messages.map(EncodedMessage.init)
      testID = event.testID.map(EncodedTest.ID.init)

      // Experimental fields
      if V.includesExperimentalFields {
        switch event.kind {
        case let .issueRecorded(recordedIssue):
          _comments = recordedIssue.comments.map(\.rawValue)
          _sourceLocation = recordedIssue.sourceLocation
        case let .valueAttached(attachment):
          _sourceLocation = attachment.sourceLocation
        case let .testCaseCancelled(skipInfo),
          let .testSkipped(skipInfo),
          let .testCancelled(skipInfo):
          _comments = Array(skipInfo.comment).map(\.rawValue)
          _sourceLocation = skipInfo.sourceLocation
        default:
          break
        }

        if eventContext.test?.isParameterized == true {
          _testCase = eventContext.testCase.map(EncodedTestCase.init)
        }
      }
    }
  }
}

// MARK: - Codable

extension ABI.EncodedEvent: Codable {}
extension ABI.EncodedEvent.Kind: Codable {}
