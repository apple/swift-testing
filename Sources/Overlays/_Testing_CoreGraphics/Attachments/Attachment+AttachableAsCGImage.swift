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

public import UniformTypeIdentifiers

@_spi(Experimental)
@available(_uttypesAPI, *)
extension Attachment {
  /// Initialize an instance of this type that encloses the given image.
  ///
  /// - Parameters:
  ///   - attachableValue: The value that will be attached to the output of
  ///     the test run.
  ///   - preferredName: The preferred name of the attachment when writing it
  ///     to a test report or to disk. If `nil`, the testing library attempts
  ///     to derive a reasonable filename for the attached value.
  ///   - contentType: The image format with which to encode `attachableValue`.
  ///   - encodingQuality: The encoding quality to use when encoding the image.
  ///     For the lowest supported quality, pass `0.0`. For the highest
  ///     supported quality, pass `1.0`.
  ///   - sourceLocation: The source location of the call to this initializer.
  ///     This value is used when recording issues associated with the
  ///     attachment.
  ///
  /// The following system-provided image types conform to the
  /// ``AttachableAsCGImage`` protocol and can be attached to a test:
  ///
  /// - [`CGImage`](https://developer.apple.com/documentation/coregraphics/cgimage)
  ///
  /// The testing library uses the image format specified by `contentType`. Pass
  /// `nil` to let the testing library decide which image format to use. If you
  /// pass `nil`, then the image format that the testing library uses depends on
  /// the path extension you specify in `preferredName`, if any. If you do not
  /// specify a path extension, or if the path extension you specify doesn't
  /// correspond to an image format the operating system knows how to write, the
  /// testing library selects an appropriate image format for you.
  ///
  /// If the target image format does not support variable-quality encoding,
  /// the value of the `encodingQuality` argument is ignored. If `contentType`
  /// is not `nil` and does not conform to [`UTType.image`](https://developer.apple.com/documentation/uniformtypeidentifiers/uttype-swift.struct/image),
  /// the result is undefined.
  public init<T>(
    _ attachableValue: T,
    named preferredName: String? = nil,
    as contentType: UTType? = nil,
    encodingQuality: Float = 1.0,
    sourceLocation: SourceLocation = #_sourceLocation
  ) where AttachableValue == _AttachableImageWrapper<T> {
    let imageWrapper = _AttachableImageWrapper(image: attachableValue, encodingQuality: encodingQuality, contentType: contentType)
    self.init(imageWrapper, named: preferredName, sourceLocation: sourceLocation)
  }

  /// Attach an image to the current test.
  ///
  /// - Parameters:
  ///   - image: The value to attach.
  ///   - preferredName: The preferred name of the attachment when writing it to
  ///     a test report or to disk. If `nil`, the testing library attempts to
  ///     derive a reasonable filename for the attached value.
  ///   - contentType: The image format with which to encode `attachableValue`.
  ///   - encodingQuality: The encoding quality to use when encoding the image.
  ///     For the lowest supported quality, pass `0.0`. For the highest
  ///     supported quality, pass `1.0`.
  ///   - sourceLocation: The source location of the call to this function.
  ///
  /// This function creates a new instance of ``Attachment`` wrapping `image`
  /// and immediately attaches it to the current test.
  ///
  /// The following system-provided image types conform to the
  /// ``AttachableAsCGImage`` protocol and can be attached to a test:
  ///
  /// - [`CGImage`](https://developer.apple.com/documentation/coregraphics/cgimage)
  ///
  /// The testing library uses the image format specified by `contentType`. Pass
  /// `nil` to let the testing library decide which image format to use. If you
  /// pass `nil`, then the image format that the testing library uses depends on
  /// the path extension you specify in `preferredName`, if any. If you do not
  /// specify a path extension, or if the path extension you specify doesn't
  /// correspond to an image format the operating system knows how to write, the
  /// testing library selects an appropriate image format for you.
  ///
  /// If the target image format does not support variable-quality encoding,
  /// the value of the `encodingQuality` argument is ignored. If `contentType`
  /// is not `nil` and does not conform to [`UTType.image`](https://developer.apple.com/documentation/uniformtypeidentifiers/uttype-swift.struct/image),
  /// the result is undefined.
  public static func record<T>(
    _ image: consuming T,
    named preferredName: String? = nil,
    as contentType: UTType? = nil,
    encodingQuality: Float = 1.0,
    sourceLocation: SourceLocation = #_sourceLocation
  ) where AttachableValue == _AttachableImageWrapper<T> {
    let attachment = Self(image, named: preferredName, as: contentType, encodingQuality: encodingQuality, sourceLocation: sourceLocation)
    Self.record(attachment, sourceLocation: sourceLocation)
  }
}
#endif
