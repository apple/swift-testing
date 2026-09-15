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

@Suite("Test.Case.Argument Tests")
struct Test_Case_ArgumentTests {
  @Test("One parameter")
  func oneParameter() async {
    var configuration = Configuration()
    configuration.setEventHandler { event, context in
      guard case .testCaseStarted = event.kind else {
        return
      }
      let arguments = try #require(context.testCase?.arguments)
      try #require(arguments.count == 1)

      let argument = arguments[0]
      #expect(argument.value as? String == "value")
      #expect(argument.parameter.index == 0)
      #expect(argument.parameter.firstName == "x")
    }

    await runTestFunction(named: "oneParameter(x:)", in: ParameterizedTests.self, configuration: configuration)
  }

  @Test("Two parameters")
  func twoParameters() async {
    var configuration = Configuration()
    configuration.setEventHandler { event, context in
      guard case .testCaseStarted = event.kind else {
        return
      }
      let arguments = try #require(context.testCase?.arguments)
      try #require(arguments.count == 2)

      do {
        let argument = arguments[0]
        #expect(argument.value as? String == "value")
        #expect(argument.parameter.index == 0)
        #expect(argument.parameter.firstName == "x")
      }
      do {
        let argument = arguments[1]
        #expect(argument.value as? Int == 123)
        #expect(argument.parameter.index == 1)
        #expect(argument.parameter.firstName == "y")
      }
    }

    await runTestFunction(named: "twoParameters(x:y:)", in: ParameterizedTests.self, configuration: configuration)
  }

  @Test("One 1-tuple parameter")
  func one1TupleParameter() async {
    var configuration = Configuration()
    configuration.setEventHandler { event, context in
      guard case .testCaseStarted = event.kind else {
        return
      }
      let arguments = try #require(context.testCase?.arguments)
      try #require(arguments.count == 1)

      let argument = arguments[0]
      #expect(argument.value as? (String) == ("value"))
      #expect(argument.parameter.index == 0)
      #expect(argument.parameter.firstName == "x")
    }

    await runTestFunction(named: "one1TupleParameter(x:)", in: ParameterizedTests.self, configuration: configuration)
  }

  @Test("One 2-tuple parameter")
  func one2TupleParameter() async {
    var configuration = Configuration()
    configuration.setEventHandler { event, context in
      guard case .testCaseStarted = event.kind else {
        return
      }
      let arguments = try #require(context.testCase?.arguments)
      try #require(arguments.count == 1)

      let argument = arguments[0]
      let value = try #require(argument.value as? (String, Int))
      #expect(value.0 == "value")
      #expect(value.1 == 123)
      #expect(argument.parameter.index == 0)
      #expect(argument.parameter.firstName == "x")
    }

    await runTestFunction(named: "one2TupleParameter(x:)", in: ParameterizedTests.self, configuration: configuration)
  }

  @Test("Two Dictionary element (key, value) parameters")
  func DictionaryElementParameters() async {
    var configuration = Configuration()
    configuration.setEventHandler { event, context in
      guard case .testCaseStarted = event.kind else {
        return
      }
      let arguments = try #require(context.testCase?.arguments)
      try #require(arguments.count == 2)

      do {
        let argument = arguments[0]
        #expect(argument.value as? String == "value")
        #expect(argument.parameter.index == 0)
        #expect(argument.parameter.firstName == "x")
      }
      do {
        let argument = arguments[1]
        #expect(argument.value as? Int == 123)
        #expect(argument.parameter.index == 1)
        #expect(argument.parameter.firstName == "y")
      }
    }

    await runTestFunction(named: "twoDictionaryElementParameters(x:y:)", in: ParameterizedTests.self, configuration: configuration)
  }

  @Test("One Dictionary element tuple (key, value) parameter")
  func oneDictionaryElementTupleParameter() async {
    var configuration = Configuration()
    configuration.setEventHandler { event, context in
      guard case .testCaseStarted = event.kind else {
        return
      }
      let arguments = try #require(context.testCase?.arguments)
      try #require(arguments.count == 1)

      let argument = arguments[0]
      let value = try #require(argument.value as? (String, Int))
      #expect(value.0 == "value")
      #expect(value.1 == 123)
      #expect(argument.parameter.index == 0)
      #expect(argument.parameter.firstName == "x")
      #expect(argument.parameter.typeInfo.fullyQualifiedName == "(key: Swift.String, value: Swift.Int)")
      #expect(argument.parameter.typeInfo.unqualifiedName == "(key: String, value: Int)")
    }

    await runTestFunction(named: "oneDictionaryElementTupleParameter(x:)", in: ParameterizedTests.self, configuration: configuration)
  }
}

// MARK: - Fixture tests

@Suite(.hidden)
struct ParameterizedTests {
  @Test(.hidden, arguments: ["value"])
  func oneParameter(x: String) {}

  @Test(.hidden, arguments: ["value"], [123])
  func twoParameters(x: String, y: Int) {}

  @Test(.hidden, arguments: [("value")])
  func one1TupleParameter(x: (String)) {}

  @Test(.hidden, arguments: [("value", 123)])
  func one2TupleParameter(x: (String, Int)) {}

  @Test(.hidden, arguments: [
    (nil, 123),
    ("value1", nil),
    ("value2", nil),
  ] as [(String?, Int?)])
  func contextualArrayLiteral(x: String?, y: Int?) {}

  @Test(.hidden, arguments: ["value": 123])
  func twoDictionaryElementParameters(x: String, y: Int) {}

  @Test(.hidden, arguments: ["value": 123])
  func oneDictionaryElementTupleParameter(x: (key: String, value: Int)) {}

  @Test(.hidden, arguments: [
    "value1": nil,
    "value2": 123,
  ] as KeyValuePairs<String, Int?>)
  func contextualDictionaryLiteral(key: String, value: Int?) {}

  @Test(.disabled(), arguments: [1, 2, 3]) func disabled(x: Int) {}
}
