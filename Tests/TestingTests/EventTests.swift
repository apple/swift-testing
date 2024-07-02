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
#if SWT_BUILDING_WITH_CMAKE
@_implementationOnly import _TestingInternals
#else
private import _TestingInternals
#endif

@Suite("Event Tests")
struct EventTests {
#if canImport(Foundation)
  @Test("Event's and Event.Kinds's Codable Conformances",
        arguments: [
          Event.Kind.expectationChecked(
            Expectation(
              evaluatedExpression: __Expression("SyntaxNode"),
              mismatchedErrorDescription: "Mismatched Error Description",
              differenceDescription: "Difference Description",
              isPassing: false,
              isRequired: true,
              sourceLocation: #_sourceLocation
            )
          ),
          Event.Kind.testSkipped(
            SkipInfo(
              comment: "Comment",
              sourceContext: SourceContext(
                backtrace: Backtrace.current(),
                sourceLocation: #_sourceLocation
              )
            )
          ),
          Event.Kind.issueRecorded(
            Issue(
              kind: .system,
              comments: ["Comment"],
              sourceContext: SourceContext(
                backtrace: nil,
                sourceLocation: nil)
            )
          ),
          Event.Kind.runStarted,
          Event.Kind.runEnded,
          Event.Kind.testCaseStarted,
          Event.Kind.testCaseEnded,
          Event.Kind.testStarted,
          Event.Kind.testEnded,
        ]
  )
  func codable(kind: Event.Kind) async throws {
    let testID = Test.ID(moduleName: "ModuleName",
                         nameComponents: ["NameComponent1", "NameComponent2"],
                         sourceLocation: #_sourceLocation)
    let testCaseID = Test.Case.ID(argumentIDs: nil)
    let event = Event(kind, testID: testID, testCaseID: testCaseID, instant: .now)
    let eventSnapshot = Event.Snapshot(snapshotting: event)
    let decoded = try JSON.encodeAndDecode(eventSnapshot)

    #expect(String(describing: decoded) == String(describing: eventSnapshot))
  }

  @Test("Event.Contexts's Codable Conformances")
  func codable() async throws {
    let eventContext = Event.Context()
    let snapshot = Event.Context.Snapshot(snapshotting: eventContext)

    let decoded = try JSON.encodeAndDecode(snapshot)

    #expect(String(describing: decoded.test) == String(describing: eventContext.test.map(Test.Snapshot.init(snapshotting:))))
    #expect(String(describing: decoded.testCase) == String(describing: eventContext.testCase.map(Test.Case.Snapshot.init(snapshotting:))))
  }
#endif
}
