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

/// @Metadata {
///   @Available(Swift, introduced: 6.3)
/// }
extension UnsafeMutablePointer: _AttachableAsImage, AttachableAsIWICBitmapSource where Pointee: _AttachableByAddressAsIWICBitmapSource {
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.3)
  /// }
  public func copyAttachableIWICBitmapSource() throws -> UnsafeMutablePointer<IWICBitmapSource> {
    let factory = try IWICImagingFactory.create()
    defer {
      _ = factory.pointee.lpVtbl.pointee.Release(factory)
    }
    return try _copyAttachableIWICBitmapSource(using: factory)
  }

  public func _copyAttachableIWICBitmapSource(using factory: UnsafeMutablePointer<IWICImagingFactory>) throws -> UnsafeMutablePointer<IWICBitmapSource> {
    try Pointee._copyAttachableIWICBitmapSource(from: self, using: factory)
  }

  public func _copyAttachableValue() -> Self {
    Pointee._copyAttachableValue(at: self)
  }

  public func _deinitializeAttachableValue() {
    Pointee._deinitializeAttachableValue(at: self)
  }
}
#endif
