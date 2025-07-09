//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if SWT_TARGET_OS_APPLE && canImport(CoreImage)
public import CoreImage
@_spi(Experimental) public import _Testing_CoreGraphics

@_spi(Experimental)
extension CIImage: AttachableAsCGImage {
  public var attachableCGImage: CGImage {
    get throws {
      guard let result = CIContext().createCGImage(self, from: extent) else {
        throw ImageAttachmentError.couldNotCreateCGImage
      }
      return result
    }
  }

  public func _makeCopyForAttachment() -> Self {
    // CIImage is documented as thread-safe, but does not conform to Sendable.
    // It conforms to NSCopying but does not actually copy itself, so there's no
    // point in calling copy().
    self
  }
}
#endif
