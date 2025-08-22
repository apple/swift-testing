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
private import _TestingInternals

@Suite("Entry point tests")
struct EntryPointTests {
  @Test("Entry point filter with filtering of hidden tests enabled")
  func hiddenTests() async throws {
    var arguments = __CommandLineArguments_v0()
    arguments.filter = ["_someHiddenTest"]
    arguments.includeHiddenTests = true
    arguments.eventStreamSchemaVersion = "0"
    arguments.verbosity = .min

    await confirmation("Test event started", expectedCount: 1) { testMatched in
      _ = await entryPoint(passing: arguments) { event, context in
        if case .testStarted = event.kind {
          testMatched()
        }
      }
    }
  }

  @Test("Entry point using event stream version 0 exits with success if all issues have severity < .error")
  func warningIssuesDisabled() async throws {
    var arguments = __CommandLineArguments_v0()
    arguments.filter = ["_recordWarningIssue"]
    arguments.includeHiddenTests = true
    // WarningIssues is available >= 6.3
    arguments.eventStreamSchemaVersion = "0"
    arguments.verbosity = .min

    let exitCode = await confirmation("Test matched", expectedCount: 1) { testMatched in
      await entryPoint(passing: arguments) { event, context in
        if case .testStarted = event.kind {
          testMatched()
        } else if case let .issueRecorded(issue) = event.kind {
          Issue.record("Unexpected issue \(issue) was recorded.")
        }
      }
    }
    #expect(exitCode == EXIT_SUCCESS)
  }


  @Test("Entry point using event stream version 6.3 propagates warning issues and exits with success if all issues have severity < .error")
  func warningIssuesEnabled() async throws {
    var arguments = __CommandLineArguments_v0()
    arguments.filter = ["_recordWarningIssue"]
    arguments.includeHiddenTests = true
    arguments.eventStreamSchemaVersion = "6.3"
    arguments.verbosity = .min

    let exitCode = await confirmation("Warning issue recorded", expectedCount: 1) { issueRecorded in
      await entryPoint(passing: arguments) { event, context in
        if case let .issueRecorded(issue) = event.kind {
          #expect(issue.severity == .warning)
          issueRecorded()
        }
      }
    }
    #expect(exitCode == EXIT_SUCCESS)
  }
}

// MARK: - Fixtures

@Test(.hidden) private func _someHiddenTest() {}

@Test(.hidden) private func _recordWarningIssue() {
  // Intentionally _only_ record issues with warning (or lower) severity.
  Issue(kind: .unconditional, severity: .warning, comments: [], sourceContext: .init()).record()
}
