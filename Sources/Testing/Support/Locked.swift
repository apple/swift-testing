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
private import Synchronization

/// A type that wraps a value requiring access from a synchronous caller during
/// concurrent execution.
///
/// Instances of this type use a lock to synchronize access to their raw values.
/// The lock is not recursive.
///
/// Instances of this type can be used to synchronize access to shared data from
/// a synchronous caller. Wherever possible, use actor isolation or other Swift
/// concurrency tools.
///
/// This type is not part of the public interface of the testing library.
struct Locked<T> {
  /// A type providing storage for the underlying lock and wrapped value.
#if SWT_TARGET_OS_APPLE && canImport(os)
  private typealias _Storage = ManagedBuffer<T, os_unfair_lock_s>
#elseif !SWT_FIXED_85448 && (os(Linux) || os(Android))
  private final class _Storage: ManagedBuffer<T, pthread_mutex_t> {
    deinit {
      withUnsafeMutablePointerToElements { lock in
        _ = pthread_mutex_destroy(lock)
      }
    }
  }
#else
  private final class _Storage {
    let mutex: Mutex<T>

    init(_ rawValue: consuming sending T) {
      mutex = Mutex(rawValue)
    }
  }
#endif

  /// Storage for the underlying lock and wrapped value.
  private nonisolated(unsafe) var _storage: _Storage
}

extension Locked: Sendable where T: Sendable {}

extension Locked: RawRepresentable {
  init(rawValue: T) {
#if SWT_TARGET_OS_APPLE && canImport(os)
    _storage = .create(minimumCapacity: 1, makingHeaderWith: { _ in rawValue })
    _storage.withUnsafeMutablePointerToElements { lock in
      lock.initialize(to: .init())
    }
#elseif !SWT_FIXED_85448 && (os(Linux) || os(Android))
    _storage = _Storage.create(minimumCapacity: 1, makingHeaderWith: { _ in rawValue }) as! _Storage
    _storage.withUnsafeMutablePointerToElements { lock in
      _ = pthread_mutex_init(lock, nil)
    }
#else
    nonisolated(unsafe) let rawValue = rawValue
    _storage = _Storage(rawValue)
#endif
  }

  var rawValue: T {
    withLock { rawValue in
      nonisolated(unsafe) let rawValue = rawValue
      return rawValue
    }
  }
}

extension Locked {
  /// Acquire the lock and invoke a function while it is held.
  ///
  /// - Parameters:
  ///   - body: A closure to invoke while the lock is held.
  ///
  /// - Returns: Whatever is returned by `body`.
  ///
  /// - Throws: Whatever is thrown by `body`.
  ///
  /// This function can be used to synchronize access to shared data from a
  /// synchronous caller. Wherever possible, use actor isolation or other Swift
  /// concurrency tools.
  func withLock<R>(_ body: (inout T) throws -> sending R) rethrows -> sending R where R: ~Copyable {
    nonisolated(unsafe) let result: R
#if SWT_TARGET_OS_APPLE && canImport(os)
    result = try _storage.withUnsafeMutablePointers { rawValue, lock in
      os_unfair_lock_lock(lock)
      defer {
        os_unfair_lock_unlock(lock)
      }
      return try body(&rawValue.pointee)
    }
#elseif !SWT_FIXED_85448 && (os(Linux) || os(Android))
     result = try _storage.withUnsafeMutablePointers { rawValue, lock in
      pthread_mutex_lock(lock)
      defer {
        pthread_mutex_unlock(lock)
      }
      return try body(&rawValue.pointee)
    }
#else
    result = try _storage.mutex.withLock { rawValue in
      try body(&rawValue)
    }
#endif
    return result
  }

  /// Try to acquire the lock and invoke a function while it is held.
  ///
  /// - Parameters:
  ///   - body: A closure to invoke while the lock is held.
  ///
  /// - Returns: Whatever is returned by `body`, or `nil` if the lock could not
  ///   be acquired.
  ///
  /// - Throws: Whatever is thrown by `body`.
  ///
  /// This function can be used to synchronize access to shared data from a
  /// synchronous caller. Wherever possible, use actor isolation or other Swift
  /// concurrency tools.
  func withLockIfAvailable<R>(_ body: (inout T) throws -> sending R) rethrows -> sending R? where R: ~Copyable {
    nonisolated(unsafe) let result: R?
#if SWT_TARGET_OS_APPLE && canImport(os)
    result = try _storage.withUnsafeMutablePointers { rawValue, lock in
      guard os_unfair_lock_trylock(lock) else {
        return nil
      }
      defer {
        os_unfair_lock_unlock(lock)
      }
      return try body(&rawValue.pointee)
    }
#elseif !SWT_FIXED_85448 && (os(Linux) || os(Android))
    result = try _storage.withUnsafeMutablePointers { rawValue, lock in
      guard 0 == pthread_mutex_trylock(lock) else {
        return nil
      }
      defer {
        pthread_mutex_unlock(lock)
      }
      return try body(&rawValue.pointee)
    }
#else
    result = try _storage.mutex.withLockIfAvailable { rawValue in
      return try body(&rawValue)
    }
#endif
    return result
  }
}

// MARK: - Additions

extension Locked where T: AdditiveArithmetic & Sendable {
  /// Add something to the current wrapped value of this instance.
  ///
  /// - Parameters:
  ///   - addend: The value to add.
  ///
  /// - Returns: The sum of ``rawValue`` and `addend`.
  @discardableResult func add(_ addend: T) -> T {
    withLock { rawValue in
      let result = rawValue + addend
      rawValue = result
      return result
    }
  }
}

extension Locked where T: Numeric & Sendable {
  /// Increment the current wrapped value of this instance.
  ///
  /// - Returns: The sum of ``rawValue`` and `1`.
  ///
  /// This function is exactly equivalent to `add(1)`.
  @discardableResult func increment() -> T {
    add(1)
  }

  /// Decrement the current wrapped value of this instance.
  ///
  /// - Returns: The sum of ``rawValue`` and `-1`.
  ///
  /// This function is exactly equivalent to `add(-1)`.
  @discardableResult func decrement() -> T {
    add(-1)
  }
}

extension Locked {
  /// Initialize an instance of this type with a raw value of `nil`.
  init<V>() where T == V? {
    self.init(rawValue: nil)
  }

  /// Initialize an instance of this type with a raw value of `[:]`.
  init<K, V>() where T == Dictionary<K, V> {
    self.init(rawValue: [:])
  }

  /// Initialize an instance of this type with a raw value of `[]`.
  init<V>() where T == [V] {
    self.init(rawValue: [])
  }
}

// MARK: - POSIX conveniences

#if os(FreeBSD) || os(OpenBSD)
typealias pthread_mutex_t = _TestingInternals.pthread_mutex_t?
typealias pthread_cond_t = _TestingInternals.pthread_cond_t?
#endif
