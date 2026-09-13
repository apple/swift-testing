//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023–2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

internal import _TestingInternals

#if canImport(Synchronization)
internal import Synchronization
#endif

#if !hasFeature(Embedded) && SWT_TARGET_OS_APPLE && !SWT_NO_OS_UNFAIR_LOCK
/// A type that replicates the interface of ``Synchronization/Mutex``.
///
/// This type is used on Apple platforms because our deployment target there is
/// earlier than the availability of the ``Synchronization/Mutex`` type. It
/// replicates the interface of that type but is implemented differently (using
/// heap-allocated storage for the underlying lock and the value it guards).
///
/// ## See Also
///
/// - ``Allocated``
/// - ``Atomic``
struct Mutex<Value>: Sendable, ~Copyable where Value: ~Copyable {
  /// The underlying lock type.
  private typealias _Lock = os_unfair_lock_s

  /// Storage for both the lock and value.
  private nonisolated(unsafe) let _baseAddress: UnsafeMutableRawPointer

  /// The offset of `_lockAddress` from `_baseAddress`.
  private static var _lockOffset: Int {
    let p = UnsafeRawPointer(bitPattern: MemoryLayout<Value>.stride)!
    return Int(bitPattern: p.alignedUp(for: _Lock.self))
  }

  /// Storage for the underlying lock.
  private var _lockAddress: UnsafeMutablePointer<_Lock> {
    (_baseAddress + Self._lockOffset).assumingMemoryBound(to: _Lock.self)
  }

  /// Storage for the value this instance guards.
  private var _valueAddress: UnsafeMutablePointer<Value> {
    _baseAddress.assumingMemoryBound(to: Value.self)
  }


  init(_ initialValue: consuming sending Value) {
    _baseAddress = .allocate(
      byteCount: Self._lockOffset + MemoryLayout<_Lock>.stride,
      alignment: max(MemoryLayout<Value>.alignment, MemoryLayout<_Lock>.alignment)
    )

    _lockAddress.initialize(to: .init())
    _valueAddress.initialize(to: initialValue)
  }

  deinit {
    _valueAddress.deinitialize(count: 1)
    _lockAddress.deinitialize(count: 1)
    _baseAddress.deallocate()
  }

  /// Acquire the lock.
  ///
  /// See ``Synchronization/Mutex/withLock(_:)`` for more details.
  borrowing func withLock<R, E>(_ body: (inout sending Value) throws(E) -> sending R) throws(E) -> sending R where R: ~Copyable {
    let lock = _lockAddress
    os_unfair_lock_lock(lock)
    defer {
      os_unfair_lock_unlock(lock)
    }
    return try body(&_valueAddress.pointee)
  }

  /// Acquire the lock if available.
  ///
  /// See ``Synchronization/Mutex/withLockIfAvailable(_:)`` for more details.
  borrowing func withLockIfAvailable<R, E>(_ body: (inout sending Value) throws(E) -> sending R) throws(E) -> sending R? where R: ~Copyable {
    let lock = _lockAddress
    guard os_unfair_lock_trylock(lock) else {
      return nil
    }
    defer {
      os_unfair_lock_unlock(lock)
    }
    return try body(&_valueAddress.pointee)
  }
}
#elseif !canImport(Synchronization)
#error("Platform-specific misconfiguration: Mutex is unavailable")
#endif

extension Mutex where Value: Copyable & Sendable {
  var rawValue: Value {
    withLock { $0 }
  }
}

// MARK: - Additions

extension Mutex where Value: ~Copyable {
  /// Initialize an instance of this type with a raw value of `nil`.
  init<V>() where Value == V?, V: ~Copyable {
    self.init(nil)
  }

  /// Initialize an instance of this type with a raw value of `[:]`.
  init<K, V>() where Value == Dictionary<K, V> {
    self.init([:])
  }

  /// Initialize an instance of this type with a raw value of `[]`.
  init<V>() where Value == [V] {
    self.init([])
  }
}

// MARK: - POSIX conveniences

#if os(FreeBSD) || os(OpenBSD)
typealias pthread_mutex_t = _TestingInternals.pthread_mutex_t?
typealias pthread_cond_t = _TestingInternals.pthread_cond_t?
#endif
