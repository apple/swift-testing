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

/// An older signature for ``ABIv0/EntryPoint-swift.typealias`` used by Xcode 16
/// Beta 1.
///
/// This type will be removed in a future update.
@available(*, deprecated, message: "Use ABIv0.EntryPoint instead.")
typealias ABIEntryPoint_v0 = @Sendable (
  _ argumentsJSON: UnsafeRawBufferPointer?,
  _ recordHandler: @escaping @Sendable (_ recordJSON: UnsafeRawBufferPointer) -> Void
) async throws -> CInt

/// An older signature for ``ABIv0/entryPoint-swift.type.property`` used by
/// Xcode 16 Beta 1.
///
/// This function will be removed in a future update.
@available(*, deprecated, message: "Use ABIv0.entryPoint (swt_abiv0_getEntryPoint()) instead.")
@_cdecl("swt_copyABIEntryPoint_v0")
@usableFromInline func copyABIEntryPoint_v0() -> UnsafeMutableRawPointer {
  let result = UnsafeMutablePointer<ABIEntryPoint_v0>.allocate(capacity: 1)
  result.initialize { try await ABIv0.entryPoint($0, $1) ? EXIT_SUCCESS : EXIT_FAILURE }
  return .init(result)
}
#endif
