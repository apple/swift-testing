//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if canImport(Foundation)
@testable @_spi(Experimental) @_spi(ForToolsIntegrationOnly) import _Testing_Foundation
@_spi(Experimental) @_spi(ForToolsIntegrationOnly) import Testing
private import TestingInternals
private import Foundation

struct FoundationTests {
  @Test("Casting Test.Clock.Instant to Date")
  func castTestClockInstantToDate() {
    let instant = Test.Clock.Instant.now
    let date = Date(instant)
    #expect(TimeInterval(instant.timeComponentsSince1970.seconds) == date.timeIntervalSince1970.rounded(.down))
  }

#if _runtime(_ObjC) && !SWT_NO_EXCEPTIONS
  @Test("#expect(throws:) with an exception")
  func expectThrowsException() {
    #expect(throws: NSException.self) {
      NSException(name: .genericException, reason: "abc123", userInfo: nil).raise()
    }

    withKnownIssue("Throws with the wrong name") {
      #expect(throws: NSException.self, named: .genericException) {
        NSException(name: .invalidArgumentException, reason: "abc123", userInfo: nil).raise()
      }
    }

    withKnownIssue("Throws a number, not an NSException") {
      #expect(throws: NSException.self) {
        swt_throwNumber(123)
      }
    }

    withKnownIssue("Throws a std::exception, not an NSException") {
      #expect(throws: NSException.self) {
        swt_throwCxxException("ceci n'est pas un NSException")
      }
    }
  }
#endif
}
#endif
