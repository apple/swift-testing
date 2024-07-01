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
      public var useANSIEscapeCodes = false

      /// The supported color bit depth when adding color to the output using
      /// [ANSI escape codes](https://en.wikipedia.org/wiki/ANSI_escape_code).
      ///
      /// Allowed values are `1` (no color support), `4` (16-color), `8`
      /// (256-color), and `24` (true color.) The default value of this property
      /// is `4` (16-color.)
      ///
      /// The value of this property is ignored unless the value of
      /// ``useANSIEscapeCodes`` is `true`.
      public var ansiColorBitDepth: Int8 = 4

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
      public var useSFSymbols = false
#endif

      /// The level of verbosity of the output.
      ///
      /// When the value of this property is greater than `0`, additional output
      /// is provided. When the value of this property is less than `0`, some
      /// output is suppressed. The exact effects of this property are
      /// implementation-defined and subject to change.
      public var verbosity = 0

      /// Storage for ``tagColors``.
      private var _tagColors = Tag.Color.predefined

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
      public var tagColors: [Tag: Tag.Color] {
        get {
          _tagColors
        }
        set {
          // Assign the new value to this property, but do not allow the
          // predefined tag colors (red, orange, etc.) to be overridden.
          var tagColors = Tag.Color.predefined
          tagColors.merge(
            newValue.lazy.filter { !$0.key.isPredefinedColor },
            uniquingKeysWith: { _, rhs in rhs }
          )
          _tagColors = tagColors
        }
      }

      /// A prefix to apply to all lines of text in the output.
      ///
      /// If set, the value of this property is written _before_ any symbol or
      /// library-supplied text.
      public var prefix: String?

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

/// The ANSI escape code prefix.
private let _ansiEscapeCodePrefix = "\u{001B}["

/// The ANSI escape code to reset text output to default settings.
private let _resetANSIEscapeCode = "\(_ansiEscapeCodePrefix)0m"

extension Event.Symbol {
  /// Get the string value for this symbol with the given write options.
  ///
  /// - Parameters:
  ///   - options: Options to use when writing this symbol.
  ///
  /// - Returns: A string representation of `self` appropriate for writing to
  ///   a stream.
  fileprivate func stringValue(options: Event.ConsoleOutputRecorder.Options) -> String {
    let useColorANSIEscapeCodes = options.useANSIEscapeCodes && options.ansiColorBitDepth >= 4

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

    if useColorANSIEscapeCodes {
      switch self {
      case .default, .skip, .difference:
        return "\(_ansiEscapeCodePrefix)90m\(symbolCharacter)\(_resetANSIEscapeCode)"
      case let .pass(knownIssueCount):
        if knownIssueCount > 0 {
          return "\(_ansiEscapeCodePrefix)90m\(symbolCharacter)\(_resetANSIEscapeCode)"
        }
        return "\(_ansiEscapeCodePrefix)92m\(symbolCharacter)\(_resetANSIEscapeCode)"
      case .fail:
        return "\(_ansiEscapeCodePrefix)91m\(symbolCharacter)\(_resetANSIEscapeCode)"
      case .warning:
        return "\(_ansiEscapeCodePrefix)93m\(symbolCharacter)\(_resetANSIEscapeCode)"
      case .details:
        return symbolCharacter
      }
    }
    return "\(symbolCharacter)"
  }
}

extension Tag.Color {
  /// Get an ANSI escape code that sets the foreground text color to this color.
  ///
  /// - Parameters:
  ///   - options: Options to use when writing this tag.
  ///
  /// - Returns: The corresponding ANSI escape code. If the
  ///   ``Event/Recorder/Option/useANSIEscapeCodes(colorBitDepth:)`` option is
  ///   not specified, returns `nil`.
  fileprivate func ansiEscapeCode(options: Event.ConsoleOutputRecorder.Options) -> String? {
    guard options.useANSIEscapeCodes && options.ansiColorBitDepth >= 4 else {
      return nil
    }
    if options.ansiColorBitDepth >= 24 {
      return "\(_ansiEscapeCodePrefix)38;2;\(redComponent);\(greenComponent);\(blueComponent)m"
    }
    if options.ansiColorBitDepth >= 8 {
      // The formula for converting an RGB value to a 256-color ANSI color
      // code can be found at https://en.wikipedia.org/wiki/ANSI_escape_code#8-bit
      let r = (Int(redComponent) * 5) / Int(UInt8.max)
      let g = (Int(greenComponent) * 5) / Int(UInt8.max)
      let b = (Int(blueComponent) * 5) / Int(UInt8.max)
      let index = 16 + 36 * r + 6 * g + b
      return "\(_ansiEscapeCodePrefix)38;5;\(index)m"
    }
    return closest16ColorEscapeCode()
  }

  /// Get the ANSI escape code that sets the foreground text color to whichever
  /// 16-color value is closest to this instance.
  ///
  /// - Returns: The corresponding ANSI escape code.
  ///
  /// An idealized color space is assumed.
  func closest16ColorEscapeCode() -> String {
    if self == .orange {
      // Special-case orange to dark yellow as it doesn't have a good mapping in
      // most low-color terminals. NOTE: Historically, the IBM PC's CGA adapter
      // and monitor had dedicated circuitry to display dark yellow as a shade
      // of orange-brown, but modern terminal applications rarely emulate it.
      return "\(_ansiEscapeCodePrefix)33m"
    } else if self == .purple {
      // Special-case purple as well since it is declared as true purple rather
      // than magenta.
      return "\(_ansiEscapeCodePrefix)95m"
    }

    let (hue, saturation, value) = hsvComponents
    if saturation <= 0.25 {
      // Some shade of gray (or a very pale color.)
      let colorValue = switch Int(value * 3.0) {
      case 0: // black
        30
      case 1: // dark gray
        90
      case 2: // light gray
        37
      default: // 3, white
        97
      }
      return "\(_ansiEscapeCodePrefix)\(colorValue)m"
    } else {
      // There is some saturation, so figure out the closest available color.
      let brightAddend = if value > 0.5 {
        60
      } else {
        0
      }
      let hueAddend = switch Int(hue * 6.0) {
      case 0, 6: // red
        31
      case 1: // yellow
        33
      case 2: // green
        32
      case 3: // cyan
        36
      case 4: // blue
        34
      default: // 5, magenta
        35
      }
      return "\(_ansiEscapeCodePrefix)\(hueAddend + brightAddend)m"
    }
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
    let tagColors = options.tagColors
    let unsortedColors = tags.lazy.compactMap { tagColors[$0] }

    let options = options
    var result: String = Set(unsortedColors)
      .sorted(by: <).lazy
      .compactMap { $0.ansiEscapeCode(options: options) }
      .map { "\($0)\u{25CF}" } // Unicode: BLACK CIRCLE
      .joined()
    if !result.isEmpty {
      result += "\(_resetANSIEscapeCode) "
    }
    return result
  }
}

// MARK: -

extension Event.ConsoleOutputRecorder {
  /// Record the specified event by generating a representation of it in this
  /// instance's output format and writing it to this instance's destination.
  ///
  /// - Parameters:
  ///   - event: The event to record.
  ///   - context: The context associated with the event.
  ///
  /// - Returns: Whether any output was produced and written to this instance's
  ///   destination.
  @discardableResult public func record(_ event: borrowing Event, in context: borrowing Event.Context) -> Bool {
    let messages = _humanReadableOutputRecorder.record(event, in: context, verbosity: options.verbosity)
    for message in messages {
      let prefix = options.prefix ?? ""
      let symbol = message.symbol?.stringValue(options: options) ?? " "

      if case .details = message.symbol, options.useANSIEscapeCodes, options.ansiColorBitDepth > 1 {
        // Special-case the detail symbol to apply grey to the entire line of
        // text instead of just the symbol.
        write("\(prefix)\(_ansiEscapeCodePrefix)90m\(symbol) \(message.stringValue)\(_resetANSIEscapeCode)\n")
      } else {
        let colorDots = context.test.map(\.tags).map { self.colorDots(for: $0) } ?? ""
        write("\(prefix)\(symbol) \(colorDots)\(message.stringValue)\n")
      }
    }
    return !messages.isEmpty
  }


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
    let prefix = options.prefix ?? ""
    let symbol = Event.Symbol.warning.stringValue(options: options)
    return "\(prefix)\(symbol) \(message)\n"
  }
}
