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
package import WinSDK

/// @Metadata {
///   @Available(Swift, introduced: 6.3)
/// }
extension UnsafeMutablePointer: AttachableAsImage, AttachableAsIWICBitmapSource where Pointee: _AttachableByAddressAsIWICBitmapSource {
  package func copyAttachableIWICBitmapSource(using factory: UnsafeMutablePointer<IWICImagingFactory>) throws -> UnsafeMutablePointer<IWICBitmapSource> {
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
