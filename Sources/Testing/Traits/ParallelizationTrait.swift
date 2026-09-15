//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if _runtime(_ObjC)
private import ObjectiveC
#endif

#if canImport(Synchronization)
private import Synchronization
#endif

// TODO: update this documentation to clarify .serialized vs. .serialized(for:)

/// A type that defines whether the testing library runs this test serially
/// or in parallel.
///
/// When you add this trait to a parameterized test function, that test runs its
/// cases serially instead of in parallel. This trait has no effect when you
/// apply it to a non-parameterized test function.
///
/// When you add this trait to a test suite, that suite runs its
/// contained test functions (including their cases, when parameterized) and
/// sub-suites serially instead of in parallel. If the sub-suites have children,
/// they also run serially.
///
/// This trait does not affect the execution of a test relative to its peers or
/// to unrelated tests. This trait has no effect if you disable test
/// parallelization globally (for example, by passing `--no-parallel` to the
/// `swift test` command.)
///
/// To add this trait to a test, use ``Trait/serialized``.
public struct ParallelizationTrait: TestTrait, SuiteTrait {
  /// A type that describes a data-based dependency that a test may have.
  ///
  /// When a test has a dependency, the testing library assumes it cannot run at
  /// the same time as other tests with the same dependency.
  ///
  /// ## See Also
  ///
  /// - ``Trait/serialized(for:)-(ParallelizationTrait.Dependency)``
  @_spi(Experimental)
  public struct Dependency: Sendable {
    /// An enumeration describing the supported kinds of dependencies.
    enum Kind: Sendable, Equatable, Hashable {
      /// An unbounded dependency.
      case unbounded

#if !hasFeature(Embedded)
      /// A dependency on a Swift type.
      ///
      /// - Parameters:
      ///   - typeInfo: The Swift type.
      case type(_ typeInfo: TypeInfo)
#endif
    }

    /// The kind of this dependency.
    var kind: Kind

    /// The key path used to construct this dependency, if any.
    nonisolated(unsafe) var originalKeyPath: AnyKeyPath?
  }

  /// This instance's dependency, if any.
  ///
  /// If the value of this property is `nil`, it is the otherwise-unspecialized
  /// ``serialized`` trait.
  var dependency: Dependency?

  /// A mapping of dependencies to serializers.
  private static let _serializers = Mutex<[Dependency.Kind: Serializer<Void>]>()
}

// MARK: - Parallelization over a dependency

extension ParallelizationTrait {
  public var isRecursive: Bool {
    // If the trait has a dependency, apply it to child tests/suites so that
    // they are able to "see" parent suites' dependencies and correctly account
    // for them.
    dependency != nil
  }

  public func prepare(for test: Test) async throws {
    guard let dependency else {
      return
    }

    // Ensure a serializer has been created for this trait's dependency (except
    // .unbounded which is special-cased.)
    let kind = dependency.kind
    if kind != .unbounded {
      Self._serializers.withLock { serializers in
        if serializers[kind] == nil {
          serializers[kind] = Serializer()
        }
      }
    }
  }
}

#if !hasFeature(Embedded)
// MARK: -

@_spi(Experimental)
extension ParallelizationTrait: ReducibleTrait {
  public func reduce(into other: Self) -> Self? {
    let selfKind = dependency?.kind
    let otherKind = other.dependency?.kind

    switch (selfKind, otherKind) {
    case (.none, .none),
      (.some, .some) where selfKind == otherKind:
      // Both traits have equivalent (or no) dependencies. It doesn't matter
      // which one we keep.
      return self
    case (.some, .some):
      // The two traits have different dependencies. Combine them into a single
      // .unbounded dependency.
      return .serialized(for: *)
    case (.some, .none):
      // This trait specifies a dependency, but the other one does not. Use this
      // trait and discard the other one.
      return self
    case (.none, .some):
      // The other trait specifies a dependency, but this one does not. Use the
      // other trait and discard this one.
      return other
    }
  }
}
#endif

// MARK: - TestScoping

extension ParallelizationTrait: TestScoping {
  public func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
    // When applied to a test function, this trait should provide scope to the
    // test function itself, not its individual test cases, since that allows
    // Runner to correctly interpret the configuration setting to disable
    // parallelization.
    test.isSuite || testCase == nil ? self : nil
  }

  public func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
    guard var configuration = Configuration.current else {
      throw SystemError(description: "There is no current Configuration when attempting to provide scope for test '\(test.name)'. \(fileABugMessage)")
    }

    configuration.isParallelizationEnabled = false
    try await Configuration.withCurrent(configuration) {
      if test.isSuite {
        // Suites do not need to use a serializer since they don't run their own
        // code. Test functions within the suite will use serializers as needed.
        return try await function()
      }
      guard let dependency else {
        // This trait does not specify a dependency to serialize for.
        return try await function()
      }

      switch dependency.kind {
      case .unbounded:
        try await withoutActuallyEscaping(function) { function in
          // The function we're running depends on all global state, so it
          // should be serialized by all serializers that were created by
          // prepare(). See Runner._applyScopingTraits() for an explanation of
          // what this code does.
          // TODO: share an implementation with that function?
          // FIXME: if this dict rehashes mid-flight, will we deadlock?
          let function = Self._serializers.rawValue.values.lazy
            .reduce(function) { function, serializer in
              {
                try await serializer.run {
                  try await function()
                }
              }
            }
          try await function()
        }
      case let kind:
        // This test function has declared a single dependency, so fetch the
        // serializer for that dependency and run the test in serial with any
        // other tests that have the same dependency.
        let serializer = Self._serializers.withLock { serializers in
          guard let serializer = serializers[kind] else {
            fatalError("Failed to find serializer for serialization trait '\(self)'. Please file a bug report at https://github.com/swiftlang/swift-testing/issues/new")
          }
          return serializer
        }
        try await serializer.run {
          try await function()
        }
      }
    }
  }
}

// MARK: -

extension ParallelizationTrait {
  /// Whether or not ``Trait/serialized`` (with no arguments) applies globally
  /// (i.e. is equivalent to ``Trait/serialized(for:)-(Self.Dependency.Unbounded)``).
  static let isSerializedWithoutArgumentsAppliedGlobally = Environment.flag(named: "SWT_EXPERIMENTAL_SERIALIZED_TRAIT_APPLIES_GLOBALLY") ?? false
}

extension Trait where Self == ParallelizationTrait {
  /// A trait that serializes the test to which it is applied.
  ///
  /// ## See Also
  ///
  /// - ``ParallelizationTrait``
  public static var serialized: Self {
    if ParallelizationTrait.isSerializedWithoutArgumentsAppliedGlobally {
      .serialized(for: *)
    } else {
      Self()
    }
  }
}

// MARK: - CustomStringConvertible

extension ParallelizationTrait: CustomStringConvertible {
  public var description: String {
    if let dependency {
      return ".serialized(for: \(dependency))"
    }
    return ".serialized"
  }
}

extension ParallelizationTrait.Dependency: CustomStringConvertible {
  public var description: String {
    if let originalKeyPath {
      return #"\#(originalKeyPath)"#
    }
    switch kind {
    case .unbounded:
      return "*"
#if !hasFeature(Embedded)
    case let .type(typeInfo):
      return #"(\#(typeInfo.fullyQualifiedName)).self"#
#endif
    }
  }
}

#if !hasFeature(Embedded)
// MARK: - Dependencies

@_spi(Experimental)
extension Trait where Self == ParallelizationTrait {
  /// Constructs a trait that describes a test's dependency on shared state
  /// using a key path.
  ///
  /// - Parameters:
  ///   - keyPath: The key path representing the dependency.
  ///
  /// - Returns: An instance of ``ParallelizationTrait`` that marks any test it
  ///   is applied to as dependent on `keyPath`.
  ///
  /// Use this trait when you write a test function is dependent on global
  /// mutable state and you can describe that state using a key path.
  ///
  /// ```swift
  /// @Test(.serialized(for: \FoodTruck.shared.freezer.door))
  /// func `Freezer door works`() {
  ///   let freezer = FoodTruck.shared.freezer
  ///   freezer.openDoor()
  ///   #expect(freezer.isOpen)
  ///   freezer.closeDoor()
  ///   #expect(!freezer.isOpen)
  /// }
  /// ```
  ///
  /// The testing library may combine dependencies represented by key paths with
  /// common prefixes. For example, the testing library treats the following key
  /// paths as equivalent for the purposes of serialization:
  ///
  /// ```swift
  /// let first = \T.x[0]
  /// let second = \T.x[1]
  /// ```
  ///
  /// ## See Also
  ///
  /// - ``ParallelizationTrait``
  public static func serialized<R, V>(for keyPath: KeyPath<R, V>) -> Self {
    let typeInfo = TypeInfo(describing: R.self)
    let dependency = ParallelizationTrait.Dependency(kind: .type(typeInfo), originalKeyPath: keyPath)
    return Self(dependency: dependency)
  }
}
#endif

// MARK: - Unbounded dependencies (*)

@_spi(Experimental)
extension ParallelizationTrait.Dependency {
  /// An unbounded dependency.
  ///
  /// An unbounded dependency is a dependency on the complete state of the
  /// current process. To specify an unbounded dependency when using
  /// ``Trait/serialized(for:)-(Self.Unbounded)``, pass a reference
  /// to this function.
  ///
  /// ```swift
  /// @Test(.serialized(for: *))
  /// func `All food truck environment variables`() { ... }
  /// ```
  ///
  /// If a test has more than one dependency, the testing library automatically
  /// treats it as if it is dependent on the program's complete state.
  ///
  /// ## See Also
  ///
  /// - ``ParallelizationTrait``
  @_documentation(visibility: private)
  public static func *(_: Self, _: Never) {}

  /// A type describing unbounded dependencies.
  ///
  /// An unbounded dependency is a dependency on the complete state of the
  /// current process. To specify an unbounded dependency when using
  /// ``Trait/serialized(for:)-(Self.Dependency.Unbounded)``, pass a reference
  /// to the `*` operator.
  ///
  /// ```swift
  /// @Test(.serialized(for: *))
  /// func `All food truck environment variables`() { ... }
  /// ```
  ///
  /// If a test has more than one dependency, the testing library automatically
  /// treats it as if it is dependent on the program's complete state.
  ///
  /// ## See Also
  ///
  /// - ``ParallelizationTrait``
  public typealias Unbounded = (Self, Never) -> Void
}

@_spi(Experimental)
extension Trait where Self == ParallelizationTrait {
  /// Constructs a trait that describes a dependency on the complete state of
  /// the current process.
  ///
  /// - Returns: An instance of ``ParallelizationTrait`` that adds a dependency
  ///   on the complete state of the current process to any test it is applied
  ///   to.
  ///
  /// Pass `*` to ``serialized(for:)-(Self.Dependency.Unbounded)`` when you
  /// write a test function is dependent on global mutable state in the current
  /// process that cannot be fully described or that isn't known until runtime.
  ///
  /// ```swift
  /// @Test(.serialized(for: *))
  /// func `All food truck environment variables`() { ... }
  /// ```
  ///
  /// If a test has more than one dependency, the testing library automatically
  /// treats it as if it is dependent on the program's complete state.
  ///
  /// ## See Also
  ///
  /// - ``ParallelizationTrait``
  public static func serialized(for _: Self.Dependency.Unbounded) -> Self {
    let dependency = ParallelizationTrait.Dependency(kind: .unbounded)
    return Self(dependency: dependency)
  }
}
