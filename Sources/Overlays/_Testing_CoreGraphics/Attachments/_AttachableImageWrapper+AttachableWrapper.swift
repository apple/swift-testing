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
private import CoreGraphics

private import UniformTypeIdentifiers

/// @Metadata {
///   @Available(Swift, introduced: 6.3)
/// }
@available(_uttypesAPI, *)
extension _AttachableImageWrapper: Attachable, AttachableWrapper where Image: AttachableAsImage {
  /// Get the image format to use when encoding an image, substituting a
  /// concrete type for `UTType.image` in particular.
  ///
  /// - Parameters:
  ///   - preferredName: The preferred name of the image for which a type is
  ///     needed.
  ///
  /// - Returns: An instance of ``AttachableImageFormat`` referring to a
  ///   concrete image type.
  ///
  /// This function is not part of the public interface of the testing library.
  private func _imageFormat(forPreferredName preferredName: String) -> AttachableImageFormat {
    if let imageFormat, case let contentType = imageFormat.contentType, contentType != .image {
      // The developer explicitly specified a type.
      return imageFormat
    }

    // The developer didn't specify a concrete type, so try to derive one from
    // the preferred name's path extension.
    let pathExtension = (preferredName as NSString).pathExtension
    if !pathExtension.isEmpty,
       let contentType = UTType(filenameExtension: pathExtension, conformingTo: .image),
       contentType.isDeclared {
      return AttachableImageFormat(contentType: contentType)
    }

    // We couldn't derive a concrete type from the path extension, so pick
    // between PNG and JPEG based on the encoding quality.
    let encodingQuality = imageFormat?.encodingQuality ?? 1.0
    return encodingQuality < 1.0 ? .jpeg : .png
  }

  /// @Metadata {
  ///   @Available(Swift, introduced: 6.3)
  /// }
  public func withUnsafeBytes<R>(for attachment: borrowing Attachment<_AttachableImageWrapper>, _ body: (UnsafeRawBufferPointer) throws -> R) throws -> R {
    let imageFormat = _imageFormat(forPreferredName: attachment.preferredName)
    return try wrappedValue.withUnsafeBytes(as: imageFormat, body)
  }

  /// @Metadata {
  ///   @Available(Swift, introduced: 6.3)
  /// }
  public borrowing func preferredName(for attachment: borrowing Attachment<_AttachableImageWrapper>, basedOn suggestedName: String) -> String {
    let imageFormat = _imageFormat(forPreferredName: suggestedName)
    return (suggestedName as NSString).appendingPathExtension(for: imageFormat.contentType)
  }
}
#endif
