//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023–2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

@_spi(Experimental) @_spi(ForToolsIntegrationOnly) private import _TestDiscovery
private import _TestingInternals

extension Test {
  /// A type that encapsulates test content records that produce instances of
  /// ``Test``.
  ///
  /// This type is necessary because such test content records produce an
  /// indirect `async` accessor function rather than directly producing
  /// instances of ``Test``, but functions are non-nominal types and cannot
  /// directly conform to protocols.
  fileprivate struct Generator: DiscoverableAsTestContent, RawRepresentable {
    static var testContentKind: TestContentKind {
      "test"
    }

    var rawValue: @Sendable () async -> Test
  }

  /// Store the test generator function into the given memory.
  ///
  /// - Parameters:
  ///   - generator: The generator function to store.
  ///   - outValue: The uninitialized memory to store `generator` into.
  ///   - typeAddress: A pointer to the expected type of `generator` as passed
  ///     to the test content record calling this function.
  ///
  /// - Returns: Whether or not `generator` was stored into `outValue`.
  ///
  /// - Warning: This function is used to implement the `@Test` macro. Do not
  ///   use it directly.
#if compiler(>=6.2)
  @safe
#endif
  public static func __store(
    _ generator: @escaping @Sendable () async -> Test,
    into outValue: UnsafeMutableRawPointer,
    asTypeAt typeAddress: UnsafeRawPointer
  ) -> CBool {
#if !hasFeature(Embedded)
    guard typeAddress.load(as: Any.Type.self) == Generator.self else {
      return false
    }
#endif
    outValue.initializeMemory(as: Generator.self, to: .init(rawValue: generator))
    return true
  }

  /// All available ``Test`` instances in the process, according to the runtime.
  ///
  /// The order of values in this sequence is unspecified.
  static var all: some Sequence<Self> {
    get async {
      // The result is a set rather than an array to deduplicate tests that were
      // generated multiple times (e.g. from multiple discovery modes or from
      // defective test records.)
      var result = Set<Self>()

      // Figure out which discovery mechanism to use. By default, we'll use both
      // the legacy and new mechanisms, but we can set an environment variable
      // to explicitly select one or the other. When we remove legacy support,
      // we can also remove this enumeration and environment variable check.
#if !SWT_NO_LEGACY_TEST_DISCOVERY
      let (useNewMode, useLegacyMode) = switch Environment.flag(named: "SWT_USE_LEGACY_TEST_DISCOVERY") {
      case .none:
        (true, true)
      case .some(true):
        (false, true)
      case .some(false):
        (true, false)
      }
#else
      let useNewMode = true
#endif

      // Walk all test content and gather generator functions, then call them in
      // a task group and collate their results.
      if useNewMode {
        let generators = Generator.allTestContentRecords().lazy.compactMap { $0.load() }
        await withTaskGroup { taskGroup in
          for (i, generator) in generators.enumerated() {
            taskGroup.addTask(name: decorateTaskName("test discovery", withAction: "loading test #\(i)")) {
              await generator.rawValue()
            }
          }
          result = await taskGroup.reduce(into: result) { $0.insert($1) }
        }
      }

#if !SWT_NO_LEGACY_TEST_DISCOVERY
      // Perform legacy test discovery if needed.
      if useLegacyMode && result.isEmpty {
        let generators = Generator.allTypeMetadataBasedTestContentRecords().lazy.compactMap { $0.load() }
        await withTaskGroup { taskGroup in
          for (i, generator) in generators.enumerated() {
            taskGroup.addTask(name: decorateTaskName("type-based test discovery", withAction: "loading test #\(i)")) {
              await generator.rawValue()
            }
          }
          result = await taskGroup.reduce(into: result) { $0.insert($1) }
        }
      }
#endif

      return result
    }
  }
}
