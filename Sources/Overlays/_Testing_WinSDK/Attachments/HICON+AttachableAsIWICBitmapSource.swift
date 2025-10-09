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

extension HICON__: _AttachableByAddressAsIWICBitmapSource {
  public static func _copyAttachableIWICBitmapSource(
    from imageAddress: UnsafeMutablePointer<Self>,
    using factory: UnsafeMutablePointer<IWICImagingFactory>
  ) throws -> UnsafeMutablePointer<IWICBitmapSource> {
    var bitmap: UnsafeMutablePointer<IWICBitmap>?
    let rCreate = factory.pointee.lpVtbl.pointee.CreateBitmapFromHICON(factory, imageAddress, &bitmap)
    guard rCreate == S_OK, let bitmap else {
      throw ImageAttachmentError.comObjectCreationFailed(IWICBitmap.self, rCreate)
    }
    return try bitmap.cast(to: IWICBitmapSource.self)
  }

  public static func _copyAttachableValue(at imageAddress: UnsafeMutablePointer<Self>) -> UnsafeMutablePointer<Self> {
    // The only reasonable failure mode for `CopyIcon()` is allocation failure,
    // and Swift treats allocation failures as fatal. Hence, we do not check for
    // `nil` on return.
    CopyIcon(imageAddress)
  }

  public static func _deinitializeAttachableValue(at imageAddress: UnsafeMutablePointer<Self>) {
    DestroyIcon(imageAddress)
  }
}
#endif
