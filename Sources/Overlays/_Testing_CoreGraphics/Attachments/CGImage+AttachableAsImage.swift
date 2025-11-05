//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024–2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if SWT_TARGET_OS_APPLE && canImport(CoreGraphics)
public import CoreGraphics

/// @Metadata {
///   @Available(Swift, introduced: 6.3)
/// }
extension CGImage: AttachableAsImage, AttachableAsCGImage {
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.3)
  /// }
  package var attachableCGImage: CGImage {
    self
  }
}
#endif
