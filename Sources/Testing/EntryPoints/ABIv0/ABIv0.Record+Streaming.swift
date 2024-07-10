//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if canImport(Foundation) && (!SWT_NO_FILE_IO || !SWT_NO_ABI_ENTRY_POINT)
extension ABIv0.Record {
  /// Create an event handler that encodes events as JSON and forwards them to
  /// an ABI-friendly event handler.
  ///
  /// - Parameters:
  ///   - eventHandler: The event handler to forward events to. See
  ///     ``ABIv0/EntryPoint`` for more information.
  ///
  /// - Returns: An event handler.
  ///
  /// The resulting event handler outputs data as JSON. For each event handled
  /// by the resulting event handler, a JSON object representing it and its
  /// associated context is created and is passed to `eventHandler`.
  ///
  /// Note that ``configurationForEntryPoint(from:)`` calls this function and
  /// performs additional postprocessing before writing JSON data to ensure it
  /// does not contain any newline characters.
  static func eventHandler(
    forwardingTo eventHandler: @escaping @Sendable (_ recordJSON: UnsafeRawBufferPointer) -> Void
  ) -> Event.Handler {
    let humanReadableOutputRecorder = Event.HumanReadableOutputRecorder()
    return { event, context in
      if case let .runStarted(plan) = event.kind {
        // Gather all tests in the run and forward records for them.
        for test in plan.steps.lazy.map(\.test) {
          try? JSON.withEncoding(of: Self(encoding: test)) { testJSON in
            eventHandler(testJSON)
          }
        }
      }

      let messages = humanReadableOutputRecorder.record(event, in: context)
      if let eventRecord = Self(encoding: event, in: context, messages: messages) {
        try? JSON.withEncoding(of: eventRecord, eventHandler)
      }
    }
  }
}

// MARK: - Experimental event streaming

/// A type containing an event snapshot and snapshots of the contents of an
/// event context suitable for streaming over JSON.
///
/// This type is not part of the public interface of the testing library.
/// External adopters are not necessarily written in Swift and are expected to
/// decode the JSON produced for this type in implementation-specific ways.
///
/// - Warning: This type supports early Xcode 16 betas and will be removed in a
///   future update.
struct EventAndContextSnapshot {
  /// A snapshot of the event.
  var event: Event.Snapshot

  /// A snapshot of the event context.
  var eventContext: Event.Context.Snapshot
}

extension EventAndContextSnapshot: Codable {}

/// Create an event handler that encodes events as JSON and forwards them to an
/// ABI-friendly event handler.
///
/// - Parameters:
///   - eventHandler: The event handler to forward events to. See
///     ``ABIEntryPoint_v0`` for more information.
///
/// - Returns: An event handler.
///
/// The resulting event handler outputs data as JSON. For each event handled by
/// the resulting event handler, a JSON object representing it and its
/// associated context is created and is passed to `eventHandler`.
///
/// Note that ``configurationForEntryPoint(from:)`` calls this function and
/// performs additional postprocessing before writing JSON data to ensure it
/// does not contain any newline characters.
///
/// - Warning: This function supports early Xcode 16 betas and will be removed
///   in a future update.
func eventHandlerForStreamingEventSnapshots(
  to eventHandler: @escaping @Sendable (_ eventAndContextJSON: UnsafeRawBufferPointer) -> Void
) -> Event.Handler {
  return { event, context in
    let snapshot = EventAndContextSnapshot(
      event: Event.Snapshot(snapshotting: event),
      eventContext: Event.Context.Snapshot(snapshotting: context)
    )
    try? JSON.withEncoding(of: snapshot) { eventAndContextJSON in
      eventAndContextJSON.withUnsafeBytes { eventAndContextJSON in
        eventHandler(eventAndContextJSON)
      }
    }
  }
}
#endif
