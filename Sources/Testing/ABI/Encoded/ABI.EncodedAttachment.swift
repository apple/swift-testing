//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if canImport(Foundation)
private import Foundation
#endif

extension ABI {
  /// A type implementing the JSON encoding of ``Attachment`` for the ABI entry
  /// point and event stream output.
  ///
  /// This type is not part of the public interface of the testing library. It
  /// assists in converting values to JSON; clients that consume this JSON are
  /// expected to write their own decoders.
  struct EncodedAttachment<V>: Sendable where V: ABI.Version {
    /// The path where the attachment was written.
    var path: String?

    /// The preferred name of the attachment.
    ///
    /// - Warning: Attachments' preferred names are not yet part of the JSON
    ///   schema.
    var _preferredName: String?

    /// The raw content of the attachment, if available.
    ///
    /// The value of this property is set if the attachment was not first saved
    /// to a file. It may also be `nil` if an error occurred while trying to get
    /// the original attachment's serialized representation.
    ///
    /// - Warning: Inline attachment content is not yet part of the JSON schema.
    var _bytes: Bytes?

    init(encoding attachment: borrowing Attachment<AnyAttachable>, in eventContext: borrowing Event.Context) {
      path = attachment.fileSystemPath

      if V.versionNumber >= ABI.v6_3.versionNumber {
        _preferredName = attachment.preferredName

        if path == nil {
          _bytes = try? attachment.withUnsafeBytes { bytes in
            return Bytes(rawValue: [UInt8](bytes))
          }
        }
      }
    }

    /// A structure representing the bytes of an attachment.
    struct Bytes: Sendable, RawRepresentable {
      var rawValue: [UInt8]
    }
  }
}

// MARK: - Codable

extension ABI.EncodedAttachment: Codable {}

extension ABI.EncodedAttachment.Bytes: Codable {
  func encode(to encoder: any Encoder) throws {
#if canImport(Foundation)
    // If possible, encode this structure as Base64 data.
    try rawValue.withUnsafeBytes { rawValue in
      let data = Data(bytesNoCopy: .init(mutating: rawValue.baseAddress!), count: rawValue.count, deallocator: .none)
      var container = encoder.singleValueContainer()
      try container.encode(data)
    }
#else
    // Otherwise, it's an array of integers.
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
#endif
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()

#if canImport(Foundation)
    // If possible, decode a whole Foundation Data object.
    if let data = try? container.decode(Data.self) {
      self.init(rawValue: [UInt8](data))
      return
    }
#endif

    // Fall back to trying to decode an array of integers.
    let bytes = try container.decode([UInt8].self)
    self.init(rawValue: bytes)
  }
}

// MARK: - Attachable

extension ABI.EncodedAttachment: Attachable {
  var estimatedAttachmentByteCount: Int? {
    _bytes?.rawValue.count
  }

  /// An error type that is thrown when ``ABI/EncodedAttachment`` cannot satisfy
  /// a request for the underlying attachment's bytes.
  fileprivate struct BytesUnavailableError: Error {}

  borrowing func withUnsafeBytes<R>(for attachment: borrowing Attachment<Self>, _ body: (UnsafeRawBufferPointer) throws -> R) throws -> R {
    if let bytes = _bytes?.rawValue {
      return try bytes.withUnsafeBytes(body)
    }

#if !SWT_NO_FILE_IO
    guard let path else {
      throw BytesUnavailableError()
    }
#if canImport(Foundation)
    // Leverage Foundation's file-mapping logic since we're using Data anyway.
    let url = URL(fileURLWithPath: path, isDirectory: false)
    let bytes = try Data(contentsOf: url, options: [.mappedIfSafe])
#else
    let fileHandle = try FileHandle(forReadingAtPath: path)
    let bytes = try fileHandle.readToEnd()
#endif
    return try bytes.withUnsafeBytes(body)
#else
    // Cannot read the attachment from disk on this platform.
    throw BytesUnavailableError()
#endif
  }

  borrowing func preferredName(for attachment: borrowing Attachment<Self>, basedOn suggestedName: String) -> String {
    _preferredName ?? suggestedName
  }
}

extension ABI.EncodedAttachment.BytesUnavailableError: CustomStringConvertible {
  var description: String {
    "The attachment's content could not be deserialized."
  }
}
