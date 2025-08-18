//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

/// A wrapper type for images that can be indirectly attached to a test.
///
/// You can attach instances of the following system-provided image types to a
/// test:
///
/// | Platform | Supported Types |
/// |-|-|
/// | macOS | [`CGImage`](https://developer.apple.com/documentation/coregraphics/cgimage), [`CIImage`](https://developer.apple.com/documentation/coreimage/ciimage), [`NSImage`](https://developer.apple.com/documentation/appkit/nsimage) |
/// | iOS, watchOS, tvOS, and visionOS | [`CGImage`](https://developer.apple.com/documentation/coregraphics/cgimage), [`CIImage`](https://developer.apple.com/documentation/coreimage/ciimage), [`UIImage`](https://developer.apple.com/documentation/uikit/uiimage) |
/// | Windows | [`HBITMAP`](https://learn.microsoft.com/en-us/windows/win32/gdi/bitmaps), [`HICON`](https://learn.microsoft.com/en-us/windows/win32/menurc/icons), [`IWICBitmapSource`](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nn-wincodec-iwicbitmapsource) (including its subclasses declared by Windows Imaging Component) |
@_spi(Experimental)
@available(_uttypesAPI, *)
public final class _AttachableImageWrapper<Image>: Sendable {
  /// The underlying image.
  private nonisolated(unsafe) let _image: Image

  /// The image format to use when encoding the represented image.
  package let imageFormat: AttachableImageFormat?

  /// A deinitializer function to call to clean up `image`.
  private let _deinit: @Sendable (consuming Image) -> Void

  package init(image: Image, imageFormat: AttachableImageFormat?, deinitializingWith `deinit`: @escaping @Sendable (consuming Image) -> Void) {
    self._image = image
    self.imageFormat = imageFormat
    self._deinit = `deinit`
  }

  deinit {
    _deinit(_image)
  }
}

@available(_uttypesAPI, *)
extension _AttachableImageWrapper {
  public var wrappedValue: Image {
    _image
  }
}
