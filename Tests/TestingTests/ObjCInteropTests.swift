//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if canImport(XCTest)
import XCTest
@testable @_spi(ForToolsIntegrationOnly) import Testing

final class NonXCTestCaseClassTests: NSObject {
  @Test("Methods on non-XCTestCase subclasses are supported")
  func testFunctionThatLooksLikeXCTest() {
    // By virtue of this test running without generating an issue, we can
    // assert that it didn't hit the XCTestCase API misuse code path.
#if _runtime(_ObjC)
    #expect(Test.current?.xcTestCompatibleSelector != nil)
#endif
  }
}

class IndirectXCTestCase: XCTestCase {}

@Suite(.hidden, .enabled(if: ObjCAndXCTestInteropTests.areObjCClassTestsEnabled))
final class ObjCClassTests: IndirectXCTestCase {
#if !SWT_TARGET_OS_APPLE
  convenience init() {
    self.init(name: "") { _ in }
  }
#endif

#if _runtime(_ObjC)
  @Test(.hidden)
  @objc(testExplicitName) func wrongAnswer() {}

  @Test(.hidden)
  @objc(testExplicitNameWithCompletionHandler:) func wrongAnswerAsync() async {}

  @Test(.hidden)
  @objc(testExplicitNameThrowsFunError:) func wrongAnswerThrows() throws {}

  @Test(.hidden)
  @objc(testExplicitNameAsyncThrowsWithCompletionHandler:) func wrongAnswerAsyncThrows() async throws {}

  @Test(.hidden)
  @objc(`testExplicitNameWithBackticks`) func wrongAnswerWithBackticks() {}
#endif

  @Test(.hidden)
  func testImplicitName() {}

  @Test(.hidden)
  func `testImplicitNameWithBackticks`() {}

  @Test(.hidden)
  func testAsynchronous() async {}

  @Test(.hidden)
  func testThrowing() throws {}

  @Test(.hidden)
  func testAsynchronousThrowing() async throws {}
}

@Suite("Objective-C/XCTest Interop Tests")
struct ObjCAndXCTestInteropTests {
  @TaskLocal static var areObjCClassTestsEnabled = false

#if _runtime(_ObjC)
  @Test("Objective-C selectors are discovered")
  func objCSelectors() async throws {
    let testPlan = await Runner.Plan(selecting: ObjCClassTests.self)
    let steps = testPlan.steps.filter { !$0.test.isSuite }
    #expect(steps.count > 0)
    for step in steps {
      let selector = try #require(step.test.xcTestCompatibleSelector)
      // A compiler crash occurs here without the bitcast. SEE: rdar://134277439
      let type = unsafeBitCast(step.test.containingTypeInfo?.type, to: Any.Type?.self)
      let testCaseClass = try #require(type as? NSObject.Type)
      #expect(testCaseClass.instancesRespond(to: selector))
    }
  }
#endif

  @Test("XCTest test methods are currently unsupported")
  func xctestMethodsCurrentlyUnsupported() async throws {
#if _runtime(_ObjC)
    let expectedCount = 10
#else
    let expectedCount = 5
#endif
    await confirmation("XCTestCase issue recorded", expectedCount: expectedCount) { issueRecorded in
      var configuration = Configuration()
      configuration.eventHandler = { event, _ in
        if case let .issueRecorded(issue) = event.kind,
           case .apiMisused = issue.kind,
           let comment = issue.comments.first,
           comment == "The @Test attribute cannot be applied to methods on a subclass of XCTestCase." {
          issueRecorded()
        }
      }
      await Self.$areObjCClassTestsEnabled.withValue(true) {
        await runTest(for: ObjCClassTests.self, configuration: configuration)
      }
    }
  }
}
#endif
