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
private import _TestingInternals

#if !SWT_NO_EXIT_TESTS
@Suite("Exit test tests") struct ExitTestTests {
  @Test("Exit tests (passing)") func passing() async {
    await #expect(exitsWith: .failure) {
      exit(EXIT_FAILURE)
    }
    if EXIT_SUCCESS != EXIT_FAILURE + 1 {
      await #expect(exitsWith: .failure) {
        exit(EXIT_FAILURE + 1)
      }
    }
    await #expect(exitsWith: .success) {
      exit(EXIT_SUCCESS)
    }
    await #expect(exitsWith: .exitCode(123)) {
      exit(123)
    }
    await #expect(exitsWith: .exitCode(123)) {
      await Task.yield()
      exit(123)
    }
#if !os(Windows)
    await #expect(exitsWith: .signal(SIGKILL)) {
      _ = kill(getpid(), SIGKILL)
      // Allow up to 1s for the signal to be delivered.
      try! await Task.sleep(nanoseconds: 1_000_000_000_000)
    }
    await #expect(exitsWith: .signal(SIGABRT)) {
      abort()
    }
#endif
#if !SWT_NO_UNSTRUCTURED_TASKS
#if false
    // Test the detached (no task-local configuration) path. Disabled because,
    // like other tests using Task.detached, it can interfere with other tests
    // running concurrently.
    #expect(Test.current != nil)
    await Task.detached {
      #expect(Test.current == nil)
      await #expect(exitsWith: .failure) {
        fatalError()
      }
    }.value
#endif
#endif
  }

  @Test("Exit tests (failing)") func failing() async {
    let expectedCount: Int
#if os(Windows)
    expectedCount = 6
#else
    expectedCount = 10
#endif
    await confirmation("Exit tests failed", expectedCount: expectedCount) { failed in
      var configuration = Configuration()
      configuration.eventHandler = { event, _ in
        if case .issueRecorded = event.kind {
          failed()
        }
      }
      configuration.exitTestHandler = ExitTest.handlerForEntryPoint()

      await runTest(for: FailingExitTests.self, configuration: configuration)
    }
  }

  @Test("Mock exit test handlers (passing)") func passingMockHandler() async {
    await confirmation("System issue recorded", expectedCount: 0) { issueRecorded in
      var configuration = Configuration()
      configuration.eventHandler = { event, _ in
        if case .issueRecorded = event.kind {
          issueRecorded()
        }
      }

      // Mock an exit test where the process exits successfully.
      configuration.exitTestHandler = { _ in
        return .exitCode(EXIT_SUCCESS)
      }
      await Test {
        await #expect(exitsWith: .success) {}
      }.run(configuration: configuration)

      // Mock an exit test where the process exits with a generic failure.
      configuration.exitTestHandler = { _ in
        return .failure
      }
      await Test {
        await #expect(exitsWith: .failure) {}
      }.run(configuration: configuration)
      await Test {
        await #expect(exitsWith: .exitCode(EXIT_FAILURE)) {}
      }.run(configuration: configuration)
#if !os(Windows)
      await Test {
        await #expect(exitsWith: .signal(SIGABRT)) {}
      }.run(configuration: configuration)
#endif

      // Mock an exit test where the process exits with a particular error code.
      configuration.exitTestHandler = { _ in
        return .exitCode(123)
      }
      await Test {
        await #expect(exitsWith: .failure) {}
      }.run(configuration: configuration)

#if !os(Windows)
      // Mock an exit test where the process exits with a signal.
      configuration.exitTestHandler = { _ in
        return .signal(SIGABRT)
      }
      await Test {
        await #expect(exitsWith: .signal(SIGABRT)) {}
      }.run(configuration: configuration)
      await Test {
        await #expect(exitsWith: .failure) {}
      }.run(configuration: configuration)
#endif
    }
  }

  @Test("Mock exit test handlers (failing)") func failingMockHandlers() async {
    let expectedCount: Int
#if os(Windows)
    expectedCount = 2
#else
    expectedCount = 6
#endif
    await confirmation("Issue recorded", expectedCount: expectedCount) { issueRecorded in
      var configuration = Configuration()
      configuration.eventHandler = { event, _ in
        if case .issueRecorded = event.kind {
          issueRecorded()
        }
      }

      // Mock exit tests that were expected to fail but passed.
      configuration.exitTestHandler = { _ in
        return .exitCode(EXIT_SUCCESS)
      }
      await Test {
        await #expect(exitsWith: .failure) {}
      }.run(configuration: configuration)
      await Test {
        await #expect(exitsWith: .exitCode(EXIT_FAILURE)) {}
      }.run(configuration: configuration)
#if !os(Windows)
      await Test {
        await #expect(exitsWith: .signal(SIGABRT)) {}
      }.run(configuration: configuration)
#endif

#if !os(Windows)
      // Mock exit tests that unexpectedly signalled.
      configuration.exitTestHandler = { _ in
        return .signal(SIGABRT)
      }
      await Test {
        await #expect(exitsWith: .exitCode(EXIT_SUCCESS)) {}
      }.run(configuration: configuration)
      await Test {
        await #expect(exitsWith: .exitCode(EXIT_FAILURE)) {}
      }.run(configuration: configuration)
      await Test {
        await #expect(exitsWith: .success) {}
      }.run(configuration: configuration)
#endif
    }
  }

  @Test("Exit test without configured exit test handler") func noHandler() async {
    await confirmation("System issue recorded") { issueRecorded in
      var configuration = Configuration()
      configuration.eventHandler = { event, _ in
        if case let .issueRecorded(issue) = event.kind, case .system = issue.kind {
          issueRecorded()
        }
      }

      await Test {
        await #expect(exitsWith: .success) {}
      }.run(configuration: configuration)
    }
  }

#if !os(Linux)
  @Test("Exit test reports > 8 bits of the exit code")
  func fullWidthExitCode() async {
    // On macOS and Linux, we use waitid() which per POSIX should report the
    // full exit code, not just the low 8 bits. This behaviour is not
    // well-documented and while Darwin correctly reports the full value, Linux
    // does not (at least as of this writing) and other POSIX-like systems may
    // also have issues. This test serves as a canary when adding new platforms
    // that we need to document the difference.
    //
    // Windows does not have the 8-bit exit code restriction and always reports
    // the full CInt value back to the testing library.
    await #expect(exitsWith: .exitCode(512)) {
      exit(512)
    }
  }
#endif
}

// MARK: - Fixtures

@Suite(.hidden) struct FailingExitTests {
  @Test(.hidden) func failingExitTests() async {
    await #expect(exitsWith: .success) {}
    await #expect(exitsWith: .failure) {}
    await #expect(exitsWith: .exitCode(123)) {}
    await #expect(exitsWith: .failure) {
      exit(EXIT_SUCCESS)
    }
    await #expect(exitsWith: .success) {
      exit(EXIT_FAILURE)
    }
    await #expect(exitsWith: .exitCode(123)) {
      exit(0)
    }

#if !os(Windows)
    await #expect(exitsWith: .exitCode(SIGABRT)) {
      // abort() raises on Windows, but we don't handle that yet and it is
      // reported as .failure (which will fuzzy-match with SIGABRT.)
      abort()
    }
    await #expect(exitsWith: .signal(123)) {}
    await #expect(exitsWith: .signal(123)) {
      exit(123)
    }
    await #expect(exitsWith: .signal(SIGSEGV)) {
      abort() // sends SIGABRT, not SIGSEGV
    }
#endif
  }
}

#if false // intentionally fails to compile
@Test(arguments: 100 ..< 200)
func sellIceCreamCones(count: Int) async throws {
  try await #require(exitsWith: .failure) {
    precondition(count < 10, "Too many ice cream cones")
  }
}
#endif
#endif
