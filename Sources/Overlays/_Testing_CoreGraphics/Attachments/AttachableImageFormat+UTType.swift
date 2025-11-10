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
public import UniformTypeIdentifiers

/// @Metadata {
///   @Available(Swift, introduced: 6.3)
/// }
@available(_uttypesAPI, *)
extension AttachableImageFormat {
  /// The content type corresponding to this image format.
  ///
  /// For example, if this image format equals ``png``, the value of this
  /// property equals [`UTType.png`](https://developer.apple.com/documentation/uniformtypeidentifiers/uttype-swift.struct/png).
  ///
  /// The value of this property always conforms to [`UTType.image`](https://developer.apple.com/documentation/uniformtypeidentifiers/uttype-swift.struct/image).
  ///
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.3)
  /// }
  public var contentType: UTType {
    kind.contentType
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
  ///
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.3)
  /// }
  public init(contentType: UTType, encodingQuality: Float = 1.0) {
    switch contentType {
    case .png:
      self.init(kind: .png, encodingQuality: encodingQuality)
    case .jpeg:
      self.init(kind: .jpeg, encodingQuality: encodingQuality)
    default:
      precondition(
        contentType.conforms(to: .image),
        "An image cannot be attached as an instance of type '\(contentType.identifier)'. Use a type that conforms to 'public.image' instead."
      )
      self.init(kind: .systemValue(contentType), encodingQuality: encodingQuality)
    }
  }

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
  ///
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.3)
  /// }
  public init?(pathExtension: String, encodingQuality: Float = 1.0) {
    let pathExtension = pathExtension.drop { $0 == "." }

    guard let contentType = UTType(filenameExtension: String(pathExtension), conformingTo: .image),
          contentType.isDeclared else {
      return nil
    }

    self.init(contentType: contentType, encodingQuality: encodingQuality)
  }
}

// MARK: - CustomStringConvertible, CustomDebugStringConvertible

@available(_uttypesAPI, *)
extension AttachableImageFormat.Kind: CustomStringConvertible, CustomDebugStringConvertible {
  /// The content type corresponding to this image format.
  fileprivate var contentType: UTType {
    switch self {
    case .png:
      return .png
    case .jpeg:
      return .jpeg
    case let .systemValue(contentType):
      return contentType as! UTType
    }
  }

  package var description: String {
    let contentType = contentType
    return contentType.localizedDescription ?? contentType.identifier
  }

  package var debugDescription: String {
    let contentType = contentType
    if let localizedDescription = contentType.localizedDescription {
      return "\(localizedDescription) (\(contentType.identifier))"
    }
    return contentType.identifier
  }
}
#endif
