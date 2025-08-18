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
@_spi(Experimental) public import Testing
public import WinSDK

extension AttachableImageFormat {
  private static let _encoderPathExtensionsByCLSID = Result<[UInt128: [String]], any Error> {
    var result = [UInt128: [String]]()

    // Create an imaging factory.
    let factory = try IWICImagingFactory.create()
    defer {
      _ = factory.pointee.lpVtbl.pointee.Release(factory)
    }

    // Create a COM enumerator over the encoders known to WIC.
    var enumerator: UnsafeMutablePointer<IEnumUnknown>?
    let rCreate = factory.pointee.lpVtbl.pointee.CreateComponentEnumerator(
      factory,
      DWORD(bitPattern: WICEncoder.rawValue),
      DWORD(bitPattern: WICComponentEnumerateDefault.rawValue),
      &enumerator
    )
    guard rCreate == S_OK, let enumerator else {
      throw ImageAttachmentError.comObjectCreationFailed(IEnumUnknown.self, rCreate)
    }
    defer {
      _ = enumerator.pointee.lpVtbl.pointee.Release(enumerator)
    }

    // Loop through the iterator and extract the path extensions and CLSID of
    // each encoder we find.
    while true {
      var nextObject: UnsafeMutablePointer<IUnknown>?
      guard S_OK == enumerator.pointee.lpVtbl.pointee.Next(enumerator, 1, &nextObject, nil), let nextObject else {
        // End of loop.
        break
      }
      defer {
        _ = nextObject.pointee.lpVtbl.pointee.Release(nextObject)
      }

      // Cast the enumerated object to the correct/expected type.
      let info = try withUnsafePointer(to: IID_IWICBitmapEncoderInfo) { IID_IWICBitmapEncoderInfo in
        var info: UnsafeMutableRawPointer?
        let rQuery = nextObject.pointee.lpVtbl.pointee.QueryInterface(nextObject, IID_IWICBitmapEncoderInfo, &info)
        guard rQuery == S_OK, let info else {
          throw ImageAttachmentError.queryInterfaceFailed(IWICBitmapEncoderInfo.self, rQuery)
        }
        return info.assumingMemoryBound(to: IWICBitmapEncoderInfo.self)
      }
      defer {
        _ = info.pointee.lpVtbl.pointee.Release(info)
      }

      var clsid = CLSID()
      guard S_OK == info.pointee.lpVtbl.pointee.GetCLSID(info, &clsid) else {
        continue
      }
      let extensions = _pathExtensions(for: info)
      result[UInt128(clsid)] = extensions
    }

    return result
  }

  /// Get the set of path extensions corresponding to the image format
  /// represented by a WIC bitmap encoder info object.
  ///
  /// - Parameters:
  ///   - info: The WIC bitmap encoder info object of interest.
  ///
  /// - Returns: An array of zero or more path extensions. The case of the
  ///   resulting strings is unspecified.
  private static func _pathExtensions(for info: UnsafeMutablePointer<IWICBitmapEncoderInfo>) -> [String] {
    // Figure out the size of the buffer we need. (Microsoft does not specify if
    // the size is in wide characters or bytes.)
    var charCount = UINT(0)
    var rGet = info.pointee.lpVtbl.pointee.GetFileExtensions(info, 0, nil, &charCount)
    guard rGet == S_OK else {
      return []
    }

    // Allocate the necessary buffer and populate it.
    let buffer = UnsafeMutableBufferPointer<CWideChar>.allocate(capacity: Int(charCount))
    defer {
      buffer.deallocate()
    }
    rGet = info.pointee.lpVtbl.pointee.GetFileExtensions(info, UINT(buffer.count), buffer.baseAddress!, &charCount)
    guard rGet == S_OK else {
      return []
    }

    // Convert the buffer to a Swift string for further manipulation.
    guard let extensions = String.decodeCString(buffer.baseAddress!, as: UTF16.self)?.result else {
      return []
    }

    return extensions
      .split(separator: ",")
      .map { ext in
        if ext.starts(with: ".") {
          ext.dropFirst(1)
        } else {
          ext
        }
      }.map(String.init)
  }

  /// Get the `CLSID` value of the WIC image encoder corresponding to the same
  /// image format as the given path extension.
  ///
  /// - Parameters:
  ///   - pathExtension: The path extension (as a wide C string) for which a
  ///     `CLSID` value is needed.
  ///
  /// - Returns: An instance of `CLSID` referring to a a WIC image encoder, or
  ///   `nil` if one could not be determined.
  private static func _computeCLSID(forPathExtension pathExtension: UnsafePointer<CWideChar>) -> CLSID? {
    let encoderPathExtensionsByCLSID = (try? _encoderPathExtensionsByCLSID.get()) ?? [:]
    return encoderPathExtensionsByCLSID
      .first { _, extensions in
        extensions.contains { encoderExt in
          encoderExt.withCString(encodedAs: UTF16.self) { encoderExt in
            0 == _wcsicmp(pathExtension, encoderExt)
          }
        }
      }.map { CLSID($0.key) }
  }

  /// Get the `CLSID` value of the WIC image encoder corresponding to the same
  /// image format as the given path extension.
  ///
  /// - Parameters:
  ///   - pathExtension: The path extension for which a `CLSID` value is needed.
  ///
  /// - Returns: An instance of `CLSID` referring to a a WIC image encoder, or
  ///   `nil` if one could not be determined.
  private static func _computeCLSID(forPathExtension pathExtension: String) -> CLSID? {
    pathExtension.withCString(encodedAs: UTF16.self) { pathExtension in
      _computeCLSID(forPathExtension: pathExtension)
    }
  }

  /// Get the `CLSID` value of the WIC image encoder corresponding to the same
  /// image format as the path extension on the given attachment filename.
  ///
  /// - Parameters:
  ///   - preferredName: The preferred name of the image for which a `CLSID`
  ///     value is needed.
  ///
  /// - Returns: An instance of `CLSID` referring to a a WIC image encoder, or
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

  /// Get the `CLSID` value of the WIC image encoder to use when encoding an
  /// image.
  ///
  /// - Parameters:
  ///   - imageFormat: The image format to use, or `nil` if the developer did
  ///     not specify one.
  ///   - preferredName: The preferred name of the image for which a type is
  ///     needed.
  ///
  /// - Returns: An instance of `CLSID` referring to a a WIC image encoder. If
  ///   none could be derived from `imageFormat` or `preferredName`, the PNG
  ///   encoder is used.
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
    return CLSID_WICPngEncoder
  }

  /// Append the path extension preferred by WIC for the image format
  /// corresponding to the given `CLSID` value or the given filename.
  ///
  /// - Parameters:
  ///   - clsid: The `CLSID` value representing the image format of interest.
  ///   - preferredName: The preferred name of the image for which a type is
  ///     needed.
  ///
  /// - Returns: A copy of `preferredName`, possibly modified to include a path
  ///   extension appropriate for `CLSID`.
  static func appendPathExtension(for clsid: CLSID, to preferredName: String) -> String {
    // If there's already a CLSID associated with the filename, and it matches
    // the one passed to us, no changes are needed.
    if let existingCLSID = _computeCLSID(forPreferredName: preferredName), clsid == existingCLSID {
      return preferredName
    }

    // Find the preferred path extension for the encoder with the given CLSID.
    let encoderPathExtensionsByCLSID = (try? _encoderPathExtensionsByCLSID.get()) ?? [:]
    if let ext = encoderPathExtensionsByCLSID[UInt128(clsid)]?.first {
      return "\(preferredName).\(ext)"
    }

    // Couldn't find anything better. Return the preferred name unmodified.
    return preferredName
  }

  /// The `CLSID` value corresponding to the WIC image encoder for this image
  /// format.
  public var clsid: CLSID {
    switch kind {
    case .png:
      CLSID_WICPngEncoder
    case .jpeg:
      CLSID_WICJpegEncoder
    case let .systemValue(clsid):
      clsid as! CLSID
    }
  }

  /// Construct an instance of this type with the given `CLSID` value and
  /// encoding quality.
  ///
  /// - Parameters:
  ///   - clsid: The `CLSID` value corresponding to a WIC image encoder to use
  ///     when encoding images.
  ///   - encodingQuality: The encoding quality to use when encoding images. For
  ///     the lowest supported quality, pass `0.0`. For the highest supported
  ///     quality, pass `1.0`.
  ///
  /// If the target image encoder does not support variable-quality encoding,
  /// the value of the `encodingQuality` argument is ignored.
  ///
  /// If `clsid` does not represent an image encoder type supported by WIC, the
  /// result is undefined. For a list of image encoders supported by WIC, see
  /// the documentation for the [`IWICBitmapEncoder`](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nn-wincodec-iwicbitmapencoder)
  /// class.
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
  /// If `pathExtension` does not correspond to a recognized image format, this
  /// initializer returns `nil`:
  ///
  /// - On Apple platforms, the content type corresponding to `pathExtension`
  ///   must conform to [`UTType.image`](https://developer.apple.com/documentation/uniformtypeidentifiers/uttype-swift.struct/image).
  /// - On Windows, there must be a corresponding subclass of [`IWICBitmapEncoder`](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nn-wincodec-iwicbitmapencoder)
  ///   registered with Windows Imaging Component.
  public init?(pathExtension: String, encodingQuality: Float = 1.0) {
    let pathExtension = pathExtension.drop { $0 == "." }

    guard let clsid = Self._computeCLSID(forPathExtension: String(pathExtension)) else {
      return nil
    }

    self.init(clsid, encodingQuality: encodingQuality)
  }
}
#endif
