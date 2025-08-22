//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

private import _TestingInternals

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
/// - Returns: An exit code representing the result of running tests.
///
/// External callers cannot call this function directly. The can use
/// ``ABI/v0/entryPoint-swift.type.property`` to get a reference to an
/// ABI-stable version of this function.
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
      if case let .issueRecorded(issue) = event.kind, issue.isFailure {
        exitCode.withLock { exitCode in
          exitCode = EXIT_FAILURE
        }
      }
      oldEventHandler(event, context)
    }
    configuration.verbosity = args.verbosity

#if !SWT_NO_FILE_IO
    // Configure the event recorder to write events to stderr.
    if configuration.verbosity > .min {
      // Check for experimental console output flag
      if Environment.flag(named: "SWT_ENABLE_EXPERIMENTAL_CONSOLE_OUTPUT") == true {
        // Use experimental AdvancedConsoleOutputRecorder
        var advancedOptions = Event.AdvancedConsoleOutputRecorder<ABI.HighestVersion>.Options()
        advancedOptions.base = .for(.stderr)

        let eventRecorder = Event.AdvancedConsoleOutputRecorder<ABI.HighestVersion>(options: advancedOptions) { string in
          try? FileHandle.stderr.write(string)
        }

        configuration.eventHandler = { [oldEventHandler = configuration.eventHandler] event, context in
          eventRecorder.record(event, in: context)
          oldEventHandler(event, context)
        }
      } else {
        // Use the standard console output recorder (default behavior)
        let eventRecorder = Event.ConsoleOutputRecorder(options: .for(.stderr)) { string in
          try? FileHandle.stderr.write(string)
        }
        configuration.eventHandler = { [oldEventHandler = configuration.eventHandler] event, context in
          eventRecorder.record(event, in: context)
          oldEventHandler(event, context)
        }
      }
    }
#endif

    // If the caller specified an alternate event handler, hook it up too.
    if let eventHandler {
      configuration.eventHandler = { [oldEventHandler = configuration.eventHandler] event, context in
        eventHandler(event, context)
        oldEventHandler(event, context)
      }
    }

    // The set of matching tests (or, in the case of `swift test list`, the set
    // of all tests.)
    let tests: [Test]

    if args.listTests ?? false {
      tests = await Array(Test.all)

      if args.verbosity > .min {
        for testID in listTestsForEntryPoint(tests, verbosity: args.verbosity) {
          // Print the test ID to stdout (classical CLI behavior.)
#if SWT_TARGET_OS_APPLE && !SWT_NO_FILE_IO
          try? FileHandle.stdout.write("\(testID)\n")
#else
          print(testID)
#endif
        }
      }

      // Post an event for every discovered test. These events are turned into
      // JSON objects if JSON output is enabled.
      for test in tests {
        Event.post(.testDiscovered, for: (test, nil), configuration: configuration)
      }
    } else {
      // Run the tests.
      let runner = await Runner(configuration: configuration)
      tests = runner.tests
      await runner.run()
    }

    // If there were no matching tests, exit with a dedicated exit code so that
    // the caller (assumed to be Swift Package Manager) can implement special
    // handling.
    if tests.isEmpty {
      exitCode.withLock { exitCode in
        if exitCode == EXIT_SUCCESS {
          exitCode = EXIT_NO_TESTS_FOUND
        }
      }
    }
  } catch {
#if !SWT_NO_FILE_IO
    try? FileHandle.stderr.write("\(error)\n")
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
///   - verbosity: The verbosity level. A level higher than `0` forces the
///     inclusion of source locations for all tests.
///
/// - Returns: An array of strings representing the IDs of `tests`.
func listTestsForEntryPoint(_ tests: some Sequence<Test>, verbosity: Int) -> [String] {
  // Filter out hidden tests and test suites. Hidden tests should not generally
  // be presented to the user, and suites (XCTestCase classes) are not included
  // in the equivalent XCTest-based output.
  let tests = tests.lazy
    .filter { !$0.isSuite }
    .filter { !$0.isHidden }

  // Early exit for verbose output (no need to check for ambiguity.)
  if verbosity > 0 {
    return tests.lazy
      .map(\.id)
      .map(String.init(describing:))
      .sorted(by: <)
  }

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

  /// The value of the `--symbolicate-backtraces` argument.
  public var symbolicateBacktraces: String?

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

  /// The value of the `--event-stream-output-path` argument.
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
  public var eventStreamOutputPath: String?

  /// The value of the `--event-stream-version` or `--experimental-event-stream-version`
  /// argument, representing the version of the event stream schema to use when
  /// writing events to ``eventStreamOutput``.
  ///
  /// This property is internal because its type is internal. External users of
  /// this structure can use the ``eventStreamSchemaVersion`` property to get or
  /// set the value of this property.
  var eventStreamVersionNumber: VersionNumber?

  /// The value of the `--event-stream-version` or `--experimental-event-stream-version`
  /// argument, representing the version of the event stream schema to use when
  /// writing events to ``eventStreamOutput``.
  ///
  /// The value of this property is a 1- or 3-component version string such as
  /// `"0"` or `"1.2.3"`. The corresponding stable schema is used to encode
  /// events to the event stream. ``ABI/Record`` is used if the value of this
  /// property is `"0.0.0"` or higher. The testing library compares components
  /// individually, so `"1.2"` is less than `"1.20"`.
  ///
  /// If the value of this property is `nil`, the testing library assumes that
  /// the current supported (non-experimental) version should be used.
  public var eventStreamSchemaVersion: String? {
    get {
      eventStreamVersionNumber.map { String(describing: $0) }
    }
    set {
      eventStreamVersionNumber = newValue.flatMap { newValue in
        guard let newValue = VersionNumber(newValue) else {
          preconditionFailure("Invalid event stream version number '\(newValue)'. Specify a version number of the form 'major.minor.patch'.")
        }
        return newValue
      }
    }
  }

  /// The value(s) of the `--filter` argument.
  public var filter: [String]?

  /// The value(s) of the `--skip` argument.
  public var skip: [String]?

  /// Whether or not to include tests with the `.hidden` trait when constructing
  /// a test filter based on these arguments.
  ///
  /// This property is intended for use in testing the testing library itself.
  /// It is not parsed as a command-line argument.
  var includeHiddenTests: Bool?

  /// The value of the `--repetitions` argument.
  public var repetitions: Int?

  /// The value of the `--repeat-until` argument.
  public var repeatUntil: String?

  /// The value of the `--attachments-path` argument.
  public var attachmentsPath: String?
}

extension __CommandLineArguments_v0: Codable {
  // Explicitly list the coding keys so that storage properties like _verbosity
  // do not end up with leading underscores when encoded.
  enum CodingKeys: String, CodingKey {
    case listTests
    case parallel
    case symbolicateBacktraces
    case verbose
    case veryVerbose
    case quiet
    case _verbosity = "verbosity"
    case xunitOutput
    case eventStreamOutputPath
    case eventStreamVersionNumber = "eventStreamVersion"
    case filter
    case skip
    case repetitions
    case repeatUntil
    case attachmentsPath
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

  // Event stream output
  if let eventOutputIndex = args.firstIndex(of: "--event-stream-output-path") ?? args.firstIndex(of: "--experimental-event-stream-output"),
     !isLastArgument(at: eventOutputIndex) {
    result.eventStreamOutputPath = args[args.index(after: eventOutputIndex)]
  }
  // Event stream version
  do {
    var eventOutputVersionIndex: Array<String>.Index?
    var allowExperimental = false
    eventOutputVersionIndex = args.firstIndex(of: "--event-stream-version")
    if eventOutputVersionIndex == nil {
      eventOutputVersionIndex = args.firstIndex(of: "--experimental-event-stream-version")
      if eventOutputVersionIndex != nil {
        allowExperimental = true
      }
    }
    if let eventOutputVersionIndex, !isLastArgument(at: eventOutputVersionIndex) {
      let versionString = args[args.index(after: eventOutputVersionIndex)]

      // If the caller specified a version that could not be parsed, treat it as
      // an invalid argument.
      guard let eventStreamVersion = VersionNumber(versionString) else {
        let argument = allowExperimental ? "--experimental-event-stream-version" : "--event-stream-version"
        throw _EntryPointError.invalidArgument(argument, value: versionString)
      }

      // If the caller specified an experimental ABI version, they must
      // explicitly use --experimental-event-stream-version, otherwise it's
      // treated as unsupported.
      if eventStreamVersion > ABI.CurrentVersion.versionNumber, !allowExperimental {
        throw _EntryPointError.experimentalABIVersion(eventStreamVersion)
      }

      result.eventStreamVersionNumber = eventStreamVersion
    }
  }
#endif

  // XML output
  if let xunitOutputIndex = args.firstIndex(of: "--xunit-output"), !isLastArgument(at: xunitOutputIndex) {
    result.xunitOutput = args[args.index(after: xunitOutputIndex)]
  }

  // Attachment output
  if let attachmentsPathIndex = args.firstIndex(of: "--attachments-path") ?? args.firstIndex(of: "--experimental-attachments-path"),
     !isLastArgument(at: attachmentsPathIndex) {
    result.attachmentsPath = args[args.index(after: attachmentsPathIndex)]
  }
#endif

  if args.contains("--list-tests") {
    result.listTests = true
  } else if args.first == "list" {
    // Allow the "list" subcommand explicitly in place of "--list-tests". This
    // makes invocation from e.g. Wasmtime a bit more intuitive/idiomatic.
    result.listTests = true
  }

  // Parallelization (on by default)
  if args.contains("--no-parallel") {
    result.parallel = false
  }

  // Whether or not to symbolicate backtraces in the event stream.
  if let symbolicateBacktracesIndex = args.firstIndex(of: "--symbolicate-backtraces"), !isLastArgument(at: symbolicateBacktracesIndex) {
    result.symbolicateBacktraces = args[args.index(after: symbolicateBacktracesIndex)]
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

  // Whether or not to symbolicate backtraces in the event stream.
  if let symbolicateBacktraces = args.symbolicateBacktraces {
    switch symbolicateBacktraces.lowercased() {
    case "mangled", "on", "true":
      configuration.backtraceSymbolicationMode = .mangled
    case "demangled":
      configuration.backtraceSymbolicationMode = .demangled
    default:
      throw _EntryPointError.invalidArgument("--symbolicate-backtraces", value: symbolicateBacktraces)

    }
  }

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

  // Attachment output.
  if let attachmentsPath = args.attachmentsPath {
    guard fileExists(atPath: attachmentsPath) else {
      throw _EntryPointError.invalidArgument("---attachments-path", value: attachmentsPath)
    }
    configuration.attachmentsPath = attachmentsPath
  }

#if canImport(Foundation)
  // Event stream output
  if let eventStreamOutputPath = args.eventStreamOutputPath {
    let file = try FileHandle(forWritingAtPath: eventStreamOutputPath)
    let eventHandler = try eventHandlerForStreamingEvents(withVersionNumber: args.eventStreamVersionNumber, encodeAsJSONLines: true) { json in
      _ = try? file.withLock {
        try file.write(json)
        try file.write("\n")
      }
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
  if args.includeHiddenTests == true {
    configuration.testFilter.includeHiddenTests = true
  }

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

  // Warning issues (experimental).
  switch args.eventStreamVersionNumber {
  case .some(..<ABI.v6_3.versionNumber):
    // If the event stream version was explicitly specified to a value < 6.3,
    // disable the warning issue event to maintain legacy behavior.
    configuration.eventHandlingOptions.isWarningIssueRecordedEventEnabled = false
  default:
    // Otherwise the requested event stream version is ≥ 6.3, so don't change
    // the warning issue event setting.
    break
  }

  return configuration
}

#if canImport(Foundation) && (!SWT_NO_FILE_IO || !SWT_NO_ABI_ENTRY_POINT)
/// Create an event handler that streams events to the given file using the
/// specified ABI version.
///
/// - Parameters:
///   - versionNumber: The numeric value of the ABI version to use.
///   - encodeAsJSONLines: Whether or not to ensure JSON passed to
///     `eventHandler` is encoded as JSON Lines (i.e. that it does not contain
///     extra newlines.)
///   - targetEventHandler: The event handler to forward encoded events to. The
///     encoding of events depends on `version`.
///
/// - Returns: An event handler.
///
/// - Throws: If `version` is not a supported ABI version.
func eventHandlerForStreamingEvents(
  withVersionNumber versionNumber: VersionNumber?,
  encodeAsJSONLines: Bool,
  forwardingTo targetEventHandler: @escaping @Sendable (UnsafeRawBufferPointer) -> Void
) throws -> Event.Handler {
  let versionNumber = versionNumber ?? ABI.CurrentVersion.versionNumber
  guard let abi = ABI.version(forVersionNumber: versionNumber) else {
    throw _EntryPointError.invalidArgument("--event-stream-version", value: "\(versionNumber)")
  }
  return abi.eventHandler(encodeAsJSONLines: encodeAsJSONLines, forwardingTo: targetEventHandler)
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
      } else if _terminalSupports16ColorANSIEscapeCodes {
        result.ansiColorBitDepth = 4
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
      result.useSFSymbols = (0 == access("/Library/Fonts/SF-Pro.ttf", F_OK))
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

#if !SWT_NO_PIPES
    // If the file handle is a pipe, assume the other end is using it to forward
    // output from this process to its own stderr file. This is how `swift test`
    // invokes the testing library, for example.
    if fileHandle.isPipe {
      return true
    }
#endif

    return false
  }

  /// Whether or not the system terminal claims to support 16-color ANSI escape
  /// codes.
  private static var _terminalSupports16ColorANSIEscapeCodes: Bool {
#if SWT_TARGET_OS_APPLE || os(Linux) || os(FreeBSD) || os(OpenBSD) || os(Android)
    if let termVariable = Environment.variable(named: "TERM") {
      return termVariable != "dumb"
    }
    return false
#elseif os(Windows)
    // Windows does not set the "TERM" variable, so assume it supports 16-color
    // ANSI escape codes.
    true
#elseif os(WASI)
    // The "Terminal" under WASI can be assumed to be the browser's JavaScript
    // console, which we don't expect supports color escape codes.
    false
#else
#warning("Platform-specific implementation missing: terminal colors unavailable")
    return false
#endif
  }

  /// Whether or not the system terminal claims to support 256-color ANSI escape
  /// codes.
  private static var _terminalSupports256ColorANSIEscapeCodes: Bool {
#if SWT_TARGET_OS_APPLE || os(Linux) || os(FreeBSD) || os(OpenBSD) || os(Android)
    if let termVariable = Environment.variable(named: "TERM") {
      return strstr(termVariable, "256") != nil
    }
    return false
#elseif os(Windows)
    // Windows does not set the "TERM" variable, so assume it supports 256-color
    // ANSI escape codes.
    true
#elseif os(WASI)
    // The "Terminal" under WASI can be assumed to be the browser's JavaScript
    // console, which we don't expect supports color escape codes.
    false
#else
#warning("Platform-specific implementation missing: terminal colors unavailable")
    return false
#endif
  }

  /// Whether or not the system terminal claims to support true-color ANSI
  /// escape codes.
  private static var _terminalSupportsTrueColorANSIEscapeCodes: Bool {
#if SWT_TARGET_OS_APPLE || os(Linux) || os(FreeBSD) || os(OpenBSD) || os(Android)
    if let colortermVariable = Environment.variable(named: "COLORTERM") {
      return strstr(colortermVariable, "truecolor") != nil
    }
    return false
#elseif os(Windows)
    // Windows does not set the "COLORTERM" variable, so assume it supports
    // true-color ANSI escape codes. SEE: https://github.com/microsoft/terminal/issues/11057
    true
#elseif os(WASI)
    // The "Terminal" under WASI can be assumed to be the browser's JavaScript
    // console, which we don't expect supports color escape codes.
    false
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

  /// The specified ABI version is experimental, but the caller did not
  /// use `--experimental-event-stream-version` to specify it.
  ///
  /// - Parameters:
  ///   - versionNumber: The experimental ABI version number.
  case experimentalABIVersion(_ versionNumber: VersionNumber)
}

extension _EntryPointError: CustomStringConvertible {
  var description: String {
    switch self {
    case let .featureUnavailable(explanation):
      explanation
    case let .invalidArgument(name, value):
      #"Invalid value "\#(value)" for argument \#(name)"#
    case let .experimentalABIVersion(versionNumber):
      "Event stream version \(versionNumber) is experimental. Use --experimental-event-stream-version to enable it."
    }
  }
}

// MARK: - Deprecated

extension __CommandLineArguments_v0 {
  @available(*, deprecated, message: "Use eventStreamSchemaVersion instead.")
  public var eventStreamVersion: Int? {
    get {
      eventStreamVersionNumber.map(\.majorComponent).map(Int.init)
    }
    set {
      eventStreamVersionNumber = newValue.map { VersionNumber(majorComponent: .init(clamping: $0), minorComponent: 0) }
    }
  }
}
