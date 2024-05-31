//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if SWT_BUILDING_WITH_CMAKE
@_implementationOnly import _TestingInternals
@_implementationOnly import _Imagery
#else
private import _TestingInternals
internal import _Imagery
#endif

/// A protocol describing a type that contains tests.
///
/// - Warning: This protocol is used to implement the `@Test` macro. Do not use
///   it directly.
@_alwaysEmitConformanceMetadata
public protocol __TestContainer {
  /// The set of tests contained by this type.
  static var __tests: [Test] { get async }
}

extension Test {
  /// A string that appears within all auto-generated types conforming to the
  /// `__TestContainer` protocol.
  private static let _testContainerTypeNameMagic = "__🟠$test_container__"

  /// All available ``Test`` instances in the process, according to the runtime.
  ///
  /// The order of values in this sequence is unspecified.
  static var all: some Sequence<Test> {
    get async {
      // Convert the raw sequence of tests to a dictionary keyed by ID.
      var result = await testsByID(_all)

      // Ensure test suite types that don't have the @Suite attribute are still
      // represented in the result.
      _synthesizeSuiteTypes(into: &result)

      return result.values
    }
  }

  /// All available ``Test`` instances in the process, according to the runtime.
  ///
  /// The order of values in this sequence is unspecified. This sequence may
  /// contain duplicates; callers should use ``all`` instead.
  private static var _all: some Sequence<Self> {
    get async {
      var types = [any __TestContainer.Type]()

      enumerateTypes(withNamesContaining: _testContainerTypeNameMagic) { type in
        if let type = type as? any __TestContainer.Type {
          types.append(type)
        }
      }

      return await withTaskGroup(of: [Self].self) { taskGroup in
        for type in types {
          taskGroup.addTask {
            await type.__tests
          }
        }
        return await taskGroup.reduce(into: [], +=)
      }
    }
  }

  /// Create a dictionary mapping the IDs of a sequence of tests to those tests.
  ///
  /// - Parameters:
  ///   - tests: The sequence to convert to a dictionary.
  ///
  /// - Returns: A dictionary containing `tests` keyed by those tests' IDs.
  static func testsByID(_ tests: some Sequence<Self>) -> [ID: Self] {
    [ID: Self](
      tests.lazy.map { ($0.id, $0) },
      uniquingKeysWith: { existing, _ in existing }
    )
  }

  /// Synthesize any missing test suite types (that is, types containing test
  /// content that do not have the `@Suite` attribute) and add them to a
  /// dictionary of tests.
  ///
  /// - Parameters:
  ///   - tests: A dictionary of tests to amend.
  ///
  /// - Returns: The number of key-value pairs added to `tests`.
  @discardableResult private static func _synthesizeSuiteTypes(into tests: inout [ID: Self]) -> Int {
    let originalCount = tests.count

    // Find any instances of Test in the input that are *not* suites. We'll be
    // checking the containing types of each one.
    for test in tests.values where !test.isSuite {
      guard let suiteTypeInfo = test.containingTypeInfo else {
        continue
      }
      let suiteID = ID(typeInfo: suiteTypeInfo)
      if tests[suiteID] == nil {
        tests[suiteID] = Test(traits: [], sourceLocation: test.sourceLocation, containingTypeInfo: suiteTypeInfo, isSynthesized: true)

        // Also synthesize any ancestral suites that don't have tests.
        for ancestralSuiteTypeInfo in suiteTypeInfo.allContainingTypeInfo {
          let ancestralSuiteID = ID(typeInfo: ancestralSuiteTypeInfo)
          if tests[ancestralSuiteID] == nil {
            tests[ancestralSuiteID] = Test(traits: [], sourceLocation: test.sourceLocation, containingTypeInfo: ancestralSuiteTypeInfo, isSynthesized: true)
          }
        }
      }
    }

    return tests.count - originalCount
  }
}

// MARK: -

/// Enumerate all types known to Swift found in the current process whose names
/// contain a given substring.
///
/// - Parameters:
///   - nameSubstring: A string which the names of matching classes all contain.
///   - typeEnumerator: A function to invoke, once per matching type.
///
/// - Bug: This function uses `rethrows` instead of typed throws due to a bug in
///   the Swift compiler. ([128710064](rdar://128710064))
func enumerateTypes(withNamesContaining nameSubstring: String, _ typeEnumerator: (_ type: Any.Type) throws -> Void) rethrows {
#if !SWT_TARGET_OS_APPLE
  swift_enumerateAllMetadataSections({ sections, _ in
    FileHandle.stderr.write("~~~ Type metadata section at \(String(reflecting: sections.pointee.swift5_type_metadata))\n")
  }, nil)
#endif

  try Image.forEach { image in
    try enumerateTypes(in: image, withNamesContaining: nameSubstring, typeEnumerator)
  }
}

/// Enumerate all types known to Swift found in a given image loaded into the
/// current process whose names contain a given substring.
///
/// - Parameters:
///   - image: The image in which to look for types.
///   - nameSubstring: A string which the names of matching classes all contain.
///   - typeEnumerator: A function to invoke, once per matching type.
///
/// - Bug: This function uses `rethrows` instead of typed throws due to a bug in
///   the Swift compiler. [(128710064)](rdar://128710064)
func enumerateTypes<E>(in image: borrowing Image, withNamesContaining nameSubstring: String, _ typeEnumerator: (_ type: Any.Type) throws(E) -> Void) throws(E) {
#if SWT_TARGET_OS_APPLE
  let sectionName = "__TEXT,__swift5_types"
#elseif os(Linux)
  let sectionName = "swift5_type_metadata"
#elseif os(Windows)
  let sectionName = ".sw5tymd"
#endif
  guard let section = image.section(named: sectionName) else {
    return
  }

#if SWT_TARGET_OS_APPLE
  let flags = image.withUnsafePointerToBaseAddress { $0.load(as: mach_header.self).flags }
  if 0 != (flags & MH_DYLIB_IN_CACHE) {
    // Ignore this Mach header if it is in the shared cache. On platforms that
    // support it (Darwin), most system images are containined in this range.
    // System images can be expected not to contain test declarations, so we
    // don't need to walk them.
    return
  }
#endif

  var result: Result<Void, E> = .success(())

  typealias Enumerator = (UnsafeRawPointer, _ stop: UnsafeMutablePointer<CBool>) -> Void
  let body: Enumerator = { type, stop in
    do {
      let type = unsafeBitCast(type, to: Any.Type.self)
      try typeEnumerator(type)
    } catch {
      result = .failure(error as! E)
      stop.pointee = true
    }
  }

  withoutActuallyEscaping(body) { body in
    withUnsafePointer(to: body) { body in
      section.withUnsafeRawBufferPointer { buffer in
        swt_enumerateTypes(
          withNamesContaining: nameSubstring,
          inSectionStartingAt: buffer.baseAddress!,
          byteCount: buffer.count,
          .init(mutating: body)
        ) { type, stop, context in
          let body = context!.load(as: Enumerator.self)
          body(type, stop)
        }
      }
    }
  }

  return try result.get()
}
