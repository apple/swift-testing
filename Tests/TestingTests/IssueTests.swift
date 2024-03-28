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
private import TestingInternals
import Foundation

#if canImport(XCTest)
import XCTest

final class IssueTests: XCTestCase {
  func testExpect() async throws {
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      XCTAssertFalse(issue.isKnown)
      guard case let .expectationFailed(expectation) = issue.kind else {
        XCTFail("Unexpected issue kind \(issue.kind)")
        return
      }
      XCTAssertFalse(expectation.isRequired)
    }

    await Test {
      #expect(Bool(true))
      #expect(Bool(false))
      #expect(Bool(false), "Custom message")
    }.run(configuration: configuration)
  }

  func testErrorThrownFromExpect() async throws {
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      XCTAssertFalse(issue.isKnown)
      guard case let .errorCaught(error) = issue.kind else {
        XCTFail("Unexpected issue kind \(issue.kind)")
        return
      }
      XCTAssertTrue(error is MyError)
    }

    await Test { () throws in
      #expect(try { throw MyError() }() as Bool)
    }.run(configuration: configuration)

    await Test { () throws in
      try #expect({ throw MyError() }())
    }.run(configuration: configuration)
  }

  func testRequire() async throws {
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      XCTAssertFalse(issue.isKnown)
      guard case let .expectationFailed(expectation) = issue.kind else {
        XCTFail("Unexpected issue kind \(issue.kind)")
        return
      }
      XCTAssertTrue(expectation.isRequired)
    }

    await Test {
      try #require(Bool(true))
      try #require(Bool(false), "Custom message")
      XCTFail("Unreachable")
    }.run(configuration: configuration)
  }

  func testOptionalUnwrapping() async throws {
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      XCTAssertFalse(issue.isKnown)
      guard case let .expectationFailed(expectation) = issue.kind else {
        XCTFail("Unexpected issue kind \(issue.kind)")
        return
      }
      XCTAssertTrue(expectation.isRequired)
    }

    await Test {
      let x: Int? = 1
      XCTAssertEqual(1, try #require(x))
      let y: String? = nil
      _ = try #require(y)
      XCTFail("Unreachable")
    }.run(configuration: configuration)
  }

  func testOptionalUnwrappingWithCoalescing() async throws {
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      if case let .issueRecorded(issue) = event.kind {
        XCTFail("Unexpected issue kind \(issue.kind)")
      }
    }

    await Test {
      let x: String? = nil
      _ = try #require(x ?? "hello")
    }.run(configuration: configuration)
  }

  func testOptionalUnwrappingWithCoalescing_Failure() async throws {
    let expectationFailed = expectation(description: "Expectation failed")

    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      if case .expectationFailed = issue.kind {
        expectationFailed.fulfill()
      }
    }

    await Test {
      let x: String? = nil
      let y: String? = nil
      _ = try #require(x ?? y)
      XCTFail("Unreachable")
    }.run(configuration: configuration)

    await fulfillment(of: [expectationFailed], timeout: 0.0)
  }

  struct TypeWithMemberFunctions {
    static func f(_ x: Int) -> Bool { false }
    static func g(label x: Int) -> Bool { false }
    static func h(_ x: () -> Void) -> Bool { false }
    static func j(_ x: Int) -> Never? { nil }
    static func k(_ x: inout Int) -> Bool { false }
    static func m(_ x: Bool) -> Bool { false }
    static func n(_ x: Int) throws -> Bool { false }
  }

  func testMemberFunctionCall() async throws {
    let expectationFailed = expectation(description: "Expectation failed")

    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      if case let .expectationFailed(expectation) = issue.kind {
        expectationFailed.fulfill()
        let desc = expectation.evaluatedExpression.expandedDescription()
        XCTAssertTrue(desc.contains("rhs → 1"))
        XCTAssertFalse(desc.contains("(("))
      }
    }

    await Test {
      let rhs = 1
      #expect(TypeWithMemberFunctions.f(rhs))
    }.run(configuration: configuration)

    await fulfillment(of: [expectationFailed], timeout: 0.0)
  }

  func testMemberFunctionCallWithLabel() async throws {
    let expectationFailed = expectation(description: "Expectation failed")

    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      if case let .expectationFailed(expectation) = issue.kind {
        expectationFailed.fulfill()
        let desc = expectation.evaluatedExpression.expandedDescription()
        XCTAssertTrue(desc.contains("label: rhs → 1"))
        XCTAssertFalse(desc.contains("(("))
      }
    }

    await Test {
      let rhs = 1
      #expect(TypeWithMemberFunctions.g(label: rhs))
    }.run(configuration: configuration)

    await fulfillment(of: [expectationFailed], timeout: 0.0)
  }

  func testMemberFunctionCallWithFunctionArgument() async throws {
    let expectationFailed = expectation(description: "Expectation failed")

    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      if case let .expectationFailed(expectation) = issue.kind {
        expectationFailed.fulfill()
        let desc = expectation.evaluatedExpression.expandedDescription()
        XCTAssertFalse(desc.contains("(Function)"))
        XCTAssertFalse(desc.contains("(("))
      }
    }

    await Test {
      #expect(TypeWithMemberFunctions.h({ }))
    }.run(configuration: configuration)

    await fulfillment(of: [expectationFailed], timeout: 0.0)
  }

  func testOptionalUnwrappingMemberFunctionCall() async throws {
    let expectationFailed = expectation(description: "Expectation failed")

    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      if case .expectationFailed = issue.kind {
        expectationFailed.fulfill()
      }
    }

    await Test {
      _ = try #require(TypeWithMemberFunctions.j(1))
    }.run(configuration: configuration)

    await fulfillment(of: [expectationFailed], timeout: 0.0)
  }

  func testMemberFunctionCallWithInoutArgument() async throws {
    let expectationFailed = expectation(description: "Expectation failed")
    expectationFailed.expectedFulfillmentCount = 2

    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      if case .expectationFailed = issue.kind {
        expectationFailed.fulfill()
      }
    }

    await Test {
      var i = 0
      #expect(TypeWithMemberFunctions.k(&i))
      #expect(TypeWithMemberFunctions.m(TypeWithMemberFunctions.k(&i)))
    }.run(configuration: configuration)

    await fulfillment(of: [expectationFailed], timeout: 0.0)
  }

  func testThrowingMemberFunctionCall() async throws {
    let expectationFailed = expectation(description: "Expectation failed")
    expectationFailed.expectedFulfillmentCount = 2

    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      if case let .expectationFailed(expectation) = issue.kind {
        expectationFailed.fulfill()
        // The presence of `try` means we don't do complex expansion (yet.)
        XCTAssertNotNil(expectation.evaluatedExpression)
        XCTAssertNil(expectation.evaluatedExpression.runtimeValue)
      }
    }

    await Test { () throws in
      #expect(try TypeWithMemberFunctions.n(0) as Bool)
      #expect(TypeWithMemberFunctions.f(try { () throws in 0 }()) as Bool)
    }.run(configuration: configuration)

    await fulfillment(of: [expectationFailed], timeout: 0.0)
  }

  func testExpectationValueLazyStringification() async {
    struct Delicate: Equatable, CustomStringConvertible {
      var description: String {
        XCTFail("Should not be called")
        return "danger"
      }
    }

    let expectationChecked = expectation(description: "expectation checked")

    var configuration = Configuration()
    configuration.deliverExpectationCheckedEvents = true
    configuration.eventHandler = { event, _ in
      guard case let .expectationChecked(expectation) = event.kind else {
        return
      }
      XCTAssertNotNil(expectation.evaluatedExpression)
      XCTAssertNil(expectation.evaluatedExpression.subexpressions[0].runtimeValue)
      expectationChecked.fulfill()
    }

    await Test {
      #expect(Delicate() == Delicate())
    }.run(configuration: configuration)
    await fulfillment(of: [expectationChecked], timeout: 0.0)
  }

  func testExpressionLiterals() async {
    func expectIssue(containing content: String, in testFunction: @escaping @Sendable () async throws -> Void) async {
      let issueRecorded = expectation(description: "Issue recorded")

      var configuration = Configuration()
      configuration.eventHandler = { event, _ in
        guard case let .issueRecorded(issue) = event.kind,
              case let .expectationFailed(expectation) = issue.kind else {
          return
        }
        XCTAssertTrue(issue.comments.isEmpty)
        let expandedExpressionDescription = expectation.evaluatedExpression.expandedDescription()
        XCTAssert(expandedExpressionDescription.contains(content))
        issueRecorded.fulfill()
      }

      await Test(testFunction: testFunction).run(configuration: configuration)
      await fulfillment(of: [issueRecorded], timeout: 0.0)
    }

    @Sendable func someInt() -> Int { 0 }
    @Sendable func someString() -> String { "a" }

    await expectIssue(containing: "(someInt() → 0) == 1") {
      #expect(someInt() == 1)
    }
    await expectIssue(containing: "1 == (someInt() → 0)") {
      #expect(1 == someInt())
    }
    await expectIssue(containing: "(someString() → \"a\") == \"b\"") {
      #expect(someString() == "b")
    }
  }

  struct ExpressionRuntimeValueCapture_Value {}

  func testExpressionRuntimeValueCapture() throws {
    var expression = Expression.__fromSyntaxNode("abc123")
    XCTAssertEqual(expression.sourceCode, "abc123")
    XCTAssertNil(expression.runtimeValue)

    do {
      expression = expression.capturingRuntimeValues(987 as Int)
      XCTAssertEqual(expression.sourceCode, "abc123")
      let runtimeValue = try XCTUnwrap(expression.runtimeValue)
      XCTAssertEqual(String(describing: runtimeValue), "987")
      XCTAssertEqual(runtimeValue.typeInfo.fullyQualifiedName, "Swift.Int")
      XCTAssertFalse(runtimeValue.isCollection)
    }

    do {
      expression = expression.capturingRuntimeValues(ExpressionRuntimeValueCapture_Value())
      XCTAssertEqual(expression.sourceCode, "abc123")
      let runtimeValue = try XCTUnwrap(expression.runtimeValue)
      XCTAssertEqual(String(describing: runtimeValue), "ExpressionRuntimeValueCapture_Value()")
      XCTAssertEqual(runtimeValue.typeInfo.fullyQualifiedName, "TestingTests.IssueTests.ExpressionRuntimeValueCapture_Value")
      XCTAssertFalse(runtimeValue.isCollection)
    }

    do {
      expression = expression.capturingRuntimeValues((123, "abc") as (Int, String), ())
      XCTAssertEqual(expression.sourceCode, "abc123")
      let runtimeValue = try XCTUnwrap(expression.runtimeValue)
      XCTAssertEqual(String(describing: runtimeValue), #"(123, "abc")"#)
      XCTAssertEqual(runtimeValue.typeInfo.fullyQualifiedName, "(Swift.Int, Swift.String)")
      XCTAssertFalse(runtimeValue.isCollection)
    }
  }

  struct ExpressionRuntimeValueCapture_ValueWithChildren {
    var contents: [Any] = []
  }

  func testExpressionRuntimeValueChildren() throws {
    var expression = Expression.__fromSyntaxNode("abc123")
    XCTAssertEqual(expression.sourceCode, "abc123")
    XCTAssertNil(expression.runtimeValue)

    do {
      expression = expression.capturingRuntimeValues(ExpressionRuntimeValueCapture_Value())
      let runtimeValue = try XCTUnwrap(expression.runtimeValue)
      XCTAssertEqual(String(describing: runtimeValue), "ExpressionRuntimeValueCapture_Value()")
      XCTAssertEqual(runtimeValue.typeInfo.fullyQualifiedName, "TestingTests.IssueTests.ExpressionRuntimeValueCapture_Value")
      XCTAssertFalse(runtimeValue.isCollection)
      XCTAssertNil(runtimeValue.children)
      XCTAssertNil(runtimeValue.label)
    }

    do {
      expression = expression.capturingRuntimeValues(ExpressionRuntimeValueCapture_ValueWithChildren(contents: [123, "abc"]))
      let runtimeValue = try XCTUnwrap(expression.runtimeValue)
      XCTAssertEqual(String(describing: runtimeValue), #"ExpressionRuntimeValueCapture_ValueWithChildren(contents: [123, "abc"])"#)
      XCTAssertEqual(runtimeValue.typeInfo.fullyQualifiedName, "TestingTests.IssueTests.ExpressionRuntimeValueCapture_ValueWithChildren")
      XCTAssertFalse(runtimeValue.isCollection)
      XCTAssertNil(runtimeValue.label)

      let children = try XCTUnwrap(runtimeValue.children)
      XCTAssertEqual(children.count, 1)
      let contentsArrayChild = try XCTUnwrap(children.first)
      XCTAssertEqual(String(describing: contentsArrayChild), #"[123, "abc"]"#)
      XCTAssertTrue(contentsArrayChild.isCollection)
      XCTAssertEqual(contentsArrayChild.label, "contents")

      let contentsChildren = try XCTUnwrap(contentsArrayChild.children)
      XCTAssertEqual(contentsChildren.count, 2)
      let firstContentsElementChild = try XCTUnwrap(contentsChildren.first)
      XCTAssertEqual(String(describing: firstContentsElementChild), "123")
      XCTAssertFalse(firstContentsElementChild.isCollection)
      XCTAssertNil(firstContentsElementChild.label)
    }

    do {
      expression = expression.capturingRuntimeValues([])
      let runtimeValue = try XCTUnwrap(expression.runtimeValue)
      XCTAssertEqual(String(describing: runtimeValue), "[]")
      XCTAssertEqual(runtimeValue.typeInfo.fullyQualifiedName, "Swift.Array<Any>")
      XCTAssertTrue(runtimeValue.isCollection)
      XCTAssertNil(runtimeValue.label)

      let children = try XCTUnwrap(runtimeValue.children)
      XCTAssertTrue(children.isEmpty)
    }
  }

  func testIsAndAsComparisons() async {
    let expectRecorded = expectation(description: "#expect recorded")
    let requireRecorded = expectation(description: "#require recorded")

    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      XCTAssertFalse(issue.isKnown)
      guard case let .expectationFailed(expectation) = issue.kind else {
        XCTFail("Unexpected issue kind \(issue.kind)")
        return
      }
      let expandedExpressionDescription = expectation.evaluatedExpression.expandedDescription()
      XCTAssertTrue(expandedExpressionDescription.contains("someString() → \"abc123\""))
      XCTAssertTrue(expandedExpressionDescription.contains("Int → String"))

      if expectation.isRequired {
        requireRecorded.fulfill()
      } else {
        expectRecorded.fulfill()
      }
    }

    await Test { () throws in
      @Sendable func randomNumber() -> Any {
        Int.random(in: 0 ..< 100)
      }
      @Sendable func someString() -> Any {
        "abc123"
      }

      #expect(randomNumber() is Int)
      let _: Int = try #require(randomNumber() as? Int)
      #expect(someString() is String)
      #expect(someString() is Int) // raises issue
      let _: Int = try #require(someString() as? Int) // raises issue
    }.run(configuration: configuration)
    await fulfillment(of: [expectRecorded, requireRecorded], timeout: 0.0)
  }

  func testCastAsAnyProtocol() async {
    // Sanity check that we parse types cleanly.
    await Test {
      #expect((1 as Any) is any Numeric)
      _ = try #require((1 as Any) as? any Numeric)
    }.run(configuration: .init())
  }

  func testErrorCheckingWithExpect() async throws {
    let expectationFailed = expectation(description: "Expectation failed")
    expectationFailed.isInverted = true

    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      guard case .expectationFailed = issue.kind else {
        XCTFail("Unexpected issue kind \(issue.kind)")
        return
      }
      expectationFailed.fulfill()
    }

    @Sendable @available(*, noasync) func asyncNotRequired() {}

    let randomNumber = Int.random(in: 0 ... .max)
    await Test {
      #expect {
        asyncNotRequired()
        throw MyError()
      } throws: {
        $0 is MyError
      }
      #expect(throws: MyError.self) {
        asyncNotRequired()
        throw MyError()
      }
      #expect(throws: MyParameterizedError(index: randomNumber)) {
        asyncNotRequired()
        throw MyParameterizedError(index: randomNumber)
      }
      #expect(throws: Never.self) {}
      func genericExpectThrows(_ type: (some Error).Type) {
        #expect(throws: type) {}
      }
      genericExpectThrows(Never.self)
      func nonVoidReturning() throws -> Int { throw MyError() }
      #expect(throws: MyError.self) {
        try nonVoidReturning()
      }
    }.run(configuration: configuration)

    await fulfillment(of: [expectationFailed], timeout: 0.0)
  }

  func testErrorCheckingWithExpect_Mismatching() async throws {
    let expectationFailed = expectation(description: "Expectation failed")
    expectationFailed.expectedFulfillmentCount = 13

    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      guard case .expectationFailed = issue.kind else {
        XCTFail("Unexpected issue kind \(issue.kind)")
        return
      }
      expectationFailed.fulfill()
    }

    @Sendable @available(*, noasync) func asyncNotRequired() {}
    let randomNumber = Int.random(in: 0 ... .max)

    await Test {
      #expect {
        asyncNotRequired()
      } throws: {
        $0 is MyError
      }
      #expect(throws: MyError.self) {
        asyncNotRequired()
      }
      #expect(throws: MyParameterizedError(index: randomNumber)) {
        asyncNotRequired()
      }
      #expect(throws: MyError.self) {
        throw MyParameterizedError(index: 0)
      }
      #expect(throws: MyError()) {
        throw MyParameterizedError(index: 0)
      }
      #expect(throws: MyError.self) {
        throw MyDescriptiveError(description: "something wrong")
      }
      #expect(throws: MyError()) {
        throw MyDescriptiveError(description: "something wrong")
      }
      #expect {
        throw MyDescriptiveError(description: "something wrong")
      } throws: {
        _ in false
      }
      #expect(throws: Never.self) {
        throw MyError()
      }
      func genericExpectThrows(_ type: (some Error).Type) {
        #expect(throws: type) {
          throw MyError()
        }
      }
      genericExpectThrows(Never.self)
      func nonVoidReturning() throws -> Int { 0 }
      #expect(throws: MyError.self) {
        try nonVoidReturning()
      }
      #expect {
        throw MyError()
      } throws: { error in
        let parameterizedError = try #require(error as? MyParameterizedError)
        return parameterizedError.index == 123
      }
    }.run(configuration: configuration)

    await fulfillment(of: [expectationFailed], timeout: 0.0)
  }

  func testErrorCheckingWithExpect_mismatchedErrorDescription() async throws {
    let expectationFailed = expectation(description: "Expectation failed")

    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      guard case let .expectationFailed(expectation) = issue.kind else {
        XCTFail("Unexpected issue kind \(issue.kind)")
        return
      }
      XCTAssertEqual(expectation.mismatchedErrorDescription, "an error was expected but none was thrown")
      expectationFailed.fulfill()
    }

    await Test {
      func voidReturning() throws {}
      #expect(throws: MyError.self) {
        try voidReturning()
      }
    }.run(configuration: configuration)

    await fulfillment(of: [expectationFailed], timeout: 0.0)
  }

  func testErrorCheckingWithExpect_mismatchedErrorDescription_nonVoid() async throws {
    let expectationFailed = expectation(description: "Expectation failed")

    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      guard case let .expectationFailed(expectation) = issue.kind else {
        XCTFail("Unexpected issue kind \(issue.kind)")
        return
      }
      XCTAssertEqual(expectation.mismatchedErrorDescription, "an error was expected but none was thrown and \"0\" was returned")
      expectationFailed.fulfill()
    }

    await Test {
      func nonVoidReturning() throws -> Int { 0 }
      #expect(throws: MyError.self) {
        try nonVoidReturning()
      }
    }.run(configuration: configuration)

    await fulfillment(of: [expectationFailed], timeout: 0.0)
  }

  func testErrorCheckingWithExpectAsync() async throws {
    let expectationFailed = expectation(description: "Expectation failed")
    expectationFailed.isInverted = true

    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      guard case .expectationFailed = issue.kind else {
        XCTFail("Unexpected issue kind \(issue.kind)")
        return
      }
      expectationFailed.fulfill()
    }

    let randomNumber = Int.random(in: 0 ... .max)
    await Test {
      await #expect { () async throws in
        throw MyError()
      } throws: {
        $0 is MyError
      }
      await #expect(throws: MyError.self) { () async throws in
        throw MyError()
      }
      await #expect(throws: MyParameterizedError(index: randomNumber)) { () async throws in
        throw MyParameterizedError(index: randomNumber)
      }
      await #expect(throws: Never.self) { () async in }
      func genericExpectThrows(_ type: (some Error).Type) async {
        await #expect(throws: type) { () async in }
      }
      await genericExpectThrows(Never.self)
      func nonVoidReturning() async throws -> Int { throw MyError() }
      await #expect(throws: MyError.self) {
        try await nonVoidReturning()
      }
    }.run(configuration: configuration)

    await fulfillment(of: [expectationFailed], timeout: 0.0)
  }

  func testErrorCheckingWithExpectAsync_Mismatching() async throws {
    let expectationFailed = expectation(description: "Expectation failed")
    expectationFailed.expectedFulfillmentCount = 13

    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      guard case .expectationFailed = issue.kind else {
        XCTFail("Unexpected issue kind \(issue.kind)")
        return
      }
      expectationFailed.fulfill()
    }

    let randomNumber = Int.random(in: 0 ... .max)
    await Test {
      await #expect { () async in } throws: {
        $0 is MyError
      }
      await #expect(throws: MyError.self) { () async in }
      await #expect(throws: MyParameterizedError(index: randomNumber)) { () async in }
      await #expect(throws: MyError.self) { () async throws in
        throw MyParameterizedError(index: 0)
      }
      await #expect(throws: MyError()) { () async throws in
        throw MyParameterizedError(index: 0)
      }
      await #expect(throws: MyError.self) { () async throws in
        throw MyDescriptiveError(description: "something wrong")
      }
      await #expect(throws: MyError()) { () async throws in
        throw MyDescriptiveError(description: "something wrong")
      }
      await #expect { () async throws in
        throw MyDescriptiveError(description: "something wrong")
      } throws: {
        _ in false
      }
      await #expect(throws: Never.self) { () async throws in
        throw MyError()
      }
      func genericExpectThrows(_ type: (some Error).Type) async {
        await #expect(throws: type) { () async throws in
          throw MyError()
        }
      }
      await genericExpectThrows(Never.self)
      func nonVoidReturning() async throws -> Int { 0 }
      await #expect(throws: MyError.self) {
        try await nonVoidReturning()
      }
      await #expect { () async throws in
        throw MyError()
      } throws: { error in
        let parameterizedError = try #require(error as? MyParameterizedError)
        return parameterizedError.index == 123
      }
    }.run(configuration: configuration)

    await fulfillment(of: [expectationFailed], timeout: 0.0)
  }

  func testErrorCheckingWithExpectAsync_mismatchedErrorDescription() async throws {
    let expectationFailed = expectation(description: "Expectation failed")

    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      guard case let .expectationFailed(expectation) = issue.kind else {
        XCTFail("Unexpected issue kind \(issue.kind)")
        return
      }
      XCTAssertEqual(expectation.mismatchedErrorDescription, "an error was expected but none was thrown")
      expectationFailed.fulfill()
    }

    await Test {
      func voidReturning() async throws {}
      await #expect(throws: MyError.self) {
        try await voidReturning()
      }
    }.run(configuration: configuration)

    await fulfillment(of: [expectationFailed], timeout: 0.0)
  }

  func testErrorCheckingWithExpectAsync_mismatchedErrorDescription_nonVoid() async throws {
    let expectationFailed = expectation(description: "Expectation failed")

    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      guard case let .expectationFailed(expectation) = issue.kind else {
        XCTFail("Unexpected issue kind \(issue.kind)")
        return
      }
      XCTAssertEqual(expectation.mismatchedErrorDescription, "an error was expected but none was thrown and \"0\" was returned")
      expectationFailed.fulfill()
    }

    await Test {
      func nonVoidReturning() async throws -> Int { 0 }
      await #expect(throws: MyError.self) {
        try await nonVoidReturning()
      }
    }.run(configuration: configuration)

    await fulfillment(of: [expectationFailed], timeout: 0.0)
  }

  func testErrorCheckingWithExpect_ThrowingFromErrorMatcher() async throws {
    let errorCaught = expectation(description: "Error matcher's error caught")
    let expectationFailed = expectation(description: "Expectation failed")

    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      if case let .errorCaught(error) = issue.kind, error is MyParameterizedError {
        errorCaught.fulfill()
      } else if case .expectationFailed = issue.kind {
        expectationFailed.fulfill()
      }
    }

    await Test {
      #expect {
        throw MyError()
      } throws: { _ in
        throw MyParameterizedError(index: 0)
      }
    }.run(configuration: configuration)

    await fulfillment(of: [errorCaught, expectationFailed], timeout: 0.0)
  }

  func testErrorCheckingWithExpectAsync_ThrowingFromErrorMatcher() async throws {
    let errorCaught = expectation(description: "Error matcher's error caught")
    let expectationFailed = expectation(description: "Expectation failed")

    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      if case let .errorCaught(error) = issue.kind, error is MyParameterizedError {
        errorCaught.fulfill()
      } else if case .expectationFailed = issue.kind {
        expectationFailed.fulfill()
      }
    }

    await Test {
      await #expect {
        throw MyError()
      } throws: { (_) async throws in
        throw MyParameterizedError(index: 0)
      }
    }.run(configuration: configuration)

    await fulfillment(of: [errorCaught, expectationFailed], timeout: 0.0)
  }

  func testErrorCheckingWithRequire_ThrowingFromErrorMatcher() async throws {
    let errorCaught = expectation(description: "Error matcher's error caught")
    let expectationFailed = expectation(description: "Expectation failed")

    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      if case let .errorCaught(error) = issue.kind, error is MyParameterizedError {
        errorCaught.fulfill()
      } else if case .expectationFailed = issue.kind {
        expectationFailed.fulfill()
      }
    }

    await Test {
      try #require {
        throw MyError()
      } throws: { _ in
        throw MyParameterizedError(index: 0)
      }
      XCTFail("Should be unreachable")
    }.run(configuration: configuration)

    await fulfillment(of: [errorCaught, expectationFailed], timeout: 0.0)
  }

  func testErrorCheckingWithRequireAsync_ThrowingFromErrorMatcher() async throws {
    let errorCaught = expectation(description: "Error matcher's error caught")
    let expectationFailed = expectation(description: "Expectation failed")

    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      if case let .errorCaught(error) = issue.kind, error is MyParameterizedError {
        errorCaught.fulfill()
      } else if case .expectationFailed = issue.kind {
        expectationFailed.fulfill()
      }
    }

    await Test {
      try await #require {
        throw MyError()
      } throws: { (_) async throws in
        throw MyParameterizedError(index: 0)
      }
      XCTFail("Should be unreachable")
    }.run(configuration: configuration)

    await fulfillment(of: [errorCaught, expectationFailed], timeout: 0.0)
  }

  func testFail() async throws {
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      XCTAssertFalse(issue.isKnown)
      guard case .unconditional = issue.kind else {
        XCTFail("Unexpected issue kind \(issue.kind)")
        return
      }
    }

    await Test {
      Issue.record()
      Issue.record("Custom message")
    }.run(configuration: configuration)
  }

#if !SWT_NO_UNSTRUCTURED_TASKS
  func testFailWithoutCurrentTest() async throws {
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      XCTAssertFalse(issue.isKnown)
      XCTAssertNil(event.testID)
    }

    await Test {
      await Task.detached {
        _ = Issue.record()
      }.value
    }.run(configuration: configuration)
  }
#endif

  func testFailBecauseOfError() async throws {
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      XCTAssertFalse(issue.isKnown)
      guard case let .errorCaught(error) = issue.kind else {
        XCTFail("Unexpected issue kind \(issue.kind)")
        return
      }
      XCTAssertTrue(error is MyError)
    }

    await Test {
      Issue.record(MyError())
      Issue.record(MyError(), "Custom message")
    }.run(configuration: configuration)
  }

  func testErrorPropertyValidForThrownErrors() async throws {
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      XCTAssertFalse(issue.isKnown)
      XCTAssertNotNil(issue.error)
    }
    await Test {
      throw MyError()
    }.run(configuration: configuration)
  }

  func testErrorPropertyNilForOtherIssueKinds() async throws {
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      XCTAssertFalse(issue.isKnown)
      XCTAssertNil(issue.error)
    }
    await Test {
      Issue.record()
    }.run(configuration: configuration)
  }

  func testGetSourceLocationProperty() async throws {
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      XCTAssertFalse(issue.isKnown)
      guard let sourceLocation = issue.sourceLocation else {
        return XCTFail("Expected a source location")
      }
      XCTAssertEqual(sourceLocation.fileID, #fileID)
    }
    await Test {
      Issue.record()
      Issue.record("Custom message")
    }.run(configuration: configuration)
  }

  func testSetSourceLocationProperty() async throws {
    let sourceLocation = SourceLocation(line: 12345)
    var issue = Issue(kind: .unconditional, comments: [], sourceContext: .init(sourceLocation: sourceLocation))

    var issueSourceLocation = try XCTUnwrap(issue.sourceLocation)
    XCTAssertEqual(issueSourceLocation.line, 12345)

    issue.sourceLocation?.line = 67890

    issueSourceLocation = try XCTUnwrap(issue.sourceLocation)
    XCTAssertEqual(issueSourceLocation.line, 67890)
  }

  func testDescriptionProperties() {
    do {
      let sourceLocation = SourceLocation.init(fileID: "FakeModule/FakeFile.swift", line: 9999, column: 1)
      let issue = Issue(kind: .system, comments: ["Some issue"], sourceContext: SourceContext(sourceLocation: sourceLocation))
      XCTAssertEqual(issue.description, "A system failure occurred: Some issue")
      XCTAssertEqual(issue.debugDescription, "A system failure occurred at FakeFile.swift:9999:1: Some issue")
    }
    do {
      let issue = Issue(kind: .system, comments: ["Some issue"], sourceContext: SourceContext(sourceLocation: nil))
      XCTAssertEqual(issue.debugDescription, "A system failure occurred: Some issue")
    }
  }

  func testCollectionDifference() async {
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      guard case let .expectationFailed(expectation) = issue.kind else {
        XCTFail("Unexpected issue kind \(issue.kind)")
        return
      }
      guard let differenceDescription = expectation.differenceDescription else {
        return XCTFail("Unexpected nil differenceDescription")
      }
      XCTAssertTrue(differenceDescription.contains("inserted ["))
      XCTAssertTrue(differenceDescription.contains("removed ["))
    }

    await Test {
      let lhs = [1, 2, 3, 4, 5]
      let rhs = [1, 2, 4, 3, 7, 5, 6]
      #expect(lhs == rhs)
    }.run(configuration: configuration)
  }

  func testCollectionDifferenceSkippedForStrings() async {
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      guard case let .expectationFailed(expectation) = issue.kind else {
        XCTFail("Unexpected issue kind \(issue.kind)")
        return
      }
      XCTAssertNil(expectation.differenceDescription)
    }

    await Test {
      #expect("hello" == "helbo")
    }.run(configuration: configuration)
  }

  func testNegatedExpressions() async {
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      if case let .issueRecorded(issue) = event.kind {
        XCTFail("Unexpected issue \(issue)")
      }
    }

    await Test {
      #expect(!Bool(false))
      #expect(Bool((!false)))
      #expect(Bool((!(false))))
      #expect(!(!true))
      #expect(!(1 > 2))
    }.run(configuration: configuration)
  }

  func testNegatedExpressionsHaveCorrectCapturedExpressions() async {
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      XCTAssertEqual(issue.comments.first, "!(   Bool(false)    )")
    }

    await Test {
      #expect(!(   Bool(false)    ))
    }.run(configuration: configuration)
  }

  func testLazyExpectDoesNotEvaluateRightHandValue() async {
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      XCTAssertFalse(issue.isKnown)
      guard case let .expectationFailed(expectation) = issue.kind else {
        XCTFail("Unexpected issue kind \(issue.kind)")
        return
      }
      let expression = expectation.evaluatedExpression
      XCTAssertTrue(expression.expandedDescription().contains("<not evaluated>"))
    }

    @Sendable func rhs() -> Bool {
      XCTFail("Invoked RHS function")
      return false
    }

    await Test {
      #expect(false && rhs())
    }.run(configuration: configuration)
  }

  func testLazyExpectEvaluatesRightHandValueWhenNeeded() async {
    let rhsCalled = expectation(description: "RHS function called")
    @Sendable func rhs() -> Bool {
      rhsCalled.fulfill()
      return true
    }

    await Test {
      #expect(false || rhs())
    }.run()

    await fulfillment(of: [rhsCalled], timeout: 0.0)
  }

  func testRequireOptionalMemberAccessEvaluatesToNil() async {
    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      XCTAssertFalse(issue.isKnown)
      guard case let .expectationFailed(expectation) = issue.kind else {
        XCTFail("Unexpected issue kind \(issue.kind)")
        return
      }
      let expression = expectation.evaluatedExpression
      XCTAssertTrue(expression.expandedDescription().contains("nil"))
      XCTAssertFalse(expression.expandedDescription().contains("<not evaluated>"))
    }

    await Test {
      let array = [String]()
      _ = try #require(array.first)
    }.run(configuration: configuration)
  }

  func testOptionalOperand() async {
    let expectationFailed = expectation(description: "Expectation failed")

    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      if case let .expectationFailed(expectation) = issue.kind {
        expectationFailed.fulfill()
        let desc = expectation.evaluatedExpression.expandedDescription()
        XCTAssertTrue(desc.contains("7"))
        XCTAssertFalse(desc.contains("Optional(7)"))
      }
    }

    await Test {
      let nonNilOptional: Int? = 7
      #expect(nonNilOptional == 8)
    }.run(configuration: configuration)

    await fulfillment(of: [expectationFailed], timeout: 0.0)
  }

  func testNilOptionalOperand() async {
    let expectationFailed = expectation(description: "Expectation failed")

    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      if case let .expectationFailed(expectation) = issue.kind {
        expectationFailed.fulfill()
        let desc = expectation.evaluatedExpression.expandedDescription()
        XCTAssertTrue(desc.contains("nil"))
      }
    }

    await Test {
      let optionalValue: Int? = nil
      #expect(optionalValue == 8)
    }.run(configuration: configuration)

    await fulfillment(of: [expectationFailed], timeout: 0.0)
  }

  func testNilOptionalCallResult() async {
    let expectationFailed = expectation(description: "Expectation failed")

    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      if case let .expectationFailed(expectation) = issue.kind {
        expectationFailed.fulfill()
        let desc = expectation.evaluatedExpression.expandedDescription()
        XCTAssertTrue(desc.contains("nil"))
      }
    }

    @Sendable func f() -> Int? { nil }

    await Test {
      _ = try #require(f())
    }.run(configuration: configuration)

    await fulfillment(of: [expectationFailed], timeout: 0.0)
  }

  func testCustomTestStringConvertible() async {
    struct Food: CustomTestStringConvertible {
      func addSeasoning() -> Bool { false }
      var testDescription: String {
        "Delicious Food, Yay!"
      }
    }

    let expectationFailed = expectation(description: "Expectation failed")

    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      if case let .expectationFailed(expectation) = issue.kind {
        expectationFailed.fulfill()
        let desc = expectation.evaluatedExpression.expandedDescription()
        XCTAssertTrue(desc.contains("Delicious Food, Yay!"))
      }
    }

    await Test {
      #expect(Food().addSeasoning())
    }.run(configuration: configuration)

    await fulfillment(of: [expectationFailed], timeout: 0.0)
  }

  func testEnumDescription() async throws {
    guard #available(_mangledTypeNameAPI, *) else {
      throw XCTSkip("Unavailable")
    }

    enum E: CaseIterable {
      case a
      case b
    }

    let expectationFailed = expectation(description: "Expectation failed")

    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      if case let .expectationFailed(expectation) = issue.kind {
        expectationFailed.fulfill()
        let desc = expectation.evaluatedExpression.expandedDescription()
        XCTAssertTrue(desc.contains(".b"))
        XCTAssertFalse(desc.contains("→ .b"))
      }
    }

    await Test(arguments: E.allCases) { e in
      #expect(e == .b)
    }.run(configuration: configuration)

    await fulfillment(of: [expectationFailed], timeout: 0.0)
  }

  func testEnumWithCustomDescription() async {
    enum E: CaseIterable, CustomStringConvertible {
      case a
      case b
      var description: String {
        "customDesc"
      }
    }

    let expectationFailed = expectation(description: "Expectation failed")

    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      if case let .expectationFailed(expectation) = issue.kind {
        expectationFailed.fulfill()
        let desc = expectation.evaluatedExpression.expandedDescription()
        XCTAssertTrue(desc.contains(".b → customDesc"))
        XCTAssertFalse(desc.contains(".customDesc"))
      }
    }

    await Test(arguments: E.allCases) { e in
      #expect(e == .b)
    }.run(configuration: configuration)

    await fulfillment(of: [expectationFailed], timeout: 0.0)
  }

  func testCEnumDescription() async throws {
    guard #available(_mangledTypeNameAPI, *) else {
      throw XCTSkip("Unavailable")
    }

    let expectationFailed = expectation(description: "Expectation failed")

    var configuration = Configuration()
    configuration.eventHandler = { event, _ in
      guard case let .issueRecorded(issue) = event.kind else {
        return
      }
      if case let .expectationFailed(expectation) = issue.kind {
        expectationFailed.fulfill()
        let desc = expectation.evaluatedExpression.expandedDescription()
        XCTAssertTrue(desc.contains(".A → SWTTestEnumeration(rawValue: \(SWTTestEnumeration.A.rawValue))"))
        XCTAssertFalse(desc.contains(".SWTTestEnumeration"))
      }
    }

    await Test(arguments: [SWTTestEnumeration.A, SWTTestEnumeration.B]) { e in
      #expect(e == .A)
    }.run(configuration: configuration)

    await fulfillment(of: [expectationFailed], timeout: 0.0)
  }
}
#endif

@Suite("Issue Codable Conformance Tests")
struct IssueCodingTests {

  @Test("Codable",
        arguments: [
          Issue.Kind.apiMisused,
          Issue.Kind.confirmationMiscounted(actual: 13, expected: 42),
          Issue.Kind.errorCaught(NSError(domain: "Domain", code: 13, userInfo: ["UserInfoKey": "UserInfoValue"])),
          Issue.Kind.expectationFailed(Expectation(evaluatedExpression: .__fromSyntaxNode("abc"), isPassing: true, isRequired: true, sourceLocation: SourceLocation())),
          Issue.Kind.knownIssueNotRecorded,
          Issue.Kind.system,
          Issue.Kind.timeLimitExceeded(timeLimitComponents: (13, 42)),
          Issue.Kind.unconditional,
        ]
  )
  func testCodable(issueKind: Issue.Kind) async throws {
    let issue = Issue(kind: issueKind,
                      comments: ["Comment"],
                      sourceContext: SourceContext(backtrace: Backtrace.current(), sourceLocation: SourceLocation()))
    let issueSnapshot = Issue.Snapshot(snapshotting: issue)
    let encoded = try JSONEncoder().encode(issueSnapshot)
    let decoded = try JSONDecoder().decode(Issue.Snapshot.self, from: encoded)

    #expect(String(describing: decoded) == String(describing: issueSnapshot))
  }

  @Test func errorSnapshot() throws {
    let issue = Issue(kind: .errorCaught(NSError(domain: "Domain", code: 13)), comments: [])
    let underlyingError = try #require(issue.error)

    let issueSnapshot = Issue.Snapshot(snapshotting: issue)
    let errorSnapshot = try #require(issueSnapshot.error)
    #expect(String(describing: errorSnapshot) == String(describing: underlyingError))
  }
}
