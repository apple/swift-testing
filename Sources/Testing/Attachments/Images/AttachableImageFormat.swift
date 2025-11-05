//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024–2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

/// A type describing image formats supported by the system that can be used
/// when attaching an image to a test.
///
/// When you attach an image to a test, you can pass an instance of this type to
/// ``Attachment/record(_:named:as:sourceLocation:)`` so that the testing
/// library knows the image format you'd like to use. If you don't pass an
/// instance of this type, the testing library infers which format to use based
/// on the attachment's preferred name.
///
/// The PNG and JPEG image formats are always supported. The set of additional
/// supported image formats is platform-specific:
///
/// - On Apple platforms, you can use [`CGImageDestinationCopyTypeIdentifiers()`](https://developer.apple.com/documentation/imageio/cgimagedestinationcopytypeidentifiers())
///   from the [Image I/O framework](https://developer.apple.com/documentation/imageio)
///   to determine which formats are supported.
/// - On Windows, you can use [`IWICImagingFactory.CreateComponentEnumerator()`](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nf-wincodec-iwicimagingfactory-createcomponentenumerator)
///   to enumerate the available image encoders.
///
/// @Metadata {
///   @Available(Swift, introduced: 6.3)
/// }
#if SWT_NO_IMAGE_ATTACHMENTS
@_unavailableInEmbedded
@available(*, unavailable, message: "Image attachments are not available on this platform.")
#endif
@available(_uttypesAPI, *)
public struct AttachableImageFormat: Sendable {
  /// An enumeration describing the various kinds of image format that can be
  /// used with an attachment.
  package enum Kind: Sendable {
    /// The (widely-supported) PNG image format.
    case png

    /// The (widely-supported) JPEG image format.
    case jpeg

    /// A platform-specific image format.
    ///
    /// - Parameters:
    ///   - value: A platform-specific value representing the image format to
    ///     use. The platform-specific cross-import overlay or package is
    ///     responsible for exposing appropriate interfaces for this case.
    ///
    /// On Apple platforms, `value` should be an instance of `UTType`. On
    /// Windows, it should be an instance of `CLSID`.
    case systemValue(_ value: any Sendable & Equatable & Hashable)
  }

  /// The kind of image format represented by this instance.
  package var kind: Kind

  /// The encoding quality to use for this image format.
  ///
  /// The meaning of the value is format-specific with `0.0` being the lowest
  /// supported encoding quality and `1.0` being the highest supported encoding
  /// quality. The value of this property is ignored for image formats that do
  /// not support variable encoding quality.
  ///
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.3)
  /// }
  public private(set) var encodingQuality: Float = 1.0

  package init(kind: Kind, encodingQuality: Float) {
    self.kind = kind
    self.encodingQuality = min(max(0.0, encodingQuality), 1.0)
  }
}

// MARK: - Equatable, Hashable

#if SWT_NO_IMAGE_ATTACHMENTS
@_unavailableInEmbedded
@available(*, unavailable, message: "Image attachments are not available on this platform.")
#endif
@available(_uttypesAPI, *)
extension AttachableImageFormat: Equatable, Hashable {}

#if SWT_NO_IMAGE_ATTACHMENTS
@_unavailableInEmbedded
@available(*, unavailable, message: "Image attachments are not available on this platform.")
#endif
@available(_uttypesAPI, *)
extension AttachableImageFormat.Kind: Equatable, Hashable {
  public static func ==(lhs: Self, rhs: Self) -> Bool {
    switch (lhs, rhs) {
    case (.png, .png), (.jpeg, .jpeg):
      return true
    case let (.systemValue(lhs), .systemValue(rhs)):
      func open<T>(_ lhs: T) -> Bool where T: Equatable {
        lhs == (rhs as? T)
      }
      return open(lhs)
    default:
      return false
    }
  }

  public func hash(into hasher: inout Hasher) {
    switch self {
    case .png:
      hasher.combine("png")
    case .jpeg:
      hasher.combine("jpeg")
    case let .systemValue(systemValue):
      hasher.combine(systemValue)
    }
  }
}

// MARK: - CustomStringConvertible, CustomDebugStringConvertible

#if SWT_NO_IMAGE_ATTACHMENTS
@_unavailableInEmbedded
@available(*, unavailable, message: "Image attachments are not available on this platform.")
#endif
@available(_uttypesAPI, *)
extension AttachableImageFormat: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String {
    let kindDescription = String(describing: kind)
    if encodingQuality < 1.0 {
      return "\(kindDescription) at \(Int(encodingQuality * 100.0))% quality"
    }
    return kindDescription
  }

  public var debugDescription: String {
    let kindDescription = String(reflecting: kind)
    return "\(kindDescription) at quality \(encodingQuality)"
  }
}

// MARK: -

#if SWT_NO_IMAGE_ATTACHMENTS
@_unavailableInEmbedded
@available(*, unavailable, message: "Image attachments are not available on this platform.")
#endif
@available(_uttypesAPI, *)
extension AttachableImageFormat {
  /// The PNG image format.
  ///
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.3)
  /// }
  public static var png: Self {
    Self(kind: .png, encodingQuality: 1.0)
  }

  /// The JPEG image format with maximum encoding quality.
  ///
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.3)
  /// }
  public static var jpeg: Self {
    Self(kind: .jpeg, encodingQuality: 1.0)
  }

  /// The JPEG image format.
  ///
  /// - Parameters:
  ///   - encodingQuality: The encoding quality to use when serializing an
  ///     image. A value of `0.0` indicates the lowest supported encoding
  ///     quality and a value of `1.0` indicates the highest supported encoding
  ///     quality.
  ///
  /// - Returns: An instance of this type representing the JPEG image format
  ///   with the specified encoding quality.
  ///
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.3)
  /// }
  public static func jpeg(withEncodingQuality encodingQuality: Float) -> Self {
    Self(kind: .jpeg, encodingQuality: encodingQuality)
  }
}
