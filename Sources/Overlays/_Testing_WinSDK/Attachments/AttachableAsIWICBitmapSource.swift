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
private import Testing
public import WinSDK

/// A protocol describing images that can be converted to instances of
/// [`Attachment`](https://developer.apple.com/documentation/testing/attachment)
/// and which can be represented as instances of [`IWICBitmapSource`](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nn-wincodec-iwicbitmapsource)
/// by address.
///
/// This protocol is not part of the public interface of the testing library.
public protocol _AttachableByAddressAsIWICBitmapSource {
  /// Create a WIC bitmap source representing an instance of this type at the
  /// given address.
  ///
  /// - Parameters:
  ///   - imageAddress: The address of the instance of this type.
  ///   - factory: A WIC imaging factory that can be used to create additional
  ///     WIC objects.
  ///
  /// - Returns: A pointer to a new WIC bitmap source representing this image.
  ///   The caller is responsible for releasing this image when done with it.
  ///
  /// - Throws: Any error that prevented the creation of the WIC bitmap.
  ///
  /// This function is not part of the public interface of the testing library.
  /// It may be removed in a future update.
  static func _copyAttachableIWICBitmapSource(
    from imageAddress: UnsafeMutablePointer<Self>,
    using factory: UnsafeMutablePointer<IWICImagingFactory>
  ) throws -> UnsafeMutablePointer<IWICBitmapSource>

  /// Make a copy of the instance of this type at the given address.
  ///
  /// - Parameters:
  ///   - imageAddress: The address of the instance of this type that should be
  ///     copied.
  ///
  /// - Returns: A copy of `imageAddress`, or `imageAddress` if this type does
  ///   not support a copying operation.
  ///
  /// The testing library uses this function to take ownership of image
  /// resources that test authors pass to it. If possible, make a copy of or add
  /// a reference to the value at `imageAddress`. If this type does not support
  /// making copies, return `imageAddress` verbatim.
  ///
  /// This function is not part of the public interface of the testing library.
  /// It may be removed in a future update.
  static func _copyAttachableValue(at imageAddress: UnsafeMutablePointer<Self>) -> UnsafeMutablePointer<Self>

  /// Manually deinitialize any resources at the given address.
  ///
  /// - Parameters:
  ///   - imageAddress: The address of the instance of this type.
  ///
  /// The implementation of this function is responsible for balancing a
  /// previous call to `_copyAttachableValue(at:)` by cleaning up any resources
  /// (such as handles or COM objects) associated with the value at
  /// `imageAddress`. The testing library automatically invokes this function as
  /// needed. If `_copyAttachableValue(at:)` threw an error, the testing library
  /// does not call this function.
  ///
  /// This function is not responsible for releasing the image returned from
  /// `_copyAttachableIWICBitmapSource(from:using:)`.
  ///
  /// This function is not part of the public interface of the testing library.
  /// It may be removed in a future update.
  static func _deinitializeAttachableValue(at imageAddress: UnsafeMutablePointer<Self>)
}

/// A protocol describing images that can be converted to instances of
/// [`Attachment`](https://developer.apple.com/documentation/testing/attachment)
/// and which can be represented as instances of [`IWICBitmapSource`](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nn-wincodec-iwicbitmapsource).
///
/// This protocol is not part of the public interface of the testing library. It
/// encapsulates Windows-specific logic for image attachments.
package protocol AttachableAsIWICBitmapSource: AttachableAsImage {
  /// Create a WIC bitmap representing an instance of this type.
  ///
  /// - Parameters:
  ///   - factory: A WIC imaging factory that can be used to create additional
  ///     WIC objects.
  ///
  /// - Returns: A pointer to a new WIC bitmap representing this image. The
  ///   caller is responsible for releasing this image when done with it.
  ///
  /// - Throws: Any error that prevented the creation of the WIC bitmap.
  func copyAttachableIWICBitmapSource(
    using factory: UnsafeMutablePointer<IWICImagingFactory>
  ) throws -> UnsafeMutablePointer<IWICBitmapSource>
}

extension AttachableAsIWICBitmapSource {
  public func withUnsafeBytes<R>(as imageFormat: AttachableImageFormat, _ body: (UnsafeRawBufferPointer) throws -> R) throws -> R {
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
    let bitmap = try copyAttachableIWICBitmapSource(using: factory)
    defer {
      _ = bitmap.pointee.lpVtbl.pointee.Release(bitmap)
    }

    // Create the encoder.
    let encoder = try withUnsafePointer(to: IID_IWICBitmapEncoder) { IID_IWICBitmapEncoder in
      var encoderCLSID = imageFormat.encoderCLSID
      var encoder: UnsafeMutableRawPointer?
      let rCreate = CoCreateInstance(
        &encoderCLSID,
        nil,
        DWORD(CLSCTX_INPROC_SERVER.rawValue),
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
    do {
      try propertyBag.write(imageFormat.encodingQuality, named: "ImageQuality")
    } catch ImageAttachmentError.propertyBagWritingFailed(_, HRESULT(bitPattern: 0x80004005)) {
      // E_FAIL: This property is not supported for the current encoder/format.
      // Eat this error silently as it's not useful to the test author.
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
    rCommit = stream.pointee.lpVtbl.pointee.Commit(stream, DWORD(STGC_DEFAULT.rawValue))
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
}
#endif
