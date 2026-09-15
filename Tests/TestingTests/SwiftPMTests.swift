//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023–2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

@testable @_spi(Experimental) @_spi(ForToolsIntegrationOnly) import Testing
private import _TestingInternals
#if !SWT_NO_FOUNDATION
private import Foundation
#endif

private func configurationForEntryPoint(withArguments args: [String], emitWarnings: Bool = true) throws -> Configuration {
  let args = try parseCommandLineArguments(from: args)
  return try configurationForEntryPoint(from: args, emitWarnings: emitWarnings)
}

private extension Tag {
  @Tag static var testTag: Self
  @Tag static var testTagOther: Self
  @Tag static var unrelatedTag: Self
}

#if !SWT_NO_ABI_JSON_SCHEMA && !SWT_NO_CODABLE
/// Reads event stream output from the provided file matching event stream
/// version `V`.
private func decodedEventStreamRecords<V: ABI.Version>(fromPath filePath: String) throws -> [ABI.Record<V>] {
  try FileHandle(forReadingAtPath: filePath).readToEnd()
    .split(whereSeparator: \.isASCIINewline)
    .map { line in
      try line.withUnsafeBytes { line in
        return try JSON.decode(ABI.Record<V>.self, from: line)
      }
    }
}
#endif

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

  @Test("--experimental-maximum-parallelization-width argument")
  func maximumParallelizationWidth() throws {
    var configuration = try configurationForEntryPoint(withArguments: ["PATH", "--experimental-maximum-parallelization-width", "12345"])
    #expect(configuration.isParallelizationEnabled)
    #expect(configuration.maximumParallelizationWidth == 12345)

    configuration = try configurationForEntryPoint(withArguments: ["PATH", "--experimental-maximum-parallelization-width", "1"])
    #expect(!configuration.isParallelizationEnabled)
    #expect(configuration.maximumParallelizationWidth == 1)

    configuration = try configurationForEntryPoint(withArguments: ["PATH", "--experimental-maximum-parallelization-width", "\(Int.max)"])
    #expect(configuration.isParallelizationEnabled)
    #expect(configuration.maximumParallelizationWidth == .max)

    #expect(throws: (any Error).self) {
      _ = try configurationForEntryPoint(withArguments: ["PATH", "--experimental-maximum-parallelization-width", "0"])
    }
  }

#if !SWT_NO_BACKTRACE_SYMBOLICATION
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
#endif

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
  func filter() async throws {
    let configuration = try configurationForEntryPoint(withArguments: ["PATH", "--filter", "hello"])
    let test1 = Test(name: "hello") {}
    let test2 = Test(name: "goodbye") {}
    let plan = await Runner.Plan(tests: [test1, test2], configuration: configuration)
    let planTests = plan.steps.map(\.test)
    #expect(planTests.contains(test1))
    #expect(!planTests.contains(test2))
  }


  @Test("--filter argument with tag: prefix")
  func filterByTag() async throws {
    let configuration = try configurationForEntryPoint(withArguments: ["PATH", "--filter", "tag:testTag"])
    let test1 = Test(.tags(.testTag), name: "hello") {}
    let test2 = Test(name: "goodbye") {}
    let plan = await Runner.Plan(tests: [test1, test2], configuration: configuration)
    let planTests = plan.steps.map(\.test)
    #expect(planTests.contains(test1))
    #expect(!planTests.contains(test2))
  }

  @Test("Multiple --filter arguments")
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
  func badArguments() throws {
    #expect(throws: (any Error).self) {
      _ = try configurationForEntryPoint(withArguments: ["PATH", "--filter", "("])
    }
    #expect(throws: (any Error).self) {
      _ = try configurationForEntryPoint(withArguments: ["PATH", "--skip", ")"])
    }
  }

  @Test("--filter with no matches")
  func filterWithNoMatches() async {
    var args = __CommandLineArguments_v0()
    args.filter = ["NOTHING_MATCHES_THIS_TEST_NAME_HOPEFULLY"]
    args.verbosity = .min
    let exitCode = await __swiftPMEntryPoint(passing: args) as CInt
    #expect(exitCode == EXIT_NO_TESTS_FOUND)
  }

  @Test("--skip argument")
  func skip() async throws {
    let configuration = try configurationForEntryPoint(withArguments: ["PATH", "--skip", "hello"])
    let test1 = Test(name: "hello") {}
    let test2 = Test(name: "goodbye") {}
    let plan = await Runner.Plan(tests: [test1, test2], configuration: configuration)
    let planTests = plan.steps.map(\.test)
    #expect(!planTests.contains(test1))
    #expect(planTests.contains(test2))
  }

  @Test("--skip argument with tag: prefix")
  func skipByTag() async throws {
    let configuration = try configurationForEntryPoint(withArguments: ["PATH", "--skip", "tag:testTag"])
    let test1 = Test(.tags(.testTag), name: "hello") {}
    let test2 = Test(name: "goodbye") {}
    let plan = await Runner.Plan(tests: [test1, test2], configuration: configuration)
    let planTests = plan.steps.map(\.test)
    #expect(!planTests.contains(test1))
    #expect(planTests.contains(test2))
  }

  @Test("--filter argument with tag: prefix supports regex patterns")
  func filterByTagRegex() async throws {
    let configuration = try configurationForEntryPoint(withArguments: ["PATH", "--filter", "tag:testTag.*"])
    let test1 = Test(.tags(.testTag), name: "hello") {}
    let test2 = Test(.tags(.testTagOther), name: "hi") {}
    let test3 = Test(.tags(.unrelatedTag), name: "goodbye") {}
    let test4 = Test(name: "untagged") {}
    let plan = await Runner.Plan(tests: [test1, test2, test3, test4], configuration: configuration)
    let planTests = plan.steps.map(\.test)
    #expect(planTests.contains(test1))
    #expect(planTests.contains(test2))
    #expect(!planTests.contains(test3))
    #expect(!planTests.contains(test4))
  }

  @Test("--filter tag: argument strips backticks around tag names")
  func filterByTagStripsBackticks() async throws {
    let configuration = try configurationForEntryPoint(withArguments: ["PATH", "--filter", "tag:`testTag`"], emitWarnings: false)
    let test1 = Test(.tags(.testTag), name: "hello") {}
    let test2 = Test(name: "goodbye") {}
    let plan = await Runner.Plan(tests: [test1, test2], configuration: configuration)
    let planTests = plan.steps.map(\.test)
    #expect(planTests.contains(test1))
    #expect(!planTests.contains(test2))
  }

  @Test("--filter combining tag: and id: patterns OR's them together")
  func mixedPrefixedAndUnprefixedFilters() async throws {
    let configuration = try configurationForEntryPoint(withArguments: ["PATH", "--filter", "tag:testTag", "--filter", "hello"])
    let test1 = Test(.tags(.testTag), name: "hello") {}
    let test2 = Test(.tags(.testTag), name: "goodbye") {}
    let test3 = Test(name: "hello") {}
    let test4 = Test(name: "goodbye") {}
    let plan = await Runner.Plan(tests: [test1, test2, test3, test4], configuration: configuration)
    let planTests = plan.steps.map(\.test)
    #expect(planTests.contains(test1))
    #expect(planTests.contains(test2))
    #expect(planTests.contains(test3))
    #expect(!planTests.contains(test4))
  }

  @Test("--skip combining tag: and id: patterns OR's them together")
  func mixedPrefixedAndUnprefixedSkips() async throws {
    let configuration = try configurationForEntryPoint(withArguments: ["PATH", "--skip", "tag:testTag", "--skip", "hello"])
    let test1 = Test(.tags(.testTag), name: "hello") {}
    let test2 = Test(.tags(.testTag), name: "goodbye") {}
    let test3 = Test(name: "hello") {}
    let test4 = Test(name: "goodbye") {}
    let plan = await Runner.Plan(tests: [test1, test2, test3, test4], configuration: configuration)
    let planTests = plan.steps.map(\.test)
    #expect(!planTests.contains(test1))
    #expect(!planTests.contains(test2))
    #expect(!planTests.contains(test3))
    #expect(planTests.contains(test4))
  }

  @Test("Multiple --skip arguments with tag: prefix")
  func multipleSkipByTag() async throws {
    let configuration = try configurationForEntryPoint(withArguments: ["PATH", "--skip", "tag:testTag", "--skip", "tag:unrelatedTag"])
    let test1 = Test(.tags(.testTag), name: "hello") {}
    let test2 = Test(.tags(.unrelatedTag), name: "goodbye") {}
    let test3 = Test(name: "untagged") {}
    let plan = await Runner.Plan(tests: [test1, test2, test3], configuration: configuration)
    let planTests = plan.steps.map(\.test)
    #expect(!planTests.contains(test1))
    #expect(!planTests.contains(test2))
    #expect(planTests.contains(test3))
  }

  @Test("--filter argument with explicit id: prefix")
  func filterByExplicitIdPrefix() async throws {
    let configuration = try configurationForEntryPoint(withArguments: ["PATH", "--filter", "id:hello"])
    let test1 = Test(name: "hello") {}
    let test2 = Test(name: "goodbye") {}
    let plan = await Runner.Plan(tests: [test1, test2], configuration: configuration)
    let planTests = plan.steps.map(\.test)
    #expect(planTests.contains(test1))
    #expect(!planTests.contains(test2))
  }

  @Test("--filter tag: combined with --skip id: in the same execution")
  func filterByTagAndSkipById() async throws {
    let configuration = try configurationForEntryPoint(withArguments: ["PATH", "--filter", "tag:testTag", "--skip", "id:goodbye"])
    let test1 = Test(.tags(.testTag), name: "hello") {}
    let test2 = Test(.tags(.testTag), name: "goodbye") {}
    let test3 = Test(.tags(.unrelatedTag), name: "hello") {}
    let test4 = Test(name: "untagged") {}
    let plan = await Runner.Plan(tests: [test1, test2, test3, test4], configuration: configuration)
    let planTests = plan.steps.map(\.test)
    #expect(planTests.contains(test1))
    #expect(!planTests.contains(test2))
    #expect(!planTests.contains(test3))
    #expect(!planTests.contains(test4))
  }

  @Test("--filter or --skip tag: argument with bad regex")
  func filterByTagWithBadRegex() throws {
    #expect(throws: (any Error).self) {
      _ = try configurationForEntryPoint(withArguments: ["PATH", "--filter", "tag:("])
    }
    #expect(throws: (any Error).self) {
      _ = try configurationForEntryPoint(withArguments: ["PATH", "--skip", "tag:)"])
    }
  }

  @Test("--filter or --skip argument as last argument")
  func filterOrSkipAsLast() async throws {
    _ = try configurationForEntryPoint(withArguments: ["PATH", "--filter"])
    _ = try configurationForEntryPoint(withArguments: ["PATH", "--skip"])
  }

#if !SWT_NO_EXIT_TESTS
  @Test("--filter suppresses console output when no tests found")
  func suppressConsoleOutputWhenFilteredToNothing() async throws {
    let result = try await #require(processExitsWith: .exitCode(EXIT_NO_TESTS_FOUND), observing: [\.standardErrorContent]) {
      var args = __CommandLineArguments_v0()
      args.filter = ["$^"] // match "nothing"
      await __swiftPMEntryPoint(passing: args) as Never
    }
    #expect(result.standardErrorContent.isEmpty)
  }

  @Test("--skip suppresses console output when no tests found")
  func suppressConsoleOutputWhenSkippedToNothing() async throws {
    let result = try await #require(processExitsWith: .exitCode(EXIT_NO_TESTS_FOUND), observing: [\.standardErrorContent]) {
      var args = __CommandLineArguments_v0()
      args.skip = [".*"] // match "anything"
      await __swiftPMEntryPoint(passing: args) as Never
    }
    #expect(result.standardErrorContent.isEmpty)
  }
#endif

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
      let eventContext = Event.Context(test: nil, testCase: nil, iteration: nil, configuration: nil)
      configuration.handleEvent(Event(.runStarted, testID: nil, testCaseID: nil), in: eventContext)
      configuration.handleEvent(Event(.runEnded, testID: nil, testCaseID: nil), in: eventContext)
    }

    let fileHandle = try Testing.FileHandle(forReadingAtPath: temporaryFilePath)
    let fileContents = try fileHandle.readToEnd()
    #expect(!fileContents.isEmpty)
    #expect(fileContents.contains(UInt8(ascii: "<")))
    #expect(fileContents.contains(UInt8(ascii: ">")))
  }

  #if !SWT_NO_FOUNDATION
  @Test(
    "--attachments-path argument (creates missing directory)",
    arguments: ["--attachments-path", "--experimental-attachments-path"]
  )
  func attachmentsPathCreatesMissingDirectory(argumentName: String) throws {
      let tempDirPath = try temporaryDirectory()
      let attachmentsPath = appendPathComponent("swt_attachments_\(UInt64.random(in: 0 ..< .max))", to: tempDirPath)
      defer {
        _ = remove(attachmentsPath)
      }
      #expect(!fileExists(atPath: attachmentsPath))
      let configuration = try configurationForEntryPoint(withArguments: ["PATH", argumentName, attachmentsPath])
      #expect(fileExists(atPath: attachmentsPath))
      let actualPath = try #require(configuration.attachmentsPath, "Attachments path is not expected to be nil")
      #expect(canonicalizePath(actualPath) == canonicalizePath(attachmentsPath))
  }
  #endif

  #if !SWT_NO_FOUNDATION
  @Test("--attachments-path argument (bad path)")
  func attachmentsPathWithBadPath() throws {
      let tempDirPath = try temporaryDirectory()
      let attachmentPath = appendPathComponent(UUID().uuidString, to: tempDirPath)
      let fileManager = FileManager()
      let success = fileManager.createFile(atPath: attachmentPath, contents: nil, )
      if !success {
        Issue.record("Test setup failure.  Could not create file at \(attachmentPath).")
      }
      defer {
        _ = remove(attachmentPath)
      }
      #expect(throws: (any Error).self, "Attachment path is: \(attachmentPath)") {
        _ = try configurationForEntryPoint(withArguments: ["PATH", "--attachments-path", attachmentPath])
      }
  }
  #endif

  @Test("--attachments-path argument (accepts existing directory)")
  func attachmentsPathAcceptsExistingDirectory() throws {
    let tempDirPath = try temporaryDirectory()
    #expect(fileExists(atPath: tempDirPath))
    let configuration = try configurationForEntryPoint(withArguments: ["PATH", "--attachments-path", tempDirPath])
    let actualPath = try #require(configuration.attachmentsPath, "Attachments path is not expected to be nil")
    #expect(
      canonicalizePath(actualPath) == canonicalizePath(tempDirPath),
      "Canonicalized actual path (\(actualPath)) is not equal to canonicalized expected path (\(tempDirPath))",
    )
  }

#if !SWT_NO_CODABLE
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
      let fileHandle = try Testing.FileHandle(forWritingAtPath: temporaryFilePath)
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
#endif

  @available(*, deprecated)
  @Test("Deprecated eventStreamVersion property")
  func deprecatedEventStreamVersionProperty() async throws {
    var args = __CommandLineArguments_v0()
    args.eventStreamVersion = 0
    #expect(args.eventStreamVersionNumber == VersionNumber(0, 0))
    #expect(args.eventStreamSchemaVersion == "0")

    args.eventStreamVersion = -1
    #expect(args.eventStreamVersionNumber == VersionNumber(-1, 0))
    #expect(args.eventStreamSchemaVersion == "-1")

    args.eventStreamVersion = 123
    #expect(args.eventStreamVersionNumber == VersionNumber(123, 0))
    #expect(args.eventStreamSchemaVersion == "123.0")

    args.eventStreamVersionNumber = VersionNumber(10, 20, 30)
    #expect(args.eventStreamVersion == 10)
    #expect(args.eventStreamSchemaVersion == "10.20.30")

    args.eventStreamSchemaVersion = "10.20.30"
    #expect(args.eventStreamVersionNumber == VersionNumber(10, 20, 30))
    #expect(args.eventStreamVersion == 10)

#if !SWT_NO_EXIT_TESTS
    await #expect(processExitsWith: .failure) {
      var args = __CommandLineArguments_v0()
      args.eventStreamSchemaVersion = "invalidVersionString"
    }
#endif
  }

  @Test("New-but-not-experimental ABI version")
  func newButNotExperimentalABIVersion() async throws {
    let currentVersionNumber = ABI.CurrentVersion.versionNumber
    var newerVersionNumber = currentVersionNumber
    newerVersionNumber.patchComponent += 1
    let version = try #require(ABI.version(forVersionNumber: newerVersionNumber, givenSwiftCompilerVersion: newerVersionNumber))
    #expect(version.versionNumber == currentVersionNumber)
  }

  @Test("Unsupported ABI version")
  func unsupportedABIVersion() async throws {
    let versionNumber = VersionNumber(-100, 0)
    let versionTypeInfo = ABI.version(forVersionNumber: versionNumber).map {TypeInfo(describing: $0) }
    #expect(versionTypeInfo == nil)
  }

  @Test("Future ABI version (should be nil)")
  func futureABIVersion() async throws {
    #expect(swiftCompilerVersion >= VersionNumber(6, 0))
    #expect(swiftCompilerVersion < VersionNumber(8, 0), "Swift 8.0 is here! Please update this test.")
    let versionNumber = VersionNumber(8, 0)
    let versionTypeInfo = ABI.version(forVersionNumber: versionNumber).map {TypeInfo(describing: $0) }
    #expect(versionTypeInfo == nil)
  }

#if !SWT_NO_SNAPSHOT_TYPES
  @Test("Severity field included in Issue.Snapshot")
  func issueSnapshotIncludesSeverity() async throws {
    let configuration = try configurationForEntryPoint(
      withArguments: ["PATH", "--event-stream-version", "-1"]
    )
    #expect(configuration.eventHandlingOptions.isWarningIssueRecordedEventEnabled)
  }
#endif

#if !SWT_NO_ABI_JSON_SCHEMA && !SWT_NO_CODABLE
  @Test("Severity and isFailure fields included in version 6.3")
  func validateEventStreamContents() async throws {
    let tempDirPath = try temporaryDirectory()
    let temporaryFilePath = appendPathComponent("\(UInt64.random(in: 0 ..< .max))", to: tempDirPath)
    defer {
      _ = remove(temporaryFilePath)
    }

    do {
      let test = Test {
        Issue.record("Test warning", severity: .warning)
      }

      let configuration = try configurationForEntryPoint(withArguments:
          ["PATH", "--event-stream-output-path", temporaryFilePath, "--experimental-event-stream-version", "6.3"]
      )

      await test.run(configuration: configuration)
    }

    let issueEventRecords = try decodedEventStreamRecords(fromPath: temporaryFilePath)
      .compactMap { (record: ABI.Record<ABI.v6_3>) in
        if case let .event(event) = record.kind, event.kind == .issueRecorded {
          return event
        }
        return nil
      }

    let issue = try #require(issueEventRecords.first?.issue)
    #expect(issueEventRecords.count == 1)
    #expect(issue.isFailure == false)
    #expect(issue.severity == .warning)
  }

  @Test("--event-stream-output-path argument (writes to a stream and can be read back)",
        arguments: [
          ("--event-stream-output-path", "--event-stream-version", ABI.v0.versionNumber),
          ("--experimental-event-stream-output", "--experimental-event-stream-version", ABI.v0.versionNumber),
          ("--experimental-event-stream-output", "--experimental-event-stream-version", ABI.v6_3.versionNumber),
          ("--experimental-event-stream-output", "--experimental-event-stream-version", ABI.v6_4.versionNumber),
          ("--event-stream-output-path", "--event-stream-version", ABI.v6_4.versionNumber),
          ("--event-stream-output-path", "--event-stream-version", ABI.v6_5.versionNumber),
        ])
  func eventStreamOutput(outputArgumentName: String, versionArgumentName: String, version: VersionNumber) async throws {
    let version = try #require(ABI.version(forVersionNumber: version))
    try await eventStreamOutput(outputArgumentName: outputArgumentName, versionArgumentName: versionArgumentName, version: version)
  }

  func eventStreamOutput<V>(outputArgumentName: String, versionArgumentName: String, version: V.Type) async throws where V: ABI.Version {
    // Test that JSON records are successfully streamed to a file and can be
    // read back into memory and decoded.
    let tempDirPath = try temporaryDirectory()
    let temporaryFilePath = appendPathComponent("\(UInt64.random(in: 0 ..< .max))", to: tempDirPath)
    defer {
      _ = remove(temporaryFilePath)
    }
    let testTimeLimit = 3
    let expectedArgs = ["argument1", "argument2"]
    do {
      let configuration = try configurationForEntryPoint(withArguments: ["PATH", outputArgumentName, temporaryFilePath, versionArgumentName, "\(version.versionNumber)"])
      let test = Test(
        .tags(.blue),
        .bug("https://my.defect.com/1234"),
        .bug("other defect"),
        .timeLimit(Swift.Duration.seconds(testTimeLimit + 100)),
        .timeLimit(Swift.Duration.seconds(testTimeLimit)),
        .timeLimit(Swift.Duration.seconds(testTimeLimit + 10)),
        arguments: expectedArgs as [String]
      ) {_ in}
      let eventContext = Event.Context(test: test, testCase: nil, iteration: nil, configuration: nil)

      configuration.handleEvent(Event(.testDiscovered, testID: test.id, testCaseID: nil), in: eventContext)
      configuration.handleEvent(Event(.runStarted, testID: nil, testCaseID: nil), in: eventContext)
      do {
        let eventContext = Event.Context(test: test, testCase: nil, iteration: nil, configuration: nil)
        configuration.handleEvent(Event(.testStarted, testID: test.id, testCaseID: nil), in: eventContext)
        configuration.handleEvent(Event(.testEnded, testID: test.id, testCaseID: nil), in: eventContext)
      }
      configuration.handleEvent(Event(.runEnded, testID: nil, testCaseID: nil), in: eventContext)
    }

    let decodedRecords: [ABI.Record<V>] = try decodedEventStreamRecords(fromPath: temporaryFilePath)

    let testRecords = decodedRecords.compactMap { record in
      if case let .test(test) = record.kind {
        return test
      }
      return nil
    }
    #expect(testRecords.count == 1)
    for testRecord in testRecords {
      if version.includesExperimentalFields {
        let actualTestCases = testRecord._testCases
        let testCases = try #require(actualTestCases)
        #expect(testCases.count == expectedArgs.count)
        #expect(testRecord._tags != nil)
      } else {
        #expect(testRecord._testCases == nil)
      }

      if version.versionNumber >= ABI.v6_4.versionNumber {
        let testTags = try #require(testRecord.tags)
        #expect(testTags.count >= 1)
        for tag in testTags {
          #expect(!tag.starts(with: "."))
        }
        let bugs = try #require(testRecord.bugs)
        #expect(bugs.count == 2)
        let timeLimit = try #require(testRecord.timeLimit)
        #expect(timeLimit == Double(testTimeLimit))
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
      var experimentalVersion = ABI.CurrentVersion.versionNumber
      experimentalVersion.minorComponent += 1
      _ = try configurationForEntryPoint(withArguments: ["PATH", "--event-stream-version", "\(experimentalVersion)"])
    }
  }

  @Test("Invalid event stream version throws an invalid argument error")
  func invalidEventStreamVersionThrows() {
    #expect(throws: (any Error).self) {
      _ = try configurationForEntryPoint(withArguments: ["PATH", "--event-stream-version", "xyz-invalid"])
    }
  }

  @Test("Can extract the ABI version from record JSON")
  func getVersionFromRecordJSON() throws {
    var json = #"{ "kind": "test", "version": "1.2.3", "payload": {} }"#
    let versionNumber = try json.withUTF8 { json in
      try ABI.VersionNumber(fromRecordJSON: UnsafeRawBufferPointer(json))
    }
    #expect(versionNumber == ABI.VersionNumber(1, 2, 3))
  }
#endif
#endif

  @Test("--repetitions argument (alone)")
  func repetitions() throws {
    let configuration = try configurationForEntryPoint(withArguments: ["PATH", "--repetitions", "2468"])
    #expect(configuration.repetitionPolicy.maximumIterationCount == 2468)
    #expect(configuration.repetitionPolicy.continuationCondition == nil)
  }

  @Test("--repeat-until pass argument (alone)")
  func repeatUntilPass() throws {
    let configuration = try configurationForEntryPoint(withArguments: ["PATH", "--repeat-until", "pass"])
    #expect(configuration.repetitionPolicy.maximumIterationCount == .max)
    #expect(configuration.repetitionPolicy.continuationCondition == .whileIssueRecorded)
  }

  @Test("--repeat-until fail argument (alone)")
  func repeatUntilFail() throws {
    let configuration = try configurationForEntryPoint(withArguments: ["PATH", "--repeat-until", "fail"])
    #expect(configuration.repetitionPolicy.maximumIterationCount == .max)
    #expect(configuration.repetitionPolicy.continuationCondition == .untilIssueRecorded)
  }

  @Test("--repeat-until argument with garbage value (alone)")
  func repeatUntilGarbage() {
    #expect(throws: (any Error).self) {
      _ = try configurationForEntryPoint(withArguments: ["PATH", "--repeat-until", "qwertyuiop"])
    }
  }

  @Test("--repetitions and --repeat-until arguments")
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

  @Test("list subcommand includes synthesized tests")
  func listIncludesSynthesizedTests() async throws {
    var args = __CommandLineArguments_v0()
    args.verbosity = .min
    args.listTests = true
    await confirmation("At least one suite was synthesized", expectedCount: 1...) { suiteSynthesized in
      _ = await entryPoint(passing: args) { event, eventContext in
        if case .testDiscovered = event.kind,
           let test = eventContext.test,
           test.isSynthesized {
          suiteSynthesized()
        }
      }
    }
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

  @Test("--foo=bar form")
  func equalsSignForm() throws {
    // We can split the string and parse the result correctly.
    do {
      let args = try parseCommandLineArguments(from: ["PATH", "--verbosity=12345"])
      #expect(args.verbosity == 12345)
    }

    // We don't overrun the string and correctly handle empty values.
    do {
      let args = try parseCommandLineArguments(from: ["PATH", "--xunit-output="])
      #expect(args.xunitOutput == "")
    }

    // We split at the first equals-sign.
    do {
      let args = try parseCommandLineArguments(from: ["PATH", "--xunit-output=abc=123"])
      #expect(args.xunitOutput == "abc=123")
    }
  }
}
