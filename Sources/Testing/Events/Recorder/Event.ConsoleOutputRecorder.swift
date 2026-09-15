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
  /// subject to change. For machine-readable output, use ``JUnitXMLRecorder``.
  @_spi(ForToolsIntegrationOnly)
  public struct ConsoleOutputRecorder: Sendable/*, ~Copyable*/ {
    /// A type describing options to use when writing events to a stream.
    public struct Options: Sendable {
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
      public var useANSIEscapeCodes: Bool = false

      /// The supported color bit depth when adding color to the output using
      /// [ANSI escape codes](https://en.wikipedia.org/wiki/ANSI_escape_code).
      ///
      /// Allowed values are `1` (no color support), `4` (16-color), `8`
      /// (256-color), and `24` (true color.) The default value of this property
      /// is `1` (no color support.) When using Swift Testing from the command
      /// line with `swift test`, the environment is automatically inspected to
      /// determine what color support is available.
      ///
      /// The value of this property is ignored unless the value of
      /// ``useANSIEscapeCodes`` is `true`.
      public var ansiColorBitDepth: Int8 = 1

      /// Whether or not colors should be added to the output using
      /// [ANSI escape codes](https://en.wikipedia.org/wiki/ANSI_escape_code).
      var useColorANSIEscapeCodes: Bool {
        useANSIEscapeCodes && ansiColorBitDepth >= 4
      }

#if os(macOS) || (os(iOS) && targetEnvironment(macCatalyst))
      /// Whether or not to use [SF&nbsp;Symbols](https://developer.apple.com/sf-symbols/)
      /// in the output.
      ///
      /// When the value of this property is `true`, SF&nbsp;Symbols are assumed
      /// to be present in the font used for rendering within the Unicode
      /// Private Use Area.
      ///
      /// If the SF&nbsp;Symbols app is not installed on the system where the
      /// output is being rendered, the effect of setting the value of this
      /// property to `true` is unspecified.
      public var useSFSymbols: Bool = false
#endif

      /// Storage for ``tagColors``.
      private var _tagColors = Color.predefinedTagColors

      /// The colors to use for tags in the output.
      ///
      /// Tags on tests that have assigned colors in this dictionary are
      /// presented as colored dots prior to the tests' names. The tags
      /// ``Tag/red``, ``Tag/orange``, ``Tag/yellow``, ``Tag/green``,
      /// ``Tag/blue``, and ``Tag/purple`` always have assigned colors and those
      /// colors cannot be overridden when setting the value of this property.
      ///
      /// The value of this property is ignored unless the value of
      /// ``useANSIEscapeCodes`` is `true` and the value of
      /// ``ansiColorBitDepth`` is greater than `1`.
      public var tagColors: [Tag: Color] {
        get {
          _tagColors
        }
        set {
          // Assign the new value to this property, but do not allow the
          // predefined tag colors (red, orange, etc.) to be overridden.
          var tagColors = Color.predefinedTagColors
          tagColors.merge(
            newValue.lazy.filter { !$0.key.isPredefinedColor }.map { $0 },
            uniquingKeysWith: { _, rhs in rhs }
          )
          _tagColors = tagColors
        }
      }

      public init() {}
    }

    /// The options for this event recorder.
    var options = Options()

    /// The write function for this event recorder.
    var write: @Sendable (String) -> Void

    /// The underlying human-readable recorder.
    private var _humanReadableOutputRecorder = HumanReadableOutputRecorder()

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
    public init(options: Options = .init(), writingUsing write: @escaping @Sendable (String) -> Void) {
      self.options = options
      self.write = write
    }
  }
}

// MARK: - ANSI Escape Code support

extension Event.Symbol {
  /// Get the string value to use for a message with no associated symbol.
  ///
  /// - Parameters:
  ///   - options: Options to use when writing the symbol.
  ///
  /// - Returns: A string representation of "no symbol" appropriate for writing
  ///   to a stream.
  fileprivate static func placeholderStringValue(options: Event.ConsoleOutputRecorder.Options) -> String {
#if os(macOS) || (os(iOS) && targetEnvironment(macCatalyst))
    if options.useSFSymbols {
      return "  "
    }
#endif
    return " "
  }

  /// Get the string value for this symbol with the given write options.
  ///
  /// - Parameters:
  ///   - options: Options to use when writing this symbol.
  ///
  /// - Returns: A string representation of `self` appropriate for writing to
  ///   a stream.
  package func stringValue(options: Event.ConsoleOutputRecorder.Options) -> String {
    var symbolCharacter = String(unicodeCharacter)
#if os(macOS) || (os(iOS) && targetEnvironment(macCatalyst))
    if options.useSFSymbols {
      symbolCharacter = String(sfSymbolCharacter)
      if options.useANSIEscapeCodes {
        // When using ANSI escape codes, assume we are interfaced with the macOS
        // Terminal application which assumes a fixed-width font. Add an extra
        // trailing space after the SF Symbols character to ensure it has enough
        // room for rendering.
        symbolCharacter = "\(symbolCharacter) "
      }
    }
#endif

    if options.useColorANSIEscapeCodes, let color {
      // Apply color. Note that for built-in symbols, we always use 4-bit color
      // because terminal apps' themes may adjust them significantly from what
      // we expect.
      let colorANSIEscapeCode: String? = if case .custom = self {
        color.ansiEscapeCode(withBitDepth: options.ansiColorBitDepth)
      } else {
        color.closest16ColorEscapeCode()
      }
      if let colorANSIEscapeCode {
        return "\(colorANSIEscapeCode)\(symbolCharacter)\(resetANSIEscapeCode)"
      }
    }
    return symbolCharacter
  }
}

extension Event.ConsoleOutputRecorder {
  /// Generate a printable string describing the colors of a set of tags
  /// suitable for display in test output.
  ///
  /// - Parameters:
  ///   - tags: The tags for which colors are needed.
  ///
  /// - Returns: A string describing the colors of `tags` as bullet characters
  ///   with ANSI escape codes used to colorize them. If ANSI escape codes are
  ///   not enabled or if no tag colors are set, returns the empty string.
  fileprivate func colorDots(for tags: Set<Tag>) -> String {
    guard options.useColorANSIEscapeCodes else {
      return ""
    }

    let tagColors = options.tagColors
    let unsortedColors = tags.lazy.compactMap { tagColors[$0] }

    let options = options
    var result: String = Set(unsortedColors)
      .sorted(by: <).lazy
      .compactMap { $0.ansiEscapeCode(withBitDepth: options.ansiColorBitDepth) }
      .map { "\($0)\u{25CF}" } // Unicode: BLACK CIRCLE
      .joined()
    if !result.isEmpty {
      result += "\(resetANSIEscapeCode) "
    }
    return result
  }
}

// MARK: -

extension Event.ConsoleOutputRecorder {
  /// Record the specified messages by generating representations of them in
  /// this instance's output format and writing them to this instance's
  /// destination.
  ///
  /// - Parameters:
  ///   - messages: The messages to record.
  ///   - tags: Tags that may be colorized and which should be applied to
  ///     `messages`.
  ///
  /// - Returns: Whether any output was produced and written to this instance's
  ///   destination.
  private func _record(_ messages: [Event.HumanReadableOutputRecorder.Message], tags: Set<Tag>?) -> Bool {
    let symbolPlaceholder = Event.Symbol.placeholderStringValue(options: options)
    let lines = messages.lazy.map { message in
      let symbol = message.symbol?.stringValue(options: options) ?? symbolPlaceholder
      let indentation = String(repeating: "  ", count: message.indentation)

      if case .details = message.symbol {
        // Special-case the detail symbol to apply grey to the entire line of
        // text instead of just the symbol. Details may be multi-line messages,
        // so split the message on newlines and indent all lines to align them
        // to the indentation provided by the symbol.
        var lines = message.stringValue.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        lines = CollectionOfOne(lines[0]) + lines.dropFirst().map { line in
          "\(indentation)\(symbolPlaceholder) \(line)"
        }
        let stringValue = lines.joined(separator: "\n")
        if options.useColorANSIEscapeCodes {
          let ansiEscapeCode = Color.darkGray.closest16ColorEscapeCode()
          return "\(ansiEscapeCode)\(symbol) \(indentation)\(stringValue)\(resetANSIEscapeCode)\n"
        } else {
          return "\(symbol) \(indentation)\(stringValue)\n"
        }
      } else {
        let colorDots = tags.map { self.colorDots(for: $0) } ?? ""
        return "\(symbol) \(indentation)\(colorDots)\(message.stringValue)\n"
      }
    }

    write(lines.joined())
    return !messages.isEmpty
  }

  /// Record the specified event by generating a representation of it in this
  /// instance's output format and writing it to this instance's destination.
  ///
  /// - Parameters:
  ///   - event: The event to record.
  ///   - context: The context associated with the event.
  ///   - configuration: The configuration to use. Various properties of this
  ///     configuration (in particular its `verbosity` property) are consulted
  ///     when generating the resulting messages. If `nil`,
  ///     `eventContext.configuration` is used instead. The exact effects of
  ///     this argument are implementation-defined and subject to change.
  ///
  /// - Returns: Whether any output was produced and written to this instance's
  ///   destination.
  @discardableResult public func record(
    _ event: borrowing Event,
    in context: borrowing Event.Context,
    configuration: Configuration? = nil
  ) -> Bool {
    let messages = _humanReadableOutputRecorder.record(event, in: context, configuration: configuration)
    return _record(messages, tags: context.test?.tags)
  }

#if !SWT_NO_ABI_JSON_SCHEMA
  /// Record the specified event by generating a representation of it in this
  /// instance's output format and writing it to this instance's destination.
  ///
  /// - Parameters:
  ///   - event: The event to record.
  ///   - context: A context value that tracks decoded tests and events.
  ///   - configuration: The configuration to use. Various properties of this
  ///     configuration (in particular its `verbosity` property) are consulted
  ///     when generating the resulting messages. The exact effects of this
  ///     argument are implementation-defined and subject to change.
  ///
  /// - Returns: Whether any output was produced and written to this instance's
  ///   destination.
  @discardableResult public func record<V>(
    _ event: borrowing ABI.EncodedEvent<V>,
    in context: inout ABI.Context,
    configuration: Configuration? = nil
  ) -> Bool {
    let messages = _humanReadableOutputRecorder.record(event, in: &context, configuration: configuration)
    return _record(messages, tags: nil)
  }
#endif

  /// Get a message warning the user of some condition in the library that may
  /// affect test results.
  ///
  /// - Parameters:
  ///   - message: The message to present to the user.
  ///   - options: The options that should be used when formatting the resulting
  ///     message.
  ///
  /// - Returns: The described message, formatted for display using `options`.
  ///
  /// The caller is responsible for presenting this message to the user.
  static func warning(_ message: String, options: Event.ConsoleOutputRecorder.Options) -> String {
    let symbol = Event.Symbol.warning.stringValue(options: options)
    return "\(symbol) \(message)\n"
  }
}
