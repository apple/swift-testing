//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

@testable @_spi(Experimental) @_spi(ForToolsIntegrationOnly) import Testing
#if !os(Windows)
import RegexBuilder
#endif
#if canImport(Foundation)
import Foundation
#endif
#if canImport(FoundationXML)
import FoundationXML
#endif

#if FIXED_118452948
@Suite("Event Recorder Tests")
#endif
struct EventRecorderTests {
  final class Stream: TextOutputStream, Sendable {
    let buffer = Locked<String>(rawValue: "")

    @Sendable func write(_ string: String) {
      buffer.withLock {
        $0.append(string)
      }
    }
  }

  private static var optionCombinations: [(useSFSymbols: Bool, ansiColorBitDepth: Int8?)] {
    var result: [(useSFSymbols: Bool, ansiColorBitDepth: Int8?)] = [
      (false, nil), (false, 1), (false, 4), (false, 8), (false, 24),
    ]
#if os(macOS)
    result += [
      (true, nil), (true, 1), (true, 4), (true, 8), (true, 24),
    ]
#endif
    return result
  }

  @Test("Writing events", arguments: optionCombinations)
  func writingToStream(useSFSymbols: Bool, ansiColorBitDepth: Int8?) async throws {
    let stream = Stream()

    var options = Event.ConsoleOutputRecorder.Options()
#if os(macOS)
    options.useSFSymbols = useSFSymbols
#endif
    if let ansiColorBitDepth {
      options.useANSIEscapeCodes = true
      options.ansiColorBitDepth = ansiColorBitDepth
    }

    var configuration = Configuration()
    configuration.eventHandlingOptions.isExpectationCheckedEventEnabled = true
    let eventRecorder = Event.ConsoleOutputRecorder(options: options, writingUsing: stream.write)
    configuration.eventHandler = { event, context in
      eventRecorder.record(event, in: context)
    }

    await runTest(for: WrittenTests.self, configuration: configuration)

    let buffer = stream.buffer.rawValue
    #expect(buffer.contains("failWhale"))
    #expect(buffer.contains("Whales fail."))
#if !SWT_NO_UNSTRUCTURED_TASKS
    #expect(buffer.contains("Whales fail asynchronously."))
#endif
    #expect(buffer.contains("\"abc\" == \"xyz\""))
    #expect(buffer.contains("Not A Lobster"))
    #expect(buffer.contains("i → 5"))
    #expect(buffer.contains("Ocelots don't like the number 3."))

    if let ansiColorBitDepth, ansiColorBitDepth > 1 {
      #expect(buffer.contains("\u{001B}["))
      #expect(buffer.contains("●"))
    } else {
      #expect(!buffer.contains("\u{001B}["))
      #expect(!buffer.contains("●"))
    }

    #expect(buffer.contains("inserted ["))

    if testsWithSignificantIOAreEnabled {
      print(buffer, terminator: "")
    }
  }

  @Test("Verbose output")
  @available(_regexAPI, *)
  func verboseOutput() async throws {
    let stream = Stream()

    var configuration = Configuration()
    configuration.eventHandlingOptions.isExpectationCheckedEventEnabled = true
    let eventRecorder = Event.ConsoleOutputRecorder(writingUsing: stream.write)
    configuration.eventHandler = { event, context in
      eventRecorder.record(event, in: context)
    }
    configuration.verbosity = 1

    await runTest(for: WrittenTests.self, configuration: configuration)

    let buffer = stream.buffer.rawValue
    #expect(buffer.contains(#"\#(Event.Symbol.details.unicodeCharacter) "abc": Swift.String"#))
    #expect(buffer.contains(#"\#(Event.Symbol.details.unicodeCharacter) lhs: Swift.String → "987""#))
    #expect(buffer.contains(#""Animal Crackers" (aka 'WrittenTests')"#))
    #expect(buffer.contains(#""Not A Lobster" (aka 'actuallyCrab()')"#))
    do {
      let regex = try Regex(".* Test case passing 1 argument i → 0 \\(Swift.Int\\) to multitudeOcelot\\(i:\\) started.")
      #expect(try buffer.split(whereSeparator: \.isNewline).compactMap(regex.wholeMatch(in:)).first != nil)
    }
    do {
      let regex = try Regex(".* Test case passing 1 argument i → 0 \\(Swift.Int\\) to multitudeOcelot\\(i:\\) passed after .*.")
      #expect(try buffer.split(whereSeparator: \.isNewline).compactMap(regex.wholeMatch(in:)).first != nil)
    }
    do {
      let regex = try Regex(".* Test case passing 1 argument i → 3 \\(Swift.Int\\) to multitudeOcelot\\(i:\\) failed after .* with 1 issue.")
      #expect(try buffer.split(whereSeparator: \.isNewline).compactMap(regex.wholeMatch(in:)).first != nil)
    }

    if testsWithSignificantIOAreEnabled {
      print(buffer, terminator: "")
    }
  }

  @Test("Quiet output")
  func quietOutput() async throws {
    let stream = Stream()

    var configuration = Configuration()
    configuration.eventHandlingOptions.isExpectationCheckedEventEnabled = true
    let eventRecorder = Event.ConsoleOutputRecorder(writingUsing: stream.write)
    configuration.eventHandler = { event, context in
      eventRecorder.record(event, in: context)
    }
    configuration.verbosity = -1

    await runTest(for: WrittenTests.self, configuration: configuration)

    let buffer = stream.buffer.rawValue
    #expect(!buffer.contains(#"\#(Event.Symbol.details.unicodeCharacter) Test run started."#))
    #expect(!buffer.contains(#"\#(Event.Symbol.default.unicodeCharacter) Passing"#))

    if testsWithSignificantIOAreEnabled {
      print(buffer, terminator: "")
    }
  }

#if !os(Windows)
  @available(_regexAPI, *)
  @Test(
    "Titles of messages ('Test' vs. 'Suite') are determined correctly",
    arguments: [
      ("f()", false),
      ("g()", false),
      ("PredictablyFailingTests", true),
    ]
  )
  func messageTitles(testName: String, isSuite: Bool) async throws {
    let stream = Stream()

    var configuration = Configuration()
    let eventRecorder = Event.ConsoleOutputRecorder(writingUsing: stream.write)
    configuration.eventHandler = { event, context in
      eventRecorder.record(event, in: context)
    }

    await runTest(for: PredictablyFailingTests.self, configuration: configuration)

    let buffer = stream.buffer.rawValue
    if testsWithSignificantIOAreEnabled {
      print(buffer, terminator: "")
    }

    let testFailureRegex = Regex {
      One(.anyGraphemeCluster)
      " \(isSuite ? "Suite" : "Test") \(testName) started."
    }
    #expect(
      try buffer
        .split(whereSeparator: \.isNewline)
        .compactMap(testFailureRegex.wholeMatch(in:))
        .first != nil
    )
  }
  
  @available(_regexAPI, *)
  @Test(
    "Log the total number of test cases in parameterized tests at the end of the test run",
    arguments: [
      ("f()", #".* Test f\(\) failed after .*"#),
      ("h()", #".* Test h\(\) passed after .+"#),
      ("l(_:)", #".* Test l\(_:\) with .+ test cases passed after.*"#),
      ("m(_:)", #".* Test m\(_:\) with .+ test cases failed after.*"#),
      ("n(_:)", #".* Test n\(_:\) with .+ test case passed after.*"#),
      ("PredictablyFailingTests", #".* Suite PredictablyFailingTests failed after .*"#),
    ]
  )
  func numberOfTestCasesAtTestEnd(testName: String, expectedPattern: String) async throws {
    let stream = Stream()

    var configuration = Configuration()
    let eventRecorder = Event.ConsoleOutputRecorder(writingUsing: stream.write)
    configuration.eventHandler = { event, context in
      eventRecorder.record(event, in: context)
    }

    await runTest(for: PredictablyFailingTests.self, configuration: configuration)

    let buffer = stream.buffer.rawValue

    let argumentRegex = try Regex(expectedPattern)
    
    #expect(
      (try buffer
        .split(whereSeparator: \.isNewline)
        .compactMap(argumentRegex.wholeMatch(in:))
        .first) != nil,
      "buffer: \(buffer)"
    )
  }

  @available(_regexAPI, *)
  @Test(
    "Issue counts are summed correctly on test end",
    arguments: [
      ("f()", #".* Test f\(\) failed after .+ seconds with 5 issues \(including 3 known issues\)\."#),
      ("g()", #".* Test g\(\) failed after .+ seconds with 2 issues \(including 1 known issue\)\."#),
      ("h()", #".* Test h\(\) passed after .+ seconds with 1 warning\."#),
      ("i()", #".* Test i\(\) failed after .+ seconds with 2 issues \(including 1 warning\)\."#),
      ("j()", #".* Test j\(\) passed after .+ seconds with 1 warning and 1 known issue\."#),
      ("k()", #".* Test k\(\) passed after .+ seconds with 1 known issue\."#),
      ("PredictablyFailingTests", #".* Suite PredictablyFailingTests failed after .+ seconds with 16 issues \(including 3 warnings and 6 known issues\)\."#),
    ]
  )
  func issueCountSummingAtTestEnd(testName: String, expectedPattern: String) async throws {
    let stream = Stream()

    var configuration = Configuration()
    configuration.eventHandlingOptions.isWarningIssueRecordedEventEnabled = true
    let eventRecorder = Event.ConsoleOutputRecorder(writingUsing: stream.write)
    configuration.eventHandler = { event, context in
      eventRecorder.record(event, in: context)
    }

    await runTest(for: PredictablyFailingTests.self, configuration: configuration)

    let buffer = stream.buffer.rawValue
    if testsWithSignificantIOAreEnabled {
      print(buffer, terminator: "")
    }

    let expectedSuffixRegex = try Regex(expectedPattern)
    #expect(try buffer
      .split(whereSeparator: \.isNewline)
      .compactMap(expectedSuffixRegex.wholeMatch(in:))
      .first != nil,
      "buffer: \(buffer)"
    )
  }
#endif

  @Test(
    "Uncommonly-formatted comments",
    .bug("rdar://149482060"),
    arguments: [
      "", // Empty string
      "\n\n\n", // Only newlines
      "\nFoo\n\nBar\n\n\nBaz\n", // Newlines interspersed with non-empty strings
    ]
  )
  func uncommonComments(text: String) async throws {
    let stream = Stream()

    var configuration = Configuration()
    configuration.eventHandlingOptions.isWarningIssueRecordedEventEnabled = true
    let eventRecorder = Event.ConsoleOutputRecorder(writingUsing: stream.write)
    configuration.eventHandler = { event, context in
      eventRecorder.record(event, in: context)
    }

    await Test {
      Issue.record(Comment(rawValue: text) /* empty */)
    }.run(configuration: configuration)
  }

  @available(_regexAPI, *)
  @Test("Issue counts are omitted on a successful test")
  func issueCountOmittedForPassingTest() async throws {
    let stream = Stream()

    var configuration = Configuration()
    let eventRecorder = Event.ConsoleOutputRecorder(writingUsing: stream.write)
    configuration.eventHandler = { event, context in
      eventRecorder.record(event, in: context)
    }

    await Test(name: "Innocuous Test Name") {
    }.run(configuration: configuration)

    let buffer = stream.buffer.rawValue
    if testsWithSignificantIOAreEnabled {
      print(buffer, terminator: "")
    }

    #expect(!buffer.contains("issue"))
  }

#if !os(Windows)
  @available(_regexAPI, *)
  @Test("Issue counts are summed correctly on run end")
  func issueCountSummingAtRunEnd() async throws {
    let stream = Stream()

    var configuration = Configuration()
    let eventRecorder = Event.ConsoleOutputRecorder(writingUsing: stream.write)
    configuration.eventHandler = { event, context in
      eventRecorder.record(event, in: context)
    }

    await runTest(for: PredictablyFailingTests.self, configuration: configuration)

    let buffer = stream.buffer.rawValue
    if testsWithSignificantIOAreEnabled {
      print(buffer, terminator: "")
    }

    let testCount = Reference<Int?>()
    let suiteCount = Reference<Int?>()
    let issueCount = Reference<Int?>()
    let warningCount = Reference<Int?>()
    let knownIssueCount = Reference<Int?>()

    let runFailureRegex = Regex {
      One(.anyGraphemeCluster)
      " Test run with "
      Capture(as: testCount) { OneOrMore(.digit) } transform: { Int($0) }
      " test"
      Optionally("s")
      " in "
      Capture(as: suiteCount) { OneOrMore(.digit) } transform: { Int($0) }
      " suite"
      Optionally("s")
      " failed "
      ZeroOrMore(.any)
      " with "
      Capture(as: issueCount) { OneOrMore(.digit) } transform: { Int($0) }
      " issue"
      Optionally("s")
      " (including "
      Capture(as: warningCount) { OneOrMore(.digit) } transform: { Int($0) }
      " warnings and "
      Capture(as: knownIssueCount) { OneOrMore(.digit) } transform: { Int($0) }
      " known issue"
      Optionally("s")
      ")."
    }
    let match = try #require(
      buffer
        .split(whereSeparator: \.isNewline)
        .compactMap(runFailureRegex.wholeMatch(in:))
        .first
    )
    #expect(match[testCount] == 9)
    #expect(match[suiteCount] == 2)
    #expect(match[issueCount] == 16)
    #expect(match[warningCount] == 3)
    #expect(match[knownIssueCount] == 6)
  }

  @Test("Issue counts are summed correctly on run end for a test with only warning issues")
  @available(_regexAPI, *)
  func warningIssueCountSummingAtRunEnd() async throws {
    let stream = Stream()

    var configuration = Configuration()
    configuration.eventHandlingOptions.isWarningIssueRecordedEventEnabled = true
    let eventRecorder = Event.ConsoleOutputRecorder(writingUsing: stream.write)
    configuration.eventHandler = { event, context in
      eventRecorder.record(event, in: context)
    }

    await runTestFunction(named: "h()", in: PredictablyFailingTests.self, configuration: configuration)

    let buffer = stream.buffer.rawValue
    if testsWithSignificantIOAreEnabled {
      print(buffer, terminator: "")
    }

    let testCount = Reference<Int?>()
    let suiteCount = Reference<Int?>()
    let warningCount = Reference<Int?>()

    let runFailureRegex = Regex {
      One(.anyGraphemeCluster)
      " Test run with "
      Capture(as: testCount) { OneOrMore(.digit) } transform: { Int($0) }
      " test"
      Optionally("s")
      " in "
      Capture(as: suiteCount) { OneOrMore(.digit) } transform: { Int($0) }
      " suite"
      Optionally("s")
      " passed "
      ZeroOrMore(.any)
      " with "
      Capture(as: warningCount) { OneOrMore(.digit) } transform: { Int($0) }
      " warning"
      Optionally("s")
      "."
    }
    let match = try #require(
      buffer
        .split(whereSeparator: \.isNewline)
        .compactMap(runFailureRegex.wholeMatch(in:))
        .first,
      "buffer: \(buffer)"
    )
    #expect(match[testCount] == 1)
    #expect(match[suiteCount] == 1)
    #expect(match[warningCount] == 1)
  }
#endif

#if canImport(Foundation) || canImport(FoundationXML)
  @Test(
    "JUnitXMLRecorder outputs valid XML",
    .bug("https://github.com/swiftlang/swift-testing/issues/254")
  )
  func junitXMLIsValid() async throws {
    let stream = Stream()

    var configuration = Configuration()
    configuration.eventHandlingOptions.isExpectationCheckedEventEnabled = true
    let eventRecorder = Event.JUnitXMLRecorder(writingUsing: stream.write)
    configuration.eventHandler = { event, context in
      eventRecorder.record(event, in: context)
    }
    await runTest(for: WrittenTests.self, configuration: configuration)

    // There is no formal schema for us to test against, so we're mostly just
    // testing that the XML can be parsed by Foundation.

    let xmlString = stream.buffer.rawValue
    #expect(xmlString.hasPrefix("<?xml"))
    let xmlData = try #require(xmlString.data(using: .utf8))
    #expect(xmlData.count > 1024)
    let parser = XMLParser(data: xmlData)

    // Set up a delegate that can look for particular XML tags of interest. Keep
    // in mind that the delegate pattern necessarily means that some of the
    // testing occurs out of source order.
    final class JUnitDelegate: NSObject, XMLParserDelegate {
      var caughtError: (any Error)?

      func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "testsuite" {
          do {
            let testCountString = try #require(attributeDict["tests"])
            let testCount = try #require(Int(testCountString))
            #expect(testCount > 0)
          } catch {
            caughtError = error
          }
        }
      }
    }
    let delegate = JUnitDelegate()
    parser.delegate = delegate

    // Perform the parsing and propagate any errors that occurred.
    #expect(parser.parse())
    if let error = parser.parserError {
      throw error
    }
    if let caughtError = delegate.caughtError {
      throw caughtError
    }
  }

  @Test(
    "JUnit XML omits time for skipped tests",
    .bug("https://github.com/swiftlang/swift-testing/issues/740")
  )
  func junitXMLWithTimelessSkippedTest() async throws {
    let stream = Stream()

    let eventRecorder = Event.JUnitXMLRecorder(writingUsing: stream.write)
    eventRecorder.record(Event(.runStarted, testID: nil, testCaseID: nil), in: Event.Context(test: nil, testCase: nil, configuration: nil))
    let test = Test {}
    eventRecorder.record(Event(.testSkipped(.init(sourceContext: .init())), testID: test.id, testCaseID: nil), in: Event.Context(test: test, testCase: nil, configuration: nil))
    eventRecorder.record(Event(.runEnded, testID: nil, testCaseID: nil), in: Event.Context(test: nil, testCase: nil, configuration: nil))

    let xmlString = stream.buffer.rawValue
    #expect(xmlString.hasPrefix("<?xml"))
    let testCaseLines = xmlString
      .split(whereSeparator: \.isNewline)
      .filter { $0.contains("<testcase") }
    #expect(!testCaseLines.isEmpty)
    #expect(!testCaseLines.contains { $0.contains("time=") })
  }
#endif

  @Test("HumanReadableOutputRecorder counts issues without associated tests")
  func humanReadableRecorderCountsIssuesWithoutTests() {
    let issue = Issue(kind: .unconditional)
    let event = Event(.issueRecorded(issue), testID: nil, testCaseID: nil)
    let context = Event.Context(test: nil, testCase: nil, configuration: nil)

    let recorder = Event.HumanReadableOutputRecorder()
    let messages = recorder.record(event, in: context)
    #expect(
      messages.map(\.stringValue).contains { message in
        message.contains("unknown")
      }
    )
  }

  @Test("JUnitXMLRecorder counts issues without associated tests")
  func junitRecorderCountsIssuesWithoutTests() async throws {
    let issue = Issue(kind: .unconditional)
    let context = Event.Context(test: nil, testCase: nil, configuration: nil)

    await confirmation { wroteTestSuite in
      let recorder = Event.JUnitXMLRecorder { string in
        if string.contains("<testsuite ") {
          #expect(string.contains(#"failures="1""#))
          wroteTestSuite()
        }
      }
      recorder.record(Event(.issueRecorded(issue), testID: nil, testCaseID: nil), in: context)
      recorder.record(Event(.runEnded, testID: nil, testCaseID: nil), in: context)
    }
  }

  @Test("JUnitXMLRecorder ignores warning issues")
  func junitRecorderIgnoresWarningIssues() async throws {
    let issue = Issue(kind: .unconditional, severity: .warning)
    let context = Event.Context(test: nil, testCase: nil, configuration: nil)

    await confirmation { wroteTestSuite in
      let recorder = Event.JUnitXMLRecorder { string in
        if string.contains("<testsuite ") {
          #expect(string.contains(#"failures="0""#))
          wroteTestSuite()
        }
      }
      recorder.record(Event(.issueRecorded(issue), testID: nil, testCaseID: nil), in: context)
      recorder.record(Event(.runEnded, testID: nil, testCaseID: nil), in: context)
    }
  }

  @Test(
    "HumanReadableOutputRecorder includes known issue comment in messages array",
    arguments: [
      ("recordWithoutKnownIssueComment()", ["#expect comment"]),
      ("recordWithKnownIssueComment()", ["#expect comment", "withKnownIssue comment"]),
      ("throwWithoutKnownIssueComment()", []),
      ("throwWithKnownIssueComment()", ["withKnownIssue comment"]),
    ]
  )
  func knownIssueComments(testName: String, expectedComments: [String]) async throws {
    var configuration = Configuration()
    let recorder = Event.HumanReadableOutputRecorder()
    let messages = Locked<[Event.HumanReadableOutputRecorder.Message]>(rawValue: [])
    configuration.eventHandler = { event, context in
      guard case .issueRecorded = event.kind else { return }
      messages.withLock {
        $0.append(contentsOf: recorder.record(event, in: context))
      }
    }

    await runTestFunction(named: testName, in: PredictablyFailingKnownIssueTests.self, configuration: configuration)

    // The first message is something along the lines of "Test foo recorded a
    // known issue" and includes a source location, so is inconvenient to
    // include in our expectation here.
    let actualComments = messages.rawValue.dropFirst().map(\.stringValue)
    #expect(actualComments == expectedComments)
  }
}

// MARK: - Fixtures

@Suite("Animal Crackers", .hidden) struct WrittenTests {
  @Test(.hidden) func failWhale() async {
    Issue.record("Whales fail.")
    await { () async in
      _ = Issue.record("Whales fail asynchronously.")
    }()
    Issue.record("Whales\nalso\nfall.")
  }
  @Test(.hidden) func expectantKangaroo() {
    #expect("abc" == "xyz")
  }
  @Test(.hidden) func nonbindingBear() {
    let lhs = "987"
    let rhs = "123"
    #expect(lhs == rhs)
  }
  @Test(.hidden) func successBadger() {}
  @Test(.hidden, .tags(.red, .orange, .green), arguments: 0 ..< 10) func severalLarks(i: Int) {}
  @Test(.hidden, .tags(.purple), arguments: 0 ..< 100) func multitudeOcelot(i: Int) {
    if i == 3 {
      Issue.record("Ocelots don't like the number 3.")
    }
  }
  @Test("Not A Lobster", .hidden) func actuallyCrab() {}
  @Test("Avoid the Komodo", .hidden, .disabled(), .tags(.red, .orange, .yellow, .green, .blue, .purple))
  func angeredKomodo() {}

  @Test("Incensed Quail", .hidden)
  func incensedQuail() throws {
    withKnownIssue {
      struct QuailError: Error {}
      throw QuailError()
    }
  }

  @Test("Unavailable Pigeon", .hidden)
  @available(*, unavailable)
  func unavailablePigeon() {}

  @Test("Future Grouse", .hidden)
  @available(macOS 999.0, iOS 999.0, watchOS 999.0, tvOS 999.0, visionOS 999.0, *)
  func futureGrouse() {}

  @Test("Future Goose", .hidden)
  @available(macOS 999, iOS 999, watchOS 999, tvOS 999, visionOS 999.0, *)
  func futureGoose() {}

  @Test("Future Mouse", .hidden)
  @available(macOS, introduced: 999.0)
  func futureMouse() {}

  @Test("Future Moose", .hidden)
  @available(macOS, introduced: 999.0.0)
  func futureMoose() {}

  @Test(.hidden, .comment("No comment"), .comment("Well, maybe"))
  func commented() {
    Issue.record()
  }

  @Test(.hidden) func diffyDuck() {
    #expect([1, 2, 3] as Array == [1, 2] as Array)
  }

  @Test(.hidden) func woefulWombat() {
    #expect(throws: MyError.self) {
      throw MyDescriptiveError(description: "Woe!")
    }
  }

  @Test(.hidden) func quotationalQuokka() throws {
    throw MyDescriptiveError(description: #""Quotation marks!""#)
  }

  @Test(.hidden) func cornyUnicorn🦄() throws {
    throw MyDescriptiveError(description: #"🦄"#)
  }

  @Test(.hidden) func burdgeoningBudgerigar() {
    Issue.record(#"</>& "Down\#nwe\#ngo!""#)
  }
}

@Suite(.hidden) struct PredictablyFailingTests {
  @Test(.hidden) func f() {
    #expect(Bool(false))
    #expect(Bool(false))
    withKnownIssue {
      #expect(Bool(false))
      #expect(Bool(false))
      #expect(Bool(false))
    }
  }

  @Test(.hidden) func g() {
    #expect(Bool(false))
    withKnownIssue {
      #expect(Bool(false))
    }
  }

  @Test(.hidden) func h() {
    Issue(kind: .unconditional, severity: .warning, comments: [], sourceContext: .init()).record()
  }

  @Test(.hidden) func i() {
    Issue(kind: .unconditional, severity: .warning, comments: [], sourceContext: .init()).record()
    #expect(Bool(false))
  }

  @Test(.hidden) func j() {
    Issue(kind: .unconditional, severity: .warning, comments: [], sourceContext: .init()).record()
    withKnownIssue {
      #expect(Bool(false))
    }
  }

  @Test(.hidden) func k() {
    withKnownIssue {
      Issue(kind: .unconditional, severity: .warning, comments: [], sourceContext: .init()).record()
    }
  }
  
  @Test(.hidden, arguments: [1, 2, 3])
  func l(_ arg: Int) {
    #expect(arg > 0)
  }
  
  @Test(.hidden, arguments: [1, 2, 3])
  func m(_ arg: Int) {
      #expect(arg < 0)
  }
  
  @Test(.hidden, arguments: [1])
  func n(_ arg: Int) {
    #expect(arg > 0)
  }

  @Suite struct PredictableSubsuite {}
}

@Suite(.hidden) struct PredictablyFailingKnownIssueTests {
  @Test(.hidden)
  func recordWithoutKnownIssueComment() {
    withKnownIssue {
      #expect(Bool(false), "#expect comment")
    }
  }

  @Test(.hidden)
  func recordWithKnownIssueComment() {
    withKnownIssue("withKnownIssue comment") {
      #expect(Bool(false), "#expect comment")
    }
  }

  @Test(.hidden)
  func throwWithoutKnownIssueComment() {
    withKnownIssue {
      struct TheError: Error {}
      throw TheError()
    }
  }

  @Test(.hidden)
  func throwWithKnownIssueComment() {
    withKnownIssue("withKnownIssue comment") {
      struct TheError: Error {}
      throw TheError()
    }
  }
}
