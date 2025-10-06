//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

/// A protocol describing a type whose instances can be recorded and saved as
/// part of a test run and which contains another value that it stands in for.
///
/// To attach an attachable value to a test, pass it to ``Attachment/record(_:named:sourceLocation:)``.
/// To further configure an attachable value before you attach it, use it to
/// initialize an instance of ``Attachment`` and set its properties before
/// passing it to ``Attachment/record(_:sourceLocation:)``. An attachable
/// value can only be attached to a test once.
///
/// A type can conform to this protocol if it represents another type that
/// cannot directly conform to ``Attachable``, such as a non-final class or a
/// type declared in a third-party module.
///
/// @Metadata {
///   @Available(Swift, introduced: 6.2)
///   @Available(Xcode, introduced: 26.0)
/// }
public protocol AttachableWrapper<Wrapped>: Attachable, ~Copyable {
  /// The type of the underlying value represented by this type.
  ///
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.2)
  ///   @Available(Xcode, introduced: 26.0)
  /// }
  associatedtype Wrapped

  /// The underlying value represented by this instance.
  ///
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.2)
  ///   @Available(Xcode, introduced: 26.0)
  /// }
  var wrappedValue: Wrapped { get }
}
