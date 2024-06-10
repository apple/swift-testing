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
#else
private import _TestingInternals
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

/// A function type for functions that produce tests.
///
/// - Parameters:
///   - taskGroup: A pointer to a task group specialized to `Array<Test>`. This
///     task group provides an asynchronous context suitable for getting tests.
///
/// This type is not simply an `async` Swift function that returns an instance
/// of ``Test`` because the `@_section` attribute does not currently function
/// correctly when provided with such a value.
/// ([rdar://123327436](rdar://123327436)).
///
/// - Warning: This typealias is used to implement the `@Test` macro. Do not use
///   it directly.
public typealias __TestGetter = @Sendable @convention(c) (_ taskGroup: UnsafeMutableRawPointer) -> Void

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
      await withTaskGroup(of: [Self].self) { taskGroup in
        // Look for tests in the dedicated tests section first.
        swt_enumerateTestGetters(&taskGroup) { fp, context in
          fp(context!)
        }

        enumerateTypes(withNamesContaining: _testContainerTypeNameMagic) { type, _ in
          if let type = type as? any __TestContainer.Type {
            taskGroup.addTask {
              await type.__tests
            }
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

/// The type of callback called by ``enumerateTypes(withNamesContaining:_:)``.
///
/// - Parameters:
///   - type: A Swift type.
///   - stop: An `inout` boolean variable indicating whether type enumeration
///     should stop after the function returns. Set `stop` to `true` to stop
///     type enumeration.
typealias TypeEnumerator = (_ type: Any.Type, _ stop: inout Bool) -> Void

/// Enumerate all types known to Swift found in the current process whose names
/// contain a given substring.
///
/// - Parameters:
///   - nameSubstring: A string which the names of matching classes all contain.
///   - body: A function to invoke, once per matching type.
func enumerateTypes(withNamesContaining nameSubstring: String, _ typeEnumerator: TypeEnumerator) {
  withoutActuallyEscaping(typeEnumerator) { typeEnumerator in
    withUnsafePointer(to: typeEnumerator) { context in
      swt_enumerateTypes(withNamesContaining: nameSubstring, .init(mutating: context)) { type, stop, context in
        let typeEnumerator = context!.load(as: TypeEnumerator.self)
        let type = unsafeBitCast(type, to: Any.Type.self)
        var stop2 = false
        typeEnumerator(type, &stop2)
        stop.pointee = stop2
      }
    }
  }
}
