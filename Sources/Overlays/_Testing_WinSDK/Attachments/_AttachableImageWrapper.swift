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

internal import WinSDK

/// A wrapper type for image types such as `HBITMAP` and `HICON` that can be
/// attached indirectly.
///
/// You do not need to use this type directly. Instead, initialize an instance
/// of ``Attachment`` using an instance of an image type that conforms to
/// ``AttachableAsIWICBitmap``. The following system-provided image types
/// conform to the ``AttachableAsIWICBitmap`` protocol and can be attached to a
/// test:
///
/// - [`HBITMAP`](https://learn.microsoft.com/en-us/windows/win32/gdi/bitmaps)
/// - [`HICON`](https://learn.microsoft.com/en-us/windows/win32/menurc/icons)
/// - [`IWICBitmap`](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nn-wincodec-iwicbitmap)
@_spi(Experimental)
public final class _AttachableImageWrapper<Image>: Sendable where Image: AttachableAsIWICBitmap {
  /// The underlying image.
  nonisolated(unsafe) let image: Image

  /// The image format to use when encoding the represented image.
  let imageFormat: AttachableImageFormat?

  init(image: borrowing Image, imageFormat: AttachableImageFormat?) {
    self.image = image._copyAttachableValue()
    self.imageFormat = imageFormat
  }

  deinit {
    image._deinitializeAttachableValue()
  }
}

// MARK: -

extension _AttachableImageWrapper: AttachableWrapper {
  public var wrappedValue: Image {
    image
  }

  public func withUnsafeBytes<R>(for attachment: borrowing Attachment<_AttachableImageWrapper>, _ body: (UnsafeRawBufferPointer) throws -> R) throws -> R {
    // Create an in-memory stream to write the image data to. Note that Windows
    // documentation recommends SHCreateMemStream() instead, but that function
    // does not provide a mechanism to access the underlying memory directly.
    var stream: UnsafeMutablePointer<IStream>?
    let rCreateStream = CreateStreamOnHGlobal(nil, true, &stream)
    guard S_OK == rCreateStream, let stream else {
      throw ImageAttachmentError.comObjectCreationFailed(IStream.self, rCreateStream)
    }
    defer {
      _ = stream.pointee.lpVtbl.pointee.Release(stream)
    }

    // Get an imaging factory to create the WIC bitmap and encoder.
    let factory = try IWICImagingFactory.create()
    defer {
      _ = factory.pointee.lpVtbl.pointee.Release(factory)
    }

    // Create the bitmap and downcast it to an IWICBitmapSource for later use.
    let bitmap = try image.copyAttachableIWICBitmapSource(using: factory)
    defer {
      _ = bitmap.pointee.lpVtbl.pointee.Release(bitmap)
    }

    // Create the encoder.
    let encoder = try withUnsafePointer(to: IID_IWICBitmapEncoder) { [preferredName = attachment.preferredName] IID_IWICBitmapEncoder in
      var encoderCLSID = AttachableImageFormat.computeCLSID(for: imageFormat, withPreferredName: preferredName)
      var encoder: UnsafeMutableRawPointer?
      let rCreate = CoCreateInstance(
        &encoderCLSID,
        nil,
        DWORD(bitPattern: CLSCTX_INPROC_SERVER.rawValue),
        IID_IWICBitmapEncoder,
        &encoder
      )
      guard rCreate == S_OK, let encoder = encoder?.assumingMemoryBound(to: IWICBitmapEncoder.self) else {
        throw ImageAttachmentError.comObjectCreationFailed(IWICBitmapEncoder.self, rCreate)
      }
      return encoder
    }
    defer {
      _ = encoder.pointee.lpVtbl.pointee.Release(encoder)
    }
    _ = encoder.pointee.lpVtbl.pointee.Initialize(encoder, stream, WICBitmapEncoderNoCache)

    // Create the frame into which the bitmap will be composited.
    var frame: UnsafeMutablePointer<IWICBitmapFrameEncode>?
    var propertyBag: UnsafeMutablePointer<IPropertyBag2>?
    let rCreateFrame = encoder.pointee.lpVtbl.pointee.CreateNewFrame(encoder, &frame, &propertyBag)
    guard rCreateFrame == S_OK, let frame, let propertyBag else {
      throw ImageAttachmentError.comObjectCreationFailed(IWICBitmapFrameEncode.self, rCreateFrame)
    }
    defer {
      _ = frame.pointee.lpVtbl.pointee.Release(frame)
      _ = propertyBag.pointee.lpVtbl.pointee.Release(propertyBag)
    }

    // Set properties. The only property we currently set is image quality.
    if let encodingQuality = imageFormat?.encodingQuality {
      try propertyBag.write(encodingQuality, named: "ImageQuality")
    }
    _ = frame.pointee.lpVtbl.pointee.Initialize(frame, propertyBag)

    // Write the image!
    let rWrite = frame.pointee.lpVtbl.pointee.WriteSource(frame, bitmap, nil)
    guard rWrite == S_OK else {
      throw ImageAttachmentError.imageWritingFailed(rWrite)
    }

    // Commit changes through the various layers.
    var rCommit = frame.pointee.lpVtbl.pointee.Commit(frame)
    guard rCommit == S_OK else {
      throw ImageAttachmentError.imageWritingFailed(rCommit)
    }
    rCommit = encoder.pointee.lpVtbl.pointee.Commit(encoder)
    guard rCommit == S_OK else {
      throw ImageAttachmentError.imageWritingFailed(rCommit)
    }
    rCommit = stream.pointee.lpVtbl.pointee.Commit(stream, DWORD(bitPattern: STGC_DEFAULT.rawValue))
    guard rCommit == S_OK else {
      throw ImageAttachmentError.imageWritingFailed(rCommit)
    }

    // Extract the serialized image and pass it back to the caller. We hold the
    // HGLOBAL locked while calling `body`, but nothing else should have a
    // reference to it.
    var global: HGLOBAL?
    let rGetGlobal = GetHGlobalFromStream(stream, &global)
    guard S_OK == rGetGlobal else {
      throw ImageAttachmentError.globalFromStreamFailed(rGetGlobal)
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

  public borrowing func preferredName(for attachment: borrowing Attachment<_AttachableImageWrapper>, basedOn suggestedName: String) -> String {
    let clsid = AttachableImageFormat.computeCLSID(for: imageFormat, withPreferredName: suggestedName)
    return AttachableImageFormat.appendPathExtension(for: clsid, to: suggestedName)
  }
}
#endif
