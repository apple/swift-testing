//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

extension Event {
  /// An experimental console output recorder that provides enhanced test result
  /// display capabilities.
  ///
  /// This recorder is currently experimental and must be enabled via the
  /// `SWT_ENABLE_EXPERIMENTAL_CONSOLE_OUTPUT` environment variable.
  struct AdvancedConsoleOutputRecorder<V: ABI.Version>: Sendable {
    /// Configuration options for the advanced console output recorder.
    struct Options: Sendable {
      /// Base console output recorder options to inherit from.
      var base: Event.ConsoleOutputRecorder.Options
      
      init() {
        self.base = Event.ConsoleOutputRecorder.Options()
      }
    }
    
    /// Context for storing data across events during test execution.
    private struct _Context: Sendable {
      /// Storage for test information, keyed by test ID string value.
      /// This is needed because ABI.EncodedEvent doesn't contain full test context.
      var testStorage: [String: ABI.EncodedTest<V>] = [:]
      
      // Future storage for result data and other event information can be added here
    }
    
    /// The options for this recorder.
    let options: Options
    
    /// The write function for this recorder.
    let write: @Sendable (String) -> Void
    
    /// The fallback console recorder for standard output.
    private let _fallbackRecorder: Event.ConsoleOutputRecorder
    
    /// Context storage for test information and results.
    private let _context: Locked<_Context>
    
    /// Human-readable output recorder for generating messages.
    private let _humanReadableRecorder: Event.HumanReadableOutputRecorder
    
    /// Initialize the advanced console output recorder.
    ///
    /// - Parameters:
    ///   - options: Configuration options for the recorder.
    ///   - write: A closure that writes output to its destination.
    init(options: Options = Options(), writingUsing write: @escaping @Sendable (String) -> Void) {
      self.options = options
      self.write = write
      self._fallbackRecorder = Event.ConsoleOutputRecorder(options: options.base, writingUsing: write)
      self._context = Locked(rawValue: _Context())
      self._humanReadableRecorder = Event.HumanReadableOutputRecorder()
    }
  }
}

extension Event.AdvancedConsoleOutputRecorder {
  /// Record an event by processing it and generating appropriate output.
  ///
  /// This implementation converts the Event to ABI.EncodedEvent for internal processing,
  /// following the ABI-based architecture for future separation into a harness process.
  ///
  /// - Parameters:
  ///   - event: The event to record.
  ///   - eventContext: The context associated with the event.
  func record(_ event: borrowing Event, in eventContext: borrowing Event.Context) {
    // Handle test discovery to populate our test storage
    if case .testDiscovered = event.kind, let test = eventContext.test {
      let encodedTest = ABI.EncodedTest<V>(encoding: test)
      _context.withLock { context in
        context.testStorage[encodedTest.id.stringValue] = encodedTest
      }
    }
    
    // Generate human-readable messages for the event
    let messages = _humanReadableRecorder.record(event, in: eventContext)
    
    // Convert Event to ABI.EncodedEvent
    if let encodedEvent = ABI.EncodedEvent<V>(encoding: event, in: eventContext, messages: messages) {
      // Process the ABI event
      _processABIEvent(encodedEvent)
    }
    
    // For now, still delegate to the fallback recorder to maintain existing functionality
    _fallbackRecorder.record(event, in: eventContext)
  }
  
  /// Process an ABI.EncodedEvent for advanced console output.
  ///
  /// This is where the enhanced console logic will be implemented in future PRs.
  /// Currently this is a placeholder that demonstrates the ABI conversion.
  ///
  /// - Parameters:
  ///   - encodedEvent: The ABI-encoded event to process.
  private func _processABIEvent(_ encodedEvent: ABI.EncodedEvent<V>) {
    // TODO: Implement enhanced console output logic here
    // This will be expanded in subsequent PRs for:
    // - Failure summary display
    // - Progress bar functionality
    // - Hierarchical test result display
    
    // For now, we just demonstrate that we can access the ABI event data
    switch encodedEvent.kind {
    case .runStarted:
      // Could implement run start logic here
      break
    case .testStarted:
      // Could implement test start logic here
      break
    case .issueRecorded:
      // Could implement issue recording logic here
      break
    case .testEnded:
      // Could implement test end logic here
      break
    case .runEnded:
      // Could implement run end logic here
      break
    default:
      // Handle other event types
      break
    }
  }
}
