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
public import CoreGraphics
private import ImageIO

/// A protocol describing images that can be converted to instances of
/// ``Testing/Attachment``.
///
/// Instances of types conforming to this protocol do not themselves conform to
/// ``Testing/Attachable``. Instead, the testing library provides additional
/// initializers on ``Testing/Attachment`` that take instances of such types and
/// handle converting them to image data when needed.
///
/// The following system-provided image types conform to this protocol and can
/// be attached to a test:
///
/// - [`CGImage`](https://developer.apple.com/documentation/coregraphics/cgimage)
/// - [`CIImage`](https://developer.apple.com/documentation/coreimage/ciimage)
/// - [`NSImage`](https://developer.apple.com/documentation/appkit/nsimage)
///   (macOS)
///
/// You do not generally need to add your own conformances to this protocol. If
/// you have an image in another format that needs to be attached to a test,
/// first convert it to an instance of one of the types above.
@_spi(Experimental)
@available(_uttypesAPI, *)
public protocol AttachableAsCGImage {
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
  /// This property is not part of the public interface of the testing
  /// library. It may be removed in a future update.
  var _attachmentOrientation: UInt32 { get }

  /// The scale factor of the image.
  ///
  /// The value of this property is typically greater than `1.0` when an image
  /// originates from a Retina Display screenshot or similar. The default value
  /// of this property is `1.0`.
  ///
  /// This property is not part of the public interface of the testing
  /// library. It may be removed in a future update.
  var _attachmentScaleFactor: CGFloat { get }

  /// Make a copy of this instance to pass to an attachment.
  ///
  /// - Returns: A copy of `self`, or `self` if no copy is needed.
  ///
  /// Several system image types do not conform to `Sendable`; use this
  /// function to make copies of such images that will not be shared outside
  /// of an attachment and so can be generally safely stored.
  ///
  /// The default implementation of this function when `Self` conforms to
  /// `Sendable` simply returns `self`.
  ///
  /// This function is not part of the public interface of the testing library.
  /// It may be removed in a future update.
  func _makeCopyForAttachment() -> Self
}

@available(_uttypesAPI, *)
extension AttachableAsCGImage {
  public var _attachmentOrientation: UInt32 {
    CGImagePropertyOrientation.up.rawValue
  }

  public var _attachmentScaleFactor: CGFloat {
    1.0
  }
}

@available(_uttypesAPI, *)
extension AttachableAsCGImage where Self: Sendable {
  public func _makeCopyForAttachment() -> Self {
    self
  }
}
#endif
