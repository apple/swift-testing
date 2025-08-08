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
extension UnsafeMutablePointer: AttachableAsIWICBitmap where Pointee: _AttachableByAddressAsIWICBitmap {
  public func _copyAttachableIWICBitmap(using factory: UnsafeMutablePointer<IWICImagingFactory>) throws -> UnsafeMutablePointer<IWICBitmap> {
    try Pointee._copyAttachableIWICBitmap(from: self, using: factory)
  }

  public func _copyAttachableValue() throws -> Self {
    try Pointee._copyAttachableValue(at: self)
  }

  public consuming func _deinitializeAttachableValue() {
    Pointee._deinitializeAttachableValue(at: self)
  }
}
#endif
