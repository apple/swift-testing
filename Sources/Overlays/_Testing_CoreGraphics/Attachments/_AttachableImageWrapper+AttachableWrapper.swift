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
private import CoreGraphics

private import ImageIO
private import UniformTypeIdentifiers

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

@available(_uttypesAPI, *)
extension _AttachableImageWrapper: Attachable, AttachableWrapper where Image: AttachableAsCGImage {
  public func withUnsafeBytes<R>(for attachment: borrowing Attachment<_AttachableImageWrapper>, _ body: (UnsafeRawBufferPointer) throws -> R) throws -> R {
    let data = NSMutableData()

    // Convert the image to a CGImage.
    let attachableCGImage = try wrappedValue.attachableCGImage

    // Create the image destination.
    let contentType = AttachableImageFormat.computeContentType(for: imageFormat, withPreferredName: attachment.preferredName)
    guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, contentType.identifier as CFString, 1, nil) else {
      throw ImageAttachmentError.couldNotCreateImageDestination
    }

    // Configure the properties of the image conversion operation.
    let orientation = wrappedValue._attachmentOrientation
    let scaleFactor = wrappedValue._attachmentScaleFactor
    let properties: [CFString: Any] = [
      kCGImageDestinationLossyCompressionQuality: CGFloat(imageFormat?.encodingQuality ?? 1.0),
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

  public borrowing func preferredName(for attachment: borrowing Attachment<_AttachableImageWrapper>, basedOn suggestedName: String) -> String {
    let contentType = AttachableImageFormat.computeContentType(for: imageFormat, withPreferredName: suggestedName)
    return (suggestedName as NSString).appendingPathExtension(for: contentType)
  }
}
#endif
