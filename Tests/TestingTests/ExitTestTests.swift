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
private import TestingInternals

#if SWIFT_PM_SUPPORTS_SWIFT_TESTING && canImport(Foundation) && (os(macOS) || os(Linux) || os(Windows))
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
#if SWT_TARGET_OS_APPLE || os(Linux)
    await #expect(exitsWith: .signal(SIGABRT)) {
      _ = kill(getpid(), SIGABRT)
    }
#endif
    await #expect(exitsWith: .signal(SIGABRT)) {
      abort()
    }
  }

  @TaskLocal
  static var isTestingFailingExitTests = false

  @Test("Exit tests (failing)") func failing() async {
    await confirmation("Exit tests failed", expectedCount: 6) { failed in
      var configuration = Configuration()
      configuration.eventHandler = { event, _ in
        if case .issueRecorded = event.kind {
          failed()
        }
      }

      await Self.$isTestingFailingExitTests.withValue(true) {
        await Runner(selecting: "failingExitTests()", configuration: configuration).run()
      }
    }
  }
}

// MARK: - Fixtures

// This fixture can't be .hidden because it needs to be discovered correctly
// when the exit tests' child processes start.
@Test(.enabled(if: ExitTestTests.isTestingFailingExitTests || isExitTestRunning))
func failingExitTests() async {
  await #expect(exitsWith: .failure) {
    exit(EXIT_SUCCESS)
  }
  await #expect(exitsWith: .success) {
    exit(EXIT_FAILURE)
  }
  await #expect(exitsWith: .exitCode(123)) {
    exit(0)
  }
  await #expect(exitsWith: .signal(123)) {
    exit(123)
  }
  await #expect(exitsWith: .exitCode(SIGABRT)) {
    abort()
  }
  await #expect(exitsWith: .signal(SIGSEGV)) {
    abort() // sends SIGABRT, not SIGSEGV
  }
}
#endif
