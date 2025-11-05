//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024–2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if SWT_TARGET_OS_APPLE && canImport(AppKit)
public import AppKit
public import _Testing_CoreGraphics

extension NSImageRep {
  /// AppKit's bundle.
  private static let _appKitBundle: Bundle = Bundle(for: NSImageRep.self)

  /// Whether or not this image rep's class is effectively thread-safe and can
  /// be treated as if it conforms to `Sendable`.
  fileprivate var isEffectivelySendable: Bool {
    if isMember(of: NSImageRep.self) || isKind(of: NSCustomImageRep.self) {
      // NSImageRep itself is an abstract class. NSCustomImageRep includes an
      // arbitrary rendering block that may not be concurrency-safe in Swift.
      return false
    }

    // Treat all other classes declared in AppKit as safe. We can't reason about
    // classes declared in other bundles, so treat them all as if they're unsafe.
    return Bundle(for: Self.self) == Self._appKitBundle
  }
}

// MARK: -

/// @Metadata {
///   @Available(Swift, introduced: 6.3)
/// }
extension NSImage: AttachableAsImage, AttachableAsCGImage {
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.3)
  /// }
  package var attachableCGImage: CGImage {
    get throws {
      let ctm = AffineTransform(scale: attachmentScaleFactor) as NSAffineTransform
      guard let result = cgImage(forProposedRect: nil, context: nil, hints: [.ctm: ctm]) else {
        throw ImageAttachmentError.couldNotCreateCGImage
      }
      return result
    }
  }

  package var attachmentScaleFactor: CGFloat {
    let maxRepWidth = representations.lazy
      .map { CGFloat($0.pixelsWide) / $0.size.width }
      .filter { $0 > 0.0 }
      .max()
    return maxRepWidth ?? 1.0
  }

  public func _copyAttachableValue() -> Self {
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
    let allImageRepsAreSafe = representations.allSatisfy(\.isEffectivelySendable)
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
