//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

private import TestingInternals
#if canImport(Foundation)
private import Foundation
#endif

/// The entry point to the testing library used by Swift Package Manager.
///
/// - Returns: The result of invoking the testing library. The type of this
///   value is subject to change.
///
/// This function examines the command-line arguments to the current process
/// and then invokes available tests in the current process.
///
/// - Warning: This function is used by Swift Package Manager. Do not call it
///   directly.
@_disfavoredOverload public func __swiftPMEntryPoint() async -> CInt {
  let exitCode = Locked(rawValue: EXIT_SUCCESS)

  do {
    let args = CommandLine.arguments()
    if args.count == 2 && args[1] == "--list-tests" {
      for testID in await listTestsForSwiftPM(Test.all) {
#if SWT_TARGET_OS_APPLE && !SWT_NO_FILE_IO
        try? FileHandle.stdout.write("\(testID)\n")
#else
        print(testID)
#endif
      }
    } else {
      var configuration = try configurationForSwiftPMEntryPoint(withArguments: args)
      let oldEventHandler = configuration.eventHandler
      configuration.eventHandler = { event, context in
        if case let .issueRecorded(issue) = event.kind, !issue.isKnown {
          exitCode.withLock { exitCode in
            exitCode = EXIT_FAILURE
          }
        }
        oldEventHandler(event, context)
      }

      var options = [Event.ConsoleOutputRecorder.Option]()
#if !SWT_NO_FILE_IO
      options += .for(.stderr)
#endif
      if args.contains("--verbose") {
        options.append(.useVerboseOutput)
      }

      // TODO: lower this flag directly to event handler once we remove XCTestScaffold
      let outputToConsole: Bool
#if SWIFT_PM_SUPPORTS_SWIFT_TESTING && canImport(Foundation) && (os(macOS) || os(Linux) || os(Windows))
      outputToConsole = currentExitTestSourceLocation(withArguments: args) == nil
#else
      outputToConsole = true
#endif

      await runTests(options: options, configuration: configuration, outputToConsole: outputToConsole)
    }
  } catch {
#if !SWT_NO_FILE_IO
    try? FileHandle.stderr.write(String(describing: error))
#endif

    exitCode.withLock { exitCode in
      exitCode = EXIT_FAILURE
    }
  }

  return exitCode.rawValue
}

/// The entry point to the testing library used by Swift Package Manager.
///
/// This function examines the command-line arguments to the current process
/// and then invokes available tests in the current process. When the tests
/// complete, the process is terminated. If tests were successful, an exit code
/// of `EXIT_SUCCESS` is used; otherwise, a (possibly platform-specific) value
/// such as `EXIT_FAILURE` is used instead.
///
/// - Warning: This function is used by Swift Package Manager. Do not call it
///   directly.
public func __swiftPMEntryPoint() async -> Never {
  let exitCode: CInt = await __swiftPMEntryPoint()
  exit(exitCode)
}

// MARK: -

/// List all of the given tests in the "specifier" format used by Swift Package
/// Manager.
///
/// - Parameters:
///   - tests: The tests to list.
///
/// - Returns: An array of strings representing the IDs of `tests`.
func listTestsForSwiftPM(_ tests: some Sequence<Test>) -> [String] {
  // Filter out hidden tests and test suites. Hidden tests should not generally
  // be presented to the user, and suites (XCTestCase classes) are not included
  // in the equivalent XCTest-based output.
  let tests = tests.lazy
    .filter { !$0.isSuite }
    .filter { !$0.isHidden }

  // Group tests by the name components of the tests' IDs. If the name
  // components of two tests' IDs are ambiguous, present their source locations
  // to disambiguate.
  return Dictionary(
    grouping: tests.lazy.map(\.id),
    by: \.nameComponents
  ).values.lazy
    .map { ($0, isAmbiguous: $0.count > 1) }
    .flatMap { testIDs, isAmbiguous in
      testIDs.lazy
        .map { testID in
          if !isAmbiguous, testID.sourceLocation != nil {
            return testID.parent ?? testID
          }
          return testID
        }
    }.map(String.init(describing:))
    .sorted(by: <)
}

/// Get an instance of ``Configuration`` given a sequence of command-line
/// arguments passed from Swift Package Manager.
///
/// - Parameters:
///   - args: The command-line arguments to interpret.
///
/// - Returns: An instance of ``Configuration``. Note that the caller is
///   responsible for setting this instance's ``Configuration/eventHandler``
///   property.
///
/// - Throws: If an argument is invalid, such as a malformed regular expression.
///
/// This function generally assumes that Swift Package Manager has already
/// validated the passed arguments.
func configurationForSwiftPMEntryPoint(withArguments args: [String]) throws -> Configuration {
  var configuration = Configuration()

  // Do not consider the executable path AKA argv[0].
  let args = args.dropFirst()

  // Parallelization (on by default)
  configuration.isParallelizationEnabled = true
  if args.contains("--no-parallel") {
    configuration.isParallelizationEnabled = false
  }

#if !SWT_NO_FILE_IO
  // XML output
  if let xunitOutputIndex = args.firstIndex(of: "--xunit-output"), xunitOutputIndex < args.endIndex {
    let xunitOutputPath = args[args.index(after: xunitOutputIndex)]

    // Open the XML file for writing.
    let file = try FileHandle(forWritingAtPath: xunitOutputPath)

    // Set up the XML recorder.
    let xmlRecorder = Event.JUnitXMLRecorder { string in
      try? file.write(string)
    }

    let oldEventHandler = configuration.eventHandler
    configuration.eventHandler = { event, context in
      _ = xmlRecorder.record(event, in: context)
      oldEventHandler(event, context)
    }
  }

#if canImport(Foundation)
  // Event stream output (experimental)
  if let eventOutputIndex = args.firstIndex(of: "--experimental-event-stream-output"), eventOutputIndex < args.endIndex {
    let eventStreamOutputPath = args[args.index(after: eventOutputIndex)]
    let eventHandler = try _eventHandlerForStreamingEvents(toFileAtPath: eventStreamOutputPath)
    let oldEventHandler = configuration.eventHandler
    configuration.eventHandler = { event, context in
      eventHandler(event, context)
      oldEventHandler(event, context)
    }
  }
#endif
#endif

  // Filtering
  var filters = [Configuration.TestFilter]()
  func testFilter(forArgumentsWithLabel label: String, membership: Configuration.TestFilter.Membership) throws -> Configuration.TestFilter {
    let matchingArgs: [String] = args.indices.lazy
      .filter { args[$0] == label && $0 < args.endIndex }
      .map { args[args.index(after: $0)] }
    if matchingArgs.isEmpty {
      return .unfiltered
    }

    guard #available(_regexAPI, *) else {
      throw _EntryPointError.featureUnavailable("The `\(label)' option is not supported on this OS version.")
    }
    return try matchingArgs.lazy
      .map { try Regex($0) }
      .map { Configuration.TestFilter(membership: membership, matching: $0) }
      .reduce(into: .unfiltered) { $0.combine(with: $1, using: .or) }
  }
  filters.append(try testFilter(forArgumentsWithLabel: "--filter", membership: .including))
  filters.append(try testFilter(forArgumentsWithLabel: "--skip", membership: .excluding))

  configuration.testFilter = filters.reduce(.unfiltered) { $0.combining(with: $1) }

  // Set up the iteration policy for the test run.
  var repetitionPolicy: Configuration.RepetitionPolicy = .once
  var hadExplicitRepetitionCount = false
  if let repetitionsIndex = args.firstIndex(of: "--repetitions"), repetitionsIndex < args.endIndex,
     let repetitionCount = Int(args[args.index(after: repetitionsIndex)]), repetitionCount > 0 {
    repetitionPolicy.maximumIterationCount = repetitionCount
    hadExplicitRepetitionCount = true
  }
  if let repeatUntilIndex = args.firstIndex(of: "--repeat-until"), repeatUntilIndex < args.endIndex {
    let repeatUntil = args[args.index(after: repeatUntilIndex)].lowercased()
    switch repeatUntil {
    case "pass":
      repetitionPolicy.continuationCondition = .whileIssueRecorded
    case "fail":
      repetitionPolicy.continuationCondition = .untilIssueRecorded
    default:
      throw _EntryPointError.invalidArgument("--repeat-until", value: repeatUntil)
    }
    if !hadExplicitRepetitionCount {
      // The caller wants to repeat until a condition is met, but didn't say how
      // many times to repeat, so assume they meant "forever".
      repetitionPolicy.maximumIterationCount = .max
    }
  }
  configuration.repetitionPolicy = repetitionPolicy

  return configuration
}

/// The common implementation of ``swiftPMEntryPoint()`` and
/// ``XCTestScaffold/runAllTests(hostedBy:)``.
///
/// - Parameters:
///   - options: Options to pass when configuring the console output recorder.
///   - configuration: The configuration to use for running.
func runTests(options: [Event.ConsoleOutputRecorder.Option], configuration: Configuration, outputToConsole: Bool = true) async {
  var configuration = configuration
  if outputToConsole {
    let eventRecorder = Event.ConsoleOutputRecorder(options: options) { string in
#if !SWT_NO_FILE_IO
      try? FileHandle.stderr.write(string)
#endif
    }

    let oldEventHandler = configuration.eventHandler
    configuration.eventHandler = { event, context in
      eventRecorder.record(event, in: context)
      oldEventHandler(event, context)
    }
  }

  let runner = await Runner(configuration: configuration)
  await runner.run()
}

// MARK: - Experimental event streaming

#if !SWT_NO_FILE_IO && canImport(Foundation)
/// A type containing an event snapshot and snapshots of the contents of an
/// event context suitable for streaming over JSON.
///
/// This function is not part of the public interface of the testing library.
/// External adopters are not necessarily written in Swift and are expected to
/// decode the JSON produced for this type in implementation-specific ways.
struct EventAndContextSnapshot {
  /// A snapshot of the event.
  var event: Event.Snapshot

  /// A snapshot of the test associated with the event, if any.
  var test: Test.Snapshot?

  /// A snapshot of the test case associated with the event, if any.
  var testCase: Test.Case.Snapshot?
}

extension EventAndContextSnapshot: Codable {}

/// Create an event handler that streams events to the file at a given path.
///
/// - Parameters:
///   - path: The path to which events should be streamed. This file will be
///     opened for writing.
///
/// - Throws: Any error that occurs opening `path`. Once `path` is opened,
///   errors that may occur writing to it are handled by the resulting event
///   handler.
///
/// - Returns: An event handler.
///
/// The resulting event handler outputs data in the [JSON Lines](https://jsonlines.org)
/// text format. For each event handled by the resulting event handler, a JSON
/// object representing it and its associated context is created and is written
/// to `path`, followed by a single line feed (`"\n"`) character. These JSON
/// objects are guaranteed not to contain any ASCII newline characters (`"\r"`
/// or `"\n"`) themselves.
///
/// The file at `path` can be a regular file, however to allow for streaming a
/// named pipe is recommended. `mkfifo()` can be used on Darwin and Linux to
/// create a named pipe; `CreateNamedPipeA()` can be used on Windows.
///
/// The file at `path` is closed when this process terminates or the
/// corresponding call to ``Runner/run()`` returns, whichever occurs first.
private func _eventHandlerForStreamingEvents(toFileAtPath path: String) throws -> Event.Handler {
  // Open the event stream file for writing.
  let file = try FileHandle(forWritingAtPath: path)

  return { event, context in
    let snapshot = EventAndContextSnapshot(
      event: Event.Snapshot(snapshotting: event),
      test: context.test.map { Test.Snapshot(snapshotting: $0) },
      testCase: context.testCase.map { Test.Case.Snapshot(snapshotting: $0) }
    )
    if var snapshotJSON = try? JSONEncoder().encode(snapshot) {
      func isASCIINewline(_ byte: UInt8) -> Bool {
        byte == 10 || byte == 13
      }

#if DEBUG
      // We don't actually expect JSONEncoder() to produce output containing
      // newline characters, so in debug builds we'll log a diagnostic message.
      if snapshotJSON.contains(where: isASCIINewline) {
        let message = Event.ConsoleOutputRecorder.warning(
          "JSONEncoder() produced one or more newline characters while encoding an event snapshot with kind '\(event.kind)'. Please file a bug report at https://github.com/apple/swift-testing/issues/new",
          options: .for(.stderr)
        )
#if SWT_TARGET_OS_APPLE
        try? FileHandle.stderr.write(message)
#else
        print(message)
#endif
      }
#endif

      // Remove newline characters to conform to JSON lines specification.
      snapshotJSON.removeAll(where: isASCIINewline)
      if !snapshotJSON.isEmpty {
        try? file.withLock {
          try snapshotJSON.withUnsafeBytes { snapshotJSON in
            try file.write(snapshotJSON)
          }
          try file.write("\n")
        }
      }
    }
  }
}
#endif

// MARK: - Command-line interface options

extension [Event.ConsoleOutputRecorder.Option] {
#if !SWT_NO_FILE_IO
  /// The set of options to use when writing to the standard error stream.
  static func `for`(_ fileHandle: borrowing FileHandle) -> Self {
    var result = Self()

    let useANSIEscapeCodes = _fileHandleSupportsANSIEscapeCodes(fileHandle)
    if useANSIEscapeCodes {
      let colorBitDepth: Int8 = if let noColor = Environment.variable(named: "NO_COLOR"), !noColor.isEmpty {
        // Respect the NO_COLOR environment variable. SEE: https://www.no-color.org
        1
      } else if _terminalSupportsTrueColorANSIEscapeCodes {
        24
      } else if _terminalSupports256ColorANSIEscapeCodes {
        8
      } else {
        4 // 16-color by default
      }
      result.append(.useANSIEscapeCodes(colorBitDepth: colorBitDepth))
    }

#if os(macOS) || (os(iOS) && targetEnvironment(macCatalyst))
    // On macOS, if we are writing to a TTY (i.e. Terminal.app) and the SF Pro
    // font is installed, we can use SF Symbols characters in place of Unicode
    // pictographs. Other platforms do not generally have this font installed.
    // In case rendering with SF Symbols is causing problems (e.g. a third-party
    // terminal app is being used that doesn't support them), allow explicitly
    // toggling them with an environment variable.
    var useSFSymbols = false
    if let environmentVariable = Environment.flag(named: "SWT_SF_SYMBOLS_ENABLED") {
      useSFSymbols = environmentVariable
    } else if useANSIEscapeCodes {
      var statStruct = stat()
      useSFSymbols = (0 == stat("/Library/Fonts/SF-Pro.ttf", &statStruct))
    }
    if useSFSymbols {
      result.append(.useSFSymbols)
    }
#endif

    // If color output is enabled, load tag colors from user/package preferences
    // on disk.
    if let colorBitDepth = result.colorBitDepth, colorBitDepth > 1 {
      if let tagColors = try? loadTagColors() {
        result.append(.useTagColors(tagColors))
      }
    }

    return result
  }

  /// Whether or not the current process's standard error stream is capable of
  /// accepting and rendering ANSI escape codes.
  private static func _fileHandleSupportsANSIEscapeCodes(_ fileHandle: borrowing FileHandle) -> Bool {
    // Determine if this file handle appears to write to a Terminal window
    // capable of accepting ANSI escape codes.
    if fileHandle.isTTY {
      return true
    }

    // If the file handle is a pipe, assume the other end is using it to forward
    // output from this process to its own stderr file. This is how `swift test`
    // invokes the testing library, for example.
    if fileHandle.isPipe {
      return true
    }

    return false
  }

  /// Whether or not the system terminal claims to support 256-color ANSI escape
  /// codes.
  private static var _terminalSupports256ColorANSIEscapeCodes: Bool {
#if SWT_TARGET_OS_APPLE || os(Linux)
    if let termVariable = Environment.variable(named: "TERM") {
      return strstr(termVariable, "256") != nil
    }
    return false
#elseif os(Windows)
    // Windows does not set the "TERM" variable, so assume it supports 256-color
    // ANSI escape codes.
    true
#else
#warning("Platform-specific implementation missing: terminal colors unavailable")
    return false
#endif
  }

  /// Whether or not the system terminal claims to support true-color ANSI
  /// escape codes.
  private static var _terminalSupportsTrueColorANSIEscapeCodes: Bool {
#if SWT_TARGET_OS_APPLE || os(Linux)
    if let colortermVariable = Environment.variable(named: "COLORTERM") {
      return strstr(colortermVariable, "truecolor") != nil
    }
    return false
#elseif os(Windows)
    // Windows does not set the "COLORTERM" variable, so assume it supports
    // true-color ANSI escape codes. SEE: https://github.com/microsoft/terminal/issues/11057
    true
#else
#warning("Platform-specific implementation missing: terminal colors unavailable")
    return false
#endif
  }
#endif
}

// MARK: - Error reporting

/// A type describing an error encountered in the entry point.
private enum _EntryPointError: Error {
  /// A feature is unavailable.
  ///
  /// - Parameters:
  ///   - explanation: An explanation of the problem.
  case featureUnavailable(_ explanation: String)

  /// An argument was invalid.
  ///
  /// - Parameters:
  ///   - name: The name of the argument.
  ///   - value: The invalid value.
  case invalidArgument(_ name: String, value: String)
}

extension _EntryPointError: CustomStringConvertible {
  var description: String {
    switch self {
    case let .featureUnavailable(explanation):
      explanation
    case let .invalidArgument(name, value):
      #"Invalid value "\#(value)" for argument \#(name)"#
    }
  }
}
