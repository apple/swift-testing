//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024–2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

/// A protocol describing images that can be converted to instances of
/// [`Attachment`](https://developer.apple.com/documentation/testing/attachment).
///
/// This protocol acts as an abstract, platform-independent base protocol for
/// ``AttachableAsCGImage`` and ``AttachableAsIWICBitmapSource``.
///
/// @Comment {
///   A future Swift Evolution proposal will promote this protocol to API so
///   that we don't need to underscore its name.
/// }
@available(_uttypesAPI, *)
public protocol _AttachableAsImage: SendableMetatype {
  /// Make a copy of this instance to pass to an attachment.
  ///
  /// - Returns: A copy of `self`, or `self` if no copy is needed.
  ///
  /// The testing library uses this function to take ownership of image
  /// resources that test authors pass to it. If possible, make a copy of or add
  /// a reference to `self`. If this type does not support making copies, return
  /// `self` verbatim.
  ///
  /// The default implementation of this function when `Self` conforms to
  /// `Sendable` simply returns `self`.
  ///
  /// This function is not part of the public interface of the testing library.
  /// It may be removed in a future update.
  func _copyAttachableValue() -> Self

  /// Manually deinitialize any resources associated with this image.
  ///
  /// The implementation of this function cleans up any resources (such as
  /// handles or COM objects) associated with this image. The testing library
  /// automatically invokes this function as needed.
  ///
  /// This function is not responsible for releasing the image returned from
  /// `_copyAttachableIWICBitmapSource(using:)`.
  ///
  /// The default implementation of this function when `Self` conforms to
  /// `Sendable` does nothing.
  ///
  /// This function is not part of the public interface of the testing library.
  /// It may be removed in a future update.
  func _deinitializeAttachableValue()
}
