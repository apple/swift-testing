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
  struct AdvancedConsoleOutputRecorder: Sendable {
    /// Configuration options for the advanced console output recorder.
    struct Options: Sendable {
      /// Base console output recorder options to inherit from.
      var base: Event.ConsoleOutputRecorder.Options
      
      init() {
        self.base = Event.ConsoleOutputRecorder.Options()
      }
    }
    
    /// The options for this recorder.
    let options: Options
    
    /// The write function for this recorder.
    let write: @Sendable (String) -> Void
    
    /// The fallback console recorder for standard output.
    private let _fallbackRecorder: Event.ConsoleOutputRecorder
    
    /// Initialize the advanced console output recorder.
    ///
    /// - Parameters:
    ///   - options: Configuration options for the recorder.
    ///   - write: A closure that writes output to its destination.
    init(options: Options = Options(), writingUsing write: @escaping @Sendable (String) -> Void) {
      self.options = options
      self.write = write
      self._fallbackRecorder = Event.ConsoleOutputRecorder(options: options.base, writingUsing: write)
    }
  }
}

extension Event.AdvancedConsoleOutputRecorder {
  /// Record an event by processing it and generating appropriate output.
  ///
  /// Currently this is a skeleton implementation that delegates to
  /// ``Event/ConsoleOutputRecorder``.
  ///
  /// - Parameters:
  ///   - event: The event to record.
  ///   - eventContext: The context associated with the event.
  func record(_ event: borrowing Event, in eventContext: borrowing Event.Context) {
    // Skeleton implementation: delegate to ConsoleOutputRecorder
    _fallbackRecorder.record(event, in: eventContext)
  }
}
