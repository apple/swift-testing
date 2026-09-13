//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

extension Test.Case {
  /// A type describing a lazily-generated sequence of test cases generated from
  /// a known collection of argument values.
  ///
  /// Instances of this type can be iterated over multiple times.
  ///
  /// @Comment {
  ///   - Bug: The testing library should support variadic generics.
  ///     ([103416861](rdar://103416861))
  /// }
  struct Generator<S>: Sendable where S: Sequence & Sendable, S.Element: Sendable {
    /// The underlying sequence of argument values.
    ///
    /// The sequence _must_ be iterable multiple times. Hence, initializers
    /// accept only _collections_, not sequences. The constraint here is only to
    /// `Sequence` to allow the storage of computed sequences over collections
    /// (such as `CartesianProduct` or `Zip2Sequence`) that are safe to iterate
    /// multiple times.
    private var _sequence: S

    /// A closure that maps an element from `_sequence` to a test case instance.
    ///
    /// - Parameters:
    ///   - element: The element from `_sequence`.
    ///
    /// - Returns: A test case instance that tests `element`.
    private var _mapElement: @Sendable (_ element: S.Element) -> Test.Case

    /// Initialize an instance of this type.
    ///
    /// - Parameters:
    ///   - sequence: The sequence of argument values for which test cases
    ///     should be generated.
    ///   - mapElement: A function that maps each element in `sequence` to a
    ///     corresponding instance of ``Test/Case``.
    private init(
      sequence: S,
      mapElement: @escaping @Sendable (_ element: S.Element) -> Test.Case
    ) {
      _sequence = sequence
      _mapElement = mapElement
    }

    /// Initialize an instance of this type that generates exactly one test
    /// case.
    ///
    /// - Parameters:
    ///   - testFunction: The test function called by the generated test case.
    init(
      testFunction: nonisolated(nonsending) @escaping @Sendable () async throws -> Void
    ) where S == CollectionOfOne<Void> {
      // A beautiful hack to give us the right number of cases: iterate over a
      // collection containing a single Void value.
      self.init(sequence: CollectionOfOne(())) { _ in
        Test.Case(body: testFunction)
      }
    }

    /// Initialize an instance of this type that iterates over the specified
    /// collection of argument values.
    ///
    /// - Parameters:
    ///   - collection: The collection of argument values for which test cases
    ///     should be generated.
    ///   - parameters: The parameters of the test function for which test cases
    ///     should be generated.
    ///   - testFunction: The test function to which each generated test case
    ///     passes an argument value from `collection`.
    ///
    /// This initializer is disfavored since it relies on `Mirror` to
    /// de-structure elements of tuples. Other initializers which are
    /// specialized to handle collections of tuple types more efficiently should
    /// be preferred.
    @_disfavoredOverload
    init(
      arguments collection: S,
      parameters: [Test.Parameter],
      testFunction: nonisolated(nonsending) @escaping @Sendable (S.Element) async throws -> Void
    ) where S: Collection {
#if !hasFeature(Embedded)
      if parameters.count > 1 {
        self.init(sequence: collection) { element in
          let mirror = Mirror(reflectingForTest: element)
          let values: [any Sendable] = if mirror.displayStyle == .tuple {
            mirror.children.map { unsafeBitCast($0.value, to: (any Sendable).self) }
          } else {
            [element]
          }

          return Test.Case(values: values, parameters: parameters) {
            try await testFunction(element)
          }
        }
        return
      }
#endif

      self.init(sequence: collection) { element in
        Test.Case(values: [element], parameters: parameters) {
          try await testFunction(element)
        }
      }
    }

    /// Initialize an instance of this type that iterates over the specified
    /// collections of argument values.
    ///
    /// - Parameters:
    ///   - collection1: The first collection of argument values for which test
    ///     cases should be generated.
    ///   - collection2: The second collection of argument values for which test
    ///     cases should be generated.
    ///   - parameters: The parameters of the test function for which test cases
    ///     should be generated.
    ///   - testFunction: The test function to which each generated test case
    ///     passes an argument value from `collection`.
    init<C1, C2>(
      arguments collection1: C1, _ collection2: C2,
      parameters: [Test.Parameter],
      testFunction: nonisolated(nonsending) @escaping @Sendable (C1.Element, C2.Element) async throws -> Void
    ) where S == CartesianProduct<C1, C2> {
      self.init(sequence: cartesianProduct(collection1, collection2)) { element in
        Test.Case(values: [element.0, element.1], parameters: parameters) {
          try await testFunction(element.0, element.1)
        }
      }
    }

    /// Initialize an instance of this type that iterates over the specified
    /// sequence of 2-tuple argument values.
    ///
    /// - Parameters:
    ///   - sequence: The sequence of 2-tuple argument values for which test
    ///     cases should be generated.
    ///   - parameters: The parameters of the test function for which test cases
    ///     should be generated.
    ///   - testFunction: The test function to which each generated test case
    ///     passes an argument value from `sequence`.
    ///
    /// This initializer overload is specialized for sequences of 2-tuples to
    /// efficiently de-structure their elements when appropriate.
    ///
    /// @Comment {
    ///   - Bug: The testing library should support variadic generics.
    ///     ([103416861](rdar://103416861))
    /// }
    private init<E1, E2>(
      sequence: S,
      parameters: [Test.Parameter],
      testFunction: nonisolated(nonsending) @escaping @Sendable ((E1, E2)) async throws -> Void
    ) where S.Element == (E1, E2), E1: Sendable, E2: Sendable {
      if parameters.count > 1 {
        self.init(sequence: sequence) { element in
          Test.Case(values: [element.0, element.1], parameters: parameters) {
            try await testFunction(element)
          }
        }
      } else {
        self.init(sequence: sequence) { element in
          Test.Case(values: [element], parameters: parameters) {
            try await testFunction(element)
          }
        }
      }
    }

    /// Initialize an instance of this type that iterates over the specified
    /// collection of 2-tuple argument values.
    ///
    /// - Parameters:
    ///   - collection: The collection of 2-tuple argument values for which test
    ///     cases should be generated.
    ///   - parameters: The parameters of the test function for which test cases
    ///     should be generated.
    ///   - testFunction: The test function to which each generated test case
    ///     passes an argument value from `collection`.
    ///
    /// This initializer overload is specialized for collections of 2-tuples to
    /// efficiently de-structure their elements when appropriate.
    ///
    /// @Comment {
    ///   - Bug: The testing library should support variadic generics.
    ///     ([103416861](rdar://103416861))
    /// }
    init<E1, E2>(
      arguments collection: S,
      parameters: [Test.Parameter],
      testFunction: nonisolated(nonsending) @escaping @Sendable ((E1, E2)) async throws -> Void
    ) where S: Collection, S.Element == (E1, E2) {
      self.init(sequence: collection, parameters: parameters, testFunction: testFunction)
    }

    /// Initialize an instance of this type that iterates over the specified
    /// zipped sequence of argument values.
    ///
    /// - Parameters:
    ///   - zippedCollections: A zipped sequence of argument values for which
    ///     test cases should be generated.
    ///   - parameters: The parameters of the test function for which test cases
    ///     should be generated.
    ///   - testFunction: The test function to which each generated test case
    ///     passes an argument value from `zippedCollections`.
    init<C1, C2>(
      arguments zippedCollections: Zip2Sequence<C1, C2>,
      parameters: [Test.Parameter],
      testFunction: nonisolated(nonsending) @escaping @Sendable ((C1.Element, C2.Element)) async throws -> Void
    ) where S == Zip2Sequence<C1, C2>, C1: Collection, C2: Collection {
      self.init(sequence: zippedCollections, parameters: parameters, testFunction: testFunction)
    }

    /// Initialize an instance of this type that iterates over the specified
    /// dictionary of argument values.
    ///
    /// - Parameters:
    ///   - dictionary: A dictionary of argument values for which test cases
    ///     should be generated.
    ///   - parameters: The parameters of the test function for which test cases
    ///     should be generated.
    ///   - testFunction: The test function to which each generated test case
    ///     passes an argument value from `dictionary`.
    ///
    /// This initializer overload is specialized for dictionary-like collections
    /// to efficiently de-structure their elements (which are known to be
    /// 2-tuples) when appropriate. This overload is distinct from those for
    /// other collections of 2-tuples because the `Element` tuple type for these
    /// kinds of collections includes labels (`(key: Key, value: Value)`).
    init(
      arguments collection: S,
      parameters: [Test.Parameter],
      testFunction: nonisolated(nonsending) @escaping @Sendable ((S.Key, S.Value)) async throws -> Void
    ) where S: ExpressibleByDictionaryLiteral, S.Element == (key: S.Key, value: S.Value) {
      if parameters.count > 1 {
        self.init(sequence: collection) { element in
          Test.Case(values: [element.key, element.value], parameters: parameters) {
            try await testFunction(element)
          }
        }
      } else {
        self.init(sequence: collection) { element in
          Test.Case(values: [element], parameters: parameters) {
            try await testFunction(element)
          }
        }
      }
    }
  }
}

// MARK: - Sequence

extension Test.Case.Generator: Sequence {
  func makeIterator() -> some IteratorProtocol<Test.Case> {
#if !hasFeature(Embedded)
    let state = (
      iterator: _sequence.makeIterator(),
      testCaseIDs: [Test.Case.ID: Int](minimumCapacity: underestimatedCount)
    )
#else
    let state = (iterator: _sequence.makeIterator(), ())
#endif

    return sequence(state: state) { state in
      guard let element = state.iterator.next() else {
        return nil
      }

#if !hasFeature(Embedded)
      var testCase = _mapElement(element)

      if testCase.isParameterized {
        // Store the original, unmodified test case ID. We're about to modify a
        // property which affects it, and we want to update state based on the
        // original one.
        let testCaseID = testCase.id

        // Ensure test cases with identical IDs each have a unique discriminator.
        let discriminator = state.testCaseIDs[testCaseID, default: 0]
        testCase.discriminator = discriminator
        state.testCaseIDs[testCaseID] = discriminator + 1
      }

      return testCase
#else
      return _mapElement(element)
#endif
    }
  }

  var underestimatedCount: Int {
    _sequence.underestimatedCount
  }
}
