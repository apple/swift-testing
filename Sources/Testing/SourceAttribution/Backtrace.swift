//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

private import _TestingInternals

/// A type representing a backtrace or stack trace.
@_spi(ForToolsIntegrationOnly)
public struct Backtrace: Sendable {
  /// A type describing an address in a backtrace.
  ///
  /// If a `nil` address is present in a backtrace, it is represented as `0`.
  public typealias Address = UInt64

  /// The addresses in this backtrace.
  public var addresses: [Address]

  /// Initialize an instance of this type with the specified addresses.
  ///
  /// - Parameters:
  ///   - addresses: The addresses in the backtrace.
  public init(addresses: some Sequence<Address>) {
    self.addresses = Array(addresses)
  }

  /// Initialize an instance of this type with the specified addresses.
  ///
  /// - Parameters:
  ///   - addresses: The addresses in the backtrace.
  ///
  /// The pointers in `addresses` are converted to instances of ``Address``. Any
  /// `nil` addresses are represented as `0`.
  public init(addresses: some Sequence<UnsafeRawPointer?>) {
    self.addresses = addresses.map { Address(UInt(bitPattern: $0)) }
  }

  /// Get the current backtrace.
  ///
  /// - Parameters:
  ///   - addressCount: The maximum number of addresses to include in the
  ///     backtrace. If the current call stack is larger than this value, the
  ///     resulting backtrace will be truncated to only the most recent
  ///     `addressCount` symbols.
  ///
  /// - Returns: A new instance of this type representing the backtrace of the
  ///   current thread. When supported by the operating system, the backtrace
  ///   continues across suspension points.
  ///
  /// The number of symbols captured in this backtrace is an implementation
  /// detail.
  public static func current(maximumAddressCount addressCount: Int = 128) -> Self {
    // NOTE: the exact argument/return types for backtrace() vary across
    // platforms, hence the use of .init() when calling it below.
    withUnsafeTemporaryAllocation(of: UnsafeMutableRawPointer?.self, capacity: addressCount) { addresses in
      var initializedCount = 0
#if SWT_TARGET_OS_APPLE
      if #available(_backtraceAsyncAPI, *) {
        initializedCount = backtrace_async(addresses.baseAddress!, addresses.count, nil)
      } else {
        initializedCount = .init(clamping: backtrace(addresses.baseAddress!, .init(clamping: addresses.count)))
      }
#elseif os(Android)
      initializedCount = addresses.withMemoryRebound(to: UnsafeMutableRawPointer.self) { addresses in
        .init(clamping: backtrace(addresses.baseAddress!, .init(clamping: addresses.count)))
      }
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD)
      initializedCount = .init(clamping: backtrace(addresses.baseAddress!, .init(clamping: addresses.count)))
#elseif os(Windows)
      initializedCount = Int(clamping: RtlCaptureStackBackTrace(0, ULONG(clamping: addresses.count), addresses.baseAddress!, nil))
#elseif os(WASI)
      // SEE: https://github.com/WebAssembly/WASI/issues/159
      // SEE: https://github.com/swiftlang/swift/pull/31693
#else
#warning("Platform-specific implementation missing: backtraces unavailable")
#endif

      let endIndex = addresses.index(addresses.startIndex, offsetBy: initializedCount)
#if _pointerBitWidth(_64)
      // The width of a pointer equals the width of an `Address`, so we can just
      // bitcast the memory rather than mapping through UInt first.
      return addresses[..<endIndex].withMemoryRebound(to: Address.self) { addresses in
        Self(addresses: addresses)
      }
#else
      return addresses[..<endIndex].withMemoryRebound(to: UnsafeRawPointer?.self) { addresses in
        Self(addresses: addresses)
      }
#endif
    }
  }
}

// MARK: - Equatable, Hashable

extension Backtrace: Equatable, Hashable {}

// MARK: - Codable

// Explicitly implement Codable support by encoding and decoding the addresses
// array directly. Doing this avoids an extra level of indirection in the
// encoded form of a backtrace.

extension Backtrace: Codable {
  public init(from decoder: any Decoder) throws {
    try self.init(addresses: [Address](from: decoder))
  }

  public func encode(to encoder: any Encoder) throws {
    try addresses.encode(to: encoder)
  }
}

// MARK: - Backtraces for thrown errors

extension Backtrace {
#if !hasFeature(Embedded)
  // MARK: - Error cache keys

  /// A type used as a cache key that uniquely identifies error existential
  /// boxes.
  private struct _ErrorMappingCacheKey: Sendable, Equatable, Hashable {
    private nonisolated(unsafe) var _rawValue: UnsafeMutableRawPointer?

    /// Initialize an instance of this type from a pointer to an error
    /// existential box.
    ///
    /// - Parameters:
    ///   - errorAddress: The address of the error existential box.
    init(_ errorAddress: UnsafeMutableRawPointer) {
      _rawValue = errorAddress
#if _runtime(_ObjC)
      let error = Unmanaged<AnyObject>.fromOpaque(errorAddress).takeUnretainedValue() as! any Error
      if type(of: error) is AnyObject.Type {
        _rawValue = Unmanaged.passUnretained(error as AnyObject).toOpaque()
      }
#else
      withUnsafeTemporaryAllocation(of: SWTErrorValueResult.self, capacity: 1) { buffer in
        var scratch: UnsafeMutableRawPointer?
        return withExtendedLifetime(scratch) {
          swift_getErrorValue(errorAddress, &scratch, buffer.baseAddress!)
          let result = buffer.baseAddress!.move()

          if unsafeBitCast(result.type, to: Any.Type.self) is AnyObject.Type {
            let errorObject = result.value.load(as: AnyObject.self)
            _rawValue = Unmanaged.passUnretained(errorObject).toOpaque()
          }
        }
      }
#endif
    }

    /// Initialize an instance of this type from an error existential box.
    ///
    /// - Parameters:
    ///   - error: The error existential box.
    ///
    /// - Note: Care must be taken to avoid unboxing and re-boxing `error`. This
    ///   initializer cannot be made an instance method or property of `Error`
    ///   because doing so will cause Swift-native errors to be unboxed into
    ///   existential containers with different addresses.
    init(_ error: any Error) {
      self.init(unsafeBitCast(error as any Error, to: UnsafeMutableRawPointer.self))
    }
  }

  /// An entry in the error-mapping cache.
  private struct _ErrorMappingCacheEntry: Sendable {
    /// The error object (`SwiftError` or `NSError`) that was thrown.
    ///
    /// - Note: It is important that this value be of type `AnyObject`
    ///     rather than `Error`. `Error` is not a reference type, so weak
    ///     references to it cannot be constructed, and `Error`'s
    ///     existential containers do not have persistent heap addresses.
    ///
    /// - Bug: On Windows, the weak reference to this object triggers a
    ///   crash. To avoid said crash, we'll keep a strong reference to the
    ///   object (abandoning memory until the process exits.)
    ///   ([swift-#62985](https://github.com/swiftlang/swift/issues/62985))
#if os(Windows) || os(FreeBSD) || os(OpenBSD)
    nonisolated(unsafe) var errorObject: AnyObject?
#else
    nonisolated(unsafe) weak var errorObject: AnyObject?
#endif

    /// The backtrace captured when `errorObject` was thrown.
    var backtrace: Backtrace
  }

  /// Storage for the error-mapping cache.
  ///
  /// Keys in this map are the object identifiers (i.e. the addresses) of the
  /// heap-allocated `SwiftError` and `NSError` boxes around thrown Swift
  /// errors. Addresses are, of course, dangerous to hold without also holding
  /// references to the relevant objects, but using `AnyObject` as a key would
  /// result in thrown errors never being deallocated.
  ///
  /// To ensure the keys remain valid, a _weak_ reference to the error object is
  /// held in the value. When an error is looked up by key, we check if the weak
  /// reference is valid. If it is, that means the error remains allocated at
  /// that address. If it is `nil`, then the error was deallocated (and the
  /// pointer we're holding is to a _different_ error that was allocated in the
  /// same location.)
  ///
  /// Access to this dictionary is guarded by a lock.
  private static let _errorMappingCache = Locked<[_ErrorMappingCacheKey: _ErrorMappingCacheEntry]>()

  /// The previous `swift_willThrow` handler, if any.
  private static let _oldWillThrowHandler = Locked<SWTWillThrowHandler?>()

  /// The previous `swift_willThrowTyped` handler, if any.
  private static let _oldWillThrowTypedHandler = Locked<SWTWillThrowTypedHandler?>()

  /// Handle a thrown error.
  ///
  /// - Parameters:
  ///   - errorObject: The error that is about to be thrown.
  ///   - backtrace: The backtrace from where the error was thrown.
  ///   - errorID: The ID under which the thrown error should be tracked.
  ///
  /// This function serves as the bottleneck for the various callbacks below.
  private static func _willThrow(_ errorObject: AnyObject, from backtrace: Backtrace, forKey errorKey: _ErrorMappingCacheKey) {
    let newEntry = _ErrorMappingCacheEntry(errorObject: errorObject, backtrace: backtrace)

    _errorMappingCache.withLock { cache in
      let oldEntry = cache[errorKey]
      if oldEntry?.errorObject == nil {
        // Either no entry yet, or its weak reference was zeroed.
        cache[errorKey] = newEntry
      }
    }
  }

  /// Handle a thrown error.
  ///
  /// - Parameters:
  ///   - errorAddress: The error that is about to be thrown. This pointer
  ///     refers to an instance of `SwiftError` or (on platforms with
  ///     Objective-C interop) an instance of `NSError`.
  ///   - backtrace: The backtrace from where the error was thrown.
  private static func _willThrow(_ errorAddress: UnsafeMutableRawPointer, from backtrace: Backtrace) {
    _oldWillThrowHandler.rawValue?(errorAddress)

    let errorObject = Unmanaged<AnyObject>.fromOpaque(errorAddress).takeUnretainedValue()
    _willThrow(errorObject, from: backtrace, forKey: .init(errorAddress))
  }

  /// Handle a typed thrown error.
  ///
  /// - Parameters:
  ///   - error: The error that is about to be thrown. If the error is of
  ///     reference type, it is forwarded to `_willThrow()`. Otherwise, it is
  ///     (currently) discarded because its identity cannot be tracked.
  ///   - backtrace: The backtrace from where the error was thrown.
  @available(_typedThrowsAPI, *)
  private static func _willThrowTyped<E>(_ error: borrowing E, from backtrace: Backtrace) where E: Error {
    if E.self is AnyObject.Type {
      // The error has a stable address and can be tracked as an object.
      let error = copy error
      _willThrow(error as AnyObject, from: backtrace, forKey: .init(error))
    } else if E.self == (any Error).self {
      // The thrown error has non-specific type (any Error). In this case,
      // the runtime produces a temporary existential box to contain the
      // error, but discards the box immediately after we return so there's
      // no stability provided by the error's address. Unbox the error and
      // recursively call this function in case it contains an instance of a
      // reference-counted error type.
      //
      // This dance through Any lets us unbox the error's existential box
      // correctly. Skipping it and calling _willThrowTyped() will fail to open
      // the existential and will result in an infinite recursion. The copy is
      // unfortunate but necessary due to casting being a consuming operation.
      let error = ((copy error) as Any) as! any Error
      _willThrowTyped(error, from: backtrace)
    } else {
      // The error does _not_ have a stable address. The Swift runtime does
      // not give us an opportunity to insert additional information into
      // arbitrary error values. Thus, we won't attempt to capture any
      // backtrace for such an error.
      //
      // We could, in the future, attempt to track such errors if they conform
      // to Identifiable, Equatable, etc., but that would still be imperfect.
      // Perhaps the compiler or runtime could assign a unique ID to each error
      // at throw time that could be looked up later. SEE: rdar://122824443.
    }
  }

  /// Handle a typed thrown error.
  ///
  /// - Parameters:
  ///   - error: The error that is about to be thrown. This pointer points
  ///     directly to the unboxed error in memory. For errors of reference type,
  ///     the pointer points to the object and is not the object's address
  ///     itself.
  ///   - errorType: The metatype of `error`.
  ///   - errorConformance: The witness table for `error`'s conformance to the
  ///     `Error` protocol.
  ///   - backtrace: The backtrace from where the error was thrown.
  @available(_typedThrowsAPI, *)
  private static func _willThrowTyped(_ errorAddress: UnsafeMutableRawPointer, _ errorType: UnsafeRawPointer, _ errorConformance: UnsafeRawPointer, from backtrace: Backtrace) {
    _oldWillThrowTypedHandler.rawValue?(errorAddress, errorType, errorConformance)

    // Get a thick protocol type back from the C pointer arguments. Ideally we
    // would specify this function as generic, but then the Swift calling
    // convention would force us to specialize it immediately in order to pass
    // it to the C++ thunk that sets the runtime's function pointer.
    let errorType = unsafeBitCast((errorType, errorConformance), to: (any Error.Type).self)

    // Open `errorType` as an existential. Rebind the memory at `errorAddress`
    // to the correct type and then pass the error to the fully Swiftified
    // handler function. Don't call load(as:) to avoid copying the error
    // (ideally this is a zero-copy operation.) The callee borrows its argument.
    func forward<E>(_ errorType: E.Type) where E: Error {
      errorAddress.withMemoryRebound(to: E.self, capacity: 1) { errorAddress in
        _willThrowTyped(errorAddress.pointee, from: backtrace)
      }
    }
    forward(errorType)
  }
#endif

  /// Whether or not Foundation provides a function that triggers the capture of
  /// backtaces when instances of `NSError` or `CFError` are created.
  ///
  /// A backtrace created by said function represents the point in execution
  /// where the error was created by an Objective-C or C stack frame. For an
  /// error thrown from Objective-C or C through Swift before being caught by
  /// the testing library, that backtrace is closer to the point of failure than
  /// the one that would be captured at the point `swift_willThrow()` is called.
  ///
  /// On non-Apple platforms, the value of this property is always `false`.
  ///
  /// - Note: The underlying Foundation function is called (if present) the
  ///   first time the value of this property is read.
  static let isFoundationCaptureEnabled = {
#if !hasFeature(Embedded) && _runtime(_ObjC) && !SWT_NO_DYNAMIC_LINKING
    if Environment.flag(named: "SWT_FOUNDATION_ERROR_BACKTRACING_ENABLED") == true {
      let _CFErrorSetCallStackCaptureEnabled = symbol(named: "_CFErrorSetCallStackCaptureEnabled").map {
        castCFunction(at: $0, to: (@convention(c) (DarwinBoolean) -> DarwinBoolean).self)
      }
      _ = _CFErrorSetCallStackCaptureEnabled?(true)
      return _CFErrorSetCallStackCaptureEnabled != nil
    }
#endif
    return false
  }()

#if !hasFeature(Embedded)
  /// The implementation of ``Backtrace/startCachingForThrownErrors()``, run
  /// only once.
  ///
  /// This value is named oddly so that it shows up clearly in symbolicated
  /// backtraces.
  private static let __SWIFT_TESTING_IS_CAPTURING_A_BACKTRACE_FOR_A_THROWN_ERROR__: Void = {
    _ = isFoundationCaptureEnabled

    if Environment.flag(named: "SWT_SWIFT_ERROR_BACKTRACING_ENABLED") != false {
      _oldWillThrowHandler.withLock { oldWillThrowHandler in
        oldWillThrowHandler = swt_setWillThrowHandler { errorAddress in
          let backtrace = Backtrace.current()
          _willThrow(errorAddress, from: backtrace)
        }
      }
      if #available(_typedThrowsAPI, *) {
        _oldWillThrowTypedHandler.withLock { oldWillThrowTypedHandler in
          oldWillThrowTypedHandler = swt_setWillThrowTypedHandler { errorAddress, errorType, errorConformance in
            let backtrace = Backtrace.current()
            _willThrowTyped(errorAddress, errorType, errorConformance, from: backtrace)
          }
        }
      }
    }
  }()
#endif

  /// Configure the Swift runtime to allow capturing backtraces when errors are
  /// thrown.
  ///
  /// The testing library should call this function before running any
  /// developer-supplied code to ensure that thrown errors' backtraces are
  /// always captured.
  static func startCachingForThrownErrors() {
#if !hasFeature(Embedded)
    __SWIFT_TESTING_IS_CAPTURING_A_BACKTRACE_FOR_A_THROWN_ERROR__
#endif
  }

  /// Flush stale entries from the error-mapping cache.
  ///
  /// Call this function periodically to ensure that errors do not continue to
  /// take up space in the cache after they have been deinitialized.
  static func flushThrownErrorCache() {
#if !hasFeature(Embedded)
    _errorMappingCache.withLock { cache in
      cache = cache.filter { $0.value.errorObject != nil }
    }
#endif
  }

  /// Initialize an instance of this type with the previously-cached backtrace
  /// for a given error.
  ///
  /// - Parameters:
  ///   - error: The error for which a backtrace is needed.
  ///   - checkFoundation: Whether or not to check for a backtrace created by
  ///     Foundation with `_CFErrorSetCallStackCaptureEnabled()`. On non-Apple
  ///     platforms, this argument has no effect.
  ///
  /// If no backtrace information is available for the specified error, this
  /// initializer returns `nil`. To start capturing backtraces, call
  /// ``Backtrace/startCachingForThrownErrors()``.
  ///
  /// - Note: Care must be taken to avoid unboxing and re-boxing `error`. This
  ///   initializer cannot be made an instance method or property of `Error`
  ///   because doing so will cause Swift-native errors to be unboxed into
  ///   existential containers with different addresses.
#if !hasFeature(Embedded)
  @inline(never)
  init?(forFirstThrowOf error: any Error, checkFoundation: Bool = true) {
    if checkFoundation && Self.isFoundationCaptureEnabled,
       let userInfo = error._userInfo as? [String: Any],
       let addresses = userInfo["NSCallStackReturnAddresses"] as? [Address], !addresses.isEmpty {
      self.init(addresses: addresses)
      return
    }

    let entry = Self._errorMappingCache.withLock { cache in
      cache[.init(error)]
    }
    if let entry, entry.errorObject != nil {
      // There was an entry and its weak reference is still valid.
      self = entry.backtrace
    } else {
      return nil
    }
  }
#else
  init?(forFirstThrowOf error: some Error, checkFoundation: Bool = true) {
    return nil
  }
#endif
}
