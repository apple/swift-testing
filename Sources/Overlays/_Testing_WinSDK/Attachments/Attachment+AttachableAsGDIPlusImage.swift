//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if os(Windows)
@_spi(Experimental) public import Testing

@_spi(Experimental)
extension Attachment where AttachableValue: ~Copyable {
  /// Initialize an instance of this type that encloses the given image.
  ///
  /// - Parameters:
  ///   - attachableValue: A pointer to the value that will be attached to the
  ///     output of the test run.
  ///   - preferredName: The preferred name of the attachment when writing it
  ///     to a test report or to disk. If `nil`, the testing library attempts
  ///     to derive a reasonable filename for the attached value.
  ///   - imageFormat: The image format with which to encode `attachableValue`.
  ///   - sourceLocation: The source location of the call to this initializer.
  ///     This value is used when recording issues associated with the
  ///     attachment.
  ///
  /// The following system-provided image types conform to the
  /// ``AttachableAsGDIPlusImage`` protocol and can be attached to a test:
  ///
  /// - [`HBITMAP`](https://learn.microsoft.com/en-us/windows/win32/gdi/bitmaps)
  /// - [`HICON`](https://learn.microsoft.com/en-us/windows/win32/menurc/icons)
  ///
  /// The testing library uses the image format specified by `imageFormat`. Pass
  /// `nil` to let the testing library decide which image format to use. If you
  /// pass `nil`, then the image format that the testing library uses depends on
  /// the path extension you specify in `preferredName`, if any. If you do not
  /// specify a path extension, or if the path extension you specify doesn't
  /// correspond to an image format the operating system knows how to write, the
  /// testing library selects an appropriate image format for you.
  ///
  /// - Important: The resulting instance of ``Attachment`` takes ownership of
  ///   `attachableValue` and frees its resources upon deinitialization. If you
  ///   do not want the testing library to take ownership of this value, call
  ///   ``Attachment/record(_:named:as:sourceLocation)`` instead of this
  ///   initializer, or make a copy of the resource before passing it to this
  ///   initializer.
  @unsafe
  public init<T>(
    _ attachableValue: consuming T,
    named preferredName: String? = nil,
    as imageFormat: AttachableImageFormat? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
  ) where AttachableValue == _AttachableImageWrapper<T> {
    let imageWrapper = _AttachableImageWrapper(image: attachableValue, imageFormat: imageFormat, cleanUpWhenDone: true)
    self.init(imageWrapper, named: preferredName, sourceLocation: sourceLocation)
  }

  /// Attach an image to the current test.
  ///
  /// - Parameters:
  ///   - image: The value to attach.
  ///   - preferredName: The preferred name of the attachment when writing it
  ///     to a test report or to disk. If `nil`, the testing library attempts
  ///     to derive a reasonable filename for the attached value.
  ///   - imageFormat: The image format with which to encode `attachableValue`.
  ///   - sourceLocation: The source location of the call to this initializer.
  ///     This value is used when recording issues associated with the
  ///     attachment.
  ///
  /// This function creates a new instance of ``Attachment`` wrapping `image`
  /// and immediately attaches it to the current test.
  ///
  /// The following system-provided image types conform to the
  /// ``AttachableAsGDIPlusImage`` protocol and can be attached to a test:
  ///
  /// - [`HBITMAP`](https://learn.microsoft.com/en-us/windows/win32/gdi/bitmaps)
  /// - [`HICON`](https://learn.microsoft.com/en-us/windows/win32/menurc/icons)
  ///
  /// The testing library uses the image format specified by `imageFormat`. Pass
  /// `nil` to let the testing library decide which image format to use. If you
  /// pass `nil`, then the image format that the testing library uses depends on
  /// the path extension you specify in `preferredName`, if any. If you do not
  /// specify a path extension, or if the path extension you specify doesn't
  /// correspond to an image format the operating system knows how to write, the
  /// testing library selects an appropriate image format for you.
  public static func record<T>(
    _ image: borrowing T,
    named preferredName: String? = nil,
    as imageFormat: AttachableImageFormat? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
  ) where AttachableValue == _AttachableImageWrapper<T> {
    let imageWrapper = _AttachableImageWrapper(image: copy image, imageFormat: imageFormat, cleanUpWhenDone: true)
    let attachment = Self(imageWrapper, named: preferredName, sourceLocation: sourceLocation)
    Self.record(attachment, sourceLocation: sourceLocation)
  }
}
#endif
