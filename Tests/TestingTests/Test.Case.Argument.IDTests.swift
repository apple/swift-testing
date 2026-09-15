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

#if !SWT_NO_CODABLE
@Suite("Test.Case.Argument.ID Tests")
struct Test_Case_Argument_IDTests {
  @Test("One Codable parameter")
  func oneCodableParameter() async throws {
    let test = Test(
      arguments: [123],
      parameters: [Test.Parameter(index: 0, firstName: "value", type: Int.self)]
    ) { _ in }
    let testCases = try #require(test.testCases)
    let testCase = try #require(testCases.first { _ in true })
    let arguments = try #require(testCase.arguments)
    #expect(arguments.count == 1)
    let argument = try #require(arguments.first)
    #expect(argument.id.bytes == SHA256.hash("123".utf8))
  }

  @Test("One CustomTestArgumentEncodable parameter")
  func oneCustomParameter() async throws {
    let argumentValue = MyCustomTestArgument(x: 123, y: "abc")
    let test = Test(
      arguments: [argumentValue],
      parameters: [Test.Parameter(index: 0, firstName: "value", type: MyCustomTestArgument.self)]
    ) { _ in }
    let testCases = try #require(test.testCases)
    let testCase = try #require(testCases.first { _ in true })
    let arguments = try #require(testCase.arguments)
    #expect(arguments.count == 1)
    let argument = try #require(arguments.first)
    try JSON.withEncoding(of: CustomArgumentWrapper(rawValue: argumentValue)) { data in
      #expect(argument.id.bytes == SHA256.hash(data))
    }
  }

  @Test("One Identifiable parameter")
  func oneIdentifiableParameter() async throws {
    let test = Test(
      arguments: [MyIdentifiableArgument(id: "abc")],
      parameters: [Test.Parameter(index: 0, firstName: "value", type: MyIdentifiableArgument.self)]
    ) { _ in }
    let testCases = try #require(test.testCases)
    let testCase = try #require(testCases.first { _ in true })
    let arguments = try #require(testCase.arguments)
    #expect(arguments.count == 1)
    let argument = try #require(arguments.first)
    #expect(argument.id.bytes == SHA256.hash(#""abc""#.utf8))
  }

  @Test("One RawRepresentable parameter")
  func oneRawRepresentableParameter() async throws {
    let test = Test(
      arguments: [MyRawRepresentableArgument(rawValue: "abc")],
      parameters: [Test.Parameter(index: 0, firstName: "value", type: MyRawRepresentableArgument.self)]
    ) { _ in }
    let testCases = try #require(test.testCases)
    let testCase = try #require(testCases.first { _ in true })
    let arguments = try #require(testCase.arguments)
    #expect(arguments.count == 1)
    let argument = try #require(arguments.first)
    #expect(argument.id.bytes == SHA256.hash(#""abc""#.utf8))
  }
}

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

extension MyCustomTestArgument: Decodable {}

@available(*, unavailable, message: "Intentionally not Encodable")
extension MyCustomTestArgument: Encodable {}

private struct MyIdentifiableArgument: Identifiable {
  var id: String
}

private struct MyRawRepresentableArgument: RawRepresentable {
  var rawValue: String
}
#endif
