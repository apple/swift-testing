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

@Suite("TestScoping-conforming Trait Tests", .tags(.traitRelated))
struct TestScopingTraitTests {
  @Test("Execute code before and after a non-parameterized test.")
  func executeCodeBeforeAndAfterNonParameterizedTest() async {
    await confirmation("Code was run before the test") { before in
      await confirmation("Code was run after the test") { after in
        await Test(CustomTrait(before: before, after: after)) {
          // do nothing
        }.run()
      }
    }
  }

  @Test("Execute code before and after a parameterized test.")
  func executeCodeBeforeAndAfterParameterizedTest() async {
    // `expectedCount` is 2 because we run it for each test case
    await confirmation("Code was run before the test", expectedCount: 2) { before in
      await confirmation("Code was run after the test", expectedCount: 2) { after in
        await Test(CustomTrait(before: before, after: after), arguments: ["Hello", "World"]) { _ in
          // do nothing
        }.run()
      }
    }
  }

  @Test("Custom execution trait throws an error")
  func customExecutionTraitThrowsAnError() async throws {
    var configuration = Configuration()
    await confirmation("Error thrown", expectedCount: 1) { errorThrownConfirmation in
      configuration.eventHandler = { event, _ in
        guard case let .issueRecorded(issue) = event.kind,
              case let .errorCaught(error) = issue.kind else {
          return
        }

        #expect(error is CustomThrowingErrorTrait.CustomTraitError)
        errorThrownConfirmation()
      }

      await Test(CustomThrowingErrorTrait()) {
        // Make sure this does not get reached
        Issue.record("Expected trait to fail the test. Should not have reached test body.")
      }.run(configuration: configuration)
    }
  }

  @Test("Teardown occurs after child tests run")
  func teardownOccursAtEnd() async throws {
    await runTest(for: TestsWithCustomTraitWithStrongOrdering.self, configuration: .init())
  }

  struct ExecutionControl {
    @Test("Trait applied directly to function is executed once")
    func traitAppliedToFunction() async {
      let counter = Locked(rawValue: 0)
      await DefaultExecutionTrait.$counter.withValue(counter) {
        await Test(DefaultExecutionTrait()) {}.run()
      }
      #expect(counter.rawValue == 1)
    }

    @Test("Non-recursive suite trait with default scope provider implementation")
    func nonRecursiveSuiteTrait() async {
      let counter = Locked(rawValue: 0)
      await DefaultExecutionTrait.$counter.withValue(counter) {
        await runTest(for: SuiteWithNonRecursiveDefaultExecutionTrait.self)
      }
      #expect(counter.rawValue == 1)
    }

    @Test("Recursive suite trait with default scope provider implementation")
    func recursiveSuiteTrait() async {
      let counter = Locked(rawValue: 0)
      await DefaultExecutionTrait.$counter.withValue(counter) {
        await runTest(for: SuiteWithRecursiveDefaultExecutionTrait.self)
      }
      #expect(counter.rawValue == 1)
    }

    @Test("Recursive, all-inclusive suite trait")
    func recursiveAllInclusiveSuiteTrait() async {
      let counter = Locked(rawValue: 0)
      await AllInclusiveExecutionTrait.$counter.withValue(counter) {
        await runTest(for: SuiteWithAllInclusiveExecutionTrait.self)
      }
      #expect(counter.rawValue == 3)
    }
  }
}

// MARK: - Fixtures

private struct CustomTrait: TestTrait, TestScoping {
  var before: Confirmation
  var after: Confirmation
  func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
    before()
    defer {
      after()
    }
    try await function()
  }
}

private struct CustomThrowingErrorTrait: TestTrait, TestScoping {
  fileprivate struct CustomTraitError: Error {}

  func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
    throw CustomTraitError()
  }
}

struct DoSomethingBeforeAndAfterTrait: SuiteTrait, TestTrait, TestScoping {
  static let state = Locked(rawValue: 0)

  func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
    #expect(Self.state.increment() == 1)

    try await function()
    #expect(Self.state.increment() == 3)
  }
}

@Suite(.hidden, DoSomethingBeforeAndAfterTrait())
struct TestsWithCustomTraitWithStrongOrdering {
  @Test(.hidden) func f() async {
    #expect(DoSomethingBeforeAndAfterTrait.state.increment() == 2)
  }
}

private struct DefaultExecutionTrait: SuiteTrait, TestTrait, TestScoping {
  @TaskLocal static var counter: Locked<Int>?
  var isRecursive: Bool = false

  func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
    Self.counter!.increment()
    try await function()
  }
}

@Suite(.hidden, DefaultExecutionTrait())
private struct SuiteWithNonRecursiveDefaultExecutionTrait {
  @Test func f() {}
}

@Suite(.hidden, DefaultExecutionTrait(isRecursive: true))
private struct SuiteWithRecursiveDefaultExecutionTrait {
  @Test func f() {}
}

private struct AllInclusiveExecutionTrait: SuiteTrait, TestTrait, TestScoping {
  @TaskLocal static var counter: Locked<Int>?

  var isRecursive: Bool {
    true
  }

  func scopeProvider(for test: Test, testCase: Test.Case?) -> AllInclusiveExecutionTrait? {
    // Unconditionally returning self makes this trait "all inclusive".
    self
  }

  func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
    Self.counter!.increment()
    try await function()
  }
}

@Suite(.hidden, AllInclusiveExecutionTrait())
private struct SuiteWithAllInclusiveExecutionTrait {
  @Test func f() {}
}
