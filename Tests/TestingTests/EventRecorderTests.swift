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
    configuration.deliverExpectationCheckedEvents = true
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
  func verboseOutput() async throws {
    let stream = Stream()

    var options = Event.ConsoleOutputRecorder.Options()
    options.verbosity = 1

    var configuration = Configuration()
    configuration.deliverExpectationCheckedEvents = true
    let eventRecorder = Event.ConsoleOutputRecorder(options: options, writingUsing: stream.write)
    configuration.eventHandler = { event, context in
      eventRecorder.record(event, in: context)
    }

    await runTest(for: WrittenTests.self, configuration: configuration)

    let buffer = stream.buffer.rawValue
    #expect(buffer.contains(#"\#(Event.Symbol.details.unicodeCharacter) "abc": Swift.String"#))
    #expect(buffer.contains(#"\#(Event.Symbol.details.unicodeCharacter) lhs: Swift.String → "987""#))
    #expect(buffer.contains(#""Animal Crackers" (aka 'WrittenTests')"#))
    #expect(buffer.contains(#""Not A Lobster" (aka 'actuallyCrab()')"#))

    if testsWithSignificantIOAreEnabled {
      print(buffer, terminator: "")
    }
  }

  @Test("Quiet output")
  func quietOutput() async throws {
    let stream = Stream()

    var options = Event.ConsoleOutputRecorder.Options()
    options.verbosity = -1

    var configuration = Configuration()
    configuration.deliverExpectationCheckedEvents = true
    let eventRecorder = Event.ConsoleOutputRecorder(options: options, writingUsing: stream.write)
    configuration.eventHandler = { event, context in
      eventRecorder.record(event, in: context)
    }

    await runTest(for: WrittenTests.self, configuration: configuration)

    let buffer = stream.buffer.rawValue
    #expect(!buffer.contains(#"\#(Event.Symbol.details.unicodeCharacter) Test run started."#))
    #expect(!buffer.contains(#"\#(Event.Symbol.default.unicodeCharacter) Passing"#))

    if testsWithSignificantIOAreEnabled {
      print(buffer, terminator: "")
    }
  }

  @Test("Output with prefix on each line")
  func prefixedOutput() async throws {
    let stream = Stream()
    let prefix = ">>What Fools These Prefixes Be<<"

    var options = Event.ConsoleOutputRecorder.Options()
    options.prefix = prefix

    var configuration = Configuration()
    configuration.deliverExpectationCheckedEvents = true
    let eventRecorder = Event.ConsoleOutputRecorder(options: options, writingUsing: stream.write)
    configuration.eventHandler = { event, context in
      eventRecorder.record(event, in: context)
    }

    await runTest(for: WrittenTests.self, configuration: configuration)

    let buffer = stream.buffer.rawValue
    #expect(buffer.contains(prefix))

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
    "Issue counts are summed correctly on test end",
    arguments: [
      ("f()", false, (total: 5, expected: 3)),
      ("g()", false, (total: 2, expected: 1)),
      ("PredictablyFailingTests", true, (total: 7, expected: 4)),
    ]
  )
  func issueCountSummingAtTestEnd(testName: String, isSuite: Bool, issueCount: (total: Int, expected: Int)) async throws {
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
      " \(isSuite ? "Suite" : "Test") \(testName) failed "
      ZeroOrMore(.any)
      " with "
      Capture { OneOrMore(.digit) } transform: { Int($0) }
      " issue"
      Optionally("s")
      " (including "
      Capture { OneOrMore(.digit) } transform: { Int($0) }
      " known issue"
      Optionally("s")
      ")."
    }
    let match = try #require(
      buffer
        .split(whereSeparator: \.isNewline)
        .compactMap(testFailureRegex.wholeMatch(in:))
        .first
    )
    #expect(issueCount.total == match.output.1)
    #expect(issueCount.expected == match.output.2)
  }
#endif

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

    let runFailureRegex = Regex {
      One(.anyGraphemeCluster)
      " Test run with "
      OneOrMore(.digit)
      " test"
      Optionally("s")
      " failed "
      ZeroOrMore(.any)
      " with "
      Capture { OneOrMore(.digit) } transform: { Int($0) }
      " issue"
      Optionally("s")
      " (including "
      Capture { OneOrMore(.digit) } transform: { Int($0) }
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
    #expect(match.output.1 == 7)
    #expect(match.output.2 == 4)
  }
#endif

#if canImport(Foundation) || canImport(FoundationXML)
  @Test(
    "JUnitXMLRecorder outputs valid XML",
    .bug("https://github.com/apple/swift-testing/issues/254")
  )
  func junitXMLIsValid() async throws {
    let stream = Stream()

    var configuration = Configuration()
    configuration.deliverExpectationCheckedEvents = true
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
#endif
}

// MARK: - Fixtures

@Suite("Animal Crackers", .hidden) struct WrittenTests {
  @Test(.hidden) func failWhale() async {
    Issue.record("Whales fail.")
    await { () async in
      _ = Issue.record("Whales fail asynchronously.")
    }()
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
}
