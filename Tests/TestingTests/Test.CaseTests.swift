//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

@testable @_spi(Experimental) @_spi(ForToolsIntegrationOnly) import Testing

@Suite("Test.Case Tests")
struct Test_CaseTests {
  @Test func nonParameterized() throws {
    let testCase = Test.Case(body: {})
    #expect(testCase.id.argumentIDs == nil)
    #expect(testCase.id.discriminator == nil)
  }

#if !SWT_NO_CODABLE
  @Test func singleStableArgument() throws {
    let testCase = Test.Case(
      values: [1],
      parameters: [Test.Parameter(index: 0, firstName: "x", type: Int.self)],
      body: {}
    )
    #expect(testCase.id.isStable)
  }

  @Test func twoStableArguments() throws {
    let testCase = Test.Case(
      values: [1, "a"],
      parameters: [
        Test.Parameter(index: 0, firstName: "x", type: Int.self),
        Test.Parameter(index: 1, firstName: "y", type: String.self),
      ],
      body: {}
    )
    #expect(testCase.id.isStable)
  }

  @Test("Two arguments: one non-stable, followed by one stable")
  func nonStableAndStableArgument() throws {
    let testCase = Test.Case(
      values: [NonCodable(), IssueRecordingEncodable()],
      parameters: [
        Test.Parameter(index: 0, firstName: "x", type: NonCodable.self),
        Test.Parameter(index: 1, firstName: "y", type: IssueRecordingEncodable.self),
      ],
      body: {}
    )
    #expect(!testCase.id.isStable)
  }

  @Suite("Test.Case.ID Tests")
  struct IDTests {
    @Test(arguments: [
      Test.Case.ID(argumentIDs: nil, discriminator: nil, isStable: true),
      Test.Case.ID(argumentIDs: [.init(bytes: "x".utf8)], discriminator: 0, isStable: false),
      Test.Case.ID(argumentIDs: [.init(bytes: #""abc""#.utf8)], discriminator: 0, isStable: true),
    ])
    func roundTripping(id: Test.Case.ID) throws {
      #expect(try JSON.encodeAndDecode(id) == id)
    }

    @Test func decoding_nonParameterized() throws {
      let encodedData = Array(#"{"isStable": true}"#.utf8)
      let testCaseID = try encodedData.withUnsafeBytes { encodedData in
        try JSON.decode(Test.Case.ID.self, from: encodedData)
      }
      #expect(testCaseID.isStable)
      #expect(testCaseID.argumentIDs == nil)
      #expect(testCaseID.discriminator == nil)
    }

    @Test func decoding_parameterizedStable() throws {
      let encodedData = Array("""
        {
          "isStable": true,
          "argIDs": [
            {"bytes": [1]}
          ],
          "discriminator": 0
        }
        """.utf8)
      let testCaseID = try encodedData.withUnsafeBytes { encodedData in
        try JSON.decode(Test.Case.ID.self, from: encodedData)
      }
      #expect(testCaseID.isStable)
      #expect(testCaseID.argumentIDs?.count == 1)
      #expect(testCaseID.discriminator == 0)
    }
  }

  @Suite("Combined argument ID Tests")
  struct CombinedArgumentIDTests {
    private func makeID(_ values: [any Sendable]) -> Test.Case.ID {
      let parameters = values.indices.map {
        Test.Parameter(index: $0, firstName: "p\($0)", type: Int.self)
      }
      return Test.Case(values: values, parameters: parameters, body: {}).id
    }

    @Test("Multiple arguments are folded into a single combined ID")
    func multipleArgumentsFoldIntoOneID() {
      let id = makeID([1, 2, 3])
      #expect(id.argumentIDs?.count == 1)
    }

    @Test("Equal arguments produce equal combined IDs")
    func equalArgumentsAreDeterministic() {
      #expect(makeID([1, 2]).argumentIDs == makeID([1, 2]).argumentIDs)
    }

    @Test("Reordered arguments produce different combined IDs")
    func combinedIDIsOrderSensitive() {
      #expect(makeID([1, 2]).argumentIDs != makeID([2, 1]).argumentIDs)
    }

    @Test("A single argument's ID is used directly without combining")
    func singleArgumentIDIsUsedDirectly() throws {
      let parameter = Test.Parameter(index: 0, firstName: "x", type: Int.self)
      let argumentID = try #require(try Test.Case.Argument.ID(identifying: 1, parameter: parameter))
      #expect(makeID([1]).argumentIDs == [argumentID])
    }

    @Test("Combining is stable when all arguments are stable")
    func combinedIDIsStableForStableArguments() {
      #expect(makeID([1, 2]).isStable)
    }

    @Test("Combining preserves the nil ID for non-parameterized cases")
    func nonParameterizedCaseHasNilArgumentIDs() {
      #expect(Test.Case(body: {}).id.argumentIDs == nil)
    }
  }
#endif
}

// MARK: - Fixtures, helpers

#if !SWT_NO_CODABLE
private struct NonCodable {}

private struct IssueRecordingEncodable: Encodable {
  func encode(to encoder: any Encoder) throws {
    Issue.record("Unexpected attempt to encode an instance of \(Self.self)")
  }
}
#endif
