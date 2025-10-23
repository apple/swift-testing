//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if !SWT_NO_INTEROP
#if SWT_TARGET_OS_APPLE && !SWT_NO_OS_UNFAIR_LOCK
private import _TestingInternals
#else
private import Synchronization
#endif

#if SWT_TARGET_OS_APPLE && !SWT_NO_OS_UNFAIR_LOCK
/// The installed event handler.
private nonisolated(unsafe) let _fallbackEventHandler = {
  let result = ManagedBuffer<FallbackEventHandler?, os_unfair_lock>.create(
    minimumCapacity: 1,
    makingHeaderWith: { _ in nil }
  )
  result.withUnsafeMutablePointerToHeader { $0.initialize(to: nil) }
  return result
}()
#else
/// The installed event handler.
private nonisolated(unsafe) let _fallbackEventHandler = Atomic<UnsafeRawPointer?>(nil)
#endif

/// A type describing a fallback event handler that testing API can invoke as an
/// alternate method of reporting test events to the current test runner.
///
/// For example, an `XCTAssert` failure in the body of a Swift Testing test
/// cannot record issues directly with the Swift Testing runner. Instead, the
/// framework packages the assertion failure as a JSON `Event` and invokes this
/// handler to report the failure.
///
/// - Parameters:
///   - recordJSONSchemaVersionNumber: The JSON schema version used to encode
///     the event record.
///   - recordJSONBaseAddress: A pointer to the first byte of the encoded event.
///   - recordJSONByteCount: The size of the encoded event in bytes.
///   - reserved: Reserved for future use.
@usableFromInline
package typealias FallbackEventHandler = @Sendable @convention(c) (
  _ recordJSONSchemaVersionNumber: UnsafePointer<CChar>,
  _ recordJSONBaseAddress: UnsafeRawPointer,
  _ recordJSONByteCount: Int,
  _ reserved: UnsafeRawPointer?
) -> Void

/// Get the current fallback event handler.
///
/// - Returns: The currently-set handler function, if any.
@_cdecl("_swift_testing_getFallbackEventHandler")
@usableFromInline
package func _swift_testing_getFallbackEventHandler() -> FallbackEventHandler? {
#if SWT_TARGET_OS_APPLE && !SWT_NO_OS_UNFAIR_LOCK
  return _fallbackEventHandler.withUnsafeMutablePointers { fallbackEventHandler, lock in
    os_unfair_lock_lock(lock)
    defer {
      os_unfair_lock_unlock(lock)
    }
    return fallbackEventHandler.pointee
  }
#else
  return _fallbackEventHandler.load(ordering: .sequentiallyConsistent).flatMap { fallbackEventHandler in
    unsafeBitCast(fallbackEventHandler, to: FallbackEventHandler?.self)
  }
#endif
}

/// Set the current fallback event handler if one has not already been set.
///
/// - Parameters:
///   - handler: The handler function to set.
///
/// - Returns: Whether or not `handler` was installed.
///
/// The fallback event handler can only be installed once per process, typically
/// by the first testing library to run. If this function has already been
/// called and the handler set, it does not replace the previous handler.
@_cdecl("_swift_testing_installFallbackEventHandler")
@usableFromInline
package func _swift_testing_installFallbackEventHandler(_ handler: FallbackEventHandler) -> CBool {
#if SWT_TARGET_OS_APPLE && !SWT_NO_OS_UNFAIR_LOCK
  return _fallbackEventHandler.withUnsafeMutablePointers { fallbackEventHandler, lock in
    os_unfair_lock_lock(lock)
    defer {
      os_unfair_lock_unlock(lock)
    }
    guard fallbackEventHandler.pointee == nil else {
      return false
    }
    fallbackEventHandler.pointee = handler
    return true
  }
#else
  let handler = unsafeBitCast(handler, to: UnsafeRawPointer.self)
  return _fallbackEventHandler.compareExchange(expected: nil, desired: handler, ordering: .sequentiallyConsistent).exchanged
#endif
}
#endif
