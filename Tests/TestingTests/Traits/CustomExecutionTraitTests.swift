//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

@testable @_spi(ExperimentalTestRunning) @_spi(ForToolsIntegrationOnly) @_spi(Experimental) import Testing

private struct CustomTrait: CustomExecutionTrait, TestTrait {
    var before: Confirmation
    var after: Confirmation
    func execute(_ function: @escaping @Sendable () async throws -> Void, for test: Test, testCase: Test.Case?) async throws {
        before()
        defer {
            after()
        }
        try await function()
    }
}

private struct CustomThrowingErrorTrait: CustomExecutionTrait, TestTrait {
    fileprivate struct CustomTraitError: Error {}

    func execute(_ function: @escaping @Sendable () async throws -> Void, for test: Test, testCase: Test.Case?) async throws {
        throw CustomTraitError()
    }
}

@Suite("CustomExecutionTrait Tests")
struct CustomExecutionTraitTests {
    @Test("Execute code before and after a non-parameterized test.")
    func executeCodeBeforeAndAfterNonParameterizedTest() async {
        // `expectedCount` is 2 because we run it both for the test and the test case
        await confirmation("Code was run before the test", expectedCount: 2) { before in
            await confirmation("Code was run after the test", expectedCount: 2) { after in
                await Test(CustomTrait(before: before, after: after)) {
                    // do nothing
                }.run()
            }
        }
    }

    @Test("Execute code before and after a parameterized test.")
    func executeCodeBeforeAndAfterParameterizedTest() async {
        // `expectedCount` is 3 because we run it both for the test and each test case
        await confirmation("Code was run before the test", expectedCount: 3) { before in
            await confirmation("Code was run after the test", expectedCount: 3) { after in
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
}
