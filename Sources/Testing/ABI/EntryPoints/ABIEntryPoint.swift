//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if canImport(Foundation) && !SWT_NO_ABI_ENTRY_POINT
private import _TestingInternals

extension ABI.v0 {
  /// The type of the entry point to the testing library used by tools that want
  /// to remain version-agnostic regarding the testing library.
  ///
  /// - Parameters:
  ///   - configurationJSON: A buffer to memory representing the test
  ///     configuration and options. If `nil`, a new instance is synthesized
  ///     from the command-line arguments to the current process.
  ///   - recordHandler: A JSON record handler to which is passed a buffer to
  ///     memory representing each record as described in `ABI/JSON.md`.
  ///
  /// - Returns: Whether or not the test run finished successfully.
  ///
  /// - Throws: Any error that occurred prior to running tests. Errors that are
  ///   thrown while tests are running are handled by the testing library.
  public typealias EntryPoint = @convention(thin) @Sendable (
    _ configurationJSON: UnsafeRawBufferPointer?,
    _ recordHandler: @escaping @Sendable (_ recordJSON: UnsafeRawBufferPointer) -> Void
  ) async throws -> Bool

  /// The entry point to the testing library used by tools that want to remain
  /// version-agnostic regarding the testing library.
  ///
  /// The value of this property is a Swift function that can be used by tools
  /// that do not link directly to the testing library and wish to invoke tests
  /// in a binary that has been loaded into the current process. The value of
  /// this property is accessible from C and C++ as a function with name
  /// `"swt_abiv0_getEntryPoint"` and can be dynamically looked up at runtime
  /// using `dlsym()` or a platform equivalent.
  ///
  /// The value of this property can be thought of as equivalent to a call to
  /// `swift test --event-stream-output-path` except that, instead of streaming
  /// JSON records to a named pipe or file, it streams them to an in-process
  /// callback.
  public static var entryPoint: EntryPoint {
    return { configurationJSON, recordHandler in
      let args = try configurationJSON.map { configurationJSON in
        try JSON.decode(__CommandLineArguments_v0.self, from: configurationJSON)
      }
      let eventHandler = try eventHandlerForStreamingEvents(version: args?.eventStreamVersion, encodeAsJSONLines: false, forwardingTo: recordHandler)

      switch await Testing.entryPoint(passing: args, eventHandler: eventHandler) {
      case EXIT_SUCCESS, EXIT_NO_TESTS_FOUND:
        return true
      default:
        return false
      }
    }
  }
}

/// An exported C function that is the equivalent of
/// ``ABI/v0/entryPoint-swift.type.property``.
///
/// - Returns: The value of ``ABI/v0/entryPoint-swift.type.property`` cast to an
///   untyped pointer.
///
/// - Note: This function's name is prefixed with `swt_` instead of
///   `swift_testing_` for binary compatibility reasons. Future ABI entry point
///   functions should use the `swift_testing_` prefix instead.
@_cdecl("swt_abiv0_getEntryPoint")
@usableFromInline func abiv0_getEntryPoint() -> UnsafeRawPointer {
  unsafeBitCast(ABI.v0.entryPoint, to: UnsafeRawPointer.self)
}

#if !SWT_NO_SNAPSHOT_TYPES
// MARK: - Xcode 16 compatibility

extension ABI.Xcode16 {
  /// An older signature for ``ABI/v0/EntryPoint-swift.typealias`` used by
  /// Xcode&nbsp;16.
  ///
  /// - Warning: This type will be removed in a future update.
  @available(*, deprecated, message: "Use ABI.v0.EntryPoint instead.")
  typealias EntryPoint = @Sendable (
    _ argumentsJSON: UnsafeRawBufferPointer?,
    _ recordHandler: @escaping @Sendable (_ recordJSON: UnsafeRawBufferPointer) -> Void
  ) async throws -> CInt
}

/// An older signature for ``ABI/v0/entryPoint-swift.type.property`` used by
/// Xcode&nbsp;16.
///
/// - Warning: This function will be removed in a future update.
@available(*, deprecated, message: "Use ABI.v0.entryPoint (swt_abiv0_getEntryPoint()) instead.")
@_cdecl("swt_copyABIEntryPoint_v0")
@usableFromInline func copyABIEntryPoint_v0() -> UnsafeMutableRawPointer {
  let result = UnsafeMutablePointer<ABI.Xcode16.EntryPoint>.allocate(capacity: 1)
  result.initialize { configurationJSON, recordHandler in
    var args = try configurationJSON.map { configurationJSON in
      try JSON.decode(__CommandLineArguments_v0.self, from: configurationJSON)
    }
    if args?.eventStreamVersion == nil {
      args?.eventStreamVersion = ABI.Xcode16.versionNumber
    }
    let eventHandler = try eventHandlerForStreamingEvents(version: args?.eventStreamVersion, encodeAsJSONLines: false, forwardingTo: recordHandler)

    var exitCode = await Testing.entryPoint(passing: args, eventHandler: eventHandler)
    if exitCode == EXIT_NO_TESTS_FOUND {
      exitCode = EXIT_SUCCESS
    }
    return exitCode
  }
  return .init(result)
}
#endif
#endif
