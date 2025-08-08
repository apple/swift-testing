//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if SWT_TARGET_OS_APPLE && canImport(CoreGraphics)
@_spi(Experimental) public import Testing

@_spi(Experimental)
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
  /// The following system-provided image types conform to the
  /// ``AttachableAsCGImage`` protocol and can be attached to a test:
  ///
  /// - [`CGImage`](https://developer.apple.com/documentation/coregraphics/cgimage)
  /// - [`CIImage`](https://developer.apple.com/documentation/coreimage/ciimage)
  /// - [`NSImage`](https://developer.apple.com/documentation/appkit/nsimage)
  ///   (macOS)
  /// - [`UIImage`](https://developer.apple.com/documentation/uikit/uiimage)
  ///   (iOS, watchOS, tvOS, visionOS, and Mac Catalyst)
  ///
  /// The testing library uses the image format specified by `imageFormat`. Pass
  /// `nil` to let the testing library decide which image format to use. If you
  /// pass `nil`, then the image format that the testing library uses depends on
  /// the path extension you specify in `preferredName`, if any. If you do not
  /// specify a path extension, or if the path extension you specify doesn't
  /// correspond to an image format the operating system knows how to write, the
  /// testing library selects an appropriate image format for you.
  public init<T>(
    _ image: T,
    named preferredName: String? = nil,
    as imageFormat: AttachableImageFormat? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
  ) where AttachableValue == _AttachableImageWrapper<T> {
    let imageWrapper = _AttachableImageWrapper(image: image, imageFormat: imageFormat)
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
  /// and immediately attaches it to the current test.
  ///
  /// The following system-provided image types conform to the
  /// ``AttachableAsCGImage`` protocol and can be attached to a test:
  ///
  /// - [`CGImage`](https://developer.apple.com/documentation/coregraphics/cgimage)
  /// - [`CIImage`](https://developer.apple.com/documentation/coreimage/ciimage)
  /// - [`NSImage`](https://developer.apple.com/documentation/appkit/nsimage)
  ///   (macOS)
  /// - [`UIImage`](https://developer.apple.com/documentation/uikit/uiimage)
  ///   (iOS, watchOS, tvOS, visionOS, and Mac Catalyst)
  ///
  /// The testing library uses the image format specified by `imageFormat`. Pass
  /// `nil` to let the testing library decide which image format to use. If you
  /// pass `nil`, then the image format that the testing library uses depends on
  /// the path extension you specify in `preferredName`, if any. If you do not
  /// specify a path extension, or if the path extension you specify doesn't
  /// correspond to an image format the operating system knows how to write, the
  /// testing library selects an appropriate image format for you.
  public static func record<T>(
    _ image: consuming T,
    named preferredName: String? = nil,
    as imageFormat: AttachableImageFormat? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
  ) where AttachableValue == _AttachableImageWrapper<T> {
    let attachment = Self(image, named: preferredName, as: imageFormat, sourceLocation: sourceLocation)
    Self.record(attachment, sourceLocation: sourceLocation)
  }
}

@_spi(Experimental) // STOP: not part of ST-0014
@available(_uttypesAPI, *)
extension Attachment where AttachableValue: AttachableWrapper, AttachableValue.Wrapped: AttachableAsCGImage {
  /// The image format to use when encoding the represented image.
  @_disfavoredOverload
  public var imageFormat: AttachableImageFormat? {
    // FIXME: no way to express `where AttachableValue == _AttachableImageWrapper<???>` on a property
    (attachableValue as? _AttachableImageWrapper<AttachableValue.Wrapped>)?.imageFormat
  }
}
#endif
