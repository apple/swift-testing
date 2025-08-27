//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024–2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if SWT_TARGET_OS_APPLE && canImport(UIKit)
public import UIKit
public import _Testing_CoreGraphics

private import ImageIO
#if canImport(UIKitCore_Private)
private import UIKitCore_Private
#endif

/// @Metadata {
///   @Available(Swift, introduced: 6.3)
/// }
extension UIImage: AttachableAsCGImage {
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.3)
  /// }
  public var attachableCGImage: CGImage {
    get throws {
#if canImport(UIKitCore_Private)
      // _UIImageGetCGImageRepresentation() is an internal UIKit function that
      // flattens any (most) UIImage instances to a CGImage. BUG: rdar://155449485
      if let cgImage = _UIImageGetCGImageRepresentation(self)?.takeUnretainedValue() {
        return cgImage
      }
#else
      // NOTE: This API is marked to-be-deprecated so we'll need to eventually
      // switch to UIGraphicsImageRenderer, but that type is not available on
      // watchOS. BUG: rdar://155452406
      UIGraphicsBeginImageContextWithOptions(size, true, scale)
      defer {
        UIGraphicsEndImageContext()
      }
      draw(at: .zero)
      if let cgImage = UIGraphicsGetImageFromCurrentImageContext()?.cgImage {
        return cgImage
      }
#endif
      throw ImageAttachmentError.couldNotCreateCGImage
    }
  }

  public var _attachmentOrientation: UInt32 {
    let result: CGImagePropertyOrientation = switch imageOrientation {
    case .up: .up
    case .down: .down
    case .left: .left
    case .right: .right
    case .upMirrored: .upMirrored
    case .downMirrored: .downMirrored
    case .leftMirrored: .leftMirrored
    case .rightMirrored: .rightMirrored
    @unknown default: .up
    }
    return result.rawValue
  }

  public var _attachmentScaleFactor: CGFloat {
    scale
  }
}
#endif
