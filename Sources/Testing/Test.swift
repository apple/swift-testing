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
  /// A type describing the indirectly stored properties of ``Test``.
  ///
  /// For a description of this type's properties, see the corresponding
  /// properties on ``Test`` itself.
  private struct _Properties: Sendable {
    var name: String
    var displayName: String?
    var traits: [any Trait]
    var sourceBounds: __SourceBounds
    var containingTypeInfo: TypeInfo?
    var xcTestCompatibleSelector: __XCTestCompatibleSelector?
    var testCasesState: TestCasesState?
    var parameters: [Parameter]?
    var isSynthesized: Bool
#if DEBUG
    var mutationCount = 0
#endif
  }

  /// Storage for most of the properties of this instance.
  private var _properties: Allocated<_Properties>

  /// Mutate a single property stored in `_properties`.
  ///
  /// - Parameters:
  ///   - newValue: The new value to assign.
  ///   - keyPath: The key path to modify.
  private mutating func _setValue<V>(_ newValue: consuming V, forKeyPath keyPath: WritableKeyPath<_Properties, V>) {
    var properties = _properties.value
    properties[keyPath: keyPath] = newValue
#if DEBUG
    properties.mutationCount += 1
#endif
    _properties = Allocated(properties)
  }

  /// The name of this instance.
  ///
  /// The value of this property is equal to the name of the symbol to which the
  /// ``Test`` attribute is applied (that is, the name of the type or function.)
  /// To get the customized display name specified as part of the ``Test``
  /// attribute, use the ``Test/displayName`` property.
  public var name: String {
    get {
      _properties.value.name
    }
    set {
      _setValue(newValue, forKeyPath: \.name)
    }
  }

  /// The customized display name of this instance, if specified.
  public var displayName: String? {
    get {
      _properties.value.displayName
    }
    set {
      _setValue(newValue, forKeyPath: \.displayName)
    }
  }

  /// The set of traits added to this instance when it was initialized.
  public var traits: [any Trait] {
    get {
      _properties.value.traits
    }
    set {
      // Prevent programmatically adding suite traits to test functions or test
      // traits to test suites.
      func traitsAreCorrectlyTyped() -> Bool {
        if isSuite {
          return newValue.allSatisfy { $0.__as((any SuiteTrait).self) != nil }
        } else {
          return newValue.allSatisfy { $0.__as((any TestTrait).self) != nil }
        }
      }
      precondition(traitsAreCorrectlyTyped(), "Programmatically added an inapplicable trait to test \(self)")
      _setValue(newValue, forKeyPath: \.traits)
    }
  }

  /// The source location of this test.
  public var sourceLocation: SourceLocation {
    get {
      sourceBounds.lowerBound
    }
    set {
      sourceBounds = __SourceBounds(lowerBoundOnly: newValue)
    }
  }

  /// The source bounds of this test.
  var sourceBounds: __SourceBounds {
    get {
      _properties.value.sourceBounds
    }
    set {
      _setValue(newValue, forKeyPath: \.sourceBounds)
    }
  }

  /// Information about the type containing this test, if any.
  ///
  /// If a test is associated with a free function or static function, the value
  /// of this property is `nil`. To determine if a specific instance of ``Test``
  /// refers to this type itself, check the ``isSuite`` property.
  var containingTypeInfo: TypeInfo? {
    get {
      _properties.value.containingTypeInfo
    }
    set {
      _setValue(newValue, forKeyPath: \.containingTypeInfo)
    }
  }

#if !hasFeature(Embedded)
  /// The XCTest-compatible Objective-C selector corresponding to this
  /// instance's underlying test function.
  ///
  /// On platforms that do not support Objective-C interop, the value of this
  /// property is always `nil`.
  @_spi(ForToolsIntegrationOnly)
  public var xcTestCompatibleSelector: __XCTestCompatibleSelector? {
    get {
      _properties.value.xcTestCompatibleSelector
    }
    set {
      _setValue(newValue, forKeyPath: \.xcTestCompatibleSelector)
    }
  }
#endif

  /// An enumeration describing the evaluation state of a test's cases.
  fileprivate enum TestCasesState: Sendable {
    /// The test's cases have not yet been evaluated.
    ///
    /// - Parameters:
    ///   - function: The function to call to evaluate the test's cases. The
    ///     result is a sequence of test cases.
    case unevaluated(_ function: @Sendable () async throws -> AnySendableSequence<Test.Case>)

    /// The test's cases have been evaluated.
    ///
    /// - Parameters:
    ///   - testCases: The test's cases.
    case evaluated(_ testCases: AnySendableSequence<Test.Case>)

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
  fileprivate var testCasesState: TestCasesState? {
    get {
      _properties.value.testCasesState
    }
    set {
      _setValue(newValue, forKeyPath: \.testCasesState)
    }
  }

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
#if !hasFeature(Embedded)
        preconditionFailure("Attempting to access test cases with invalid state. \(fileABugMessage(context: String(reflecting: testCasesState)))")
#else
        preconditionFailure("Attempting to access test cases with invalid state. \(fileABugMessage)")
#endif
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
  @_spi(Experimental) @_spi(ForToolsIntegrationOnly)
  public var parameters: [Parameter]? {
    get {
      _properties.value.parameters
    }
    set {
      _setValue(newValue, forKeyPath: \.parameters)
    }
  }

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
  public var isSynthesized: Bool {
    get {
      _properties.value.isSynthesized
    }
    set {
      _setValue(newValue, forKeyPath: \.isSynthesized)
    }
  }

#if DEBUG
  /// The number of times any property on this instance of ``Test`` has been
  /// mutated after initialization.
  var mutationCount: Int {
    _properties.value.mutationCount
  }
#endif

  /// Initialize an instance of this type representing a test suite type.
  init(
    displayName: String? = nil,
    traits: [any Trait],
    sourceLocation: SourceLocation,
    containingTypeInfo: TypeInfo,
    isSynthesized: Bool = false
  ) {
    let name = containingTypeInfo.unqualifiedName
    var displayName = displayName
    if displayName == nil && isSynthesized,
       name.count > 2 && name.first == "`" && name.last == "`" {
      displayName = String(name.dropFirst().dropLast())
    }
    let sourceBounds = __SourceBounds(lowerBoundOnly: sourceLocation)
    let properties = _Properties(
      name: name,
      displayName: displayName,
      traits: traits,
      sourceBounds: sourceBounds,
      containingTypeInfo: containingTypeInfo,
      isSynthesized: isSynthesized
    )
    _properties = Allocated(properties)
  }

  /// Initialize an instance of this type representing a test function.
  init<S>(
    name: String,
    displayName: String? = nil,
    traits: [any Trait],
    sourceBounds: __SourceBounds,
    containingTypeInfo: TypeInfo? = nil,
    xcTestCompatibleSelector: __XCTestCompatibleSelector? = nil,
    testCases: @escaping @Sendable () async throws -> Test.Case.Generator<S>,
    parameters: [Parameter]
  ) {
    let properties = _Properties(
      name: name,
      displayName: displayName,
      traits: traits,
      sourceBounds: sourceBounds,
      containingTypeInfo: containingTypeInfo,
      xcTestCompatibleSelector: xcTestCompatibleSelector,
      testCasesState: .unevaluated { try await AnySendableSequence(testCases()) },
      parameters: parameters,
      isSynthesized: false
    )
    _properties = Allocated(properties)
  }

  /// Initialize an instance of this type representing a test function.
  init<S>(
    name: String,
    displayName: String? = nil,
    traits: [any Trait],
    sourceBounds: __SourceBounds,
    containingTypeInfo: TypeInfo? = nil,
    xcTestCompatibleSelector: __XCTestCompatibleSelector? = nil,
    testCases: Test.Case.Generator<S>,
    parameters: [Parameter]
  ) {
    let properties = _Properties(
      name: name,
      displayName: displayName,
      traits: traits,
      sourceBounds: sourceBounds,
      containingTypeInfo: containingTypeInfo,
      xcTestCompatibleSelector: xcTestCompatibleSelector,
      testCasesState: .evaluated(AnySendableSequence(testCases)),
      parameters: parameters,
      isSynthesized: false
    )
    _properties = Allocated(properties)
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

#if !SWT_NO_SNAPSHOT_TYPES
// MARK: - Snapshotting

#if SWT_NO_CODABLE
#error("Platform-specific misconfiguration: support for snapshot types requires support for 'Codable'")
#endif

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
    public var timeLimit: Duration? {
      _timeLimit?.rawValue
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
      _timeLimit = test.timeLimit.map(TimeValue.init)

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
#endif
