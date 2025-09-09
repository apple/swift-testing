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
internal import WinSDK

extension IWICImagingFactory {
  /// Create an imaging factory.
  ///
  /// - Returns: A pointer to a new instance of this type. The caller is
  ///   responsible for releasing this object when done with it.
  ///
  /// - Throws: Any error that occurred while creating the object.
  static func create() throws -> UnsafeMutablePointer<Self> {
    try withUnsafePointer(to: CLSID_WICImagingFactory) { CLSID_WICImagingFactory in
      try withUnsafePointer(to: IID_IWICImagingFactory) { IID_IWICImagingFactory in
        var factory: UnsafeMutableRawPointer?
        let rCreate = CoCreateInstance(
          CLSID_WICImagingFactory,
          nil,
          DWORD(CLSCTX_INPROC_SERVER.rawValue),
          IID_IWICImagingFactory,
          &factory
        )
        guard rCreate == S_OK, let factory = factory?.assumingMemoryBound(to: Self.self) else {
          throw ImageAttachmentError.comObjectCreationFailed(Self.self, rCreate)
        }
        return factory
      }
    }
  }
}
#endif
