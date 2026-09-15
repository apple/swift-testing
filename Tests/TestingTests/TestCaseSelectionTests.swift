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

@Suite("Test.Case Selection Tests")
struct TestCaseSelectionTests {
  @Test("Multiple arguments passed to one parameter, selecting one case")
  func oneParameterSelectingOneCase() async throws {
    let fixtureTest = Test(arguments: ["a", "b"], parameters: [Test.Parameter(index: 0, firstName: "value", type: String.self)]) { value in
      #expect(value == "a")
    }

    let firstTestCase = try #require(fixtureTest.testCases?.first { _ in true })

    var configuration = Configuration()
    configuration.testCaseFilter = { testCase, _ in
      testCase.id == firstTestCase.id
    }

    await confirmation { testStarted in
      configuration.eventHandler = { event, context in
        if case .testCaseStarted = event.kind {
          testStarted()
        }
        if case let .issueRecorded(issue) = event.kind {
          Issue.record("Unexpected issue: \(issue)")
        }
      }

      await fixtureTest.run(configuration: configuration)
    }
  }

  @Test("Multiple arguments passed to one parameter, selecting a subset of cases")
  func oneParameterSelectingMultipleCases() async throws {
    let fixtureTest = Test(arguments: ["a", "b", "c"], parameters: [Test.Parameter(index: 0, firstName: "value", type: String.self)]) { value in
      #expect(value != "b")
    }

    let testCases = Array(try #require(fixtureTest.testCases))
    let firstTestCaseID = try #require(testCases.first?.id)
    let lastTestCaseID = try #require(testCases.last?.id)

    var configuration = Configuration()
    configuration.testCaseFilter = { testCase, _ in
      Set<Test.Case.ID>([
        firstTestCaseID,
        lastTestCaseID
      ]).contains(testCase.id)
    }

    await confirmation(expectedCount: 2) { testStarted in
      configuration.eventHandler = { event, context in
        if case .testCaseStarted = event.kind {
          testStarted()
        }
        if case let .issueRecorded(issue) = event.kind {
          Issue.record("Unexpected issue: \(issue)")
        }
      }

      let runner = await Runner(testing: [fixtureTest], configuration: configuration)
      await runner.run()
    }
  }

  @Test("Two collections, each with multiple arguments, passed to two parameters, selecting one case")
  func twoParametersSelectingOneCase() async throws {
    let fixtureTest = Test(
      arguments: ["a", "b"], [1, 2],
      parameters: [
        Test.Parameter(index: 0, firstName: "stringValue", type: String.self),
        Test.Parameter(index: 1, firstName: "intValue", type: Int.self),
      ]
    ) { stringValue, intValue in
      #expect(stringValue == "b" && intValue == 2)
    }

    let selectedTestCase = try #require(fixtureTest.testCases?.first { testCase in
      guard let arguments = testCase.arguments,
            let firstArg = arguments.first?.value as? String,
            let secondArg = arguments.last?.value as? Int
      else {
        return false
      }
      return firstArg == "b" && secondArg == 2
    })

    var configuration = Configuration()
    configuration.testCaseFilter = { testCase, _ in
      testCase.id == selectedTestCase.id
    }

    await confirmation { testStarted in
      configuration.eventHandler = { event, context in
        if case .testCaseStarted = event.kind {
          testStarted()
        }
        if case let .issueRecorded(issue) = event.kind {
          Issue.record("Unexpected issue: \(issue)")
        }
      }

      await fixtureTest.run(configuration: configuration)
    }
  }

#if !SWT_NO_CODABLE
  @Test("Multiple arguments conforming to CustomTestArgumentEncodable, passed to one parameter, selecting one case")
  func oneParameterAcceptingCustomTestArgumentSelectingOneCase() async throws {
    let fixtureTest = Test(arguments: [
      MyCustomTestArgument(x: 1, y: "a"),
      MyCustomTestArgument(x: 2, y: "b"),
    ], parameters: [Test.Parameter(index: 0, firstName: "value", type: MyCustomTestArgument.self)]) { arg in
      #expect(arg.x == 1 && arg.y == "a")
    }

    let firstTestCase = try #require(fixtureTest.testCases?.first { _ in true })

    var configuration = Configuration()
    configuration.testCaseFilter = { testCase, _ in
      testCase.id == firstTestCase.id
    }

    await confirmation { testStarted in
      configuration.eventHandler = { event, context in
        if case .testCaseStarted = event.kind {
          testStarted()
        }
        if case let .issueRecorded(issue) = event.kind {
          Issue.record("Unexpected issue: \(issue)")
        }
      }

      await fixtureTest.run(configuration: configuration)
    }
  }

  @Test("Multiple arguments conforming to Identifiable, passed to one parameter, selecting one case")
  func oneParameterAcceptingIdentifiableArgumentSelectingOneCase() async throws {
    let fixtureTest = Test(arguments: [
      MyCustomIdentifiableArgument(id: "a"),
      MyCustomIdentifiableArgument(id: "b"),
    ], parameters: [Test.Parameter(index: 0, firstName: "value", type: MyCustomIdentifiableArgument.self)]) { arg in
      #expect(arg.id == "a")
    }

    let selectedTestCase = try #require(fixtureTest.testCases?.first { _ in true })

    var configuration = Configuration()
    configuration.testCaseFilter = { testCase, _ in
      testCase.id == selectedTestCase.id
    }

    await confirmation { testStarted in
      configuration.eventHandler = { event, context in
        if case .testCaseStarted = event.kind {
          testStarted()
        }
        if case let .issueRecorded(issue) = event.kind {
          Issue.record("Unexpected issue: \(issue)")
        }
      }

      await fixtureTest.run(configuration: configuration)
    }
  }
#endif

  @Test("Multiple arguments conforming to RawRepresentable, passed to one parameter, selecting one case")
  func oneParameterAcceptingRawRepresentableArgumentSelectingOneCase() async throws {
    let fixtureTest = Test(arguments: [
      MyCustomRawRepresentableArgument(rawValue: "a"),
      MyCustomRawRepresentableArgument(rawValue: "b"),
    ], parameters: [Test.Parameter(index: 0, firstName: "value", type: MyCustomRawRepresentableArgument.self)]) { arg in
      #expect(arg.rawValue == "a")
    }

    let selectedTestCase = try #require(fixtureTest.testCases?.first { _ in true })

    var configuration = Configuration()
    configuration.testCaseFilter = { testCase, _ in
      testCase.id == selectedTestCase.id
    }

    await confirmation { testStarted in
      configuration.eventHandler = { event, context in
        if case .testCaseStarted = event.kind {
          testStarted()
        }
        if case let .issueRecorded(issue) = event.kind {
          Issue.record("Unexpected issue: \(issue)")
        }
      }

      await fixtureTest.run(configuration: configuration)
    }
  }
}

#if !SWT_NO_CODABLE
// MARK: - Fixture parameter types

private struct MyCustomTestArgument: CustomTestArgumentEncodable, Equatable {
  var x: Int
  var y: String

  private enum CodingKeys: CodingKey {
    case x, y
  }

  func encodeTestArgument(to encoder: some Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(x, forKey: .x)
    try container.encode(y, forKey: .y)
  }
}
#endif

private struct MyCustomIdentifiableArgument: Identifiable, CustomStringConvertible {
  var id: String

  var description: String {
    fatalError("Should not be called")
  }
}

private struct MyCustomRawRepresentableArgument: RawRepresentable {
  var rawValue: String
}
