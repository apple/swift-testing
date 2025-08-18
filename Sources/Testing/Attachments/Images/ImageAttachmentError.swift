//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

private import _TestingInternals

/// A type representing an error that can occur when attaching an image.
package enum ImageAttachmentError: Error {
#if SWT_TARGET_OS_APPLE
  /// The image could not be converted to an instance of `CGImage`.
  case couldNotCreateCGImage

  /// The image destination could not be created.
  case couldNotCreateImageDestination

  /// The image could not be converted.
  case couldNotConvertImage
#elseif os(Windows)
  /// A call to `QueryInterface()` failed.
  case queryInterfaceFailed(Any.Type, Int32)

  /// The testing library failed to create a COM object.
  case comObjectCreationFailed(Any.Type, Int32)

  /// An image could not be written.
  case imageWritingFailed(Int32)

  /// The testing library failed to get an in-memory stream's underlying buffer.
  case globalFromStreamFailed(Int32)

  /// A property could not be written to a property bag.
  case propertyBagWritingFailed(String, Int32)
#endif
}

extension ImageAttachmentError: CustomStringConvertible {
  package var description: String {
#if SWT_TARGET_OS_APPLE
    switch self {
    case .couldNotCreateCGImage:
      "Could not create the corresponding Core Graphics image."
    case .couldNotCreateImageDestination:
      "Could not create the Core Graphics image destination to encode this image."
    case .couldNotConvertImage:
      "Could not convert the image to the specified format."
    }
#elseif os(Windows)
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
#else
    swt_unreachable()
#endif
  }
}
