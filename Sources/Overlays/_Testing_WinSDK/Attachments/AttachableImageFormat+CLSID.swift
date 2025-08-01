//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024–2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if os(Windows)
@_spi(Experimental) import Testing
private import _TestingInternals.GDIPlus

public import WinSDK

extension AttachableImageFormat {
  /// The set of `ImageCodecInfo` instances known to GDI+.
  ///
  /// If the testing library was unable to determine the set of image formats,
  /// the value of this property is `nil`.
  ///
  /// - Note: The type of this property is a buffer pointer rather than an array
  ///   because the resulting buffer owns trailing untyped memory where path
  ///   extensions and other fields are stored. Do not deallocate this buffer.
  private static nonisolated(unsafe) let _allCodecs: UnsafeBufferPointer<Gdiplus.ImageCodecInfo> = {
    let result = try? withGDIPlus {
      // Find out the size of the buffer needed.
      var codecCount = UINT(0)
      var byteCount = UINT(0)
      let rGetSize = Gdiplus.GetImageEncodersSize(&codecCount, &byteCount)
      guard rGetSize == Gdiplus.Ok else {
        throw GDIPlusError.status(rGetSize)
      }

      // Allocate a buffer of sufficient byte size, then bind the leading bytes
      // to ImageCodecInfo. This leaves some number of trailing bytes unbound to
      // any Swift type.
      let result = UnsafeMutableRawBufferPointer.allocate(
        byteCount: Int(byteCount),
        alignment: MemoryLayout<Gdiplus.ImageCodecInfo>.alignment
      )
      let codecBuffer = result
        .prefix(MemoryLayout<Gdiplus.ImageCodecInfo>.stride * Int(codecCount))
        .bindMemory(to: Gdiplus.ImageCodecInfo.self)

      // Read the encoders list.
      let rGetEncoders = Gdiplus.GetImageEncoders(codecCount, byteCount, codecBuffer.baseAddress!)
      guard rGetEncoders == Gdiplus.Ok else {
        result.deallocate()
        throw GDIPlusError.status(rGetEncoders)
      }
      return UnsafeBufferPointer(codecBuffer)
    }
    return result ?? UnsafeBufferPointer(start: nil, count: 0)
  }()

  /// Get the set of path extensions corresponding to the image format
  /// represented by a GDI+ codec info structure.
  ///
  /// - Parameters:
  ///   - codec: The GDI+ codec info structure of interest.
  ///
  /// - Returns: An array of zero or more path extensions. The case of the
  ///   resulting strings is unspecified.
  private static func _pathExtensions(for codec: Gdiplus.ImageCodecInfo) -> [String] {
    guard let extensions = String.decodeCString(codec.FilenameExtension, as: UTF16.self)?.result else {
      return []
    }
    return extensions
      .split(separator: ";")
      .map { ext in
        if ext.starts(with: "*.") {
          ext.dropFirst(2)
        } else {
          ext[...]
        }
      }.map{ $0.lowercased() } // Vestiges of MS-DOS...
  }

  /// Get the `CLSID` value corresponding to the same image format as the given
  /// path extension.
  ///
  /// - Parameters:
  ///   - pathExtension: The path extension (as a wide C string) for which a
  ///     `CLSID` value is needed.
  ///
  /// - Returns: An instance of `CLSID` referring to a concrete image type, or
  ///   `nil` if one could not be determined.
  private static func _computeCLSID(forPathExtension pathExtension: UnsafePointer<CWideChar>) -> CLSID? {
    _allCodecs.first { codec in
      _pathExtensions(for: codec)
        .contains { codecExtension in
          codecExtension.withCString(encodedAs: UTF16.self) { codecExtension in
            0 == _wcsicmp(pathExtension, codecExtension)
          }
        }
    }.map(\.Clsid)
  }

  /// Get the `CLSID` value corresponding to the same image format as the given
  /// path extension.
  ///
  /// - Parameters:
  ///   - pathExtension: The path extension for which a `CLSID` value is needed.
  ///
  /// - Returns: An instance of `CLSID` referring to a concrete image type, or
  ///   `nil` if one could not be determined.
  private static func _computeCLSID(forPathExtension pathExtension: String) -> CLSID? {
    pathExtension.withCString(encodedAs: UTF16.self) { pathExtension in
      _computeCLSID(forPathExtension: pathExtension)
    }
  }

  /// Get the `CLSID` value corresponding to the same image format as the path
  /// extension on the given attachment filename.
  ///
  /// - Parameters:
  ///   - preferredName: The preferred name of the image for which a `CLSID`
  ///     value is needed.
  ///
  /// - Returns: An instance of `CLSID` referring to a concrete image type, or
  ///   `nil` if one could not be determined.
  private static func _computeCLSID(forPreferredName preferredName: String) -> CLSID? {
    preferredName.withCString(encodedAs: UTF16.self) { (preferredName) -> CLSID? in
      // Get the path extension on the preferred name, if any.
      var dot: PCWSTR?
      guard S_OK == PathCchFindExtension(preferredName, wcslen(preferredName) + 1, &dot), let dot, dot[0] != 0 else {
        return nil
      }
      return _computeCLSID(forPathExtension: dot + 1)
    }
  }

  /// Get the `CLSID` value` to use when encoding the image.
  ///
  /// - Parameters:
  ///   - imageFormat: The image format to use, or `nil` if the developer did
  ///     not specify one.
  ///   - preferredName: The preferred name of the image for which a type is
  ///     needed.
  ///
  /// - Returns: An instance of `CLSID` referring to a concrete image type, or
  ///   `nil` if one could not be determined.
  ///
  /// This function is not part of the public interface of the testing library.
  static func computeCLSID(for imageFormat: Self?, withPreferredName preferredName: String) -> CLSID {
    if let clsid = imageFormat?.clsid {
      return clsid
    }

    // The developer didn't specify a CLSID, or we couldn't figure one out from
    // context, so try to derive one from the preferred name's path extension.
    if let inferredCLSID = _computeCLSID(forPreferredName: preferredName) {
      return inferredCLSID
    }

    // We couldn't derive a concrete type from the path extension, so default
    // to PNG. Unlike Apple platforms, there's no abstract "image" type on
    // Windows so we don't need to make any more decisions.
    return _pngCLSID
  }

  /// Append the path extension preferred by GDI+ for the given `CLSID` value
  /// representing an image format to a suggested extension filename.
  ///
  /// - Parameters:
  ///   - clsid: The `CLSID` value representing the image format of interest.
  ///   - preferredName: The preferred name of the image for which a type is
  ///     needed.
  ///
  /// - Returns: A string containing the corresponding path extension, or `nil`
  ///   if none could be determined.
  static func appendPathExtension(for clsid: CLSID, to preferredName: String) -> String {
    // If there's already a CLSID associated with the filename, and it matches
    // the one passed to us, no changes are needed.
    if let existingCLSID = _computeCLSID(forPreferredName: preferredName), clsid == existingCLSID {
      return preferredName
    }

    let ext = _allCodecs
      .first { $0.Clsid == clsid }
      .flatMap { _pathExtensions(for: $0).first }
    guard let ext else {
      // Couldn't find a path extension for the given CLSID, so make no changes.
      return preferredName
    }

    return "\(preferredName).\(ext)"
  }

  /// The `CLSID` value corresponding to the PNG image format.
  ///
  /// - Note: The named constant [`ImageFormatPNG`](https://learn.microsoft.com/en-us/windows/win32/gdiplus/-gdiplus-constant-image-file-format-constants)
  ///   is not the correct value and will cause `Image::Save()` to fail if
  ///   passed to it.
  private static let _pngCLSID = _computeCLSID(forPathExtension: "png")!

  /// The `CLSID` value corresponding to the JPEG image format.
  ///
  /// - Note: The named constant [`ImageFormatJPEG`](https://learn.microsoft.com/en-us/windows/win32/gdiplus/-gdiplus-constant-image-file-format-constants)
  ///   is not the correct value and will cause `Image::Save()` to fail if
  ///   passed to it.
  private static let _jpegCLSID = _computeCLSID(forPathExtension: "jpg")!

  /// The `CLSID` value corresponding to this image format.
  public var clsid: CLSID {
    switch kind {
    case .png:
      Self._pngCLSID
    case .jpeg:
      Self._jpegCLSID
    case let .systemValue(clsid):
      clsid as! CLSID
    }
  }

  /// Construct an instance of this type with the given `CLSID` value and
  /// encoding quality.
  ///
  /// - Parameters:
  ///   - clsid: The `CLSID` value corresponding to the image format to use when
  ///     encoding images.
  ///   - encodingQuality: The encoding quality to use when encoding images. For
  ///     the lowest supported quality, pass `0.0`. For the highest supported
  ///     quality, pass `1.0`.
  ///
  /// If the target image format does not support variable-quality encoding,
  /// the value of the `encodingQuality` argument is ignored.
  ///
  /// If `clsid` does not represent an image format supported by GDI+, the
  /// result is undefined. For a list of image formats supported by GDI+, see
  /// the [GetImageEncoders()](https://learn.microsoft.com/en-us/windows/win32/api/gdiplusimagecodec/nf-gdiplusimagecodec-getimageencoders)
  /// function.
  public init(_ clsid: CLSID, encodingQuality: Float = 1.0) {
    self.init(kind: .systemValue(clsid), encodingQuality: encodingQuality)
  }

  /// Construct an instance of this type with the given path extension and
  /// encoding quality.
  ///
  /// - Parameters:
  ///   - pathExtension: A path extension corresponding to the image format to
  ///     use when encoding images.
  ///   - encodingQuality: The encoding quality to use when encoding images. For
  ///     the lowest supported quality, pass `0.0`. For the highest supported
  ///     quality, pass `1.0`.
  ///
  /// If the target image format does not support variable-quality encoding,
  /// the value of the `encodingQuality` argument is ignored.
  ///
  /// If `pathExtension` does not correspond to an image format supported by
  /// GDI+, this initializer returns `nil`. For a list of image formats
  /// supported by GDI+, see the [GetImageEncoders()](https://learn.microsoft.com/en-us/windows/win32/api/gdiplusimagecodec/nf-gdiplusimagecodec-getimageencoders)
  /// function.
  public init?(pathExtension: String, encodingQuality: Float = 1.0) {
    let pathExtension = pathExtension.drop { $0 == "." }
    let clsid = Self._computeCLSID(forPathExtension: String(pathExtension))
    if let clsid {
      self.init(clsid, encodingQuality: encodingQuality)
    } else {
      return nil
    }
  }
}
#endif
