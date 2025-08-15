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
@_spi(Experimental) public import Testing

public import UniformTypeIdentifiers

@available(_uttypesAPI, *)
extension AttachableImageFormat {
  /// Get the content type to use when encoding the image, substituting a
  /// concrete type for `UTType.image` in particular.
  ///
  /// - Parameters:
  ///   - imageFormat: The image format to use, or `nil` if the developer did
  ///     not specify one.
  ///   - preferredName: The preferred name of the image for which a type is
  ///     needed.
  ///
  /// - Returns: An instance of `UTType` referring to a concrete image type.
  ///
  /// This function is not part of the public interface of the testing library.
  static func computeContentType(for imageFormat: Self?, withPreferredName preferredName: String) -> UTType {
    guard let imageFormat else {
      // The developer didn't specify a type. Substitute the generic `.image`
      // and solve for that instead.
      return computeContentType(for: Self(.image, encodingQuality: 1.0), withPreferredName: preferredName)
    }

    switch imageFormat.kind {
    case .png:
      return .png
    case .jpeg:
      return .jpeg
    case let .systemValue(contentType):
      let contentType = contentType as! UTType
      if contentType != .image {
        // The developer explicitly specified a type.
        return contentType
      }

      // The developer didn't specify a concrete type, so try to derive one from
      // the preferred name's path extension.
      let pathExtension = (preferredName as NSString).pathExtension
      if !pathExtension.isEmpty,
         let contentType = UTType(filenameExtension: pathExtension, conformingTo: .image),
         contentType.isDeclared {
        return contentType
      }

      // We couldn't derive a concrete type from the path extension, so pick
      // between PNG and JPEG based on the encoding quality.
      return imageFormat.encodingQuality < 1.0 ? .jpeg : .png
    }
  }

  /// The content type corresponding to this image format.
  ///
  /// The value of this property always conforms to [`UTType.image`](https://developer.apple.com/documentation/uniformtypeidentifiers/uttype-swift.struct/image).
  public var contentType: UTType {
    switch kind {
    case .png:
      return .png
    case .jpeg:
      return .jpeg
    case let .systemValue(contentType):
      return contentType as! UTType
    }
  }

  /// Initialize an instance of this type with the given content type and
  /// encoding quality.
  ///
  /// - Parameters:
  ///   - contentType: The image format to use when encoding images.
  ///   - encodingQuality: The encoding quality to use when encoding images. For
  ///     the lowest supported quality, pass `0.0`. For the highest supported
  ///     quality, pass `1.0`.
  ///
  /// If the target image format does not support variable-quality encoding,
  /// the value of the `encodingQuality` argument is ignored.
  ///
  /// If `contentType` does not conform to [`UTType.image`](https://developer.apple.com/documentation/uniformtypeidentifiers/uttype-swift.struct/image),
  /// the result is undefined.
  public init(_ contentType: UTType, encodingQuality: Float = 1.0) {
    precondition(
      contentType.conforms(to: .image),
      "An image cannot be attached as an instance of type '\(contentType.identifier)'. Use a type that conforms to 'public.image' instead."
    )
    self.init(kind: .systemValue(contentType), encodingQuality: encodingQuality)
  }
}

@available(_uttypesAPI, *)
@_spi(Experimental) // STOP: not part of ST-0014
extension AttachableImageFormat {
  /// Construct an instance of this type with the given path extension and
  /// encoding quality.
  ///
  /// - Parameters:
  ///   - pathExtension: A path extension corresponding to the image format to
  ///     use when encoding images.
  ///   - encodingQuality: The encoding quality to use when encoding images. For
  ///     the lowest supported quality, pass `0.0`. For the highest supported
  ///     quality, pass `1.0`.
  ///
  /// If the target image format does not support variable-quality encoding,
  /// the value of the `encodingQuality` argument is ignored.
  ///
  /// If `pathExtension` does not correspond to a recognized image format, this
  /// initializer returns `nil`:
  ///
  /// - On Apple platforms, the content type corresponding to `pathExtension`
  ///   must conform to [`UTType.image`](https://developer.apple.com/documentation/uniformtypeidentifiers/uttype-swift.struct/image).
  /// - On Windows, there must be a corresponding subclass of [`IWICBitmapEncoder`](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nn-wincodec-iwicbitmapencoder)
  ///   registered with Windows Imaging Component.
  public init?(pathExtension: String, encodingQuality: Float = 1.0) {
    let pathExtension = pathExtension.drop { $0 == "." }

    guard let contentType = UTType(filenameExtension: String(pathExtension), conformingTo: .image) else {
      return nil
    }

    self.init(contentType, encodingQuality: encodingQuality)
  }
}
#endif
