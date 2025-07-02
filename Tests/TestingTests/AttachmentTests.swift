//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

@testable @_spi(ForToolsIntegrationOnly) import Testing
private import _TestingInternals
#if canImport(Foundation)
import Foundation
import _Testing_Foundation
#endif
#if canImport(CoreGraphics)
import CoreGraphics
@_spi(Experimental) import _Testing_CoreGraphics
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

@Suite("Attachment Tests")
struct AttachmentTests {
  @Test func saveValue() {
    let attachableValue = MyAttachable(string: "<!doctype html>")
    let attachment = Attachment(attachableValue, named: "AttachmentTests.saveValue.html")
    Attachment.record(attachment)
  }

  @Test func description() {
    let attachableValue = MySendableAttachable(string: "<!doctype html>")
    let attachment = Attachment(attachableValue, named: "AttachmentTests.saveValue.html")
    #expect(String(describing: attachment).contains(#""\#(attachment.preferredName)""#))
    #expect(attachment.description.contains("MySendableAttachable("))
  }

  @Test func moveOnlyDescription() {
    let attachableValue = MyAttachable(string: "<!doctype html>")
    let attachment = Attachment(attachableValue, named: "AttachmentTests.saveValue.html")
    #expect(attachment.description.contains(#""\#(attachment.preferredName)""#))
    #expect(attachment.description.contains("'MyAttachable'"))
  }

#if !SWT_NO_FILE_IO
  func compare(_ attachableValue: borrowing MySendableAttachable, toContentsOfFileAtPath filePath: String) throws {
    let file = try FileHandle(forReadingAtPath: filePath)
    let bytes = try file.readToEnd()

    let decodedValue = if #available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
      try #require(String(validating: bytes, as: UTF8.self))
    } else {
      String(decoding: bytes, as: UTF8.self)
    }
    #expect(decodedValue == attachableValue.string)
  }

  @Test func writeAttachment() throws {
    let attachableValue = MySendableAttachable(string: "<!doctype html>")
    let attachment = Attachment(attachableValue, named: "loremipsum.html")

    // Write the attachment to disk, then read it back.
    let filePath = try attachment.write(toFileInDirectoryAtPath: temporaryDirectory())
    defer {
      remove(filePath)
    }
    try compare(attachableValue, toContentsOfFileAtPath: filePath)
  }

  @Test func writeAttachmentWithNameConflict() throws {
    // A sequence of suffixes that are guaranteed to cause conflict.
    let randomBaseValue = UInt64.random(in: 0 ..< (.max - 10))
    var suffixes = (randomBaseValue ..< randomBaseValue + 10).lazy
      .flatMap { [$0, $0, $0] }
      .map { String($0, radix: 36) }
      .makeIterator()
    let baseFileName = "\(UInt64.random(in: 0 ..< .max))loremipsum.html"
    var createdFilePaths = [String]()
    defer {
      for filePath in createdFilePaths {
        remove(filePath)
      }
    }

    for i in 0 ..< 5 {
      let attachableValue = MySendableAttachable(string: "<!doctype html>\(i)")
      let attachment = Attachment(attachableValue, named: baseFileName)

      // Write the attachment to disk, then read it back.
      let filePath = try attachment.write(toFileInDirectoryAtPath: temporaryDirectory(), appending: suffixes.next()!)
      createdFilePaths.append(filePath)
      let filePathComponents = filePath.split { $0 == "/" || $0 == #"\"# }
      let fileName = try #require(filePathComponents.last)
      if i == 0 {
        #expect(fileName == baseFileName)
      } else {
        #expect(fileName != baseFileName)
      }
      try compare(attachableValue, toContentsOfFileAtPath: filePath)
    }
  }

  @Test func writeAttachmentWithMultiplePathExtensions() throws {
    let attachableValue = MySendableAttachable(string: "<!doctype html>")
    let attachment = Attachment(attachableValue, named: "loremipsum.tgz.gif.jpeg.html")

    // Write the attachment to disk once to ensure the original filename is not
    // available and we add a suffix.
    let originalFilePath = try attachment.write(toFileInDirectoryAtPath: temporaryDirectory())
    defer {
      remove(originalFilePath)
    }

    // Write the attachment to disk, then read it back.
    let suffix = String(UInt64.random(in: 0 ..< .max), radix: 36)
    let filePath = try attachment.write(toFileInDirectoryAtPath: temporaryDirectory(), appending: suffix)
    defer {
      remove(filePath)
    }
    let filePathComponents = filePath.split { $0 == "/" || $0 == #"\"# }
    let fileName = try #require(filePathComponents.last)
    #expect(fileName == "loremipsum-\(suffix).tgz.gif.jpeg.html")
    try compare(attachableValue, toContentsOfFileAtPath: filePath)
  }

#if os(Windows)
  static let maximumNameCount = Int(_MAX_FNAME)
#else
  static let maximumNameCount = Int(NAME_MAX)
#endif

  @Test(arguments: [
    #"/\:"#,
    String(repeating: "a", count: maximumNameCount),
    String(repeating: "a", count: maximumNameCount + 1),
    String(repeating: "a", count: maximumNameCount + 2),
  ]) func writeAttachmentWithBadName(name: String) throws {
    let attachableValue = MySendableAttachable(string: "<!doctype html>")
    let attachment = Attachment(attachableValue, named: name)

    // Write the attachment to disk, then read it back.
    let filePath = try attachment.write(toFileInDirectoryAtPath: temporaryDirectory())
    defer {
      remove(filePath)
    }
    try compare(attachableValue, toContentsOfFileAtPath: filePath)
  }

  @Test func fileSystemPathIsSetAfterWritingViaEventHandler() async throws {
    let attachableValue = MySendableAttachable(string: "<!doctype html>")
    try await confirmation("Attachment detected") { valueAttached in
      var configuration = Configuration()
      configuration.attachmentsPath = try temporaryDirectory()
      configuration.eventHandler = { event, _ in
        guard case let .valueAttached(attachment) = event.kind else {
          return
        }
        valueAttached()

        // BUG: We could use #expect(throws: Never.self) here, but the Swift 6.1
        // compiler crashes trying to expand the macro (rdar://138997009)
        do {
          let filePath = try #require(attachment.fileSystemPath)
          defer {
            remove(filePath)
          }
          try compare(attachableValue, toContentsOfFileAtPath: filePath)
        } catch {
          Issue.record(error)
        }
      }

      await Test {
        let attachment = Attachment(attachableValue, named: "loremipsum.html")
        Attachment.record(attachment)
      }.run(configuration: configuration)
    }
  }
#endif

  @Test func attachValue() async {
    await confirmation("Attachment detected", expectedCount: 2) { valueAttached in
      var configuration = Configuration()
      configuration.eventHandler = { event, _ in
        guard case let .valueAttached(attachment) = event.kind else {
          return
        }

        #expect(attachment.sourceLocation.fileID == #fileID)
        valueAttached()
      }

      await Test {
        let attachableValue1 = MyAttachable(string: "<!doctype html>")
        Attachment.record(attachableValue1)
        let attachableValue2 = MyAttachable(string: "<!doctype html>")
        Attachment.record(Attachment(attachableValue2))
      }.run(configuration: configuration)
    }
  }

  @Test func attachSendableValue() async {
    await confirmation("Attachment detected", expectedCount: 2) { valueAttached in
      var configuration = Configuration()
      configuration.eventHandler = { event, _ in
        guard case let .valueAttached(attachment) = event.kind else {
          return
        }

        #expect(attachment.attachableValue is MySendableAttachable)
        #expect(attachment.sourceLocation.fileID == #fileID)
       valueAttached()
      }

      await Test {
        let attachableValue = MySendableAttachable(string: "<!doctype html>")
        Attachment.record(attachableValue)
        Attachment.record(Attachment(attachableValue))
      }.run(configuration: configuration)
    }
  }

  @Test func issueRecordedWhenAttachingNonSendableValueThatThrows() async {
    await confirmation("Attachment detected", expectedCount: 0) { valueAttached in
      await confirmation("Issue recorded") { issueRecorded in
        var configuration = Configuration()
        configuration.eventHandler = { event, _ in
          if case let .valueAttached(attachment) = event.kind {
            #expect(attachment.sourceLocation.fileID == #fileID)
            valueAttached()
          } else if case let .issueRecorded(issue) = event.kind,
                    case let .valueAttachmentFailed(error) = issue.kind,
                    error is MyError {
            #expect(issue.sourceLocation?.fileID == #fileID)
            issueRecorded()
          }
        }

        await Test {
          var attachableValue = MyAttachable(string: "<!doctype html>")
          attachableValue.errorToThrow = MyError()
          Attachment.record(Attachment(attachableValue, named: "loremipsum"))
        }.run(configuration: configuration)
      }
    }
  }

#if canImport(Foundation)
#if !SWT_NO_FILE_IO
  @Test func attachContentsOfFileURL() async throws {
    let data = try #require("<!doctype html>".data(using: .utf8))
    let temporaryFileName = "\(UUID().uuidString).html"
    let temporaryPath = try appendPathComponent(temporaryFileName, to: temporaryDirectory())
    let temporaryURL = URL(fileURLWithPath: temporaryPath, isDirectory: false)
    try data.write(to: temporaryURL)
    defer {
      try? FileManager.default.removeItem(at: temporaryURL)
    }

    await confirmation("Attachment detected") { valueAttached in
      var configuration = Configuration()
      configuration.eventHandler = { event, _ in
        guard case let .valueAttached(attachment) = event.kind else {
          return
        }

        #expect(attachment.preferredName == temporaryFileName)
        #expect(throws: Never.self) {
          try attachment.withUnsafeBytes { buffer in
            #expect(buffer.count == data.count)
          }
        }
        valueAttached()
      }

      await Test {
        let attachment = try await Attachment(contentsOf: temporaryURL)
        Attachment.record(attachment)
      }.run(configuration: configuration)
    }
  }

#if !SWT_NO_PROCESS_SPAWNING
  @Test func attachContentsOfDirectoryURL() async throws {
    let temporaryDirectoryName = UUID().uuidString
    let temporaryPath = try appendPathComponent(temporaryDirectoryName, to: temporaryDirectory())
    let temporaryURL = URL(fileURLWithPath: temporaryPath, isDirectory: false)
    try FileManager.default.createDirectory(at: temporaryURL, withIntermediateDirectories: true)

    let fileData = try #require("Hello world".data(using: .utf8))
    try fileData.write(to: temporaryURL.appendingPathComponent("loremipsum.txt"), options: [.atomic])

    await confirmation("Attachment detected") { valueAttached in
      var configuration = Configuration()
      configuration.eventHandler = { event, _ in
        guard case let .valueAttached(attachment) = event.kind else {
          return
        }

        #expect(attachment.preferredName == "\(temporaryDirectoryName).zip")
        try! attachment.withUnsafeBytes { buffer in
          #expect(buffer.count > 32)
          #expect(buffer[0] == UInt8(ascii: "P"))
          #expect(buffer[1] == UInt8(ascii: "K"))
          if #available(_regexAPI, *) {
            #expect(buffer.contains("loremipsum.txt".utf8))
          }
        }
        valueAttached()
      }

      await Test {
        let attachment = try await Attachment(contentsOf: temporaryURL)
        Attachment.record(attachment)
      }.run(configuration: configuration)
    }
  }
#endif

  @Test func attachUnsupportedContentsOfURL() async throws {
    let url = try #require(URL(string: "https://www.example.com"))
    await #expect(throws: CocoaError.self) {
      _ = try await Attachment(contentsOf: url)
    }
  }
#endif

  struct CodableAttachmentArguments: Sendable, CustomTestArgumentEncodable, CustomTestStringConvertible {
    var forSecureCoding: Bool
    var pathExtension: String?
    var firstCharacter: Character
    var decode: @Sendable (Data) throws -> String

    @Sendable static func decodeWithJSONDecoder(_ data: Data) throws -> String {
      try JSONDecoder().decode(MyCodableAttachable.self, from: data).string
    }

    @Sendable static func decodeWithPropertyListDecoder(_ data: Data) throws -> String {
      try PropertyListDecoder().decode(MyCodableAttachable.self, from: data).string
    }

    @Sendable static func decodeWithNSKeyedUnarchiver(_ data: Data) throws -> String {
      let result = try NSKeyedUnarchiver.unarchivedObject(ofClass: MySecureCodingAttachable.self, from: data)
      return try #require(result).string
    }

    static func all() -> [Self] {
      var result = [Self]()

      for forSecureCoding in [false, true] {
        let decode = forSecureCoding ? decodeWithNSKeyedUnarchiver : decodeWithPropertyListDecoder
        result += [
          Self(
            forSecureCoding: forSecureCoding,
            firstCharacter: forSecureCoding ? "b" : "{",
            decode: forSecureCoding ? decodeWithNSKeyedUnarchiver : decodeWithJSONDecoder
          )
        ]

        result += [
          Self(forSecureCoding: forSecureCoding, pathExtension: "xml", firstCharacter: "<", decode: decode),
          Self(forSecureCoding: forSecureCoding, pathExtension: "plist", firstCharacter: "b", decode: decode),
        ]

        if !forSecureCoding {
          result += [
            Self(forSecureCoding: forSecureCoding, pathExtension: "json", firstCharacter: "{", decode: decodeWithJSONDecoder),
          ]
        }
      }

      return result
    }

    func encodeTestArgument(to encoder: some Encoder) throws {
      var container = encoder.unkeyedContainer()
      try container.encode(pathExtension)
      try container.encode(forSecureCoding)
      try container.encode(firstCharacter.asciiValue!)
    }

    var testDescription: String {
      "(forSecureCoding: \(forSecureCoding), extension: \(String(describingForTest: pathExtension)))"
    }
  }

  @Test("Attach Codable- and NSSecureCoding-conformant values", .serialized, arguments: CodableAttachmentArguments.all())
  func attachCodable(args: CodableAttachmentArguments) async throws {
    var name = "loremipsum"
    if let ext = args.pathExtension {
      name = "\(name).\(ext)"
    }

    func open<T>(_ attachment: borrowing Attachment<T>) throws where T: Attachable {
      try attachment.attachableValue.withUnsafeBytes(for: attachment) { bytes in
        #expect(bytes.first == args.firstCharacter.asciiValue)
        let decodedStringValue = try args.decode(Data(bytes))
        #expect(decodedStringValue == "stringly speaking")
      }
    }

    if args.forSecureCoding {
      let attachableValue = MySecureCodingAttachable(string: "stringly speaking")
      let attachment = Attachment(attachableValue, named: name)
      try open(attachment)
    } else {
      let attachableValue = MyCodableAttachable(string: "stringly speaking")
      let attachment = Attachment(attachableValue, named: name)
      try open(attachment)
    }
  }

  @Test("Attach NSSecureCoding-conformant value but with a JSON type")
  func attachNSSecureCodingAsJSON() async throws {
    let attachableValue = MySecureCodingAttachable(string: "stringly speaking")
    let attachment = Attachment(attachableValue, named: "loremipsum.json")
    #expect(throws: CocoaError.self) {
      try attachment.attachableValue.withUnsafeBytes(for: attachment) { _ in }
    }
  }

  @Test("Attach NSSecureCoding-conformant value but with a nonsensical type")
  func attachNSSecureCodingAsNonsensical() async throws {
    let attachableValue = MySecureCodingAttachable(string: "stringly speaking")
    let attachment = Attachment(attachableValue, named: "loremipsum.gif")
    #expect(throws: CocoaError.self) {
      try attachment.attachableValue.withUnsafeBytes(for: attachment) { _ in }
    }
  }
#endif
}

extension AttachmentTests {
  @Suite("Built-in conformances")
  struct BuiltInConformances {
    func test(_ value: some Attachable) throws {
      #expect(value.estimatedAttachmentByteCount == 6)
      let attachment = Attachment(value)
      try attachment.withUnsafeBytes { buffer in
        #expect(buffer.elementsEqual("abc123".utf8))
        #expect(buffer.count == 6)
      }
    }

    @Test func uint8Array() throws {
      let value: [UInt8] = Array("abc123".utf8)
      try test(value)
    }

    @Test func uint8ContiguousArray() throws {
      let value: ContiguousArray<UInt8> = ContiguousArray("abc123".utf8)
      try test(value)
    }

    @Test func uint8ArraySlice() throws {
      let value: ArraySlice<UInt8> = Array("abc123".utf8)[...]
      try test(value)
    }

    @Test func string() throws {
      let value = "abc123"
      try test(value)
    }

    @Test func substring() throws {
      let value: Substring = "abc123"[...]
      try test(value)
    }

#if canImport(Foundation)
    @Test func data() throws {
      let value = try #require("abc123".data(using: .utf8))
      try test(value)
    }
#endif
  }
}

extension AttachmentTests {
  @Suite("Image tests")
  struct ImageTests {
    enum ImageTestError: Error {
      case couldNotCreateCGContext
      case couldNotCreateCGGradient
      case couldNotCreateCGImage
    }

#if canImport(CoreGraphics)
    static let cgImage = Result<CGImage, any Error> {
      let size = CGSize(width: 32.0, height: 32.0)
      let rgb = CGColorSpaceCreateDeviceRGB()
      let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
      guard let context = CGContext(
        data: nil,
        width: Int(size.width),
        height: Int(size.height),
        bitsPerComponent: 8,
        bytesPerRow: Int(size.width) * 4,
        space: rgb,
        bitmapInfo: bitmapInfo
      ) else {
        throw ImageTestError.couldNotCreateCGContext
      }
      guard let gradient = CGGradient(
        colorsSpace: rgb,
        colors: [
          CGColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0),
          CGColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0),
          CGColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0),
        ] as CFArray,
        locations: nil
      ) else {
        throw ImageTestError.couldNotCreateCGGradient
      }
      context.drawLinearGradient(
        gradient,
        start: .zero,
        end: CGPoint(x: size.width, y: size.height),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
      )
      guard let image = context.makeImage() else {
        throw ImageTestError.couldNotCreateCGImage
      }
      return image
    }

    @available(_uttypesAPI, *)
    @Test func attachCGImage() throws {
      let image = try Self.cgImage.get()
      let attachment = Attachment(image, named: "diamond")
      #expect(attachment.attachableValue === image)
      try attachment.attachableValue.withUnsafeBytes(for: attachment) { buffer in
        #expect(buffer.count > 32)
      }
      Attachment.record(attachment)
    }

    @available(_uttypesAPI, *)
    @Test func attachCGImageDirectly() async throws {
      await confirmation("Attachment detected") { valueAttached in
        var configuration = Configuration()
        configuration.eventHandler = { event, _ in
          if case .valueAttached = event.kind {
            valueAttached()
          }
        }

        await Test {
          let image = try Self.cgImage.get()
          Attachment.record(image, named: "diamond.jpg")
        }.run(configuration: configuration)
      }
    }

    @available(_uttypesAPI, *)
    @Test(arguments: [Float(0.0).nextUp, 0.25, 0.5, 0.75, 1.0], [.png as UTType?, .jpeg, .gif, .image, nil])
    func attachCGImage(quality: Float, type: UTType?) throws {
      let image = try Self.cgImage.get()
      let attachment = Attachment(image, named: "diamond", as: type, encodingQuality: quality)
      #expect(attachment.attachableValue === image)
      try attachment.attachableValue.withUnsafeBytes(for: attachment) { buffer in
        #expect(buffer.count > 32)
      }
      if let ext = type?.preferredFilenameExtension {
        #expect(attachment.preferredName == ("diamond" as NSString).appendingPathExtension(ext))
      }
    }

#if !SWT_NO_EXIT_TESTS
    @available(_uttypesAPI, *)
    @Test func cannotAttachCGImageWithNonImageType() async {
      await #expect(processExitsWith: .failure) {
        let attachment = Attachment(try Self.cgImage.get(), named: "diamond", as: .mp3)
        try attachment.attachableValue.withUnsafeBytes(for: attachment) { _ in }
      }
    }
#endif
#endif
  }
}

// MARK: - Fixtures

struct MyAttachable: Attachable, ~Copyable {
  var string: String
  var errorToThrow: (any Error)?

  func withUnsafeBytes<R>(for attachment: borrowing Attachment<Self>, _ body: (UnsafeRawBufferPointer) throws -> R) throws -> R {
    if let errorToThrow {
      throw errorToThrow
    }

    var string = string
    return try string.withUTF8 { buffer in
      try body(.init(buffer))
    }
  }
}

@available(*, unavailable)
extension MyAttachable: Sendable {}

struct MySendableAttachable: Attachable, Sendable {
  var string: String

  func withUnsafeBytes<R>(for attachment: borrowing Attachment<Self>, _ body: (UnsafeRawBufferPointer) throws -> R) throws -> R {
    #expect(attachment.attachableValue.string == string)
    var string = string
    return try string.withUTF8 { buffer in
      try body(.init(buffer))
    }
  }
}

struct MySendableAttachableWithDefaultByteCount: Attachable, Sendable {
  var string: String

  func withUnsafeBytes<R>(for attachment: borrowing Attachment<Self>, _ body: (UnsafeRawBufferPointer) throws -> R) throws -> R {
    var string = string
    return try string.withUTF8 { buffer in
      try body(.init(buffer))
    }
  }
}

#if canImport(Foundation)
struct MyCodableAttachable: Codable, Attachable, Sendable {
  var string: String
}

final class MySecureCodingAttachable: NSObject, NSSecureCoding, Attachable, Sendable {
  let string: String

  init(string: String) {
    self.string = string
  }

  static var supportsSecureCoding: Bool {
    true
  }

  func encode(with coder: NSCoder) {
    coder.encode(string, forKey: "string")
  }

  required init?(coder: NSCoder) {
    string = (coder.decodeObject(of: NSString.self, forKey: "string") as? String) ?? ""
  }
}

final class MyCodableAndSecureCodingAttachable: NSObject, Codable, NSSecureCoding, Attachable, Sendable {
  let string: String

  static var supportsSecureCoding: Bool {
    true
  }

  func encode(with coder: NSCoder) {
    coder.encode(string, forKey: "string")
  }

  required init?(coder: NSCoder) {
    string = (coder.decodeObject(of: NSString.self, forKey: "string") as? String) ?? ""
  }
}
#endif
