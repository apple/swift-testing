//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023–2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

internal import _TestingInternals

extension Never: Lockable {
  static func initializeLock(at lock: UnsafeMutablePointer<Self>) {}
  static func deinitializeLock(at lock: UnsafeMutablePointer<Self>) {}
  static func unsafelyAcquireLock(at lock: UnsafeMutablePointer<Self>) {}
  static func unsafelyRelinquishLock(at lock: UnsafeMutablePointer<Self>) {}
}

#if SWT_TARGET_OS_APPLE && !SWT_NO_OS_UNFAIR_LOCK
extension os_unfair_lock_s: Lockable {
  static func initializeLock(at lock: UnsafeMutablePointer<Self>) {
    lock.initialize(to: .init())
  }

  static func deinitializeLock(at lock: UnsafeMutablePointer<Self>) {
    // No deinitialization needed.
  }

  static func unsafelyAcquireLock(at lock: UnsafeMutablePointer<Self>) {
    os_unfair_lock_lock(lock)
  }

  static func unsafelyRelinquishLock(at lock: UnsafeMutablePointer<Self>) {
    os_unfair_lock_unlock(lock)
  }
}
#endif

#if os(FreeBSD) || os(OpenBSD)
typealias pthread_mutex_t = _TestingInternals.pthread_mutex_t?
#endif

#if SWT_TARGET_OS_APPLE || os(Linux) || os(Android) || (os(WASI) && _runtime(_multithreaded)) || os(FreeBSD) || os(OpenBSD)
extension pthread_mutex_t: Lockable {
  static func initializeLock(at lock: UnsafeMutablePointer<Self>) {
    _ = pthread_mutex_init(lock, nil)
  }

  static func deinitializeLock(at lock: UnsafeMutablePointer<Self>) {
    _ = pthread_mutex_destroy(lock)
  }

  static func unsafelyAcquireLock(at lock: UnsafeMutablePointer<Self>) {
    _ = pthread_mutex_lock(lock)
  }

  static func unsafelyRelinquishLock(at lock: UnsafeMutablePointer<Self>) {
    _ = pthread_mutex_unlock(lock)
  }
}
#endif

#if os(Windows)
extension SRWLOCK: Lockable {
  static func initializeLock(at lock: UnsafeMutablePointer<Self>) {
    InitializeSRWLock(lock)
  }

  static func deinitializeLock(at lock: UnsafeMutablePointer<Self>) {
    // No deinitialization needed.
  }

  static func unsafelyAcquireLock(at lock: UnsafeMutablePointer<Self>) {
    AcquireSRWLockExclusive(lock)
  }

  static func unsafelyRelinquishLock(at lock: UnsafeMutablePointer<Self>) {
    ReleaseSRWLockExclusive(lock)
  }
}
#endif

#if SWT_TARGET_OS_APPLE && !SWT_NO_OS_UNFAIR_LOCK
typealias DefaultLock = os_unfair_lock
#elseif SWT_TARGET_OS_APPLE || os(Linux) || os(Android) || (os(WASI) && _runtime(_multithreaded)) || os(FreeBSD) || os(OpenBSD)
typealias DefaultLock = pthread_mutex_t
#elseif os(Windows)
typealias DefaultLock = SRWLOCK
#elseif os(WASI)
// No locks on WASI without multithreaded runtime.
typealias DefaultLock = Never
#else
#warning("Platform-specific implementation missing: locking unavailable")
typealias DefaultLock = Never
#endif
