//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

private import _TestingInternals

/// A protocol describing a type whose instances can be recorded and saved as
/// part of a test run.
///
/// To attach an attachable value to a test, pass it to ``Attachment/record(_:named:sourceLocation:)``.
/// To further configure an attachable value before you attach it, use it to
/// initialize an instance of ``Attachment`` and set its properties before
/// passing it to ``Attachment/record(_:sourceLocation:)``.
///
/// The testing library provides default conformances to this protocol for a
/// variety of standard library types. Most user-defined types do not need to
/// conform to this protocol.
///
/// A type should conform to this protocol if it can be represented as a
/// sequence of bytes that would be diagnostically useful if a test fails. If a
/// type cannot conform directly to this protocol (such as a non-final class or
/// a type declared in a third-party module), you can create a wrapper type that
/// conforms to ``AttachableWrapper`` to act as a proxy.
///
/// @Metadata {
///   @Available(Swift, introduced: 6.2)
///   @Available(Xcode, introduced: 26.0)
/// }
public protocol Attachable: ~Copyable {
  /// An estimate of the number of bytes of memory needed to store this value as
  /// an attachment.
  ///
  /// The testing library uses this property to determine if an attachment
  /// should be held in memory or should be immediately saved. Larger
  /// attachments are more likely to be saved immediately, but the algorithm the
  /// testing library uses is an implementation detail and is subject to change.
  ///
  /// The value of this property is approximately equal to the number of bytes
  /// that will actually be needed, or `nil` if the value cannot be computed
  /// efficiently. The default implementation of this property returns `nil`.
  ///
  /// - Complexity: O(1) unless `Self` conforms to `Collection`, in which case
  ///   up to O(_n_) where _n_ is the length of the collection.
  ///
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.2)
  ///   @Available(Xcode, introduced: 26.0)
  /// }
  var estimatedAttachmentByteCount: Int? { get }

  /// Call a function and pass a buffer representing this instance to it.
  ///
  /// - Parameters:
  ///   - attachment: The attachment that is requesting a buffer (that is, the
  ///     attachment containing this instance.)
  ///   - body: A function to call. A temporary buffer containing a data
  ///     representation of this instance is passed to it.
  ///
  /// - Returns: Whatever is returned by `body`.
  ///
  /// - Throws: Whatever is thrown by `body`, or any error that prevented the
  ///   creation of the buffer.
  ///
  /// The testing library uses this function when saving an attachment. The
  /// format of the buffer is implementation-defined, but should be "idiomatic"
  /// for this type: for example, if this type represents an image, it would be
  /// appropriate for the buffer to contain an image in PNG format, JPEG format,
  /// etc., but it would not be idiomatic for the buffer to contain a textual
  /// description of the image.
  ///
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.2)
  ///   @Available(Xcode, introduced: 26.0)
  /// }
  borrowing func withUnsafeBytes<R>(for attachment: borrowing Attachment<Self>, _ body: (UnsafeRawBufferPointer) throws -> R) throws -> R

  /// Generate a preferred name for the given attachment.
  ///
  /// - Parameters:
  ///   - attachment: The attachment that needs to be named.
  ///   - suggestedName: A suggested name to use as the basis of the preferred
  ///     name. This string was provided by the developer when they initialized
  ///     `attachment`.
  ///
  /// - Returns: The preferred name for `attachment`.
  ///
  /// The testing library uses this function to determine the best name to use
  /// when saving `attachment`. The default implementation of this function
  /// returns `suggestedName` without any changes.
  ///
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.2)
  ///   @Available(Xcode, introduced: 26.0)
  /// }
  borrowing func preferredName(for attachment: borrowing Attachment<Self>, basedOn suggestedName: String) -> String
}

// MARK: - Default implementations

extension Attachable where Self: ~Copyable {
  public var estimatedAttachmentByteCount: Int? {
    nil
  }

  public borrowing func preferredName(for attachment: borrowing Attachment<Self>, basedOn suggestedName: String) -> String {
    suggestedName
  }
}

extension Attachable where Self: Collection, Element == UInt8 {
  public var estimatedAttachmentByteCount: Int? {
    count
  }

  // We do not provide an implementation of withUnsafeBytes(for:_:) here because
  // there is no way in the standard library to statically detect if a
  // collection can provide contiguous storage (_HasContiguousBytes is not API.)
  // If withContiguousStorageIfAvailable(_:) fails, we don't want to make a
  // (potentially expensive!) copy of the collection.
}

extension Attachable where Self: StringProtocol {
  public var estimatedAttachmentByteCount: Int? {
    // NOTE: utf8.count may be O(n) for foreign strings.
    // SEE: https://github.com/swiftlang/swift/blob/main/stdlib/public/core/StringUTF8View.swift
    utf8.count
  }
}

// MARK: - Default conformances

// Implement the protocol requirements for byte arrays and buffers so that
// developers can attach raw data when needed.
extension Array<UInt8>: Attachable {
  public func withUnsafeBytes<R>(for attachment: borrowing Attachment<Self>, _ body: (UnsafeRawBufferPointer) throws -> R) throws -> R {
    try withUnsafeBytes(body)
  }
}

extension ContiguousArray<UInt8>: Attachable {
  public func withUnsafeBytes<R>(for attachment: borrowing Attachment<Self>, _ body: (UnsafeRawBufferPointer) throws -> R) throws -> R {
    try withUnsafeBytes(body)
  }
}

extension ArraySlice<UInt8>: Attachable {
  public func withUnsafeBytes<R>(for attachment: borrowing Attachment<Self>, _ body: (UnsafeRawBufferPointer) throws -> R) throws -> R {
    try withUnsafeBytes(body)
  }
}

extension String: Attachable {
  public func withUnsafeBytes<R>(for attachment: borrowing Attachment<Self>, _ body: (UnsafeRawBufferPointer) throws -> R) throws -> R {
    var selfCopy = self
    return try selfCopy.withUTF8 { utf8 in
      try body(UnsafeRawBufferPointer(utf8))
    }
  }
}

extension Substring: Attachable {
  public func withUnsafeBytes<R>(for attachment: borrowing Attachment<Self>, _ body: (UnsafeRawBufferPointer) throws -> R) throws -> R {
    var selfCopy = self
    return try selfCopy.withUTF8 { utf8 in
      try body(UnsafeRawBufferPointer(utf8))
    }
  }
}
