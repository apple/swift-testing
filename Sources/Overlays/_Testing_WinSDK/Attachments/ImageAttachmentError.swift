//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if os(Windows)
@_spi(Experimental) import Testing

internal import WinSDK

/// A type describing errors that can be thrown by WIC or COM while attaching an
/// image.
enum ImageAttachmentError: Error {
  /// A call to `QueryInterface()` failed.
  case queryInterfaceFailed(Any.Type, HRESULT)

  /// The testing library failed to create a WIC object.
  case comObjectCreationFailed(Any.Type, HRESULT)

  /// An image could not be written.
  case imageWritingFailed(HRESULT)

  /// The testing library failed to get an in-memory stream's underlying buffer.
  case globalFromStreamFailed(HRESULT)

  /// A property could not be written to a property bag.
  case propertyBagWritingFailed(String, HRESULT)
}

extension ImageAttachmentError: CustomStringConvertible {
  var description: String {
    switch self {
    case let .queryInterfaceFailed(type, result):
      "Could not cast a COM object to type '\(type)' (HRESULT \(result))."
    case let .comObjectCreationFailed(type, result):
      "Could not create a COM object of type '\(type)' (HRESULT \(result))."
    case let .imageWritingFailed(result):
      "Could not write the image (HRESULT \(result))."
    case let .globalFromStreamFailed(result):
      "Could not access the buffer containing the encoded image (HRESULT \(result))."
    case let .propertyBagWritingFailed(name, result):
      "Could not set the property '\(name)' (HRESULT \(result))."
    }
  }
}
#endif
