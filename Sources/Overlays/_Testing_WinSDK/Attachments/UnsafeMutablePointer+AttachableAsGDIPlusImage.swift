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

@_spi(Experimental)
extension UnsafeMutablePointer: AttachableAsGDIPlusImage where Pointee: _AttachableByAddressAsGDIPlusImage {
  public func _copyAttachableGDIPlusImage() throws -> OpaquePointer {
    try Pointee._copyAttachableGDIPlusImage(at: self)
  }

  public func _cleanUpAttachment() {
    Pointee._cleanUpAttachment(at: self)
  }
}
#endif
