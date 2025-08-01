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
private import _TestingInternals.GDIPlus

internal import WinSDK

/// A protocol describing images that can be converted to instances of
/// ``Testing/Attachment``.
///
/// Instances of types conforming to this protocol do not themselves conform to
/// ``Testing/Attachable``. Instead, the testing library provides additional
/// initializers on ``Testing/Attachment`` that take instances of such types and
/// handle converting them to image data when needed.
///
/// The following system-provided image types conform to this protocol and can
/// be attached to a test:
///
/// - [`HBITMAP`](https://learn.microsoft.com/en-us/windows/win32/gdi/bitmaps)
/// - [`HICON`](https://learn.microsoft.com/en-us/windows/win32/menurc/icons)
///
/// You do not generally need to add your own conformances to this protocol. If
/// you have an image in another format that needs to be attached to a test,
/// first convert it to an instance of one of the types above.
@_spi(Experimental)
public protocol _AttachableByAddressAsGDIPlusImage {
  /// Create a GDI+ image representing an instance of this type at the given
  /// address.
  ///
  /// - Parameters:
  ///   - imageAddress: The address of the instance of this type.
  ///
  /// - Returns: A pointer to a new GDI+ image representing this image. The
  ///   caller is responsible for deleting this image when done with it.
  ///
  /// - Throws: Any error that prevented the creation of the GDI+ image.
  ///
  /// - Note: This function returns a value of C++ type `Gdiplus::Image *`. That
  ///   type cannot be directly represented in Swift. If this function returns a
  ///   value of any other concrete type, the result is undefined.
  ///
  /// The testing library automatically calls `GdiplusStartup()` and
  /// `GdiplusShutdown()` before and after calling this function. This function
  /// can therefore assume that GDI+ is correctly configured on the current
  /// thread when it is called.
  ///
  /// This function is not part of the public interface of the testing library.
  /// It may be removed in a future update.
  static func _copyAttachableGDIPlusImage(at imageAddress: UnsafeMutablePointer<Self>) throws -> OpaquePointer

  /// Clean up any resources at the given address.
  ///
  /// - Parameters:
  ///   - imageAddress: The address of the instance of this type.
  ///
  /// The implementation of this function cleans up any resources (such as
  /// handles or COM objects) associated with this value. The testing library
  /// automatically invokes this function as needed.
  ///
  /// This function is not responsible for deleting the image returned from
  /// `_copyAttachableGDIPlusImage(at:)`.
  ///
  /// This function is not part of the public interface of the testing library.
  /// It may be removed in a future update.
  static func _cleanUpAttachment(at imageAddress: UnsafeMutablePointer<Self>)
}

/// A protocol describing images that can be converted to instances of
/// ``Testing/Attachment``.
///
/// Instances of types conforming to this protocol do not themselves conform to
/// ``Testing/Attachable``. Instead, the testing library provides additional
/// initializers on ``Testing/Attachment`` that take instances of such types and
/// handle converting them to image data when needed.
///
/// The following system-provided image types conform to this protocol and can
/// be attached to a test:
///
/// - [`HBITMAP`](https://learn.microsoft.com/en-us/windows/win32/gdi/bitmaps)
/// - [`HICON`](https://learn.microsoft.com/en-us/windows/win32/menurc/icons)
///
/// You do not generally need to add your own conformances to this protocol. If
/// you have an image in another format that needs to be attached to a test,
/// first convert it to an instance of one of the types above.
@_spi(Experimental)
public protocol AttachableAsGDIPlusImage {
  /// Create a GDI+ image representing this instance.
  ///
  /// - Returns: A pointer to a new GDI+ image representing this image. The
  ///   caller is responsible for deleting this image when done with it.
  ///
  /// - Throws: Any error that prevented the creation of the GDI+ image.
  ///
  /// - Note: This function returns a value of C++ type `Gdiplus::Image *`. That
  ///   type cannot be directly represented in Swift. If this function returns a
  ///   value of any other concrete type, the result is undefined.
  ///
  /// The testing library automatically calls `GdiplusStartup()` and
  /// `GdiplusShutdown()` before and after calling this function. This function
  /// can therefore assume that GDI+ is correctly configured on the current
  /// thread when it is called.
  ///
  /// This function is not part of the public interface of the testing library.
  /// It may be removed in a future update.
  func _copyAttachableGDIPlusImage() throws -> OpaquePointer

  /// Clean up any resources associated with this instance.
  ///
  /// The implementation of this function cleans up any resources (such as
  /// handles or COM objects) associated with this value. The testing library
  /// automatically invokes this function as needed.
  ///
  /// This function is not responsible for deleting the image returned from
  /// `_copyAttachableGDIPlusImage()`.
  ///
  /// This function is not part of the public interface of the testing library.
  /// It may be removed in a future update.
  func _cleanUpAttachment()
}
#endif
