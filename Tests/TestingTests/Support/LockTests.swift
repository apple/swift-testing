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
  func testLock<L>(_ lock: LockedWith<L, Int>) {
    #expect(lock.rawValue == 0)
    lock.withLock { value in
      value = 1
    }
    #expect(lock.rawValue == 1)
  }

  @Test("Platform-default lock")
  func locking() {
    testLock(Locked(rawValue: 0))
  }

#if SWT_TARGET_OS_APPLE && !SWT_NO_OS_UNFAIR_LOCK
  @Test("pthread_mutex_t (Darwin alternate)")
  func lockingWith_pthread_mutex_t() {
    testLock(LockedWith<pthread_mutex_t, Int>(rawValue: 0))
  }
#endif

  @Test("No lock")
  func noLock() async {
    let lock = LockedWith<Never, Int>(rawValue: 0)
    await withTaskGroup { taskGroup in
      for _ in 0 ..< 100_000 {
        taskGroup.addTask {
          lock.increment()
        }
      }
    }
    #expect(lock.rawValue != 100_000)
  }

  @Test("Get the underlying lock")
  func underlyingLock() {
    let lock = Locked(rawValue: 0)
    testLock(lock)
    lock.withUnsafeUnderlyingLock { underlyingLock, _ in
      DefaultLock.unsafelyRelinquishLock(at: underlyingLock)
      lock.withLock { value in
        value += 1000
      }
      DefaultLock.unsafelyAcquireLock(at: underlyingLock)
    }
    #expect(lock.rawValue == 1001)
  }
}
