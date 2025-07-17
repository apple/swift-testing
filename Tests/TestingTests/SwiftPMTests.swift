//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

@testable @_spi(Experimental) @_spi(ForToolsIntegrationOnly) import Testing
private import _TestingInternals

#if canImport(Foundation)
private import Foundation
#endif

private func configurationForEntryPoint(withArguments args: [String]) throws -> Configuration {
  let args = try parseCommandLineArguments(from: args)
  return try configurationForEntryPoint(from: args)
}

@Suite("Swift Package Manager Integration Tests")
struct SwiftPMTests {
  @Test("Command line arguments are available")
  func commandLineArguments() {
    // We can't meaningfully check the actual values of this process' arguments,
    // but we can check that the arguments() function has a non-empty result.
    #expect(!CommandLine.arguments.isEmpty)
  }

  @Test("EXIT_NO_TESTS_FOUND is unique")
  func valueOfEXIT_NO_TESTS_FOUND() {
    #expect(EXIT_NO_TESTS_FOUND != EXIT_SUCCESS)
    #expect(EXIT_NO_TESTS_FOUND != EXIT_FAILURE)
  }

  @Test("--parallel/--no-parallel argument")
  func parallel() throws {
    var configuration = try configurationForEntryPoint(withArguments: ["PATH"])
    #expect(configuration.isParallelizationEnabled)

    configuration = try configurationForEntryPoint(withArguments: ["PATH", "--parallel"])
    #expect(configuration.isParallelizationEnabled)

    configuration = try configurationForEntryPoint(withArguments: ["PATH", "--no-parallel"])
    #expect(!configuration.isParallelizationEnabled)
  }

  @Test("--symbolicate-backtraces argument",
    arguments: [
      (String?.none, Backtrace.SymbolicationMode?.none),
      ("mangled", .mangled), ("on", .mangled), ("true", .mangled),
      ("demangled", .demangled),
    ]
  )
  func symbolicateBacktraces(argumentValue: String?, expectedMode: Backtrace.SymbolicationMode?) throws {
    let configuration = if let argumentValue {
      try configurationForEntryPoint(withArguments: ["PATH", "--symbolicate-backtraces", argumentValue])
    } else {
      try configurationForEntryPoint(withArguments: ["PATH"])
    }
    #expect(configuration.backtraceSymbolicationMode == expectedMode)
  }

  @Test("No --filter or --skip argument")
  func defaultFiltering() async throws {
    let configuration = try configurationForEntryPoint(withArguments: ["PATH"])
    let test1 = Test(name: "hello") {}
    let test2 = Test(name: "goodbye") {}
    let plan = await Runner.Plan(tests: [test1, test2], configuration: configuration)
    let planTests = plan.steps.map(\.test)
    #expect(planTests.contains(test1))
    #expect(planTests.contains(test2))
  }

  @Test("--filter argument")
  @available(_regexAPI, *)
  func filter() async throws {
    let configuration = try configurationForEntryPoint(withArguments: ["PATH", "--filter", "hello"])
    let test1 = Test(name: "hello") {}
    let test2 = Test(name: "goodbye") {}
    let plan = await Runner.Plan(tests: [test1, test2], configuration: configuration)
    let planTests = plan.steps.map(\.test)
    #expect(planTests.contains(test1))
    #expect(!planTests.contains(test2))
  }

  @Test("Multiple --filter arguments")
  @available(_regexAPI, *)
  func multipleFilter() async throws {
    let configuration = try configurationForEntryPoint(withArguments: ["PATH", "--filter", "hello", "--filter", "sorry"])
    let test1 = Test(name: "hello") {}
    let test2 = Test(name: "goodbye") {}
    let test3 = Test(name: "sorry") {}
    let plan = await Runner.Plan(tests: [test1, test2, test3], configuration: configuration)
    let planTests = plan.steps.map(\.test)
    #expect(planTests.contains(test1))
    #expect(!planTests.contains(test2))
    #expect(planTests.contains(test3))
  }

  @Test("--filter or --skip argument with bad regex")
  @available(_regexAPI, *)
  func badArguments() throws {
    #expect(throws: (any Error).self) {
      _ = try configurationForEntryPoint(withArguments: ["PATH", "--filter", "("])
    }
    #expect(throws: (any Error).self) {
      _ = try configurationForEntryPoint(withArguments: ["PATH", "--skip", ")"])
    }
  }

  @Test("--filter with no matches")
  @available(_regexAPI, *)
  func filterWithNoMatches() async {
    var args = __CommandLineArguments_v0()
    args.filter = ["NOTHING_MATCHES_THIS_TEST_NAME_HOPEFULLY"]
    args.verbosity = .min
    let exitCode = await __swiftPMEntryPoint(passing: args) as CInt
    #expect(exitCode == EXIT_NO_TESTS_FOUND)
  }

  @Test("--skip argument")
  @available(_regexAPI, *)
  func skip() async throws {
    let configuration = try configurationForEntryPoint(withArguments: ["PATH", "--skip", "hello"])
    let test1 = Test(name: "hello") {}
    let test2 = Test(name: "goodbye") {}
    let plan = await Runner.Plan(tests: [test1, test2], configuration: configuration)
    let planTests = plan.steps.map(\.test)
    #expect(!planTests.contains(test1))
    #expect(planTests.contains(test2))
  }

  @Test(".hidden trait", .tags(.traitRelated))
  func hidden() async throws {
    let configuration = try configurationForEntryPoint(withArguments: ["PATH"])
    let test1 = Test(name: "hello") {}
    let test2 = Test(.hidden, name: "goodbye") {}
    let plan = await Runner.Plan(tests: [test1, test2], configuration: configuration)
    let planTests = plan.steps.map(\.test)
    #expect(planTests.contains(test1))
    #expect(!planTests.contains(test2))
  }

  @Test("--filter/--skip arguments and .hidden trait")
  @available(_regexAPI, *)
  func filterAndSkipAndHidden() async throws {
    let configuration = try configurationForEntryPoint(withArguments: ["PATH", "--filter", "hello", "--skip", "hello2"])
    let test1 = Test(name: "hello") {}
    let test2 = Test(name: "hello2") {}
    let test3 = Test(.hidden, name: "hello") {}
    let test4 = Test(.hidden, name: "hello2") {}
    let plan = await Runner.Plan(tests: [test1, test2, test3, test4], configuration: configuration)
    let planTests = plan.steps.map(\.test)
    #expect(planTests.contains(test1))
    #expect(!planTests.contains(test2))
    #expect(!planTests.contains(test3))
    #expect(!planTests.contains(test4))
  }

#if !SWT_NO_FILE_IO
  @Test("--xunit-output argument (bad path)")
  func xunitOutputWithBadPath() {
    // Test that a bad path produces an error.
    #expect(throws: CError.self) {
      _ = try configurationForEntryPoint(withArguments: ["PATH", "--xunit-output", "/nonexistent/path/we/cannot/write/to"])
    }
  }

  @Test("--xunit-output argument (missing path)")
  func xunitOutputWithMissingPath() throws {
    // Test that a missing path doesn't read off the end of the argument array.
    let args = try parseCommandLineArguments(from: ["PATH", "--xunit-output"])
    #expect(args.xunitOutput == nil)
  }

  @Test("--xunit-output argument (writes to file)")
  func xunitOutputIsWrittenToFile() throws {
    // Test that a file is opened when requested. Testing of the actual output
    // occurs in ConsoleOutputRecorderTests.
    let tempDirPath = try temporaryDirectory()
    let temporaryFilePath = appendPathComponent("\(UInt64.random(in: 0 ..< .max))", to: tempDirPath)
    defer {
      _ = remove(temporaryFilePath)
    }
    do {
      let configuration = try configurationForEntryPoint(withArguments: ["PATH", "--xunit-output", temporaryFilePath])
      let eventContext = Event.Context(test: nil, testCase: nil, configuration: nil)
      configuration.handleEvent(Event(.runStarted, testID: nil, testCaseID: nil), in: eventContext)
      configuration.handleEvent(Event(.runEnded, testID: nil, testCaseID: nil), in: eventContext)
    }

    let fileHandle = try FileHandle(forReadingAtPath: temporaryFilePath)
    let fileContents = try fileHandle.readToEnd()
    #expect(!fileContents.isEmpty)
    #expect(fileContents.contains(UInt8(ascii: "<")))
    #expect(fileContents.contains(UInt8(ascii: ">")))
  }

#if canImport(Foundation)
  @Test("--configuration-path argument", arguments: [
    "--configuration-path", "--experimental-configuration-path",
  ])
  func configurationPath(argumentName: String) async throws {
    let tempDirPath = try temporaryDirectory()
    let temporaryFilePath = appendPathComponent("\(UInt64.random(in: 0 ..< .max))", to: tempDirPath)
    defer {
      _ = remove(temporaryFilePath)
    }
    do {
      let fileHandle = try FileHandle(forWritingAtPath: temporaryFilePath)
      try fileHandle.write(
        """
        {
          "verbosity": 50,
          "filter": ["hello", "world"],
          "parallel": false
        }
        """
      )
    }
    let args = try parseCommandLineArguments(from: ["PATH", argumentName, temporaryFilePath])
    #expect(args.verbose == nil)
    #expect(args.quiet == nil)
    #expect(args.verbosity == 50)
    #expect(args.filter == ["hello", "world"])
    #expect(args.skip == nil)
    #expect(args.parallel == false)
  }

  @Test("--event-stream-output-path argument (writes to a stream and can be read back)",
        arguments: [
          ("--event-stream-output-path", "--event-stream-version", ABI.v0.versionNumber),
          ("--experimental-event-stream-output", "--experimental-event-stream-version", ABI.v0.versionNumber),
          ("--experimental-event-stream-output", "--experimental-event-stream-version", ABI.v1.versionNumber),
        ])
  func eventStreamOutput(outputArgumentName: String, versionArgumentName: String, version: Int) async throws {
    switch version {
    case ABI.v0.versionNumber:
      try await eventStreamOutput(outputArgumentName: outputArgumentName, versionArgumentName: versionArgumentName, version: ABI.v0.self)
    case ABI.v1.versionNumber:
      try await eventStreamOutput(outputArgumentName: outputArgumentName, versionArgumentName: versionArgumentName, version: ABI.v1.self)
    default:
      Issue.record("Unreachable event stream version \(version)")
    }
  }

  func eventStreamOutput<V>(outputArgumentName: String, versionArgumentName: String, version: V.Type) async throws where V: ABI.Version {
    // Test that JSON records are successfully streamed to a file and can be
    // read back into memory and decoded.
    let tempDirPath = try temporaryDirectory()
    let temporaryFilePath = appendPathComponent("\(UInt64.random(in: 0 ..< .max))", to: tempDirPath)
    defer {
      _ = remove(temporaryFilePath)
    }
    do {
      let configuration = try configurationForEntryPoint(withArguments: ["PATH", outputArgumentName, temporaryFilePath, versionArgumentName, "\(version.versionNumber)"])
      let test = Test(.tags(.blue)) {}
      let eventContext = Event.Context(test: test, testCase: nil, configuration: nil)

      configuration.handleEvent(Event(.testDiscovered, testID: test.id, testCaseID: nil), in: eventContext)
      configuration.handleEvent(Event(.runStarted, testID: nil, testCaseID: nil), in: eventContext)
      do {
        let eventContext = Event.Context(test: test, testCase: nil, configuration: nil)
        configuration.handleEvent(Event(.testStarted, testID: test.id, testCaseID: nil), in: eventContext)
        configuration.handleEvent(Event(.testEnded, testID: test.id, testCaseID: nil), in: eventContext)
      }
      configuration.handleEvent(Event(.runEnded, testID: nil, testCaseID: nil), in: eventContext)
    }

    let decodedRecords = try FileHandle(forReadingAtPath: temporaryFilePath).readToEnd()
      .split(whereSeparator: \.isASCIINewline)
      .map { line in
        try line.withUnsafeBytes { line in
          try JSON.decode(ABI.Record<V>.self, from: line)
        }
      }

    let testRecords = decodedRecords.compactMap { record in
      if case let .test(test) = record.kind {
        return test
      }
      return nil
    }
    #expect(testRecords.count == 1)
    for testRecord in testRecords {
      if version.versionNumber >= ABI.v1.versionNumber {
        #expect(testRecord._tags != nil)
      } else {
        #expect(testRecord._tags == nil)
      }
    }
    let eventRecords = decodedRecords.compactMap { record in
      if case let .event(event) = record.kind {
        return event
      }
      return nil
    }
    #expect(eventRecords.count == 4)
  }

  @Test("Experimental ABI version requires --experimental-event-stream-version argument")
  func experimentalABIVersionNeedsExperimentalFlag() {
    #expect(throws: (any Error).self) {
      let experimentalVersion = ABI.CurrentVersion.versionNumber + 1
      _ = try configurationForEntryPoint(withArguments: ["PATH", "--event-stream-version", "\(experimentalVersion)"])
    }
  }

  @Test("Invalid event stream version throws an invalid argument error")
  func invalidEventStreamVersionThrows() {
    #expect(throws: (any Error).self) {
      _ = try configurationForEntryPoint(withArguments: ["PATH", "--event-stream-version", "xyz-invalid"])
    }
  }
#endif
#endif

  @Test("--repetitions argument (alone)")
  @available(_regexAPI, *)
  func repetitions() throws {
    let configuration = try configurationForEntryPoint(withArguments: ["PATH", "--repetitions", "2468"])
    #expect(configuration.repetitionPolicy.maximumIterationCount == 2468)
    #expect(configuration.repetitionPolicy.continuationCondition == nil)
  }

  @Test("--repeat-until pass argument (alone)")
  @available(_regexAPI, *)
  func repeatUntilPass() throws {
    let configuration = try configurationForEntryPoint(withArguments: ["PATH", "--repeat-until", "pass"])
    #expect(configuration.repetitionPolicy.maximumIterationCount == .max)
    #expect(configuration.repetitionPolicy.continuationCondition == .whileIssueRecorded)
  }

  @Test("--repeat-until fail argument (alone)")
  @available(_regexAPI, *)
  func repeatUntilFail() throws {
    let configuration = try configurationForEntryPoint(withArguments: ["PATH", "--repeat-until", "fail"])
    #expect(configuration.repetitionPolicy.maximumIterationCount == .max)
    #expect(configuration.repetitionPolicy.continuationCondition == .untilIssueRecorded)
  }

  @Test("--repeat-until argument with garbage value (alone)")
  @available(_regexAPI, *)
  func repeatUntilGarbage() {
    #expect(throws: (any Error).self) {
      _ = try configurationForEntryPoint(withArguments: ["PATH", "--repeat-until", "qwertyuiop"])
    }
  }

  @Test("--repetitions and --repeat-until arguments")
  @available(_regexAPI, *)
  func repetitionsAndRepeatUntil() throws {
    let configuration = try configurationForEntryPoint(withArguments: ["PATH", "--repetitions", "2468", "--repeat-until", "pass"])
    #expect(configuration.repetitionPolicy.maximumIterationCount == 2468)
    #expect(configuration.repetitionPolicy.continuationCondition == .whileIssueRecorded)
  }

  @Test("list subcommand")
  func list() async throws {
    do {
      let args = try parseCommandLineArguments(from: ["PATH", "--list-tests"])
      #expect(args.listTests == true)
    }
    do {
      let args = try parseCommandLineArguments(from: ["PATH", "list"])
      #expect(args.listTests == true)
    }
    let testIDs = await listTestsForEntryPoint(Test.all, verbosity: 0)
    let currentTestID = String(describing: try #require(Test.current?.id.parent))
    #expect(testIDs.contains(currentTestID))
  }

  @Test("list --verbose subcommand")
  func listVerbose() async throws {
    let testIDs = await listTestsForEntryPoint(Test.all, verbosity: 1)
    let currentTestID = String(describing: try #require(Test.current?.id))
    #expect(testIDs.contains(currentTestID))
    #expect(testIDs.allSatisfy { $0.contains(".swift:") })
  }

  @Test(
    "--verbose, --very-verbose, and --quiet arguments",
    arguments: [
      ("--verbose", 1),
      ("-v", 1),
      ("--very-verbose", 2),
      ("--vv", 2),
      ("--quiet", -1),
      ("-q", -1),
    ]
  ) func verbosity(argument: String, expectedVerbosity: Int) throws {
    let args = try parseCommandLineArguments(from: ["PATH", argument])
    #expect(args.verbosity == expectedVerbosity)
  }

  @Test("--verbosity argument")
  func verbosity() throws {
    let args = try parseCommandLineArguments(from: ["PATH", "--verbosity", "12345"])
    #expect(args.verbosity == 12345)
  }
}
