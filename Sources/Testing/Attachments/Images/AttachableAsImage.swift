//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024–2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if SWT_TARGET_OS_APPLE || os(Windows)
// These platforms support image attachments.
#elseif !SWT_NO_IMAGE_ATTACHMENTS
#error("Platform-specific misconfiguration: support for image attachments requires a platform-specific implementation")
#endif

/// ## Why can't images directly conform to Attachable?
///
/// Three reasons:
///
/// 1. Several image classes are not marked `Sendable`, which means that as far
///    as Swift is concerned, they cannot be safely passed to Swift Testing's
///    event handler (primarily because `Event` is `Sendable`.) So we would have
///    to eagerly serialize them, which is unnecessarily expensive if we know
///    they're actually concurrency-safe.
/// 2. We would have no place to store metadata such as the encoding quality
///    (although in the future we may introduce a "metadata" associated type to
///    `Attachable` that could store that info.)
/// 3. `Attachable` has a requirement with `Self` in non-parameter, non-return
///    position. As far as Swift is concerned, a non-final class cannot satisfy
///    such a requirement, and all image types we care about are non-final
///    classes. Thus, the compiler will steadfastly refuse to allow non-final
///    classes to conform to the `Attachable` protocol. We could get around this
///    by changing the signature of `withUnsafeBytes()` so that the
///    generic parameter to `Attachment` is not `Self`, but that would defeat
///    much of the purpose of making `Attachment` generic in the first place.
///    (And no, the language does not let us write `where T: Self` anywhere
///    useful.)

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
/// @Comment {
/// | Windows | [`HBITMAP`](https://learn.microsoft.com/en-us/windows/win32/gdi/bitmaps), [`HICON`](https://learn.microsoft.com/en-us/windows/win32/menurc/icons), [`IWICBitmapSource`](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nn-wincodec-iwicbitmapsource) (including its subclasses declared by Windows Imaging Component) |
/// }
///
/// You do not generally need to add your own conformances to this protocol. If
/// you have an image in another format that needs to be attached to a test,
/// first convert it to an instance of one of the types above.
///
/// @Metadata {
///   @Available(Swift, introduced: 6.3)
/// }
#if SWT_NO_IMAGE_ATTACHMENTS
@available(*, unavailable, message: "Image attachments are not available on this platform.")
#endif
@available(_uttypesAPI, *)
public protocol AttachableAsImage {
  /// Encode a representation of this image in a given image format.
  ///
  /// - Parameters:
  ///   - imageFormat: The image format to use when encoding this image.
  ///   - body: A function to call. A temporary buffer containing a data
  ///     representation of this instance is passed to it.
  ///
  /// - Returns: Whatever is returned by `body`.
  ///
  /// - Throws: Whatever is thrown by `body`, or any error that prevented the
  ///   creation of the buffer.
  ///
  /// The testing library uses this function when saving an image as an
  /// attachment. The implementation should use `imageFormat` to determine what
  /// encoder to use.
  borrowing func withUnsafeBytes<R>(as imageFormat: AttachableImageFormat, _ body: (UnsafeRawBufferPointer) throws -> R) throws -> R

  /// Make a copy of this instance to pass to an attachment.
  ///
  /// - Returns: A copy of `self`, or `self` if no copy is needed.
  ///
  /// The testing library uses this function to take ownership of image
  /// resources that test authors pass to it. If possible, make a copy of or add
  /// a reference to `self`. If this type does not support making copies, return
  /// `self` verbatim.
  ///
  /// The default implementation of this function when `Self` conforms to
  /// `Sendable` simply returns `self`.
  ///
  /// This function is not part of the public interface of the testing library.
  /// It may be removed in a future update.
  func _copyAttachableValue() -> Self

  /// Manually deinitialize any resources associated with this image.
  ///
  /// The implementation of this function cleans up any resources (such as
  /// handles or COM objects) associated with this image. The testing library
  /// automatically invokes this function as needed.
  ///
  /// This function is not responsible for releasing the image returned from
  /// `_copyAttachableIWICBitmapSource(using:)`.
  ///
  /// The default implementation of this function when `Self` conforms to
  /// `Sendable` does nothing.
  ///
  /// This function is not part of the public interface of the testing library.
  /// It may be removed in a future update.
  func _deinitializeAttachableValue()
}

#if SWT_NO_IMAGE_ATTACHMENTS
@available(*, unavailable, message: "Image attachments are not available on this platform.")
#endif
@available(_uttypesAPI, *)
extension AttachableAsImage {
  public func _copyAttachableValue() -> Self {
    self
  }

  public func _deinitializeAttachableValue() {}
}
