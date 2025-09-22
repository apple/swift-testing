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
private import Testing
public import WinSDK

/// A protocol describing images that can be converted to instances of
/// ``Testing/Attachment``.
///
/// Instances of types conforming to this protocol do not themselves conform to
/// ``Testing/Attachable``. Instead, the testing library provides additional
/// initializers on ``Testing/Attachment`` that take instances of such types and
/// handle converting them to image data when needed.
///
/// You can attach instances of the following system-provided image types to a
/// test:
///
/// | Platform | Supported Types |
/// |-|-|
/// | macOS | [`CGImage`](https://developer.apple.com/documentation/coregraphics/cgimage), [`CIImage`](https://developer.apple.com/documentation/coreimage/ciimage), [`NSImage`](https://developer.apple.com/documentation/appkit/nsimage) |
/// | iOS, watchOS, tvOS, and visionOS | [`CGImage`](https://developer.apple.com/documentation/coregraphics/cgimage), [`CIImage`](https://developer.apple.com/documentation/coreimage/ciimage), [`UIImage`](https://developer.apple.com/documentation/uikit/uiimage) |
/// | Windows | [`HBITMAP`](https://learn.microsoft.com/en-us/windows/win32/gdi/bitmaps), [`HICON`](https://learn.microsoft.com/en-us/windows/win32/menurc/icons), [`IWICBitmapSource`](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nn-wincodec-iwicbitmapsource) (including its subclasses declared by Windows Imaging Component) |
///
/// You do not generally need to add your own conformances to this protocol. If
/// you have an image in another format that needs to be attached to a test,
/// first convert it to an instance of one of the types above.
@_spi(Experimental)
public protocol _AttachableByAddressAsIWICBitmapSource {
  /// Create a WIC bitmap source representing an instance of this type at the
  /// given address.
  ///
  /// - Parameters:
  ///   - imageAddress: The address of the instance of this type.
  ///   - factory: A WIC imaging factory that can be used to create additional
  ///     WIC objects.
  ///
  /// - Returns: A pointer to a new WIC bitmap source representing this image.
  ///   The caller is responsible for releasing this image when done with it.
  ///
  /// - Throws: Any error that prevented the creation of the WIC bitmap.
  ///
  /// This function is not part of the public interface of the testing library.
  /// It may be removed in a future update.
  static func _copyAttachableIWICBitmapSource(
    from imageAddress: UnsafeMutablePointer<Self>,
    using factory: UnsafeMutablePointer<IWICImagingFactory>
  ) throws -> UnsafeMutablePointer<IWICBitmapSource>

  /// Make a copy of the instance of this type at the given address.
  ///
  /// - Parameters:
  ///   - imageAddress: The address of the instance of this type that should be
  ///     copied.
  ///
  /// - Returns: A copy of `imageAddress`, or `imageAddress` if this type does
  ///   not support a copying operation.
  ///
  /// The testing library uses this function to take ownership of image
  /// resources that test authors pass to it. If possible, make a copy of or add
  /// a reference to the value at `imageAddress`. If this type does not support
  /// making copies, return `imageAddress` verbatim.
  ///
  /// This function is not part of the public interface of the testing library.
  /// It may be removed in a future update.
  static func _copyAttachableValue(at imageAddress: UnsafeMutablePointer<Self>) -> UnsafeMutablePointer<Self>

  /// Manually deinitialize any resources at the given address.
  ///
  /// - Parameters:
  ///   - imageAddress: The address of the instance of this type.
  ///
  /// The implementation of this function is responsible for balancing a
  /// previous call to `_copyAttachableValue(at:)` by cleaning up any resources
  /// (such as handles or COM objects) associated with the value at
  /// `imageAddress`. The testing library automatically invokes this function as
  /// needed. If `_copyAttachableValue(at:)` threw an error, the testing library
  /// does not call this function.
  ///
  /// This function is not responsible for releasing the image returned from
  /// `_copyAttachableIWICBitmapSource(from:using:)`.
  ///
  /// This function is not part of the public interface of the testing library.
  /// It may be removed in a future update.
  static func _deinitializeAttachableValue(at imageAddress: UnsafeMutablePointer<Self>)
}

/// A protocol describing images that can be converted to instances of
/// [`Attachment`](https://developer.apple.com/documentation/testing/attachment).
///
/// Instances of types conforming to this protocol do not themselves conform to
/// [`Attachable`](https://developer.apple.com/documentation/testing/attachable).
/// Instead, the testing library provides additional initializers on [`Attachment`](https://developer.apple.com/documentation/testing/attachment)
/// that take instances of such types and handle converting them to image data when needed.
///
/// You can attach instances of the following system-provided image types to a
/// test:
///
/// | Platform | Supported Types |
/// |-|-|
/// | macOS | [`CGImage`](https://developer.apple.com/documentation/coregraphics/cgimage), [`CIImage`](https://developer.apple.com/documentation/coreimage/ciimage), [`NSImage`](https://developer.apple.com/documentation/appkit/nsimage) |
/// | iOS, watchOS, tvOS, and visionOS | [`CGImage`](https://developer.apple.com/documentation/coregraphics/cgimage), [`CIImage`](https://developer.apple.com/documentation/coreimage/ciimage), [`UIImage`](https://developer.apple.com/documentation/uikit/uiimage) |
/// | Windows | [`HBITMAP`](https://learn.microsoft.com/en-us/windows/win32/gdi/bitmaps), [`HICON`](https://learn.microsoft.com/en-us/windows/win32/menurc/icons), [`IWICBitmapSource`](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nn-wincodec-iwicbitmapsource) (including its subclasses declared by Windows Imaging Component) |
///
/// You do not generally need to add your own conformances to this protocol. If
/// you have an image in another format that needs to be attached to a test,
/// first convert it to an instance of one of the types above.
@_spi(Experimental)
public protocol AttachableAsIWICBitmapSource: _AttachableAsImage, SendableMetatype {
  /// Create a WIC bitmap source representing an instance of this type.
  ///
  /// - Returns: A pointer to a new WIC bitmap source representing this image.
  ///   The caller is responsible for releasing this image when done with it.
  ///
  /// - Throws: Any error that prevented the creation of the WIC bitmap source.
  func copyAttachableIWICBitmapSource() throws -> UnsafeMutablePointer<IWICBitmapSource>

  /// Create a WIC bitmap representing an instance of this type.
  ///
  /// - Parameters:
  ///   - factory: A WIC imaging factory that can be used to create additional
  ///     WIC objects.
  ///
  /// - Returns: A pointer to a new WIC bitmap representing this image. The
  ///   caller is responsible for releasing this image when done with it.
  ///
  /// - Throws: Any error that prevented the creation of the WIC bitmap.
  ///
  /// The default implementation of this function ignores `factory` and calls
  /// ``copyAttachableIWICBitmapSource()``. If your implementation of
  /// ``copyAttachableIWICBitmapSource()`` needs to create a WIC imaging factory
  /// in order to return a result, it is more efficient to implement this
  /// function too so that the testing library can pass the WIC imaging factory
  /// it creates.
  ///
  /// This function is not part of the public interface of the testing library.
  /// It may be removed in a future update.
  func _copyAttachableIWICBitmapSource(
    using factory: UnsafeMutablePointer<IWICImagingFactory>
  ) throws -> UnsafeMutablePointer<IWICBitmapSource>
}

extension AttachableAsIWICBitmapSource {
  public func _copyAttachableIWICBitmapSource(
    using factory: UnsafeMutablePointer<IWICImagingFactory>
  ) throws -> UnsafeMutablePointer<IWICBitmapSource> {
    try copyAttachableIWICBitmapSource()
  }
}
#endif
