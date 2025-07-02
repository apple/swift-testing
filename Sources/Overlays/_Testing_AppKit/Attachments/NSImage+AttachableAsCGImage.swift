//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if SWT_TARGET_OS_APPLE && canImport(AppKit)
public import AppKit
@_spi(ForSwiftTestingOnly) @_spi(Experimental) public import _Testing_CoreGraphics

@_spi(Experimental)
extension NSImage: AttachableAsCGImage {
  public var attachableCGImage: CGImage {
    get throws {
      let ctm = AffineTransform(scale: _attachmentScaleFactor) as NSAffineTransform
      guard let result = cgImage(forProposedRect: nil, context: nil, hints: [.ctm: ctm]) else {
        throw ImageAttachmentError.couldNotCreateCGImage
      }
      return result
    }
  }

  public var _attachmentScaleFactor: CGFloat {
    let maxRepWidth = representations.lazy
      .map { CGFloat($0.pixelsWide) / $0.size.width }
      .filter { $0 > 0.0 }
      .max()
    return maxRepWidth ?? 1.0
  }

  /// Get the base address of the loaded image containing `class`.
  ///
  /// - Parameters:
  ///   - class: The class to look for.
  ///
  /// - Returns: The base address of the image containing `class`, or `nil` if
  ///   no image was found (for instance, if the class is generic or dynamically
  ///   generated.)
  ///
  /// "Image" in this context refers to a binary/executable image.
  private static func _baseAddressOfImage(containing `class`: AnyClass) -> UnsafeRawPointer? {
    let classAsAddress = Unmanaged.passUnretained(`class` as AnyObject).toOpaque()

    var info = Dl_info()
    guard 0 != dladdr(classAsAddress, &info) else {
      return nil
    }
    return .init(info.dli_fbase)
  }

  /// The base address of the image containing AppKit's symbols, if known.
  private static nonisolated(unsafe) let _appKitBaseAddress = _baseAddressOfImage(containing: NSImageRep.self)

  public func _makeCopyForAttachment() -> Self {
    // If this image is of an NSImage subclass, we cannot reliably make a deep
    // copy of it because we don't know what its `init(data:)` implementation
    // might do. Try to make a copy (using NSCopying), but if that doesn't work
    // then just return `self` verbatim.
    //
    // Third-party NSImage subclasses are presumably rare in the wild, so
    // hopefully this case doesn't pop up too often.
    guard isMember(of: NSImage.self) else {
      return self.copy() as? Self ?? self
    }

    // Check whether the image contains any representations that we don't think
    // are safe. If it does, then make a "safe" copy.
    let allImageRepsAreSafe = representations.allSatisfy { imageRep in
      // NSCustomImageRep includes an arbitrary rendering block that may not be
      // concurrency-safe in Swift.
      if imageRep is NSCustomImageRep {
        return false
      }

      // Treat all other classes declared in AppKit as safe. We can't reason
      // about classes declared in other modules, so treat them all as if they
      // are unsafe.
      return Self._baseAddressOfImage(containing: type(of: imageRep)) == Self._appKitBaseAddress
    }
    if !allImageRepsAreSafe, let safeCopy = tiffRepresentation.flatMap(Self.init(data:)) {
      // Create a "safe" copy of this image by flattening it to TIFF and then
      // creating a new NSImage instance from it.
      return safeCopy
    }

    // This image appears to be safe to copy directly. (This call should never
    // fail since we already know `self` is a direct instance of `NSImage`.)
    return unsafeDowncast(self.copy() as AnyObject, to: Self.self)
  }
}
#endif
