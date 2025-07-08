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
@_spi(Experimental)
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
    /// On Apple platforms, `value` should be an instance of `UTType`.
    case systemValue(_ value: any Sendable)
  }

  /// The kind of image format represented by this instance.
  package var kind: Kind

  /// The encoding quality to use for this image format.
  ///
  /// The meaning of the value is format-specific with `0.0` being the lowest
  /// supported encoding quality and `1.0` being the highest supported encoding
  /// quality. The value of this property is ignored for image formats that do
  /// not support variable encoding quality.
  public internal(set) var encodingQuality: Float = 1.0

  package init(kind: Kind, encodingQuality: Float) {
    self.kind = kind
    self.encodingQuality = min(max(0.0, encodingQuality), 1.0)
  }
}

// MARK: -

@available(_uttypesAPI, *)
extension AttachableImageFormat {
  /// The PNG image format.
  public static var png: Self {
    Self(kind: .png, encodingQuality: 1.0)
  }

  /// The JPEG image format with maximum encoding quality.
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
  public static func jpeg(withEncodingQuality encodingQuality: Float) -> Self {
    Self(kind: .jpeg, encodingQuality: encodingQuality)
  }
}
