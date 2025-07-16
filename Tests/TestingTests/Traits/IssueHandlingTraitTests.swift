//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

@testable @_spi(ForToolsIntegrationOnly) import Testing

@Suite("IssueHandlingTrait Tests", .tags(.traitRelated))
struct IssueHandlingTraitTests {
  @Test("Transforming an issue by appending a comment")
  func addComment() async throws {
    var configuration = Configuration()
    configuration.eventHandler = { event, context in
      guard case let .issueRecorded(issue) = event.kind, case .unconditional = issue.kind else {
        return
      }

      #expect(issue.comments == ["Foo", "Bar"])
    }

    let handler = IssueHandlingTrait.compactMapIssues { issue in
      var issue = issue
      issue.comments.append("Bar")
      return issue
    }

    await Test(handler) {
      Issue.record("Foo")
    }.run(configuration: configuration)
  }

  @Test("Suppressing an issue by returning `nil` from the closure passed to compactMapIssues()")
  func suppressIssueUsingCompactMapIssues() async throws {
    var configuration = Configuration()
    configuration.eventHandler = { event, context in
      if case .issueRecorded = event.kind {
        Issue.record("Unexpected issue recorded event: \(event)")
      }
    }

    let handler = IssueHandlingTrait.compactMapIssues { _ in
      // Return nil to suppress the issue.
      nil
    }

    await Test(handler) {
      Issue.record("Foo")
    }.run(configuration: configuration)
  }

  @Test("Suppressing an issue by returning `false` from the filter closure")
  func filterIssue() async throws {
    var configuration = Configuration()
    configuration.eventHandler = { event, context in
      if case .issueRecorded = event.kind {
        Issue.record("Unexpected issue recorded event: \(event)")
      }
    }

    await Test(.filterIssues { _ in false }) {
      Issue.record("Foo")
    }.run(configuration: configuration)
  }

#if !SWT_NO_UNSTRUCTURED_TASKS
  @Test("Transforming an issue recorded from another trait on the test")
  func skipIssue() async throws {
    var configuration = Configuration()
    configuration.eventHandler = { event, context in
      guard case let .issueRecorded(issue) = event.kind, case .errorCaught = issue.kind else {
        return
      }

      #expect(issue.comments == ["Transformed!"])
    }

    struct MyError: Error {}

    try await confirmation("Issue handler closure is called") { issueHandlerCalled in
      let transform: @Sendable (Issue) -> Issue? = { issue in
        defer {
          issueHandlerCalled()
        }

        #expect(Test.Case.current == nil)

        var issue = issue
        issue.comments = ["Transformed!"]
        return issue
      }

      let test = Test(
        .enabled(if: try { throw MyError() }()),
        .compactMapIssues(transform)
      ) {}

      // Use a detached task to intentionally clear task local values for the
      // current test and test case, since this test validates their value.
      await Task.detached { [configuration] in
        await test.run(configuration: configuration)
      }.value
    }
  }
#endif

  @Test("Accessing the current Test and Test.Case from an issue handler closure")
  func currentTestAndCase() async throws {
    await confirmation("Issue handler closure is called") { issueHandlerCalled in
      let handler = IssueHandlingTrait.compactMapIssues { issue in
        defer {
          issueHandlerCalled()
        }
        #expect(Test.current?.name == "fixture()")
        #expect(Test.Case.current != nil)
        return issue
      }

      var test = Test(handler) {
        Issue.record("Foo")
      }
      test.name = "fixture()"
      await test.run()
    }
  }

  @Test("Validate the relative execution order of multiple issue handling traits")
  func traitOrder() async throws {
    var configuration = Configuration()
    configuration.eventHandler = { event, context in
      guard case let .issueRecorded(issue) = event.kind, case .unconditional = issue.kind else {
        return
      }

      // Ordering is intentional
      #expect(issue.comments == ["Foo", "Bar", "Baz"])
    }

    let outerHandler = IssueHandlingTrait.compactMapIssues { issue in
      var issue = issue
      issue.comments.append("Baz")
      return issue
    }
    let innerHandler = IssueHandlingTrait.compactMapIssues { issue in
      var issue = issue
      issue.comments.append("Bar")
      return issue
    }

    await Test(outerHandler, innerHandler) {
      Issue.record("Foo")
    }.run(configuration: configuration)
  }

  @Test("Secondary issue recorded from an issue handler closure")
  func issueRecordedFromClosure() async throws {
    await confirmation("Original issue recorded") { originalIssueRecorded in
      await confirmation("Secondary issue recorded") { secondaryIssueRecorded in
        var configuration = Configuration()
        configuration.eventHandler = { event, context in
          guard case let .issueRecorded(issue) = event.kind, case .unconditional = issue.kind else {
            return
          }

          if issue.comments.contains("Foo") {
            originalIssueRecorded()
          } else if issue.comments.contains("Something else") {
            secondaryIssueRecorded()
          } else {
            Issue.record("Unexpected issue recorded: \(issue)")
          }
        }

        let handler1 = IssueHandlingTrait.compactMapIssues { issue in
          return issue
        }
        let handler2 = IssueHandlingTrait.compactMapIssues { issue in
          Issue.record("Something else")
          return issue
        }
        let handler3 = IssueHandlingTrait.compactMapIssues { issue in
          // The "Something else" issue should not be passed to this closure.
          #expect(issue.comments.contains("Foo"))
          return issue
        }

        await Test(handler1, handler2, handler3) {
          Issue.record("Foo")
        }.run(configuration: configuration)
      }
    }
  }

  @Test("System issues are not passed to issue handler closures")
  func ignoresSystemIssues() async throws {
    var configuration = Configuration()
    configuration.eventHandler = { event, context in
      if case let .issueRecorded(issue) = event.kind, case .unconditional = issue.kind {
        issue.record()
      }
    }

    let handler = IssueHandlingTrait.compactMapIssues { issue in
      if case .system = issue.kind {
        Issue.record("Unexpectedly received a system issue")
      }
      return nil
    }

    await Test(handler) {
      Issue(kind: .system).record()
    }.run(configuration: configuration)
  }

  @Test("An API misused issue can be returned by issue handler closure when the original issue had that kind")
  func returningAPIMisusedIssue() async throws {
    var configuration = Configuration()
    configuration.eventHandler = { event, context in
      if case let .issueRecorded(issue) = event.kind, case .unconditional = issue.kind {
        issue.record()
      }
    }

    let handler = IssueHandlingTrait.compactMapIssues { issue in
      guard case .apiMisused = issue.kind else {
        return Issue.record("Expected an issue of kind 'apiMisused': \(issue)")
      }
      return issue
    }

    await Test(handler) {
      Issue(kind: .apiMisused).record()
    }.run(configuration: configuration)
  }

#if !SWT_NO_EXIT_TESTS
  @Test("Disallow assigning kind to .system")
  func disallowAssigningSystemKind() async throws {
    await #expect(processExitsWith: .failure) {
      await Test(.compactMapIssues { issue in
        var issue = issue
        issue.kind = .system
        return issue
      }) {
        Issue.record("A non-system issue")
      }.run()
    }
  }

  @Test("Disallow assigning kind to .apiMisused")
  func disallowAssigningAPIMisusedKind() async throws {
    await #expect(processExitsWith: .failure) {
      await Test(.compactMapIssues { issue in
        var issue = issue
        issue.kind = .apiMisused
        return issue
      }) {
        Issue.record("A non-system issue")
      }.run()
    }
  }
#endif
}
