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
@_spi(Experimental) @_spi(ForToolsIntegrationOnly) import _TestDiscovery
private import _TestingInternals

#if canImport(Foundation)
private import Foundation
#endif

@Test(/* name unspecified */ .hidden)
@Sendable func freeSyncFunction() {}
@Sendable func freeAsyncFunction() async {}

@Test("Named Free Sync Function", .hidden)
@Sendable func namedFreeSyncFunction() {}

@Sendable func freeSyncFunctionParameterized(i: Int) {}
@Sendable func freeAsyncFunctionParameterized(_ s: String) async {}

@Sendable func freeSyncFunctionParameterized2(_ i: Int, _ j: String) {}

// This type ensures the parser can correctly infer that f() is a member
// function even though @Test is preceded by another attribute or is embedded in
// a #if statement.
@Suite(.hidden) struct TestWithPrecedingAttribute {
  @inlinable @Test(.hidden) func f() {}

#if true
  @Test(.hidden)
#endif
  func g() {}
}

@`Suite`(.hidden) struct `SuiteWithBackticks` {
  @`Test`(.hidden, .`tags`(.namedConstant)) func `testWithBackticks`() {
    #`expect`(Bool(true))
  }
}

private enum FixtureData {
  static let zeroUpTo100 = 0 ..< 100
  static let smallStringArray = ["a", "b", "c", "d"]
  static let stringReturningClosureArray = [{ @Sendable in "" }]
}

@Suite(.hidden)
@_nonSendable
private struct NonSendableTests {
  @Test(.hidden)
  func succeeds() throws {}

  @Test(.hidden, arguments: FixtureData.zeroUpTo100)
  func parameterized(i: Int) throws {}

  @Test(.hidden, arguments: FixtureData.zeroUpTo100, FixtureData.smallStringArray)
  func parameterized2(i: Int, j k: String) throws {}
}

@Suite(.hidden)
struct SendableTests: Sendable {
  @Test(.hidden)
  func succeeds() throws {}

  @Test(.hidden)
  func succeedsAsync() async throws {}

  @Test(.hidden, .disabled("Some comment"))
  func disabled() throws {}

  @Test(.hidden, arguments: FixtureData.zeroUpTo100)
  func parameterized(i: Int) async throws {}

  @Test(.hidden) static func `static`() async throws {}

  @Test(.hidden, arguments: FixtureData.zeroUpTo100)
  static func `reserved1`(`reserved2`: Int) async throws {}

  @Suite(.hidden, .tags(.namedConstant))
  struct NestedSendableTests: Sendable {
    @Test(.hidden, .tags(.anotherConstant))
    func succeeds() throws {}

    @Test(.hidden)
    func otherSucceeds() throws {}
  }

  @Test(.hidden, arguments: FixtureData.zeroUpTo100)
  func parameterizedOwned(i: __owned Int) {}

  @Test(.hidden, arguments: FixtureData.zeroUpTo100)
  func parameterizedShared(i: __shared Int) {}

  @Test(.hidden, arguments: FixtureData.zeroUpTo100)
  func parameterizedBorrowing(i: borrowing Int) {}

  @Test(.hidden, arguments: FixtureData.zeroUpTo100)
  func parameterizedBorrowingAsync(i: borrowing Int) async {}

  @MainActor
  @Test(.hidden, arguments: FixtureData.zeroUpTo100)
  func parameterizedBorrowingMainActor(i: borrowing Int) {}

  @available(*, noasync)
  @Test(.hidden, arguments: FixtureData.zeroUpTo100)
  func parameterizedBorrowingNoasync(i: borrowing Int) {}

  @Test(.hidden, arguments: FixtureData.zeroUpTo100)
  func parameterizedConsuming(i: consuming Int) {}

  @Test(.hidden, arguments: FixtureData.zeroUpTo100)
  func parameterizedConsumingAsync(i: consuming Int) async { }

  @MainActor
  @Test(.hidden, arguments: FixtureData.zeroUpTo100)
  func parameterizedConsumingMainActor(i: consuming Int) {}

  @available(*, noasync)
  @Test(.hidden, arguments: FixtureData.zeroUpTo100)
  func parameterizedConsumingNoasync(i: consuming Int) {}

  @Test(.hidden, arguments: FixtureData.stringReturningClosureArray)
  func parameterizedAcceptingFunction(f: @Sendable () -> String) {}

  @Test(.hidden) func throwKeywordInExpectation() throws {
    #expect(UInt() == UInt(try #require(Int("0"))))
  }

  @Test(.hidden) func asyncKeywordInExpectation() async {
    func f() async -> Int { 0 }
    #expect(UInt() == UInt(await f()))
  }
}

@Suite("Named Sendable test type", .hidden)
struct NamedSendableTests: Sendable {}

// This is meant to help detect unqualified usages of the `Actor` protocol from
// Swift's `_Concurrency` module in macro expansion code, since it's possible
// for another module to declare a type with that name.
private class Actor {}

#if !SWT_NO_GLOBAL_ACTORS
@Suite(.hidden)
@MainActor
struct MainActorIsolatedTests {
  @Test(.hidden)
  func succeeds() throws {}

  @Test(.hidden)
  func succeedsAsync() async throws {}

  @Test(.hidden)
  nonisolated func succeedsNonisolated() {}

  @Test(.hidden, arguments: FixtureData.zeroUpTo100)
  func parameterized(i: Int) async throws {}

  @Test(.hidden, arguments: FixtureData.zeroUpTo100)
  nonisolated func parameterizedNonisolated(i: Int) async throws {}
}
#endif

@Suite(.hidden)
actor ActorTests {
  @Test(.hidden)
  func succeeds() throws {}

  @Test(.hidden)
  func succeedsAsync() async throws {}

  @Test(.hidden)
  nonisolated func succeedsNonisolated() {}

  @Test(.hidden, arguments: FixtureData.zeroUpTo100)
  func parameterized(i: Int) async throws {}

  @Test(.hidden, arguments: FixtureData.zeroUpTo100)
  nonisolated func parameterizedNonisolated(i: Int) async throws {}
}

@Suite(.hidden) class NonFinalClassTests {
  @Test(.hidden) func f() {}
}

@Suite(.hidden)
struct TestsWithStaticMemberAccessBySelfKeyword {
  static let x = 0 ..< 100

  @Sendable static func f(max: Int) -> Range<Int> {
    0 ..< max
  }

  @Test(.hidden, arguments: Self.x)
  func f(i: Int) {}

#if FIXED_135346598
  @Test(.hidden, arguments: Self.f(max: 100))
  func g(i: Int) {}

  @Test(.hidden, arguments: [Self.f(max:)])
  func h(i: @Sendable (Int) -> Range<Int>) {}

  struct Box<RawValue>: Sendable, RawRepresentable where RawValue: Sendable {
    var rawValue: RawValue
  }

  @Test(.hidden, arguments: [Box(rawValue: Self.f(max:))])
  func j(i: Box<@Sendable (Int) -> Range<Int>>) {}
#endif

  struct Nested {
    static let x = 0 ..< 100
  }

  @Test(.hidden, arguments: Self.Nested.x)
  func i(i: Int) {}
}

@Test(.hidden, arguments: [0]) func A(🙃: Int) {}
@Test(.hidden, arguments: [0]) func A(🙂: Int) {}

func asyncTrait() async -> some SuiteTrait & TestTrait {
  .bug("")
}

@Suite(.hidden, await asyncTrait())
struct TestsWithAsyncArguments {
  static func asyncCollection() async throws -> [Int] { [] }

  @Test(.hidden, await asyncTrait(), arguments: try await asyncCollection())
  func f(i: Int) {}

  @Test(.hidden, arguments: try await asyncCollection(), try await asyncCollection())
  func g(i: Int, j: Int) {}
}

@Test(
  .hidden,
  arguments: [0] // Meaningful trivia: This line comment should be omitted during macro expansion
)
func parameterizedTestWithTrailingComment(value: Int) {}

@Suite(
  .hidden,
  .serialized // Meaningful trivia: This line comment should be omitted during macro expansion
)
private struct SuiteWithTraitContainingTrailingComment {}

@Test(.hidden) func // Meaningful trivia: intentional newline before name
globalMultiLineTestDecl() async {}

@Suite(.hidden)
struct MultiLineSuite {
  @Test(.hidden) func // Meaningful trivia: intentional newline before name
  multiLineTestDecl() async {}

  @Test(.hidden) static func // Meaningful trivia: intentional newline before name
  staticMultiLineTestDecl() async {}
}

@Test(.hidden) func complexOptionalChainingWithRequire() throws {
  let x: String? = nil
  _ = try #require(x?[...].last)
}

@Suite("Miscellaneous tests")
struct MiscellaneousTests {
  @Test("Free function's name")
  func unnamedFreeFunctionTest() async throws {
    let testFunction = try #require(await Test.all.first(where: { $0.name.contains("freeSyncFunction") }))
    #expect(testFunction.name == "freeSyncFunction()")
  }

  @Test("Test suite type's name")
  func unnamedMemberFunctionTest() async throws {
    let testType = try #require(await test(for: SendableTests.self))
    #expect(testType.name == "SendableTests")
  }

  @Test("Free function has custom display name")
  func namedFreeFunctionTest() async throws {
    #expect(await Test.all.first { $0.displayName == "Named Free Sync Function" && !$0.isSuite && $0.containingTypeInfo == nil } != nil)
  }

  @Test("Member function has custom display name")
  func namedMemberFunctionTest() async throws {
    let testType = try #require(await test(for: NamedSendableTests.self))
    #expect(testType.displayName == "Named Sendable test type")
  }

  @Test func `Test with raw identifier gets a display name`() throws {
    let test = try #require(Test.current)
    #expect(test.displayName == "Test with raw identifier gets a display name")
    #expect(test.name == "`Test with raw identifier gets a display name`()")
    let id = test.id
    #expect(id.moduleName == "TestingTests")
    #expect(id.nameComponents == ["MiscellaneousTests", "`Test with raw identifier gets a display name`()"])
  }

  @Test func `Suite type with raw identifier gets a display name`() throws {
    struct `Suite With De Facto Display Name` {}
    let typeInfo = TypeInfo(describing: `Suite With De Facto Display Name`.self)
    let suite = Test(traits: [], sourceLocation: #_sourceLocation, containingTypeInfo: typeInfo, isSynthesized: true)
    #expect(suite.name == "`Suite With De Facto Display Name`")
    let displayName = try #require(suite.displayName)
    #expect(displayName == "Suite With De Facto Display Name")
  }

  @Test(arguments: [0])
  func `Test with raw identifier and raw identifier parameter labels can compile`(`argument name` i: Int) {
    #expect(i == 0)
  }

  @Test("Free functions are runnable")
  func freeFunction() async throws {
    await Test(testFunction: freeSyncFunction).run()
    await Test(testFunction: freeSyncFunction).run()
    await Test(testFunction: freeAsyncFunction).run()
  }

  @Test("Instance methods are runnable")
  func instanceMethod() async throws {
    await runTestFunction(named: "succeeds()", in: SendableTests.self)
    await runTestFunction(named: "succeedsAsync()", in: SendableTests.self)
  }

  static var testSuiteTypes: [Any.Type] {
    var result: [Any.Type] = [
      NonSendableTests.self,
      SendableTests.self,
    ]

#if !SWT_NO_GLOBAL_ACTORS
    result.append(MainActorIsolatedTests.self)
#endif

    return result
  }

  @Test("Test suite types are runnable", arguments: testSuiteTypes)
  func suiteTypeIsRunnable(_ type: Any.Type) async throws {
    await runTest(for: type)
  }

  @Test("Parameterized free functions are runnable")
  func parameterizedFreeFunction() async throws {
    await Test(arguments: FixtureData.zeroUpTo100, testFunction: freeSyncFunctionParameterized).run()
    await Test(arguments: FixtureData.smallStringArray, testFunction: freeAsyncFunctionParameterized).run()
    await Test(arguments: FixtureData.zeroUpTo100, FixtureData.smallStringArray, testFunction: freeSyncFunctionParameterized2).run()
  }

  @Test("Parameterized member functions are runnable")
  func parameterizedFunctionsOnTypes() async throws {
    await runTestFunction(named: "parameterized(i:)", in: NonSendableTests.self)
    await runTestFunction(named: "parameterized2(i:j:)", in: NonSendableTests.self)
    await runTestFunction(named: "parameterized(i:)", in: SendableTests.self)
#if !SWT_NO_GLOBAL_ACTORS
    await runTestFunction(named: "parameterized(i:)", in: MainActorIsolatedTests.self)
    await runTestFunction(named: "parameterizedNonisolated(i:)", in: MainActorIsolatedTests.self)
#endif
  }

  @Test("Parameterized cases are all executed (1 argument)")
  func parameterizedCasesAreExecuted() async throws {
    let range = 0 ..< 100
    await confirmation("Iterated \(range.count) times", expectedCount: range.count) { iteratedNTimes in
      let test = Test(arguments: range) { i in
        iteratedNTimes()
      }
      await test.run()
    }
  }

  @Test("Parameterized cases are all executed (2 arguments)")
  func parameterized2CasesAreExecuted() async throws {
    struct Case: Sendable, Hashable {
      var i: Int
      var j: String
    }

    actor ValueGrid {
      var cells = [Case: Bool]()

      init(range: Range<Int>, strings: [String]) {
        for i in range {
          for j in strings {
            cells[.init(i: i, j: j)] = false
          }
        }
        let cellCount = cells.count
        #expect(range.count * strings.count == cellCount)
      }

      func setCell(_ i: Int, _ j: String) {
        cells[.init(i: i, j: j)] = true
      }

      func validateCells() {
        #expect(cells.map(\.value).allSatisfy { $0 })
      }
    }

    let range = 0 ..< 10
    let strings = ["a", "b", "c", "d", "e", "f", "g"]
    let valueGrid = ValueGrid(range: range, strings: strings)

    let test = Test(.tags(.red), .enabled(if: true), arguments: range, strings) { i, j in
      await valueGrid.setCell(i, j)
    }
    await test.run()

    await valueGrid.validateCells()
  }

  @Test("Test.parameters property")
  func parametersProperty() async throws {
    do {
      let theTest = try #require(await test(for: SendableTests.self))
      #expect(theTest.parameters == nil)
    }

    do {
      let test = try #require(await testFunction(named: "succeeds()", in: SendableTests.self))
      let parameters = try #require(test.parameters)
      #expect(parameters.isEmpty)
    } catch {}

    do {
      let test = try #require(await testFunction(named: "parameterized(i:)", in: NonSendableTests.self))
      let parameters = try #require(test.parameters)
      #expect(parameters.count == 1)
      let firstParameter = try #require(parameters.first)
      #expect(firstParameter.index == 0)
      #expect(firstParameter.firstName == "i")
      #expect(firstParameter.secondName == nil)
      #expect(firstParameter.typeInfo.fullyQualifiedName == "Swift.Int")
      #expect(firstParameter.typeInfo.unqualifiedName == "Int")
    } catch {}

    do {
      let test = try #require(await testFunction(named: "parameterized2(i:j:)", in: NonSendableTests.self))
      let parameters = try #require(test.parameters)
      #expect(parameters.count == 2)
      let firstParameter = try #require(parameters.first)
      #expect(firstParameter.index == 0)
      #expect(firstParameter.firstName == "i")
      #expect(firstParameter.secondName == nil)
      let secondParameter = try #require(parameters.last)
      #expect(secondParameter.index == 1)
      #expect(secondParameter.firstName == "j")
      #expect(secondParameter.secondName == "k")
      #expect(secondParameter.typeInfo.fullyQualifiedName == "Swift.String")
      #expect(secondParameter.typeInfo.unqualifiedName == "String")
    } catch {}
  }

  @Test("Test.sourceLocation.column is used when sorting", arguments: 0 ..< 10)
  func testsSortByColumn(_: Int) async throws {
    // Keep these test declarations on one line! We're testing that they sort
    // correctly with the same file ID and line number.
    var tests = [Test(name: "A") {}, Test(name: "B") {}, Test(name: "C") {}, Test(name: "D") {}, Test(name: "E") {}, Test(name: "F") {}, Test(name: "G") {},]
    tests.shuffle()
    tests.sort { $0.sourceLocation < $1.sourceLocation }
    #expect(tests.map(\.displayName) == ["A", "B", "C", "D", "E", "F", "G"])
  }

  @Test("Parameterizing over a collection with a poor underestimatedCount property")
  func testParameterizedOverCollectionWithBadUnderestimatedCount() async throws {
    struct PoorlyEstimatedCollection<C>: Collection where C: Collection & Sendable {
      var collection: C

      var startIndex: C.Index {
        collection.startIndex
      }

      var endIndex: C.Index {
        collection.endIndex
      }

      func index(after i: C.Index) -> C.Index {
        collection.index(after: i)
      }

      subscript(position: C.Index) -> C.Element {
        collection[position]
      }

      var underestimatedCount: Int {
        0
      }
    }

    let range = PoorlyEstimatedCollection(collection: 1 ... 100)
    let test = Test(arguments: range) { i in
      #expect(i > 0)
    }
    await test.run()
  }

  @Test("Properties related to parameterization")
  func parameterizationRelatedProperties() async throws {
    do {
      let test = Test.__type(SendableTests.self, displayName: "", traits: [], sourceLocation: #_sourceLocation)
      #expect(!test.isParameterized)
      #expect(test.testCases == nil)
      #expect(test.parameters == nil)
    }
    do {
      let test = Test {}
      #expect(!test.isParameterized)
      let testCases = try #require(test.testCases)
      #expect(testCases.underestimatedCount == 1)
      let parameters = try #require(test.parameters)
      #expect(parameters.isEmpty)
    }
    do {
      let test = Test(arguments: 0 ..< 100, parameters: [Test.Parameter(index: 0, firstName: "i", type: Int.self)]) { _ in }
      #expect(test.isParameterized)
      let testCases = try #require(test.testCases)
      #expect(testCases.underestimatedCount == 100)
      let parameters = try #require(test.parameters)
      #expect(parameters.count == 1)
      let firstParameter = try #require(parameters.first)
      #expect(firstParameter.firstName == "i")
    }
    do {
      let test = Test(arguments: 0 ..< 100, 0 ..< 100, parameters: [
        Test.Parameter(index: 0, firstName: "i", type: Int.self),
        Test.Parameter(index: 1, firstName: "j", secondName: "value", type: Int.self),
      ]) { _, _ in }
      #expect(test.isParameterized)
      let testCases = try #require(test.testCases)
      #expect(testCases.underestimatedCount == 100 * 100)
      let parameters = try #require(test.parameters)
      #expect(parameters.count == 2)
      let firstParameter = try #require(parameters.first)
      #expect(firstParameter.firstName == "i")
      let lastParameter = try #require(parameters.last)
      #expect(lastParameter.firstName == "j")
      #expect(lastParameter.secondName == "value")
    }
  }

  @Test("Test.id property")
  func id() async throws {
    let typeTest = Test.__type(SendableTests.self, displayName: "SendableTests", traits: [], sourceLocation: #_sourceLocation)
    #expect(String(describing: typeTest.id) == "TestingTests.SendableTests")

    let fileID = "Module/Y.swift"
    let filePath = "/Y.swift"
    let line = 12345
    let column = 67890
    let sourceLocation = SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column)
    let testFunction = Test.__function(named: "myTestFunction()", in: nil, xcTestCompatibleSelector: nil, displayName: nil, traits: [], sourceLocation: sourceLocation) {}
    #expect(String(describing: testFunction.id) == "Module.myTestFunction()/Y.swift:12345:67890")
  }

  @Test("Test.ID.parent property")
  func idParent() async throws {
    let idWithParent = Test.ID(["A", "B"])
    #expect(idWithParent.parent != nil)
    #expect(idWithParent.parent?.parent == nil)

    let functionIDWithParent = Test.ID(moduleName: "A", nameComponents: ["B"], sourceLocation: #_sourceLocation)
    let parentOfFunctionID = try #require(functionIDWithParent.parent)
    #expect(parentOfFunctionID.moduleName == "A")
    #expect(parentOfFunctionID.nameComponents == ["B"])
    #expect(parentOfFunctionID.sourceLocation == nil)
  }

  @Test("Test.ID.init() with no arguments")
  func idWithNoArguments() {
    let id = Test.ID([])
    #expect(id.moduleName == "")
    #expect(id.nameComponents.isEmpty)
    #expect(id.sourceLocation == nil)
    #expect(id.keyPathRepresentation == [""])
  }

  @Test("failureBreakpoint() call")
  func failureBreakpointCall() {
    failureBreakpointValue = 1
    failureBreakpoint()
    #expect(failureBreakpointValue == 0)
  }

  @available(_clockAPI, *)
  @Test("Repeated calls to #expect() run in reasonable time", .disabled("time-sensitive"))
  func repeatedlyExpect() {
    let duration = Test.Clock().measure {
      for _ in 0 ..< 1_000_000 {
        #expect(true as Bool)
      }
    }
    #expect(duration < .seconds(1))
  }
}
