//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023–2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

// MARK: Low-level structure

/// The type of the accessor function used to access a test content record.
///
/// - Parameters:
///   - outValue: A pointer to uninitialized memory large enough to contain the
///     corresponding test content record's value.
///   - type: A pointer to the expected type of `outValue`. Use `load(as:)` to
///     get the Swift type, not `unsafeBitCast(_:to:)`.
///   - hint: An optional pointer to a hint value.
///
/// - Returns: Whether or not `outValue` was initialized. The caller is
///   responsible for deinitializing `outValue` if it was initialized.
private typealias _TestContentRecordAccessor = @convention(c) (
  _ outValue: UnsafeMutableRawPointer,
  _ type: UnsafeRawPointer,
  _ hint: UnsafeRawPointer?,
  _ reserved: UInt
) -> CBool

/// The content of a test content record.
///
/// - Parameters:
///   - kind: The kind of this record.
///   - reserved1: Reserved for future use.
///   - accessor: A function which, when called, produces the test content.
///   - context: Kind-specific context for this record.
///   - reserved2: Reserved for future use.
private typealias _TestContentRecord = (
  kind: UInt32,
  reserved1: UInt32,
  accessor: _TestContentRecordAccessor?,
  context: UInt,
  reserved2: UInt
)

extension DiscoverableAsTestContent {
  /// Check that the layout of this structure in memory matches its expected
  /// layout in the test content section.
  ///
  /// It is not currently possible to perform this validation at compile time.
  /// ([swift-#79667](https://github.com/swiftlang/swift/issues/79667))
  fileprivate static func validateMemoryLayout() {
    precondition(MemoryLayout<TestContentContext>.stride == MemoryLayout<UInt>.stride, "'\(self).TestContentContext' aka '\(TestContentContext.self)' must have the same stride as 'UInt'.")
    precondition(MemoryLayout<TestContentContext>.alignment <= MemoryLayout<UInt>.alignment, "'\(self).TestContentContext' aka '\(TestContentContext.self)' must have an alignment less than or equal to that of 'UInt'.")
  }
}

// MARK: - Individual test content records

/// A type describing a test content record of a particular (known) type.
///
/// Instances of this type can be created by calling
/// ``DiscoverableAsTestContent/allTestContentRecords()`` on a type that
/// conforms to ``DiscoverableAsTestContent``.
@_spi(Experimental) @_spi(ForToolsIntegrationOnly)
public struct TestContentRecord<T> where T: DiscoverableAsTestContent {
  /// The base address of the image containing this instance, if known.
  ///
  /// The type of this pointer is platform-dependent:
  ///
  /// | Platform | Pointer Type |
  /// |-|-|
  /// | macOS, iOS, watchOS, tvOS, visionOS | `UnsafePointer<mach_header_64>` |
  /// | Linux, FreeBSD, Android | `UnsafePointer<ElfW(Ehdr)>` |
  /// | OpenBSD | `UnsafePointer<Elf_Ehdr>` |
  /// | Windows | `HMODULE` |
  ///
  /// On platforms such as WASI that statically link to the testing library, the
  /// value of this property is always `nil`.
  ///
  /// - Note: The value of this property is distinct from the pointer returned
  ///   by `dlopen()` (on platforms that have that function) and cannot be used
  ///   with interfaces such as `dlsym()` that expect such a pointer.
  public private(set) nonisolated(unsafe) var imageAddress: UnsafeRawPointer?

  /// A type defining storage for the underlying test content record.
  private enum _RecordStorage {
    /// The test content record is stored by address.
    case atAddress(UnsafePointer<_TestContentRecord>)

    /// The test content record is stored in-place.
    case inline(_TestContentRecord)
  }

  /// Storage for `_record`.
  private nonisolated(unsafe) var _recordStorage: _RecordStorage

  /// The underlying test content record.
  private var _record: _TestContentRecord {
    _read {
      switch _recordStorage {
      case let .atAddress(recordAddress):
        yield recordAddress.pointee
      case let .inline(record):
        yield record
      }
    }
  }

  fileprivate init(imageAddress: UnsafeRawPointer?, recordAddress: UnsafePointer<_TestContentRecord>) {
    precondition(recordAddress.pointee.kind == T.testContentKind.rawValue)
    self.imageAddress = imageAddress
    self._recordStorage = .atAddress(recordAddress)
  }

  fileprivate init(imageAddress: UnsafeRawPointer?, record: _TestContentRecord) {
    precondition(record.kind == T.testContentKind.rawValue)
    self.imageAddress = imageAddress
    self._recordStorage = .inline(record)
  }

  /// The kind of this test content record.
  public var kind: TestContentKind {
    TestContentKind(rawValue: _record.kind)
  }

  /// The type of the ``context`` property.
  public typealias Context = T.TestContentContext

  /// The context of this test content record.
  public var context: Context {
    T.validateMemoryLayout()
    return withUnsafeBytes(of: _record.context) { context in
      context.load(as: Context.self)
    }
  }

  /// The type of the `hint` argument to ``load(withHint:)``.
  public typealias Hint = T.TestContentAccessorHint

  /// Invoke an accessor function to load a test content record.
  ///
  /// - Parameters:
  /// 	- accessor: The accessor function to call.
  ///   - typeAddress: A pointer to the type of test content record.
  ///   - hint: An optional hint value.
  ///
  /// - Returns: An instance of the test content type `T`, or `nil` if the
  ///   underlying test content record did not match `hint` or otherwise did not
  ///   produce a value.
  ///
  /// Do not call this function directly. Instead, call ``load(withHint:)``.
  private static func _load(using accessor: _TestContentRecordAccessor, withTypeAt typeAddress: UnsafeRawPointer, withHint hint: Hint? = nil) -> T? {
    withUnsafeTemporaryAllocation(of: T.self, capacity: 1) { buffer in
      let initialized = if let hint {
        withUnsafePointer(to: hint) { hint in
          accessor(buffer.baseAddress!, typeAddress, hint, 0)
        }
      } else {
        accessor(buffer.baseAddress!, typeAddress, nil, 0)
      }
      guard initialized else {
        return nil
      }
      return buffer.baseAddress!.move()
    }
  }

  /// Load the value represented by this record.
  ///
  /// - Parameters:
  ///   - hint: An optional hint value. If not `nil`, this value is passed to
  ///     the accessor function of the underlying test content record.
  ///
  /// - Returns: An instance of the test content type `T`, or `nil` if the
  ///   underlying test content record did not match `hint` or otherwise did not
  ///   produce a value.
  ///
  /// The result of this function is not cached. If this function is called more
  /// than once on the same instance, the testing library calls the underlying
  /// test content record's accessor function each time.
  public func load(withHint hint: Hint? = nil) -> T? {
    guard let accessor = _record.accessor else {
      return nil
    }

#if !hasFeature(Embedded)
    return withUnsafePointer(to: T.self) { typeAddress in
      Self._load(using: accessor, withTypeAt: typeAddress, withHint: hint)
    }
#else
    let typeAddress = UnsafeRawPointer(bitPattern: UInt(T.testContentKind.rawValue)).unsafelyUnwrapped
    return Self._load(using: accessor, withTypeAt: typeAddress, withHint: hint)
#endif
  }
}

// Test content sections effectively exist outside any Swift isolation context.
// We can only be (reasonably) sure that the data backing the test content
// record is concurrency-safe if all fields in the test content record are. The
// pointers stored in this structure are read-only and come from a loaded image,
// and all fields of `_TestContentRecord` as we define it are sendable. However,
// the custom `Context` type may or may not be sendable (it could validly be a
// pointer to more data, for instance.)
extension TestContentRecord: Sendable where Context: Sendable {}

// MARK: - CustomStringConvertible

extension TestContentRecord: CustomStringConvertible {
  public var description: String {
#if !hasFeature(Embedded)
    let typeName = String(describing: Self.self)
#else
    let typeName = "TestContentRecord"
#endif
    switch _recordStorage {
    case let .atAddress(recordAddress):
      let recordAddress = imageAddress.map { imageAddress in
        let recordAddressDelta = UnsafeRawPointer(recordAddress) - imageAddress
        return "\(imageAddress)+0x\(String(recordAddressDelta, radix: 16))"
      } ?? "\(recordAddress)"
      return "<\(typeName) \(recordAddress)> { kind: \(kind), context: \(context) }"
    case .inline:
      return "<\(typeName)> { kind: \(kind), context: \(context) }"
    }
  }
}

// MARK: - Enumeration of test content records

extension DiscoverableAsTestContent {
  /// Get all test content of this type known to Swift and found in the current
  /// process.
  ///
  /// - Returns: A sequence of instances of ``TestContentRecord``. Only test
  ///   content records matching this ``TestContent`` type's requirements are
  ///   included in the sequence.
  public static func allTestContentRecords() -> some Sequence<TestContentRecord<Self>> {
    validateMemoryLayout()

    let kind = testContentKind.rawValue

    return SectionBounds.all(.testContent).lazy.flatMap { sb in
      sb.buffer.withMemoryRebound(to: _TestContentRecord.self) { records in
        (0 ..< records.count).lazy
          .map { (records.baseAddress! + $0) as UnsafePointer<_TestContentRecord> }
          .filter { $0.pointee.kind == kind }
          .map { TestContentRecord<Self>(imageAddress: sb.imageAddress, recordAddress: $0) }
      }
    }
  }
}

#if !SWT_NO_LEGACY_TEST_DISCOVERY
// MARK: - Legacy test content discovery

private import _TestingInternals

extension DiscoverableAsTestContent {
  /// Get all test content of this type known to Swift and found in the current
  /// process using the legacy discovery mechanism.
  ///
  /// - Parameters:
  ///   - baseType: The type which all discovered container types must
  ///     conform to or subclass.
  ///   - loader: A function that is called once per type conforming to or
  ///     subclassing `baseType`. This function should load the corresponding
  ///     test content record into the buffer passed to it.
  ///
  /// - Returns: A sequence of instances of ``TestContentRecord``. Only test
  ///   content records matching this ``TestContent`` type's requirements are
  ///   included in the sequence.
  @available(swift, deprecated: 100000.0, message: "Do not adopt this functionality in new code. It will be removed in a future release.")
  public static func allTypeMetadataBasedTestContentRecords(
    loadingWith loader: @escaping @Sendable (Any.Type, UnsafeMutableRawBufferPointer) -> Bool
  ) -> some Sequence<TestContentRecord<Self>> {
    validateMemoryLayout()

    let typeNameHint = _testContentTypeNameHint
    let kind = testContentKind.rawValue
    let loader: @Sendable (Any.Type) -> _TestContentRecord? = { type in
      withUnsafeTemporaryAllocation(of: _TestContentRecord.self, capacity: 1) { buffer in
        // Load the record from the container type.
        guard loader(type, .init(buffer)) else {
          return nil
        }
        return buffer.baseAddress!.move()
      }
    }

    return SectionBounds.all(.typeMetadata).lazy.flatMap { sb in
      stride(from: 0, to: sb.buffer.count, by: SWTTypeMetadataRecordByteCount).lazy
        .map { sb.buffer.baseAddress! + $0 }
        .compactMap { swt_getType(fromTypeMetadataRecord: $0, ifNameContains: typeNameHint) }
        .map { unsafeBitCast($0, to: Any.Type.self) }
        .compactMap(loader)
        .filter { $0.kind == kind }
        .map { TestContentRecord<Self>(imageAddress: sb.imageAddress, record: $0) }
    }
  }
}
#endif
