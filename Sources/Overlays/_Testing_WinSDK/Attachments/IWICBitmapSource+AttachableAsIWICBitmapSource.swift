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
public import WinSDK

/// - Important: The casts in this file to `IUnknown` are safe insofar as we use
///   them to access fixed members of the COM vtable. The casts would become
///   unsafe if we allowed the resulting pointers to escape _and_ if any of the
///   types we use them on have multiple non-virtual inheritance to `IUnknown`.

/// A protocol that identifies a type as a COM subclass of `IWICBitmapSource`.
///
/// Because COM class inheritance is not visible in Swift, we must manually
/// apply conformances to this protocol to each COM type that inherits from
/// `IWICBitmapSource`.
///
/// Because this protocol is not `public`, we must also explicitly restate
/// conformance to the public protocol `_AttachableByAddressAsIWICBitmapSource`
/// even though this protocol refines that one. This protocol refines
/// `_AttachableByAddressAsIWICBitmapSource` because otherwise the compiler will
/// not allow us to declare `public` members in its extension that provides the
/// implementation of `_AttachableByAddressAsIWICBitmapSource` below.
///
/// This protocol is not part of the public interface of the testing library. It
/// allows us to reuse code across all subclasses of `IWICBitmapSource`.
protocol IWICBitmapSourceProtocol: _AttachableByAddressAsIWICBitmapSource {}

extension IWICBitmapSource: _AttachableByAddressAsIWICBitmapSource, IWICBitmapSourceProtocol {}
extension IWICBitmap: _AttachableByAddressAsIWICBitmapSource, IWICBitmapSourceProtocol {}
extension IWICBitmapClipper: _AttachableByAddressAsIWICBitmapSource, IWICBitmapSourceProtocol {}
extension IWICBitmapFlipRotator: _AttachableByAddressAsIWICBitmapSource, IWICBitmapSourceProtocol {}
extension IWICBitmapFrameDecode: _AttachableByAddressAsIWICBitmapSource, IWICBitmapSourceProtocol {}
extension IWICBitmapScaler: _AttachableByAddressAsIWICBitmapSource, IWICBitmapSourceProtocol {}
extension IWICColorTransform: _AttachableByAddressAsIWICBitmapSource, IWICBitmapSourceProtocol {}
extension IWICFormatConverter: _AttachableByAddressAsIWICBitmapSource, IWICBitmapSourceProtocol {}
extension IWICPlanarFormatConverter: _AttachableByAddressAsIWICBitmapSource, IWICBitmapSourceProtocol {}

// MARK: - Upcasting conveniences

extension UnsafeMutablePointer where Pointee: IWICBitmapSourceProtocol {
  /// Upcast this WIC bitmap to a WIC bitmap source (its parent type).
  ///
  /// - Returns: `self`, cast to the parent type via `QueryInterface()`. The
  ///   caller is responsible for releasing the resulting object.
  ///
  /// - Throws: Any error that occurs while calling `QueryInterface()`. In
  ///   practice, this function is not expected to throw an error as it should
  ///   always be possible to cast a valid instance of `IWICBitmap` to
  ///   `IWICBitmapSource`.
  ///
  /// - Important: This function consumes a reference to `self` even if the cast
  ///   fails.
  consuming func cast(to _: IWICBitmapSource.Type) throws -> UnsafeMutablePointer<IWICBitmapSource> {
    try self.withMemoryRebound(to: IUnknown.self, capacity: 1) { `self` in
      defer {
        _ = self.pointee.lpVtbl.pointee.Release(self)
      }

      return try withUnsafePointer(to: IID_IWICBitmapSource) { IID_IWICBitmapSource in
        var bitmapSource: UnsafeMutableRawPointer?
        let rQuery = self.pointee.lpVtbl.pointee.QueryInterface(self, IID_IWICBitmapSource, &bitmapSource)
        guard rQuery == S_OK, let bitmapSource else {
          throw ImageAttachmentError.queryInterfaceFailed(IWICBitmapSource.self, rQuery)
        }
        return bitmapSource.assumingMemoryBound(to: IWICBitmapSource.self)
      }
    }
  }
}

// MARK: - _AttachableByAddressAsIWICBitmapSource implementation

extension IWICBitmapSourceProtocol {
  public static func _copyAttachableIWICBitmapSource(
    from imageAddress: UnsafeMutablePointer<Self>,
    using factory: UnsafeMutablePointer<IWICImagingFactory>
  ) throws -> UnsafeMutablePointer<IWICBitmapSource> {
    try _copyAttachableValue(at: imageAddress).cast(to: IWICBitmapSource.self)
  }

  public static func _copyAttachableValue(at imageAddress: UnsafeMutablePointer<Self>) -> UnsafeMutablePointer<Self> {
    imageAddress.withMemoryRebound(to: IUnknown.self, capacity: 1) { imageAddress in
      _ = imageAddress.pointee.lpVtbl.pointee.AddRef(imageAddress)
    }
    return imageAddress
  }

  public static func _deinitializeAttachableValue(at imageAddress: UnsafeMutablePointer<Self>) {
    imageAddress.withMemoryRebound(to: IUnknown.self, capacity: 1) { imageAddress in
      _ = imageAddress.pointee.lpVtbl.pointee.Release(imageAddress)
    }
  }
}

extension IWICBitmapSource {
  public static func _copyAttachableIWICBitmapSource(
    from imageAddress: UnsafeMutablePointer<Self>,
    using factory: UnsafeMutablePointer<IWICImagingFactory>
  ) throws -> UnsafeMutablePointer<IWICBitmapSource> {
    _ = imageAddress.pointee.lpVtbl.pointee.AddRef(imageAddress)
    return imageAddress
  }
}
#endif
