//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if SWT_BUILDING_WITH_CMAKE
@_implementationOnly import _TestingInternals
#else
private import _TestingInternals
#endif

/// The common implementation of the entry point functions in this package.
///
/// - Parameters:
///   - args: A previously-parsed command-line arguments structure to interpret.
///     If `nil`, a new instance is created from the command-line arguments to
///     the current process.
///   - eventHandler: An optional event handler. The testing library always
///     writes events to the standard error stream in addition to passing them
///     to this function.
///
/// External callers cannot call this function directly. The can use
/// ``ABIv0/entryPoint-swift.type.property`` to get a reference to an ABI-stable
/// version of this function.
func entryPoint(passing args: __CommandLineArguments_v0?, eventHandler: Event.Handler?) async -> CInt {
  let exitCode = Locked(rawValue: EXIT_SUCCESS)

  do {
#if !SWT_NO_EXIT_TESTS
      // If an exit test was specified, run it. `exitTest` returns `Never`.
      if let exitTest = ExitTest.findInEnvironmentForEntryPoint() {
        await exitTest()
      }
#endif

    let args = try args ?? parseCommandLineArguments(from: CommandLine.arguments)
    // Configure the test runner.
    var configuration = try configurationForEntryPoint(from: args)

    // Set up the event handler.
    configuration.eventHandler = { [oldEventHandler = configuration.eventHandler] event, context in
      if case let .issueRecorded(issue) = event.kind, !issue.isKnown {
        exitCode.withLock { exitCode in
          exitCode = EXIT_FAILURE
        }
      }
      oldEventHandler(event, context)
    }

#if !SWT_NO_FILE_IO
    // Configure the event recorder to write events to stderr.
    var options = Event.ConsoleOutputRecorder.Options()
    options = .for(.stderr)
    options.verbosity = args.verbosity
    let eventRecorder = Event.ConsoleOutputRecorder(options: options) { string in
      try? FileHandle.stderr.write(string)
    }
    configuration.eventHandler = { [oldEventHandler = configuration.eventHandler] event, context in
      eventRecorder.record(event, in: context)
      oldEventHandler(event, context)
    }
#endif

    // If the caller specified an alternate event handler, hook it up too.
    if let eventHandler {
      configuration.eventHandler = { [oldEventHandler = configuration.eventHandler] event, context in
        eventHandler(event, context)
        oldEventHandler(event, context)
      }
    }

    if args.listTests ?? false {
      let tests = await Test.all
      for testID in listTestsForEntryPoint(tests) {
        // Print the test ID to stdout (classical CLI behavior.)
#if SWT_TARGET_OS_APPLE && !SWT_NO_FILE_IO
        try? FileHandle.stdout.write("\(testID)\n")
#else
        print(testID)
#endif
      }

      // Post an event for every discovered test. These events are turned into
      // JSON objects if JSON output is enabled.
      for test in tests {
        Event.post(.testDiscovered, for: test, testCase: nil, configuration: configuration)
      }
    } else {
      // Run the tests.
      let runner = await Runner(configuration: configuration)
      await runner.run()
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

// MARK: - Listing tests

/// List all of the given tests in the "specifier" format used by Swift Package
/// Manager.
///
/// - Parameters:
///   - tests: The tests to list.
///
/// - Returns: An array of strings representing the IDs of `tests`.
func listTestsForEntryPoint(_ tests: some Sequence<Test>) -> [String] {
  // Filter out hidden tests and test suites. Hidden tests should not generally
  // be presented to the user, and suites (XCTestCase classes) are not included
  // in the equivalent XCTest-based output.
  let tests = tests.lazy
    .filter { !$0.isSuite }
    .filter { !$0.isHidden }

  // Group tests by the name components of the tests' IDs. If the name
  // components of two tests' IDs are ambiguous, present their source locations
  // to disambiguate.
  let initialGroups = Dictionary(
    grouping: tests.lazy.map(\.id),
    by: \.nameComponents
  ).values.lazy
    .map { ($0, isAmbiguous: $0.count > 1) }

  // This operation is split to improve type-checking performance.
  return initialGroups.flatMap { testIDs, isAmbiguous in
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

// MARK: - Command-line arguments and configuration

/// A type describing the command-line arguments passed by Swift Package Manager
/// to the testing library's entry point.
///
/// - Warning: This type's definition and JSON-encoded form have not been
///   finalized yet.
///
/// - Warning: This type is used by Swift Package Manager. Do not use it
///   directly.
public struct __CommandLineArguments_v0: Sendable {
  public init() {}

  /// The value of the `--list-tests` argument.
  public var listTests: Bool?

  /// The value of the `--parallel` or `--no-parallel` argument.
  public var parallel: Bool?

  /// The value of the `--verbose` argument.
  public var verbose: Bool?

  /// The value of the `--very-verbose` argument.
  public var veryVerbose: Bool?

  /// The value of the `--quiet` argument.
  public var quiet: Bool?

  /// Storage for the ``verbosity`` property.
  private var _verbosity: Int?

  /// The value of the `--verbosity` argument.
  ///
  /// The value of this property may be synthesized from the `--verbose`,
  /// `--very-verbose`, or `--quiet` arguments.
  ///
  /// When the value of this property is greater than `0`, additional output
  /// is provided. When the value of this property is less than `0`, some
  /// output is suppressed. The exact effects of this property are
  /// implementation-defined and subject to change.
  public var verbosity: Int {
    get {
      if let _verbosity {
        return _verbosity
      } else if veryVerbose == true {
        return 2
      } else if verbose == true {
        return 1
      } else if quiet == true {
        return -1
      }
      return 0
    }
    set {
      _verbosity = newValue
    }
  }

  /// The value of the `--xunit-output` argument.
  public var xunitOutput: String?

  /// The value of the `--event-stream-output` argument.
  ///
  /// Data is written to this file in the [JSON Lines](https://jsonlines.org)
  /// text format. For each event handled by the resulting event handler, a JSON
  /// object representing it and its associated context is created and is
  /// written, followed by a single line feed (`"\n"`) character. These JSON
  /// objects are guaranteed not to contain any ASCII newline characters (`"\r"`
  /// or `"\n"`) themselves.
  ///
  /// The file can be a regular file, however to allow for streaming a named
  /// pipe is recommended. `mkfifo()` can be used on Darwin and Linux to create
  /// a named pipe; `CreateNamedPipeA()` can be used on Windows.
  ///
  /// The file is closed when this process terminates or the test run completes,
  /// whichever occurs first.
  public var eventStreamOutput: String?

  /// The version of the event stream schema to use when writing events to
  /// ``eventStreamOutput``.
  ///
  /// If the value of this property is `nil`, events are encoded verbatim (using
  /// ``Event/Snapshot``.) Otherwise, the corresponding stable schema is used
  /// (e.g. ``ABIv0/Record`` for `0`.)
  ///
  /// - Warning: The behavior of this property will change when the ABI version
  ///   0 JSON schema is finalized.
  public var eventStreamVersion: Int?

  /// The value(s) of the `--filter` argument.
  public var filter: [String]?

  /// The value(s) of the `--skip` argument.
  public var skip: [String]?

  /// The value of the `--repetitions` argument.
  public var repetitions: Int?

  /// The value of the `--repeat-until` argument.
  public var repeatUntil: String?
}

extension __CommandLineArguments_v0: Codable {
  // Explicitly list the coding keys so that storage properties like _verbosity
  // do not end up with leading underscores when encoded.
  enum CodingKeys: String, CodingKey {
    case listTests
    case parallel
    case verbose
    case veryVerbose
    case quiet
    case _verbosity = "verbosity"
    case xunitOutput
    case eventStreamOutput
    case eventStreamVersion
    case filter
    case skip
    case repetitions
    case repeatUntil
  }
}

/// Initialize this instance given a sequence of command-line arguments passed
/// from Swift Package Manager.
///
/// - Parameters:
///   - args: The command-line arguments to interpret.
///
/// This function generally assumes that Swift Package Manager has already
/// validated the passed arguments.
func parseCommandLineArguments(from args: [String]) throws -> __CommandLineArguments_v0 {
  var result = __CommandLineArguments_v0()

  // Do not consider the executable path AKA argv[0].
  let args = args.dropFirst()

  func isLastArgument(at index: [String].Index) -> Bool {
    args.index(after: index) >= args.endIndex
  }

#if !SWT_NO_FILE_IO
#if canImport(Foundation)
  // Configuration for the test run passed in as a JSON file (experimental)
  //
  // This argument should always be the first one we parse.
  //
  // NOTE: While the output event stream is opened later, it is necessary to
  // open the configuration file early (here) in order to correctly construct
  // the resulting __CommandLineArguments_v0 instance.
  if let configurationIndex = args.firstIndex(of: "--configuration-path") ?? args.firstIndex(of: "--experimental-configuration-path"),
     !isLastArgument(at: configurationIndex) {
    let path = args[args.index(after: configurationIndex)]
    let file = try FileHandle(forReadingAtPath: path)
    let configurationJSON = try file.readToEnd()
    result = try configurationJSON.withUnsafeBufferPointer { configurationJSON in
      try JSON.decode(__CommandLineArguments_v0.self, from: .init(configurationJSON))
    }

    // NOTE: We don't return early or block other arguments here: a caller is
    // allowed to pass a configuration AND e.g. "--verbose" and they'll both be
    // respected (it should be the least "surprising" outcome of passing both.)
  }

  // Event stream output (experimental)
  if let eventOutputIndex = args.firstIndex(of: "--event-stream-output") ?? args.firstIndex(of: "--experimental-event-stream-output"),
     !isLastArgument(at: eventOutputIndex) {
    result.eventStreamOutput = args[args.index(after: eventOutputIndex)]
  }
  // Event stream output (experimental)
  if let eventOutputVersionIndex = args.firstIndex(of: "--event-stream-version") ?? args.firstIndex(of: "--experimental-event-stream-version"),
     !isLastArgument(at: eventOutputVersionIndex) {
    result.eventStreamVersion = Int(args[args.index(after: eventOutputVersionIndex)])
  }
#endif

  // XML output
  if let xunitOutputIndex = args.firstIndex(of: "--xunit-output"), !isLastArgument(at: xunitOutputIndex) {
    result.xunitOutput = args[args.index(after: xunitOutputIndex)]
  }
#endif

  if args.contains("--list-tests") {
    result.listTests = true
  }

  // Parallelization (on by default)
  if args.contains("--no-parallel") {
    result.parallel = false
  }

  // Verbosity
  if let verbosityIndex = args.firstIndex(of: "--verbosity"), !isLastArgument(at: verbosityIndex),
     let verbosity = Int(args[args.index(after: verbosityIndex)]) {
    result.verbosity = verbosity
  }
  if args.contains("--verbose") || args.contains("-v") {
    result.verbose = true
  }
  if args.contains("--very-verbose") || args.contains("--vv") {
    result.veryVerbose = true
  }
  if args.contains("--quiet") || args.contains("-q") {
    result.quiet = true
  }

  // Filtering
  func filterValues(forArgumentsWithLabel label: String) -> [String] {
    args.indices.lazy
      .filter { args[$0] == label && $0 < args.endIndex }
      .map { args[args.index(after: $0)] }
  }
  let filter = filterValues(forArgumentsWithLabel: "--filter")
  if !filter.isEmpty {
    result.filter = result.filter.map { $0 + filter } ?? filter
  }
  let skip = filterValues(forArgumentsWithLabel: "--skip")
  if !skip.isEmpty {
    result.skip = result.skip.map { $0 + skip } ?? skip
  }

  // Set up the iteration policy for the test run.
  if let repetitionsIndex = args.firstIndex(of: "--repetitions"), !isLastArgument(at: repetitionsIndex) {
    result.repetitions = Int(args[args.index(after: repetitionsIndex)])
  }
  if let repeatUntilIndex = args.firstIndex(of: "--repeat-until"), !isLastArgument(at: repeatUntilIndex) {
    result.repeatUntil = args[args.index(after: repeatUntilIndex)]
  }

  return result
}

/// Get an instance of ``Configuration`` given a sequence of command-line
/// arguments passed from Swift Package Manager.
///
/// - Parameters:
///   - args: A previously-parsed command-line arguments structure to interpret.
///
/// - Returns: An instance of ``Configuration``. Note that the caller is
///   responsible for setting this instance's ``Configuration/eventHandler``
///   property.
///
/// - Throws: If an argument is invalid, such as a malformed regular expression.
@_spi(ForToolsIntegrationOnly)
public func configurationForEntryPoint(from args: __CommandLineArguments_v0) throws -> Configuration {
  var configuration = Configuration()

  // Parallelization (on by default)
  configuration.isParallelizationEnabled = args.parallel ?? true

#if !SWT_NO_FILE_IO
  // XML output
  if let xunitOutputPath = args.xunitOutput {
    // Open the XML file for writing.
    let file = try FileHandle(forWritingAtPath: xunitOutputPath)

    // Set up the XML recorder.
    let xmlRecorder = Event.JUnitXMLRecorder { string in
      try? file.write(string)
    }

    configuration.eventHandler = { [oldEventHandler = configuration.eventHandler] event, context in
      _ = xmlRecorder.record(event, in: context)
      oldEventHandler(event, context)
    }
  }

#if canImport(Foundation)
  // Event stream output (experimental)
  if let eventStreamOutputPath = args.eventStreamOutput {
    let file = try FileHandle(forWritingAtPath: eventStreamOutputPath)
    let eventHandler = try eventHandlerForStreamingEvents(version: args.eventStreamVersion) { json in
      try? _writeJSONLine(json, to: file)
    }
    configuration.eventHandler = { [oldEventHandler = configuration.eventHandler] event, context in
      eventHandler(event, context)
      oldEventHandler(event, context)
    }
  }
#endif
#endif

  // Filtering
  var filters = [Configuration.TestFilter]()
  func testFilter(forRegularExpressions regexes: [String]?, label: String, membership: Configuration.TestFilter.Membership) throws -> Configuration.TestFilter {
    guard let regexes, !regexes.isEmpty else {
      // Return early if empty, even though the `reduce` logic below can handle
      // this case, in order to avoid the `#available` guard.
      return .unfiltered
    }

    guard #available(_regexAPI, *) else {
      throw _EntryPointError.featureUnavailable("The `\(label)' option is not supported on this OS version.")
    }
    return try Configuration.TestFilter(membership: membership, matchingAnyOf: regexes)
  }
  filters.append(try testFilter(forRegularExpressions: args.filter, label: "--filter", membership: .including))
  filters.append(try testFilter(forRegularExpressions: args.skip, label: "--skip", membership: .excluding))

  configuration.testFilter = filters.reduce(.unfiltered) { $0.combining(with: $1) }

  // Set up the iteration policy for the test run.
  var repetitionPolicy: Configuration.RepetitionPolicy = .once
  var hadExplicitRepetitionCount = false
  if let repetitionCount = args.repetitions, repetitionCount > 0 {
    repetitionPolicy.maximumIterationCount = repetitionCount
    hadExplicitRepetitionCount = true
  }
  if let repeatUntil = args.repeatUntil {
    switch repeatUntil.lowercased() {
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

#if !SWT_NO_EXIT_TESTS
  // Enable exit test handling via __swiftPMEntryPoint().
  configuration.exitTestHandler = ExitTest.handlerForEntryPoint()
#endif

  return configuration
}

#if canImport(Foundation) && !SWT_NO_FILE_IO
/// Create an event handler that streams events to the given file using the
/// specified ABI version.
///
/// - Parameters:
///   - version: The ABI version to use.
///   - eventHandler: The event handler to forward encoded events to. The
///     encoding of events depends on `version`.
///
/// - Returns: An event handler.
///
/// - Throws: If `version` is not a supported ABI version.
func eventHandlerForStreamingEvents(version: Int?, forwardingTo eventHandler: @escaping @Sendable (UnsafeRawBufferPointer) -> Void) throws -> Event.Handler {
  switch version {
  case nil:
    eventHandlerForStreamingEventSnapshots(to: eventHandler)
  case 0:
    ABIv0.Record.eventHandler(forwardingTo: eventHandler)
  case let .some(unsupportedVersion):
    throw _EntryPointError.invalidArgument("--event-stream-version", value: "\(unsupportedVersion)")
  }
}

/// Post-process encoded JSON and write it to a file.
///
/// - Parameters:
///   - json: The JSON to write.
///   - file: The file to write to.
///
/// - Throws: Whatever is thrown when writing to `file`.
private func _writeJSONLine(_ json: UnsafeRawBufferPointer, to file: borrowing FileHandle) throws {
  func isASCIINewline(_ byte: UInt8) -> Bool {
    byte == UInt8(ascii: "\r") || byte == UInt8(ascii: "\n")
  }

  func write(_ json: UnsafeRawBufferPointer) throws {
    try file.withLock {
      try file.write(json)
      try file.write("\n")
    }
  }

  // We don't actually expect the JSON encoder to produce output containing
  // newline characters, so in debug builds we'll log a diagnostic message.
  if _slowPath(json.contains(where: isASCIINewline)) {
#if DEBUG
    let message = Event.ConsoleOutputRecorder.warning(
      "JSON encoder produced one or more newline characters while encoding an event snapshot. Please file a bug report at https://github.com/apple/swift-testing/issues/new",
      options: .for(.stderr)
    )
#if SWT_TARGET_OS_APPLE
    try? FileHandle.stderr.write(message)
#else
    print(message)
#endif
#endif

    // Remove the newline characters to conform to JSON lines specification.
    var json = Array(json)
    json.removeAll(where: isASCIINewline)
    try json.withUnsafeBytes { json in
      try write(json)
    }
  } else {
    // No newlines found, no need to copy the buffer.
    try write(json)
  }
}
#endif

// MARK: - Command-line interface options

extension Event.ConsoleOutputRecorder.Options {
#if !SWT_NO_FILE_IO
  /// The set of options to use when writing to the standard error stream.
  static func `for`(_ fileHandle: borrowing FileHandle) -> Self {
    var result = Self()

    result.useANSIEscapeCodes = _fileHandleSupportsANSIEscapeCodes(fileHandle)
    if result.useANSIEscapeCodes {
      if let noColor = Environment.variable(named: "NO_COLOR"), !noColor.isEmpty {
        // Respect the NO_COLOR environment variable. SEE: https://www.no-color.org
        result.ansiColorBitDepth = 1
      } else if _terminalSupportsTrueColorANSIEscapeCodes {
        result.ansiColorBitDepth = 24
      } else if _terminalSupports256ColorANSIEscapeCodes {
        result.ansiColorBitDepth = 8
      }
    }

#if os(macOS) || (os(iOS) && targetEnvironment(macCatalyst))
    // On macOS, if we are writing to a TTY (i.e. Terminal.app) and the SF Pro
    // font is installed, we can use SF Symbols characters in place of Unicode
    // pictographs. Other platforms do not generally have this font installed.
    // In case rendering with SF Symbols is causing problems (e.g. a third-party
    // terminal app is being used that doesn't support them), allow explicitly
    // toggling them with an environment variable.
    if let environmentVariable = Environment.flag(named: "SWT_SF_SYMBOLS_ENABLED") {
      result.useSFSymbols = environmentVariable
    } else {
      var statStruct = stat()
      result.useSFSymbols = (0 == stat("/Library/Fonts/SF-Pro.ttf", &statStruct))
    }
#endif

    // If color output is enabled, load tag colors from user/package preferences
    // on disk.
    if result.useANSIEscapeCodes && result.ansiColorBitDepth > 1 {
      if let tagColors = try? loadTagColors() {
        result.tagColors = tagColors
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
