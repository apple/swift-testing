//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

@testable import Testing

@Suite("Condition Trait Tests", .tags(.traitRelated))
struct ConditionTraitTests {
  @Test(
    ".enabled trait",
    .enabled { true },
    .bug("https://github.com/swiftlang/swift/issues/76409", "Verify the custom trait with closure causes @Test macro to fail is fixed")
  )
  func enabledTraitClosure() throws {}

  @Test(
    ".enabled if trait",
    .enabled(if: true)
  )
  func enabledTraitIf() throws {}

  @Test(
    ".disabled trait",
    .disabled { false },
    .bug("https://github.com/swiftlang/swift/issues/76409", "Verify the custom trait with closure causes @Test macro to fail is fixed")
  )
  func disabledTraitClosure() throws {}

  @Test(
    ".disabled if trait",
    .disabled(if: false)
  )
  func disabledTraitIf() throws {}
  
  @Test
  func evaluateCondition() async throws {
    let trueUnconditional = ConditionTrait(kind: .unconditional(true), comments: [], sourceLocation: #_sourceLocation)
    let falseUnconditional = ConditionTrait.disabled()
    let enabledTrue = ConditionTrait.enabled(if: true)
    let enabledFalse = ConditionTrait.enabled(if: false)
    var result: Bool
    
    result = try await trueUnconditional.evaluate()
    #expect(result)
    result = try await falseUnconditional.evaluate()
    #expect(!result)
    result = try await enabledTrue.evaluate()
    #expect(result)
    result = try await enabledFalse.evaluate()
    #expect(!result)
  }
}
