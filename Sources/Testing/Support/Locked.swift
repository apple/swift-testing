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

/// A protocol defining a type, generally platform-specific, that satisfies the
/// requirements of a lock or mutex.
protocol Lockable {
  /// Initialize the lock at the given address.
  ///
  /// - Parameters:
  ///   - lock: A pointer to uninitialized memory that should be initialized as
  ///     an instance of this type.
  static func initializeLock(at lock: UnsafeMutablePointer<Self>)

  /// Deinitialize the lock at the given address.
  ///
  /// - Parameters:
  ///   - lock: A pointer to initialized memory that should be deinitialized.
  static func deinitializeLock(at lock: UnsafeMutablePointer<Self>)

  /// Acquire the lock at the given address.
  ///
  /// - Parameters:
  ///   - lock: The address of the lock to acquire.
  static func unsafelyAcquireLock(at lock: UnsafeMutablePointer<Self>)

  /// Relinquish the lock at the given address.
  ///
  /// - Parameters:
  ///   - lock: The address of the lock to relinquish.
  static func unsafelyRelinquishLock(at lock: UnsafeMutablePointer<Self>)
}

// MARK: -

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
struct LockedWith<L, T>: RawRepresentable where L: Lockable {
  /// A type providing heap-allocated storage for an instance of ``Locked``.
  private final class _Storage: ManagedBuffer<T, L> {
    deinit {
      withUnsafeMutablePointerToElements { lock in
        L.deinitializeLock(at: lock)
      }
    }
  }

  /// Storage for the underlying lock and wrapped value.
  private nonisolated(unsafe) var _storage: ManagedBuffer<T, L>

  init(rawValue: T) {
    _storage = _Storage.create(minimumCapacity: 1, makingHeaderWith: { _ in rawValue })
    _storage.withUnsafeMutablePointerToElements { lock in
      L.initializeLock(at: lock)
    }
  }

  var rawValue: T {
    withLock { $0 }
  }

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
  nonmutating func withLock<R>(_ body: (inout T) throws -> R) rethrows -> R where R: ~Copyable {
    try _storage.withUnsafeMutablePointers { rawValue, lock in
      L.unsafelyAcquireLock(at: lock)
      defer {
        L.unsafelyRelinquishLock(at: lock)
      }
      return try body(&rawValue.pointee)
    }
  }

  /// Acquire the lock and invoke a function while it is held, yielding both the
  /// protected value and a reference to the underlying lock guarding it.
  ///
  /// - Parameters:
  ///   - body: A closure to invoke while the lock is held.
  ///
  /// - Returns: Whatever is returned by `body`.
  ///
  /// - Throws: Whatever is thrown by `body`.
  ///
  /// This function is equivalent to ``withLock(_:)`` except that the closure
  /// passed to it also takes a reference to the underlying lock guarding this
  /// instance's wrapped value. This function can be used when platform-specific
  /// functionality such as a `pthread_cond_t` is needed. Because the caller has
  /// direct access to the lock and is able to unlock and re-lock it, it is
  /// unsafe to modify the protected value.
  ///
  /// - Warning: Callers that unlock the lock _must_ lock it again before the
  ///   closure returns. If the lock is not acquired when `body` returns, the
  ///   effect is undefined.
  nonmutating func withUnsafeUnderlyingLock<R>(_ body: (UnsafeMutablePointer<L>, T) throws -> R) rethrows -> R where R: ~Copyable {
    try withLock { value in
      try _storage.withUnsafeMutablePointerToElements { lock in
        try body(lock, value)
      }
    }
  }
}

extension LockedWith: Sendable where T: Sendable {}

/// A type that wraps a value requiring access from a synchronous caller during
/// concurrent execution and which uses the default platform-specific lock type
/// for the current platform.
typealias Locked<T> = LockedWith<DefaultLock, T>

// MARK: - Additions

extension LockedWith where T: AdditiveArithmetic {
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

extension LockedWith where T: Numeric {
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

extension LockedWith {
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
