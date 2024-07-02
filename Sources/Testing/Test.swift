//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if _runtime(_ObjC)
public import ObjectiveC
#endif

/// A type representing a test or suite.
///
/// An instance of this type may represent:
///
/// - A type containing zero or more tests (i.e. a _test suite_);
/// - An individual test function (possibly contained within a type); or
/// - A test function parameterized over one or more sequences of inputs.
///
/// Two instances of this type are considered to be equal if the values of their
/// ``Test/id-swift.property`` properties are equal.
public struct Test: Sendable {
  /// The name of this instance.
  ///
  /// The value of this property is equal to the name of the symbol to which the
  /// ``Test`` attribute is applied (that is, the name of the type or function.)
  /// To get the customized display name specified as part of the ``Test``
  /// attribute, use the ``Test/displayName`` property.
  public var name: String

  /// The customized display name of this instance, if specified.
  public var displayName: String?

  /// The set of traits added to this instance when it was initialized.
  public var traits: [any Trait] {
    willSet {
      // Prevent programmatically adding suite traits to test functions or test
      // traits to test suites.
      func traitsAreCorrectlyTyped() -> Bool {
        if isSuite {
          return newValue.allSatisfy { $0 is any SuiteTrait }
        } else {
          return newValue.allSatisfy { $0 is any TestTrait }
        }
      }
      precondition(traitsAreCorrectlyTyped(), "Programmatically added an inapplicable trait to test \(self)")
    }
  }

  /// The source location of this test.
  public var sourceLocation: SourceLocation

  /// Information about the type containing this test, if any.
  ///
  /// If a test is associated with a free function or static function, the value
  /// of this property is `nil`. To determine if a specific instance of ``Test``
  /// refers to this type itself, check the ``isSuite`` property.
  var containingTypeInfo: TypeInfo?

  /// The XCTest-compatible Objective-C selector corresponding to this
  /// instance's underlying test function.
  ///
  /// On platforms that do not support Objective-C interop, the value of this
  /// property is always `nil`.
  @_spi(ForToolsIntegrationOnly)
  public var xcTestCompatibleSelector: __XCTestCompatibleSelector?

  /// An enumeration describing the evaluation state of a test's cases.
  ///
  /// This use of `@unchecked Sendable` and of `AnySequence` in this type's
  /// cases is necessary because it is not currently possible to express
  /// `Sequence<Test.Case> & Sendable` as an existential (`any`)
  /// ([96960993](rdar://96960993)). It is also not possible to have a value of
  /// an underlying generic sequence type without specifying its generic
  /// parameters.
  fileprivate enum TestCasesState: @unchecked Sendable {
    /// The test's cases have not yet been evaluated.
    ///
    /// - Parameters:
    ///   - function: The function to call to evaluate the test's cases. The
    ///     result is a sequence of test cases.
    case unevaluated(_ function: @Sendable () async throws -> AnySequence<Test.Case>)

    /// The test's cases have been evaluated.
    ///
    /// - Parameters:
    ///   - testCases: The test's cases.
    case evaluated(_ testCases: AnySequence<Test.Case>)

    /// An error was thrown when the testing library attempted to evaluate the
    /// test's cases.
    ///
    /// - Parameters:
    ///   - error: The thrown error.
    case failed(_ error: any Error)
  }

  /// The evaluation state of this test's cases, if any.
  ///
  /// If this test represents a suite type, the value of this property is `nil`.
  fileprivate var testCasesState: TestCasesState?

  /// The set of test cases associated with this test, if any.
  ///
  /// - Precondition: This property may only be accessed on test instances
  ///   representing suites, or on test functions whose ``testCaseState``
  ///   indicates a successfully-evaluated state.
  ///
  /// For parameterized tests, each test case is associated with a single
  /// combination of parameterized inputs. For non-parameterized tests, a single
  /// test case is synthesized. For test suite types (as opposed to test
  /// functions), the value of this property is `nil`.
  var testCases: (some Sequence<Test.Case>)? {
    testCasesState.map { testCasesState in
      guard case let .evaluated(testCases) = testCasesState else {
        // Callers are expected to first attempt to evaluate a test's cases by
        // calling `evaluateTestCases()`, and are never expected to access this
        // property after evaluating a test's cases if that evaluation threw an
        // error (because the test cannot be run.) If an error was thrown, a
        // `Runner.Plan` is expected to record issue for the test, rather than
        // attempt to run it, and thus never access this property.
        preconditionFailure("Attempting to access test cases with invalid state. Please file a bug report at https://github.com/apple/swift-testing/issues/new and include this information: \(String(reflecting: testCasesState))")
      }
      return testCases
    }
  }
  
  /// Equivalent to ``testCases``, but without requiring that the test cases be
  /// evaluated first.
  ///
  /// Most callers should not use this property and should prefer ``testCases``
  /// since it will help catch logic errors in the testing library. Use this
  /// property if you are interested in the test's test cases, but the test has
  /// not been evaluated by an instance of ``Runner/Plan`` (e.g. if you are
  /// implementing `swift test list`.)
  var uncheckedTestCases: (some Sequence<Test.Case>)? {
    testCasesState.flatMap { testCasesState in
      if case let .evaluated(testCases) = testCasesState {
        return testCases
      }
      return nil
    }
  }

  /// Evaluate this test's cases if they have not been evaluated yet.
  ///
  /// The arguments of a test are captured into a closure so they can be lazily
  /// evaluated only if the test will run to avoid unnecessary work. This
  /// function may be called once that determination has been made, to perform
  /// this evaluation once. The resulting arguments are stored on this instance
  /// so that subsequent calls to ``testCases`` do not cause the arguments to be
  /// re-evaluated.
  ///
  /// - Throws: Any error caught while first evaluating the test arguments.
  mutating func evaluateTestCases() async throws {
    if case let .unevaluated(function) = testCasesState {
      do {
        let sequence = try await function()
        self.testCasesState = .evaluated(sequence)
      } catch {
        self.testCasesState = .failed(error)
        throw error
      }
    }
  }

  /// Whether or not this test is parameterized.
  public var isParameterized: Bool {
    parameters?.isEmpty == false
  }

  /// The test function parameters, if any.
  ///
  /// If this instance represents a test function, the value of this property is
  /// an array of values describing its parameters, which may be empty if the
  /// test function is non-parameterized. If this instance represents a test
  /// suite, the value of this property is `nil`.
  public var parameters: [Parameter]?

  /// Whether or not this instance is a test suite containing other tests.
  ///
  /// Instances of ``Test`` attached to types rather than functions are test
  /// suites. They do not contain any test logic of their own, but they may
  /// have traits added to them that also apply to their subtests.
  ///
  /// A test suite can be declared using the ``Suite(_:_:)`` macro.
  public var isSuite: Bool {
    containingTypeInfo != nil && testCasesState == nil
  }

  /// Whether or not this instance was synthesized at runtime.
  ///
  /// During test planning, suites that are not explicitly marked with the
  /// `@Suite` attribute are synthesized from available type information before
  /// being added to the plan. For such suites, the value of this property is
  /// `true`.
  @_spi(ForToolsIntegrationOnly)
  public var isSynthesized = false

  /// Initialize an instance of this type representing a test suite type.
  init(
    displayName: String? = nil,
    traits: [any Trait],
    sourceLocation: SourceLocation,
    containingTypeInfo: TypeInfo,
    isSynthesized: Bool = false
  ) {
    self.name = containingTypeInfo.unqualifiedName
    self.displayName = displayName
    self.traits = traits
    self.sourceLocation = sourceLocation
    self.containingTypeInfo = containingTypeInfo
    self.isSynthesized = isSynthesized
  }

  /// Initialize an instance of this type representing a test function.
  init<S>(
    name: String,
    displayName: String? = nil,
    traits: [any Trait],
    sourceLocation: SourceLocation,
    containingTypeInfo: TypeInfo? = nil,
    xcTestCompatibleSelector: __XCTestCompatibleSelector? = nil,
    testCases: @escaping @Sendable () async throws -> Test.Case.Generator<S>,
    parameters: [Parameter]
  ) {
    self.name = name
    self.displayName = displayName
    self.traits = traits
    self.sourceLocation = sourceLocation
    self.containingTypeInfo = containingTypeInfo
    self.xcTestCompatibleSelector = xcTestCompatibleSelector
    self.testCasesState = .unevaluated { .init(try await testCases()) }
    self.parameters = parameters
  }

  /// Initialize an instance of this type representing a test function.
  init<S>(
    name: String,
    displayName: String? = nil,
    traits: [any Trait],
    sourceLocation: SourceLocation,
    containingTypeInfo: TypeInfo? = nil,
    xcTestCompatibleSelector: __XCTestCompatibleSelector? = nil,
    testCases: Test.Case.Generator<S>,
    parameters: [Parameter]
  ) {
    self.name = name
    self.displayName = displayName
    self.traits = traits
    self.sourceLocation = sourceLocation
    self.containingTypeInfo = containingTypeInfo
    self.xcTestCompatibleSelector = xcTestCompatibleSelector
    self.testCasesState = .evaluated(.init(testCases))
    self.parameters = parameters
  }
}

// MARK: - Equatable, Hashable

extension Test: Equatable, Hashable {
  public static func ==(lhs: Test, rhs: Test) -> Bool {
    lhs.id == rhs.id
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

// MARK: - Snapshotting

extension Test {
  /// A serializable snapshot of a ``Test`` instance.
  @_spi(ForToolsIntegrationOnly)
  public struct Snapshot: Sendable, Codable, Identifiable {

    private enum CodingKeys: String, CodingKey {
      case id
      case name
      case displayName
      case sourceLocation
      case testCases
      case parameters
      case comments
      case tags
      case associatedBugs
      case _timeLimit = "timeLimit"
    }

    /// The ID of this test.
    public var id: Test.ID

    /// The name of this test.
    ///
    /// ## See Also
    ///
    /// - ``Test/name``
    public var name: String

    /// The customized display name of this test, if any.
    public var displayName: String?

    /// The source location of this test.
    public var sourceLocation: SourceLocation

    /// The set of test cases associated with this test, if any.
    ///
    /// If the ``Test`` this instance was snapshotted from represented a
    /// parameterized test function but its test cases had not yet been
    /// evaluated when the snapshot was taken, or the evaluation attempt failed,
    /// the value of this property will be an empty array.
    public var testCases: [Test.Case.Snapshot]?

    /// The test function parameters, if any.
    ///
    /// ## See Also
    ///
    /// - ``Test/parameters``
    public var parameters: [Parameter]?

    /// The complete set of comments about this test from all of its traits.
    public var comments: [Comment]

    /// The complete, unique set of tags associated with this test.
    public var tags: Set<Tag>

    /// The set of bugs associated with this test.
    ///
    /// For information on how to associate a bug with a test, see the
    /// documentation for ``Bug``.
    public var associatedBugs: [Bug]

    // Backing storage for ``Test/Snapshot/timeLimit``.
    private var _timeLimit: TimeValue?

    /// The maximum amount of time a test may run for before timing out.
    @available(_clockAPI, *)
    public var timeLimit: Duration? {
      _timeLimit.map(Duration.init)
    }

    /// Initialize an instance of this type by snapshotting the specified test.
    ///
    /// - Parameters:
    ///   - test: The original test to snapshot.
    public init(snapshotting test: borrowing Test) {
      id = test.id
      name = test.name
      displayName = test.displayName
      sourceLocation = test.sourceLocation
      parameters = test.parameters
      comments = test.comments
      tags = test.tags
      associatedBugs = test.associatedBugs
      if #available(_clockAPI, *) {
        _timeLimit = test.timeLimit.map(TimeValue.init)
      }

      testCases = test.testCasesState.map { testCasesState in
        if case let .evaluated(testCases) = testCasesState {
          testCases.map(Test.Case.Snapshot.init(snapshotting:))
        } else {
          []
        }
      }
    }

    /// Whether or not this test is parameterized.
    ///
    /// ## See Also
    ///
    /// - ``Test/isParameterized``
    public var isParameterized: Bool {
      parameters?.isEmpty == false
    }

    /// Whether or not this instance is a test suite containing other tests.
    ///
    /// ## See Also
    ///
    /// - ``Test/isSuite``
    public var isSuite: Bool {
      testCases == nil
    }
  }
}
