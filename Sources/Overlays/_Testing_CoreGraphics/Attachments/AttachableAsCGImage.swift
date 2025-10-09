//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024–2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if SWT_TARGET_OS_APPLE && canImport(CoreGraphics)
public import CoreGraphics
private import ImageIO

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
///
/// @Metadata {
///   @Available(Swift, introduced: 6.3)
/// }
@available(_uttypesAPI, *)
public protocol AttachableAsCGImage: _AttachableAsImage, SendableMetatype {
  /// An instance of `CGImage` representing this image.
  ///
  /// - Throws: Any error that prevents the creation of an image.
  ///
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.3)
  /// }
  var attachableCGImage: CGImage { get throws }

  /// The orientation of the image.
  ///
  /// The value of this property is the raw value of an instance of
  /// `CGImagePropertyOrientation`. The default value of this property is
  /// `.up`.
  ///
  /// This property is not part of the public interface of the testing
  /// library. It may be removed in a future update.
  var _attachmentOrientation: UInt32 { get }

  /// The scale factor of the image.
  ///
  /// The value of this property is typically greater than `1.0` when an image
  /// originates from a Retina Display screenshot or similar. The default value
  /// of this property is `1.0`.
  ///
  /// This property is not part of the public interface of the testing
  /// library. It may be removed in a future update.
  var _attachmentScaleFactor: CGFloat { get }
}

@available(_uttypesAPI, *)
extension AttachableAsCGImage {
  public var _attachmentOrientation: UInt32 {
    CGImagePropertyOrientation.up.rawValue
  }

  public var _attachmentScaleFactor: CGFloat {
    1.0
  }

  public func _deinitializeAttachableValue() {}
}

@available(_uttypesAPI, *)
extension AttachableAsCGImage where Self: Sendable {
  public func _copyAttachableValue() -> Self {
    self
  }
}
#endif
