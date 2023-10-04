//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

@testable @_spi(ExperimentalTestRunning) @_spi(ExperimentalParameterizedTesting) import Testing
#if canImport(XCTest)
import XCTest
#endif

/// Get the ``Test`` instance representing a type, if one is found in the
/// current process.
///
/// - Parameters:
///   - containingType: The type for which a ``Test`` instance is needed.
///
/// - Returns: The test instance representing the specified type, or `nil` if
///   none is found.
func test(for containingType: Any.Type) async -> Test? {
  await Test.all.first {
    $0.isSuite && $0.containingType == containingType
  }
}

/// Get the ``Test`` instance representing the test function named `name`
/// defined within a suite type, if one is found in the current process.
///
/// - Parameters:
///   - name: The name of the test function to search for.
///
/// - Returns: The test instance representing the specified test function, or
///   `nil` if none is found.
func testFunction(named name: String, in containingType: Any.Type) async -> Test? {
  await Test.all.first {
    $0.name == name && !$0.isSuite && $0.containingType == containingType
  }
}

/// Run the ``Test`` instance representing a suite type, if one is found in the
/// current process.
///
/// - Parameters:
///   - containingType: The type containing the tests that should be run.
///   - configuration: The configuration to use for running.
///
/// Any tests defined within `containingType` are also run. If no test is found
/// representing that type, nothing is run.
func runTest(for containingType: Any.Type, configuration: Configuration = .init()) async {
  let plan = await Runner.Plan(selecting: containingType, configuration: configuration)
  let runner = Runner(plan: plan, configuration: configuration)
  await runner.run()
}

/// Run the ``Test`` instance representing the test function named `name`
/// defined within a suite type, if one is found in the current process.
///
/// - Parameters:
///   - name: The name of the test function to run.
///   - containingType: The type under which the test function should be found.
///   - configuration: The configuration to use for running.
///
/// If no test is found representing `containingType`, nothing is run.
func runTestFunction(named name: String, in containingType: Any.Type, configuration: Configuration = .init()) async {
  var configuration = configuration
  let testID = Test.ID.Selection(testIDs: [Test.ID(type: containingType).child(named: name)])
  configuration.testFilter = { test in
    testID.contains(test)
  }

  let runner = await Runner(configuration: configuration)
  await runner.run()
}

extension Runner {
  /// Initialize an instance of this type that runs the free test function
  /// named `testName` in the module specified in `fileID`.
  ///
  /// - Parameters:
  ///   - testName: The name of the test function this instance should run.
  ///   - fileID: The `#fileID` string whose module should be used to locate
  ///     the test function to run.
  ///   - configuration: The configuration to use for running.
  init(
    selecting testName: String,
    inModuleOf fileID: String = #fileID,
    configuration: Configuration = .init()
  ) async {
    let moduleName = String(fileID[..<fileID.lastIndex(of: "/")!])

    var configuration = configuration
    let selection = Test.ID.Selection(testIDs: [Test.ID(moduleName: moduleName, nameComponents: [testName], sourceLocation: nil)])
    configuration.testFilter = { test in
        selection.contains(test)
    }

    await self.init(configuration: configuration)
  }
}

extension Runner.Plan {
  /// Initialize an instance of this type with the specified suite type.
  ///
  /// - Parameters:
  ///   - containingType: The suite type this plan should select.
  ///   - configuration: The configuration to use for planning.
  init(selecting containingType: Any.Type, configuration: Configuration = .init()) async {
    var configuration = configuration
    let selection = Test.ID.Selection(testIDs: [Test.ID(type: containingType)])
    configuration.testFilter = { test in
      selection.contains(test)
    }

    await self.init(configuration: configuration)
  }
}

extension Test {
  /// Initialize an instance of this type with a function or closure to call.
  ///
  /// - Parameters:
  ///   - traits: Zero or more traits to apply to this test.
  ///   - testFunction: The function to call when running this test.
  ///
  /// Use this initializer to construct an instance of ``Test`` without using
  /// the `@Test` macro.
  init(
    _ traits: any TestTrait...,
    fileID: String = #fileID,
    filePath: StaticString = #filePath,
    line: Int = #line,
    column: Int = #column,
    name: String = #function,
    testFunction: @escaping @Sendable () async throws -> Void
  ) {
    let sourceLocation = SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column)
    let caseGenerator = Case.Generator(testFunction: testFunction)
    self.init(name: name, displayName: name, traits: traits, sourceLocation: sourceLocation, containingType: nil, testCases: caseGenerator, parameters: [])
  }

  /// Initialize an instance of this type with a function or closure to call,
  /// parameterized over a collection of values.
  ///
  /// - Parameters:
  ///   - traits: Zero or more traits to apply to this test.
  ///   - collection: A collection of values to pass to `testFunction`.
  ///   - parameters: The parameters of this instance's test function.
  ///   - testFunction: The function to call when running this test. During
  ///     testing, this function is called once for each element in
  ///     `collection`.
  ///
  /// @Comment {
  ///   - Bug: The testing library should support variadic generics.
  ///     ([103416861](rdar://103416861))
  /// }
  init<C>(
    _ traits: any TestTrait...,
    arguments collection: C,
    parameters: [ParameterInfo] = [],
    fileID: String = #fileID,
    filePath: StaticString = #filePath,
    line: Int = #line,
    column: Int = #column,
    name: String = #function,
    testFunction: @escaping @Sendable (C.Element) async throws -> Void
  ) where C: Collection & Sendable, C.Element: Sendable {
    let sourceLocation = SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column)
    let caseGenerator = Case.Generator(arguments: collection, testFunction: testFunction)
    self.init(name: name, displayName: name, traits: traits, sourceLocation: sourceLocation, containingType: nil, testCases: caseGenerator, parameters: parameters)
  }

  /// Initialize an instance of this type with a function or closure to call,
  /// parameterized over two collections of values.
  ///
  /// - Parameters:
  ///   - traits: Zero or more traits to apply to this test.
  ///   - collection1: A collection of values to pass to `testFunction`.
  ///   - collection2: A second collection of values to pass to `testFunction`.
  ///   - parameters: The parameters of this instance's test function.
  ///   - testFunction: The function to call when running this test. During
  ///     testing, this function is called once for each pair of elements in
  ///     `collection1` and `collection2`.
  ///
  /// @Comment {
  ///   - Bug: The testing library should support variadic generics.
  ///     ([103416861](rdar://103416861))
  /// }
  init<C1, C2>(
    _ traits: any TestTrait...,
    arguments collection1: C1, _ collection2: C2,
    parameters: [ParameterInfo] = [],
    fileID: String = #fileID,
    filePath: StaticString = #filePath,
    line: Int = #line,
    column: Int = #column,
    name: String = #function,
    testFunction: @escaping @Sendable (C1.Element, C2.Element) async throws -> Void
  ) where C1: Collection & Sendable, C1.Element: Sendable, C2: Collection & Sendable, C2.Element: Sendable {
    let sourceLocation = SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column)
    let caseGenerator = Case.Generator(arguments: collection1, collection2, testFunction: testFunction)
    self.init(name: name, displayName: name, traits: traits, sourceLocation: sourceLocation, containingType: nil, testCases: caseGenerator, parameters: parameters)
  }

  /// Initialize an instance of this type with a function or closure to call,
  /// parameterized over a zipped sequence of argument values.
  ///
  /// - Parameters:
  ///   - traits: Zero or more traits to apply to this test.
  ///   - zippedCollections: A zipped sequence of argument values to pass to
  ///     `testFunction`.
  ///   - parameters: The parameters of this instance's test function.
  ///   - testFunction: The function to call when running this test. During
  ///     testing, this function is called once for each pair of elements in
  ///     `zippedCollections`.
  init<C1, C2>(
    _ traits: any TestTrait...,
    arguments zippedCollections: Zip2Sequence<C1, C2>,
    parameters: [ParameterInfo] = [],
    fileID: String = #fileID,
    filePath: StaticString = #filePath,
    line: Int = #line,
    column: Int = #column,
    name: String = #function,
    testFunction: @escaping @Sendable ((C1.Element, C2.Element)) async throws -> Void
  ) where C1: Collection & Sendable, C1.Element: Sendable, C2: Collection & Sendable, C2.Element: Sendable {
    let sourceLocation = SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column)
    let caseGenerator = Case.Generator(arguments: zippedCollections, testFunction: testFunction)
    self.init(name: name, displayName: name, traits: traits, sourceLocation: sourceLocation, containingType: nil, testCases: caseGenerator, parameters: parameters)
  }
}

extension Test {
  /// Run a single test in isolation.
  ///
  /// - Parameters:
  ///   - configuration: The configuration to apply when running this test.
  ///
  /// This function constructs an instance of ``Runner`` to run this test, then
  /// runs it. It is provided as a convenience for use in the testing library's
  /// own test suite; when writing tests for other test suites, it should not be
  /// necessary to call this function.
  func run(configuration: Configuration = .init()) async {
    let runner = await Runner(testing: [self], configuration: configuration)
    await runner.run()
  }
}

extension Test.ID {
  /// Whether or not this instance can be used to create child test IDs.
  ///
  /// A test ID can have children unless it represents a test function (as
  /// indicated by the presence of a value for its ``sourceLocation``
  /// property.)
  ///
  /// ## See Also
  ///
  /// - ``child(named:)``
  var canHaveChildren: Bool {
    sourceLocation == nil
  }

  /// Make an ID for a test that is a child of this instance.
  ///
  /// - Parameters:
  ///   - name: The name of the child test, relative to this instance's
  ///     corresponding test. For example, if `self` represents a test named
  ///     `"A.B.C"`, and the fully-qualified name of the child is `"A.B.C.D"`,
  ///     pass `"D"`.
  ///
  /// - Returns: An instance of this type representing the specified child test.
  ///
  /// - Precondition: The value of this instance's ``canHaveChildren`` property
  ///   must be `true`.
  func child(named name: String) -> Self {
    precondition(canHaveChildren, "A child test cannot be added to this test ID because it represents a function.")

    var result = self
    result.nameComponents.append(name)
    return result
  }
}

extension Test.ID.Selection {
  /// Initialize an instance of this type with test IDs created from the
  /// specified collection of fully-qualified name components.
  ///
  /// - Parameters:
  ///   - testIDs: The collection of fully-qualified name components from test
  ///     IDs to include in the selection.
  init(testIDs: some Collection<[String]>) {
    self.init(testIDs: testIDs.lazy.map(Test.ID.init(_:)))
  }
}

// TODO: Provide some convenience utilities for our own unit tests to streamline
// creating a `Configuration` consisting of a selected tests predicate based on
// a `Test.ID.Selection` and eliminate boilerplate.

/// Whether or not to enable "noisy" tests that produce a lot of output.
///
/// This flag can be used with `.enabled(if:)` to disable noisy tests unless the
/// developer specifies an environment variable when testing. Use it with tests
/// whose output could make it hard to read "real" output from the testing
/// library.
let testsWithSignificantIOAreEnabled = Environment.flag(named: "SWT_ENABLE_TESTS_WITH_SIGNIFICANT_IO") == true
