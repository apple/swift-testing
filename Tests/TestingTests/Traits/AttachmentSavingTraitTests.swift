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

struct `AttachmentSavingTrait tests` {
  func runAttachmentSavingTests(with trait: AttachmentSavingTrait?, expectedCount: Int, expectedIssueCount: Int = Self.issueCountFromTestBodies, expectedPreferredName: String?) async throws {
    let traitToApply = trait as (any SuiteTrait)? ?? Self.currentAttachmentSavingTrait
    try await Self.$currentAttachmentSavingTrait.withValue(traitToApply) {
      try await confirmation("Issue recorded", expectedCount: expectedIssueCount) { issueRecorded in
        try await confirmation("Attachment detected", expectedCount: expectedCount) { valueAttached in
          var configuration = Configuration()
          configuration.attachmentsPath = try temporaryDirectory()
          configuration.eventHandler = { event, _ in
            switch event.kind {
            case .issueRecorded:
              issueRecorded()
            case let .valueAttached(attachment):
#if DEBUG
              if trait != nil {
                #expect(event.wasDeferred)
              }
#endif
              if let expectedPreferredName {
                #expect(attachment.preferredName == expectedPreferredName)
              }
              valueAttached()
            default:
              break
            }
          }

          await runTest(for: FixtureSuite.self, configuration: configuration)
        }
      }
    }
  }

  @Test func `Saving attachments without conditions`() async throws {
    try await runAttachmentSavingTests(
      with: nil,
      expectedCount: Self.totalTestCaseCount,
      expectedPreferredName: nil
    )
  }

  @Test func `Saving attachments only on test pass`() async throws {
    try await runAttachmentSavingTests(
      with: .savingAttachments(if: .testPasses),
      expectedCount: Self.passingTestCaseCount,
      expectedPreferredName: "PASSING TEST"
    )
  }

  @Test func `Saving attachments with warning issue`() async throws {
    try await runAttachmentSavingTests(
      with: .savingAttachments(if: .testRecordsIssue { $0.severity == .warning }),
      expectedCount: Self.warningTestCaseCount,
      expectedPreferredName: "PASSING TEST"
    )
  }

  @Test func `Saving attachments only on test failure`() async throws {
    try await runAttachmentSavingTests(
      with: .savingAttachments(if: .testFails),
      expectedCount: Self.failingTestCaseCount,
      expectedPreferredName: "FAILING TEST"
    )
  }

  @Test func `Saving attachments with custom condition`() async throws {
    try await runAttachmentSavingTests(
      with: .savingAttachments(if: true),
      expectedCount: Self.totalTestCaseCount,
      expectedPreferredName: nil
    )

    try await runAttachmentSavingTests(
      with: .savingAttachments(if: false),
      expectedCount: 0,
      expectedPreferredName: nil
    )
  }

  @Test func `Saving attachments with custom async condition`() async throws {
    @Sendable func conditionFunction() async -> Bool {
      true
    }

    try await runAttachmentSavingTests(
      with: .savingAttachments(if: conditionFunction),
      expectedCount: Self.totalTestCaseCount,
      expectedPreferredName: nil
    )
  }

  @Test func `Saving attachments but the condition throws`() async throws {
    @Sendable func conditionFunction() throws -> Bool {
      throw MyError()
    }

    try await runAttachmentSavingTests(
      with: .savingAttachments(if: conditionFunction),
      expectedCount: 0,
      expectedIssueCount: Self.issueCountFromTestBodies + Self.totalTestCaseCount /* thrown from conditionFunction */,
      expectedPreferredName: nil
    )
  }
}

// MARK: - Fixtures

extension `AttachmentSavingTrait tests` {
  static let totalTestCaseCount = passingTestCaseCount + failingTestCaseCount
  static let passingTestCaseCount = 1 + 5 + warningTestCaseCount
  static let warningTestCaseCount = 1
  static let failingTestCaseCount = 1 + 7
  static let issueCountFromTestBodies = warningTestCaseCount + failingTestCaseCount

  @TaskLocal
  static var currentAttachmentSavingTrait: any SuiteTrait = Comment(rawValue: "<no .savingAttachments trait set>")

  @Suite(.hidden, currentAttachmentSavingTrait)
  struct FixtureSuite {
    @Test(.hidden) func `Records an attachment (passing)`() {
      Attachment.record([], named: "PASSING TEST")
    }

    @Test(.hidden) func `Records an attachment (warning)`() {
      Attachment.record([], named: "PASSING TEST")
      Issue.record("", severity: .warning)
    }

    @Test(.hidden) func `Records an attachment (failing)`() {
      Attachment.record([], named: "FAILING TEST")
      Issue.record("")
    }

    @Test(.hidden, arguments: 0 ..< 5)
    func `Records an attachment (passing, parameterized)`(i: Int) async {
      Attachment.record([UInt8(i)], named: "PASSING TEST")
    }

    @Test(.hidden, arguments: 0 ..< 7) // intentionally different count
    func `Records an attachment (failing, parameterized)`(i: Int) async {
      Attachment.record([UInt8(i)], named: "FAILING TEST")
      Issue.record("\(i)")
    }
  }
}

