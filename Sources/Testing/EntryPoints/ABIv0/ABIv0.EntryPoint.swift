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

@_spi(ForToolsIntegrationOnly)
extension ABIv0 {
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
  /// The value of this property can be thought of as equivalent to
  /// `swift test --event-stream-output` except that, instead of streaming JSON
  /// records to a named pipe or file, it streams them to an in-process
  /// callback.
  public static var entryPoint: EntryPoint {
    return { configurationJSON, recordHandler in
      let args = try configurationJSON.map { configurationJSON in
        try JSON.decode(__CommandLineArguments_v0.self, from: configurationJSON)
      }

      let eventHandler = try eventHandlerForStreamingEvents(version: args?.eventStreamVersion, forwardingTo: recordHandler)
      let exitCode = await Testing.entryPoint(passing: args, eventHandler: eventHandler)
      return exitCode == EXIT_SUCCESS
    }
  }
}

/// An exported C function that is the equivalent of
/// ``ABIv0/entryPoint-swift.type.property``.
///
/// - Returns: The value of ``ABIv0/entryPoint-swift.type.property`` cast to an
///   untyped pointer.
@_cdecl("swt_abiv0_getEntryPoint")
@usableFromInline func abiv0_getEntryPoint() -> UnsafeRawPointer {
  unsafeBitCast(ABIv0.entryPoint, to: UnsafeRawPointer.self)
}
#endif
