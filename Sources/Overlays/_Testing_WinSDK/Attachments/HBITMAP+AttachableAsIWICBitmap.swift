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
import Testing

public import WinSDK

@_spi(Experimental)
extension HBITMAP__: _AttachableByAddressAsIWICBitmap {
  public static func _copyAttachableIWICBitmap(
    from imageAddress: UnsafeMutablePointer<Self>,
    using factory: UnsafeMutablePointer<IWICImagingFactory>
  ) throws -> UnsafeMutablePointer<IWICBitmap> {
    var bitmap: UnsafeMutablePointer<IWICBitmap>!
    let rCreate = factory.pointee.lpVtbl.pointee.CreateBitmapFromHBITMAP(factory, imageAddress, nil, WICBitmapUsePremultipliedAlpha, &bitmap)
    guard rCreate == S_OK, let bitmap else {
      throw ImageAttachmentError.comObjectCreationFailed(IWICBitmap.self, rCreate)
    }
    return bitmap
  }

  public static func _copyAttachableValue(at imageAddress: UnsafeMutablePointer<Self>) throws -> UnsafeMutablePointer<Self> {
    let result: HBITMAP? = CopyImage(imageAddress, UINT(IMAGE_BITMAP), 0, 0, 0).assumingMemoryBound(to: Self.self)
    guard let result else {
      throw Win32Error(rawValue: GetLastError())
    }
    return result
  }

  public static func _deinitializeAttachableValue(at imageAddress: UnsafeMutablePointer<Self>) {
    DeleteObject(imageAddress)
  }
}
#endif
