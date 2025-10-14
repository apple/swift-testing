//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

@testable import Testing
private import _TestingInternals

@Suite("Locked Tests")
struct LockTests {
  @Test("Locking and unlocking")
  func locking() {
    let lock = Locked(rawValue: 0)
    #expect(lock.rawValue == 0)
    lock.withLock { value in
      value = 1
    }
    #expect(lock.rawValue == 1)
  }

  @Test("Repeatedly accessing a lock")
  func lockRepeatedly() async {
    let lock = Locked(rawValue: 0)
    await withTaskGroup { taskGroup in
      for _ in 0 ..< 100_000 {
        taskGroup.addTask {
          lock.increment()
        }
      }
    }
    #expect(lock.rawValue == 100_000)
  }
}
