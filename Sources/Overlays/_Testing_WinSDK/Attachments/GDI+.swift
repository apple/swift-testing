//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if os(Windows)
@_spi(Experimental) import Testing
internal import _TestingInternals.GDIPlus

internal import WinSDK

/// A type describing errors that can be thrown by GDI+.
enum GDIPlusError: Error {
  /// A GDI+ status code.
  case status(Gdiplus.Status)

  /// The testing library failed to create an in-memory stream.
  case streamCreationFailed(HRESULT)

  /// The testing library failed to get an in-memory stream's underlying buffer.
  case globalFromStreamFailed(HRESULT)
}

extension GDIPlusError: CustomStringConvertible {
  var description: String {
    switch self {
    case let .status(status):
      "Could not create the corresponding GDI+ image (Gdiplus.Status \(status.rawValue))."
    case let .streamCreationFailed(result):
      "Could not create an in-memory stream (HRESULT \(result))."
    case let .globalFromStreamFailed(result):
      "Could not access the buffer containing the encoded image (HRESULT \(result))."
    }
  }
}

// MARK: -

/// Call a function while GDI+ is set up on the current thread.
/// 
/// - Parameters:
///   - body: The function to invoke.
///
/// - Returns: Whatever is returned by `body`.
///
/// - Throws: Whatever is thrown by `body`.
func withGDIPlus<R>(_ body: () throws -> R) throws -> R {
  // "Escape hatch" if the program being tested calls GdiplusStartup() itself in
  // some way that is incompatible with our assumptions about it.
  if Environment.flag(named: "SWT_GDIPLUS_STARTUP_ENABLED") == false {
    return try body()
  }

  var token = ULONG_PTR(0)
  var input = Gdiplus.GdiplusStartupInput(nil, false, false)
  let rStartup = swt_GdiplusStartup(&token, &input, nil)
  guard rStartup == Gdiplus.Ok else {
    throw GDIPlusError.status(rStartup)
  }
  defer {
    swt_GdiplusShutdown(token)
  }

  return try body()
}
#endif
