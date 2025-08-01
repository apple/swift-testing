//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if os(Windows)
@_spi(Experimental) public import Testing
private import _TestingInternals.GDIPlus

internal import WinSDK

/// A wrapper type for image types such as `HBITMAP` and `HICON` that can be
/// attached indirectly.
///
/// You do not need to use this type directly. Instead, initialize an instance
/// of ``Attachment`` using an instance of an image type that conforms to
/// ``AttachableAsGDIPlusImage``. The following system-provided image types
/// conform to the ``AttachableAsGDIPlusImage`` protocol and can be attached to
/// a test:
///
/// - [`HBITMAP`](https://learn.microsoft.com/en-us/windows/win32/gdi/bitmaps)
/// - [`HICON`](https://learn.microsoft.com/en-us/windows/win32/menurc/icons)
@_spi(Experimental)
public struct _AttachableImageWrapper<Image>: ~Copyable where Image: AttachableAsGDIPlusImage {
  /// The underlying image.
  var image: Image

  /// The image format to use when encoding the represented image.
  var imageFormat: AttachableImageFormat?

  /// Whether or not to call `_cleanUpAttachment(at:)` on `pointer` when this
  /// instance is deinitialized.
  ///
  /// - Note: If cleanup is not performed, `pointer` is effectively being
  ///   borrowed from the calling context.
  var cleanUpWhenDone: Bool

  init(image: Image, imageFormat: AttachableImageFormat?, cleanUpWhenDone: Bool) {
    self.image = image
    self.imageFormat = imageFormat
    self.cleanUpWhenDone = cleanUpWhenDone
  }

  deinit {
    if cleanUpWhenDone {
      image._cleanUpAttachment()
    }
  }
}

@available(*, unavailable)
extension _AttachableImageWrapper: Sendable {}

// MARK: -

extension _AttachableImageWrapper: AttachableWrapper {
  public var wrappedValue: Image {
    image
  }

  public func withUnsafeBytes<R>(for attachment: borrowing Attachment<Self>, _ body: (UnsafeRawBufferPointer) throws -> R) throws -> R {
    // Create an in-memory stream to write the image data to. Note that Windows
    // documentation recommends SHCreateMemStream() instead, but that function
    // does not provide a mechanism to access the underlying memory directly.
    var stream: UnsafeMutablePointer<IStream>?
    let rCreateStream = CreateStreamOnHGlobal(nil, true, &stream)
    guard S_OK == rCreateStream, let stream else {
      throw GDIPlusError.streamCreationFailed(rCreateStream)
    }
    defer {
      stream.withMemoryRebound(to: IUnknown.self, capacity: 1) { stream in
        _ = swt_IUnknown_Release(stream)
      }
    }

    try withGDIPlus {
      // Get a GDI+ image from the attachment.
      let image = try image._copyAttachableGDIPlusImage()
      defer {
        swt_GdiplusImageDelete(image)
      }

      // Get the CLSID of the image encoder corresponding to the specified image
      // format.
      var clsid = AttachableImageFormat.computeCLSID(for: imageFormat, withPreferredName: attachment.preferredName)

      var encodingQuality = LONG((imageFormat?.encodingQuality ?? 1.0) * 100.0)
      try withUnsafeMutableBytes(of: &encodingQuality) { encodingQuality in
        var encoderParams = Gdiplus.EncoderParameters()
        encoderParams.Count = 1
        encoderParams.Parameter.Guid = swt_GdiplusEncoderQuality()
        encoderParams.Parameter.Type = ULONG(Gdiplus.EncoderParameterValueTypeLong.rawValue)
        encoderParams.Parameter.NumberOfValues = 1
        encoderParams.Parameter.Value = encodingQuality.baseAddress

        // Save the image into the stream.
        let rSave = swt_GdiplusImageSave(image, stream, &clsid, &encoderParams)
        guard rSave == Gdiplus.Ok else {
          throw GDIPlusError.status(rSave)
        }
      }
    }

    // Extract the serialized image and pass it back to the caller. We hold the
    // HGLOBAL locked while calling `body`, but nothing else should have a
    // reference to it.
    var global: HGLOBAL?
    let rGetGlobal = GetHGlobalFromStream(stream, &global)
    guard S_OK == rGetGlobal else {
      throw GDIPlusError.globalFromStreamFailed(rGetGlobal)
    }
    guard let baseAddress = GlobalLock(global) else {
      throw Win32Error(rawValue: GetLastError())
    }
    defer {
      GlobalUnlock(global)
    }
    let byteCount = GlobalSize(global)
    return try body(UnsafeRawBufferPointer(start: baseAddress, count: Int(byteCount)))
  }

  public borrowing func preferredName(for attachment: borrowing Attachment<Self>, basedOn suggestedName: String) -> String {
    let clsid = AttachableImageFormat.computeCLSID(for: imageFormat, withPreferredName: suggestedName)
    return AttachableImageFormat.appendPathExtension(for: clsid, to: suggestedName)
  }
}
#endif
