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
package import CoreGraphics
package import ImageIO
private import UniformTypeIdentifiers
#if canImport(UniformTypeIdentifiers_Private)
@_spi(Private) private import UniformTypeIdentifiers
#endif

/// A protocol describing images that can be converted to instances of
/// [`Attachment`](https://developer.apple.com/documentation/testing/attachment)
/// and which can be represented as instances of [`CGImage`](https://developer.apple.com/documentation/coregraphics/cgimage).
///
/// This protocol is not part of the public interface of the testing library. It
/// encapsulates Apple-specific logic for image attachments.
@available(_uttypesAPI, *)
package protocol AttachableAsCGImage: AttachableAsImage {
  /// An instance of `CGImage` representing this image.
  ///
  /// - Throws: Any error that prevents the creation of an image.
  var attachableCGImage: CGImage { get throws }

  /// The orientation of the image.
  ///
  /// The value of this property is the raw value of an instance of
  /// `CGImagePropertyOrientation`. The default value of this property is
  /// `.up`.
  ///
  /// This property is not part of the public interface of the testing library.
  /// It may be removed in a future update.
  var attachmentOrientation: CGImagePropertyOrientation { get }

  /// The scale factor of the image.
  ///
  /// The value of this property is typically greater than `1.0` when an image
  /// originates from a Retina Display screenshot or similar. The default value
  /// of this property is `1.0`.
  ///
  /// This property is not part of the public interface of the testing library.
  /// It may be removed in a future update.
  var attachmentScaleFactor: CGFloat { get }
}

/// All type identifiers supported by Image I/O.
@available(_uttypesAPI, *)
private let _supportedTypeIdentifiers = Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])

/// All content types supported by Image I/O.
@available(_uttypesAPI, *)
private let _supportedContentTypes = {
#if canImport(UniformTypeIdentifiers_Private)
  UTType._types(identifiers: _supportedTypeIdentifiers).values
#else
  _supportedTypeIdentifiers.compactMap(UTType.init(_:))
#endif
}()

@available(_uttypesAPI, *)
extension AttachableAsCGImage {
  package var attachmentOrientation: CGImagePropertyOrientation {
    .up
  }

  package var attachmentScaleFactor: CGFloat {
    1.0
  }

  public func withUnsafeBytes<R>(as imageFormat: AttachableImageFormat, _ body: (UnsafeRawBufferPointer) throws -> R) throws -> R {
    let data = NSMutableData()

    // Convert the image to a CGImage.
    let attachableCGImage = try attachableCGImage

    // Determine the base content type to use. We do a naïve case-sensitive
    // string comparison on the identifier first as it's faster than querying
    // the corresponding UTType instances (because it doesn't need to touch the
    // Launch Services database). The common cases where the developer passes
    // no image format or passes .png/.jpeg are covered by the fast path.
    var contentType = imageFormat.contentType
    if !_supportedTypeIdentifiers.contains(contentType.identifier) {
      guard let baseType = _supportedContentTypes.first(where: contentType.conforms(to:)) else {
        throw ImageAttachmentError.unsupportedImageFormat(contentType.identifier)
      }
      contentType = baseType
    }

    // Create the image destination.
    guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, contentType.identifier as CFString, 1, nil) else {
      throw ImageAttachmentError.couldNotCreateImageDestination
    }

    // Configure the properties of the image conversion operation.
    let orientation = attachmentOrientation
    let scaleFactor = attachmentScaleFactor
    let properties: [CFString: Any] = [
      kCGImageDestinationLossyCompressionQuality: CGFloat(imageFormat.encodingQuality),
      kCGImagePropertyOrientation: orientation,
      kCGImagePropertyDPIWidth: 72.0 * scaleFactor,
      kCGImagePropertyDPIHeight: 72.0 * scaleFactor,
    ]

    // Perform the image conversion.
    CGImageDestinationAddImage(dest, attachableCGImage, properties as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
      throw ImageAttachmentError.couldNotConvertImage
    }

    // Pass the bits of the image out to the body. Note that we have an
    // NSMutableData here so we have to use slightly different API than we would
    // with an instance of Data.
    return try withExtendedLifetime(data) {
      try body(UnsafeRawBufferPointer(start: data.bytes, count: data.length))
    }
  }
}
#endif
