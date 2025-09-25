//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024–2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if SWT_NO_EXIT_TESTS
@_unavailableInEmbedded
@available(*, unavailable, message: "Exit tests are not available on this platform.")
#endif
extension ExitTest {
  /// A type representing the result of an exit test after it has exited and
  /// returned control to the calling test function.
  ///
  /// Both ``expect(processExitsWith:observing:_:sourceLocation:performing:)``
  /// and ``require(processExitsWith:observing:_:sourceLocation:performing:)``
  /// return instances of this type.
  ///
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.2)
  ///   @Available(Xcode, introduced: 26.0)
  /// }
  public struct Result: Sendable {
    /// The exit status reported by the process hosting the exit test.
    ///
    /// @Metadata {
    ///   @Available(Swift, introduced: 6.2)
    ///   @Available(Xcode, introduced: 26.0)
    /// }
    public var exitStatus: ExitStatus

    /// All bytes written to the standard output stream of the exit test before
    /// it exited.
    ///
    /// The value of this property may contain any arbitrary sequence of bytes,
    /// including sequences that are not valid UTF-8 and cannot be decoded by
    /// [`String.init(cString:)`](https://developer.apple.com/documentation/swift/string/init(cstring:)-6kr8s).
    /// Consider using [`String.init(validating:as:)`](https://developer.apple.com/documentation/swift/string/init(validating:as:)-84qr9)
    /// instead.
    ///
    /// When checking the value of this property, keep in mind that the standard
    /// output stream is globally accessible, and any code running in an exit
    /// test may write to it including the operating system and any third-party
    /// dependencies you have declared in your package. Rather than comparing
    /// the value of this property with [`==`](https://developer.apple.com/documentation/swift/array/==(_:_:)),
    /// use [`contains(_:)`](https://developer.apple.com/documentation/swift/collection/contains(_:))
    /// to check if expected output is present.
    ///
    /// To enable gathering output from the standard output stream during an
    /// exit test, pass `\.standardOutputContent` in the `observedValues`
    /// argument of ``expect(processExitsWith:observing:_:sourceLocation:performing:)``
    /// or ``require(processExitsWith:observing:_:sourceLocation:performing:)``.
    ///
    /// If you did not request standard output content when running an exit
    /// test, the value of this property is the empty array.
    ///
    /// @Metadata {
    ///   @Available(Swift, introduced: 6.2)
    ///   @Available(Xcode, introduced: 26.0)
    /// }
    public var standardOutputContent: [UInt8] = []

    /// All bytes written to the standard error stream of the exit test before
    /// it exited.
    ///
    /// The value of this property may contain any arbitrary sequence of bytes,
    /// including sequences that are not valid UTF-8 and cannot be decoded by
    /// [`String.init(cString:)`](https://developer.apple.com/documentation/swift/string/init(cstring:)-6kr8s).
    /// Consider using [`String.init(validating:as:)`](https://developer.apple.com/documentation/swift/string/init(validating:as:)-84qr9)
    /// instead.
    ///
    /// When checking the value of this property, keep in mind that the standard
    /// output stream is globally accessible, and any code running in an exit
    /// test may write to it including the operating system and any third-party
    /// dependencies you have declared in your package. Rather than comparing
    /// the value of this property with [`==`](https://developer.apple.com/documentation/swift/array/==(_:_:)),
    /// use [`contains(_:)`](https://developer.apple.com/documentation/swift/collection/contains(_:))
    /// to check if expected output is present.
    ///
    /// To enable gathering output from the standard error stream during an exit
    /// test, pass `\.standardErrorContent` in the `observedValues` argument of
    /// ``expect(processExitsWith:observing:_:sourceLocation:performing:)`` or
    /// ``require(processExitsWith:observing:_:sourceLocation:performing:)``.
    ///
    /// If you did not request standard error content when running an exit test,
    /// the value of this property is the empty array.
    ///
    /// @Metadata {
    ///   @Available(Swift, introduced: 6.2)
    ///   @Available(Xcode, introduced: 26.0)
    /// }
    public var standardErrorContent: [UInt8] = []

    @_spi(ForToolsIntegrationOnly)
    public init(exitStatus: ExitStatus) {
      self.exitStatus = exitStatus
    }
  }
}
