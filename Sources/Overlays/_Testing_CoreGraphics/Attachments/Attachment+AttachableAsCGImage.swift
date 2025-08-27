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
public import Testing

@available(_uttypesAPI, *)
extension Attachment {
  /// Initialize an instance of this type that encloses the given image.
  ///
  /// - Parameters:
  ///   - image: The value that will be attached to the output of the test run.
  ///   - preferredName: The preferred name of the attachment when writing it
  ///     to a test report or to disk. If `nil`, the testing library attempts
  ///     to derive a reasonable filename for the attached value.
  ///   - imageFormat: The image format with which to encode `image`.
  ///   - sourceLocation: The source location of the call to this initializer.
  ///     This value is used when recording issues associated with the
  ///     attachment.
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
  /// The testing library uses the image format specified by `imageFormat`. Pass
  /// `nil` to let the testing library decide which image format to use. If you
  /// pass `nil`, then the image format that the testing library uses depends on
  /// the path extension you specify in `preferredName`, if any. If you do not
  /// specify a path extension, or if the path extension you specify doesn't
  /// correspond to an image format the operating system knows how to write, the
  /// testing library selects an appropriate image format for you.
  ///
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.3)
  /// }
  public init<T>(
    _ image: T,
    named preferredName: String? = nil,
    as imageFormat: AttachableImageFormat? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
  ) where T: AttachableAsCGImage, AttachableValue == _AttachableImageWrapper<T> {
    let imageWrapper = _AttachableImageWrapper(
      image: image._copyAttachableValue(),
      imageFormat: imageFormat,
      deinitializingWith: { _ in }
    )
    self.init(imageWrapper, named: preferredName, sourceLocation: sourceLocation)
  }

  /// Attach an image to the current test.
  ///
  /// - Parameters:
  ///   - image: The value to attach.
  ///   - preferredName: The preferred name of the attachment when writing it to
  ///     a test report or to disk. If `nil`, the testing library attempts to
  ///     derive a reasonable filename for the attached value.
  ///   - imageFormat: The image format with which to encode `image`.
  ///   - sourceLocation: The source location of the call to this function.
  ///
  /// This function creates a new instance of ``Attachment`` wrapping `image`
  /// and immediately attaches it to the current test. You can attach instances
  /// of the following system-provided image types to a test:
  ///
  /// | Platform | Supported Types |
  /// |-|-|
  /// | macOS | [`CGImage`](https://developer.apple.com/documentation/coregraphics/cgimage), [`CIImage`](https://developer.apple.com/documentation/coreimage/ciimage), [`NSImage`](https://developer.apple.com/documentation/appkit/nsimage) |
  /// | iOS, watchOS, tvOS, and visionOS | [`CGImage`](https://developer.apple.com/documentation/coregraphics/cgimage), [`CIImage`](https://developer.apple.com/documentation/coreimage/ciimage), [`UIImage`](https://developer.apple.com/documentation/uikit/uiimage) |
  /// @Comment {
  /// | Windows | [`HBITMAP`](https://learn.microsoft.com/en-us/windows/win32/gdi/bitmaps), [`HICON`](https://learn.microsoft.com/en-us/windows/win32/menurc/icons), [`IWICBitmapSource`](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nn-wincodec-iwicbitmapsource) (including its subclasses declared by Windows Imaging Component) |
  /// }
  ///
  /// The testing library uses the image format specified by `imageFormat`. Pass
  /// `nil` to let the testing library decide which image format to use. If you
  /// pass `nil`, then the image format that the testing library uses depends on
  /// the path extension you specify in `preferredName`, if any. If you do not
  /// specify a path extension, or if the path extension you specify doesn't
  /// correspond to an image format the operating system knows how to write, the
  /// testing library selects an appropriate image format for you.
  ///
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.3)
  /// }
  public static func record<T>(
    _ image: T,
    named preferredName: String? = nil,
    as imageFormat: AttachableImageFormat? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
  ) where T: AttachableAsCGImage, AttachableValue == _AttachableImageWrapper<T> {
    let attachment = Self(image, named: preferredName, as: imageFormat, sourceLocation: sourceLocation)
    Self.record(attachment, sourceLocation: sourceLocation)
  }
}

// MARK: -

@_spi(Experimental) // STOP: not part of ST-0014
@available(_uttypesAPI, *)
extension Attachment where AttachableValue: AttachableWrapper, AttachableValue.Wrapped: AttachableAsCGImage {
  /// The image format to use when encoding the represented image.
  @_disfavoredOverload public var imageFormat: AttachableImageFormat? {
    // FIXME: no way to express `where AttachableValue == _AttachableImageWrapper<???>` on a property (see rdar://47559973)
    (attachableValue as? _AttachableImageWrapper<AttachableValue.Wrapped>)?.imageFormat
  }
}
#endif
