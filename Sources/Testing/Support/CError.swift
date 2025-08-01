//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

internal import _TestingInternals

/// A type representing an error from a C function such as `fopen()`.
///
/// This type is necessary because Foundation's `POSIXError` is not available in
/// all contexts.
///
/// This type is not part of the public interface of the testing library.
struct CError: Error, RawRepresentable {
  var rawValue: CInt
}

#if os(Windows)
/// A type representing a Windows error from a Win32 API function.
///
/// Values of this type are in the domain described by Microsoft
/// [here](https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes).
///
/// This type is not part of the public interface of the testing library.
package struct Win32Error: Error, RawRepresentable {
  package var rawValue: CUnsignedLong

  package init(rawValue: CUnsignedLong) {
    self.rawValue = rawValue
  }
}
#endif

// MARK: - CustomStringConvertible

/// Get a string describing a C error code.
///
/// - Parameters:
///   - errorCode: The error code to describe.
///
/// - Returns: A Swift string equal to the result of `strerror()` from the C
///   standard library.
func strerror(_ errorCode: CInt) -> String {
#if os(Windows)
  String(unsafeUninitializedCapacity: 1024) { buffer in
    _ = strerror_s(buffer.baseAddress!, buffer.count, errorCode)
    return strnlen(buffer.baseAddress!, buffer.count)
  }
#elseif os(FreeBSD) || os(OpenBSD)
  // FreeBSD's/OpenBSD's implementation of strerror() is not thread-safe.
  String(unsafeUninitializedCapacity: 1024) { buffer in
    _ = strerror_r(errorCode, buffer.baseAddress!, buffer.count)
    return strnlen(buffer.baseAddress!, buffer.count)
  }
#else
  String(cString: _TestingInternals.strerror(errorCode))
#endif
}

extension CError: CustomStringConvertible {
  var description: String {
    strerror(rawValue)
  }
}

#if os(Windows)
extension Win32Error: CustomStringConvertible {
  package var description: String {
    let (address, count) = withUnsafeTemporaryAllocation(of: LPWSTR?.self, capacity: 1) { buffer in
      // FormatMessageW() takes a wide-character buffer into which it writes the
      // error message... _unless_ you pass `FORMAT_MESSAGE_ALLOCATE_BUFFER` in
      // which case it takes a pointer-to-pointer that it populates with a
      // heap-allocated string. However, the signature for FormatMessageW()
      // still takes an LPWSTR? (Optional<UnsafeMutablePointer<wchar_t>>), so we
      // need to temporarily mis-cast the pointer before we can pass it in.
      let count = buffer.withMemoryRebound(to: wchar_t.self) { buffer in
        FormatMessageW(
          DWORD(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS | FORMAT_MESSAGE_MAX_WIDTH_MASK),
          nil,
          rawValue,
          DWORD(swt_MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT)),
          buffer.baseAddress,
          0,
          nil
        )
      }
      return (buffer.moveElement(from: buffer.startIndex), count)
    }
    defer {
      LocalFree(address)
    }
    if count > 0, let address, var result = String.decodeCString(address, as: UTF16.self)?.result {
      // Some of the strings produced by FormatMessageW() have trailing
      // whitespace we will want to remove.
      while let lastCharacter = result.last, lastCharacter.isWhitespace {
        result.removeLast()
      }
      return result
    }
    return "An unknown error occurred (\(rawValue))."
  }
}
#endif
