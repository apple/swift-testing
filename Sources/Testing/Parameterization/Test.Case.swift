//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

extension Test {
  /// A single test case from a parameterized ``Test``.
  ///
  /// A test case represents a test run with a particular combination of inputs.
  /// Tests that are _not_ parameterized map to a single instance of
  /// ``Test/Case``.
  public struct Case: Sendable {
    /// An enumeration describing the various kinds of test cases.
    private enum _Kind: Sendable {
      /// A test case associated with a non-parameterized test function.
      ///
      /// There is only one test case with this kind associated with each
      /// non-parameterized test function.
      case nonParameterized

#if !hasFeature(Embedded)
      /// A test case associated with a parameterized test function.
      ///
      /// - Parameters:
      ///   - arguments: The arguments passed to the parameterized test function
      ///     this test case is associated with.
      ///   - discriminator: A number used to distinguish this test case from
      ///     others associated with the same parameterized test function whose
      ///     arguments have the same ID.
      ///   - isStable: Whether or not this test case is considered stable
      ///     across successive runs.
      case parameterized(arguments: [Argument], discriminator: Int, isStable: Bool)
#else
      /// A test case associated with a parameterized test function.
      case parameterized
#endif
    }

    /// The kind of this test case.
    private var _kind: _Kind

#if !hasFeature(Embedded)
    /// A type representing an argument passed to a parameter of a parameterized
    /// test function.
    @_spi(Experimental) @_spi(ForToolsIntegrationOnly)
    public struct Argument: Sendable {
      /// A type representing the stable, unique identifier of a parameterized
      /// test argument.
      @_spi(ForToolsIntegrationOnly)
      public struct ID: Sendable {
        /// The raw bytes of this instance's identifier.
        public var bytes: [UInt8]

        init(bytes: some Sequence<UInt8>) {
          self.bytes = Array(bytes)
        }
      }

      /// The value of this parameterized test argument.
      public var value: any Sendable

      /// The ID of this parameterized test argument.
      ///
      /// The uniqueness of this value is narrow: it is considered unique only
      /// within the scope of the parameter of the test function this argument
      /// was passed to.
      ///
      /// ## See Also
      ///
      /// - ``CustomTestArgumentEncodable``
      public var id: ID

      /// The parameter of the test function to which this argument was passed.
      public var parameter: Parameter

      init(id: ID, value: any Sendable, parameter: Parameter) {
        self.id = id
        self.value = value
        self.parameter = parameter
      }
    }

    /// The arguments passed to this test case, if any.
    ///
    /// If the argument was a tuple but its elements were passed to distinct
    /// parameters of the test function, each element of the tuple will be
    /// represented as a separate ``Argument`` instance paired with the
    /// ``Test/Parameter`` to which it was passed. However, if the test
    /// function has a single tuple parameter, the tuple will be preserved and
    /// represented as one ``Argument`` instance.
    ///
    /// Non-parameterized test functions will have a single test case instance,
    /// and the value of this property will be `nil` for such test cases.
    @_spi(Experimental) @_spi(ForToolsIntegrationOnly)
    public var arguments: [Argument]? {
      switch _kind {
      case .nonParameterized:
        nil
      case let .parameterized(arguments, _, _):
        arguments
      }
    }

    /// A number used to distinguish this test case from others associated with
    /// the same parameterized test function whose arguments have the same ID.
    ///
    /// As an example, imagine the same argument is passed more than once to a
    /// parameterized test:
    ///
    /// ```swift
    /// @Test(arguments: [1, 1])
    /// func example(x: Int) { ... }
    /// ```
    ///
    /// There will be two ``Test/Case`` instances associated with this test
    /// function. Each will represent one instance of the repeated argument `1`,
    /// and each will have a different value for this property.
    ///
    /// The value of this property for successive runs of the same test are not
    /// guaranteed to be the same. The value of this property may be equal for
    /// two test cases associated with the same test if the IDs of their
    /// arguments are different. The value of this property is `nil` for the
    /// single test case associated with a non-parameterized test function.
    @_spi(Experimental) @_spi(ForToolsIntegrationOnly)
    public internal(set) var discriminator: Int? {
      get {
        switch _kind {
        case .nonParameterized:
          nil
        case let .parameterized(_, discriminator, _):
          discriminator
        }
      }
      set {
        switch _kind {
        case .nonParameterized:
          precondition(newValue == nil, "A non-nil discriminator may only be set for a test case which is parameterized.")
        case let .parameterized(arguments, _, isStable):
          guard let newValue else {
            preconditionFailure("A nil discriminator may only be set for a test case which is not parameterized.")
          }
          _kind = .parameterized(arguments: arguments, discriminator: newValue, isStable: isStable)
        }
      }
    }

    /// Whether or not this test case is considered stable across successive
    /// runs.
    @_spi(Experimental) @_spi(ForToolsIntegrationOnly)
    public var isStable: Bool {
      switch _kind {
      case .nonParameterized:
        true
      case let .parameterized(_, _, isStable):
        isStable
      }
    }
#else
    /// Storage for ``id`` under Embedded Swift.
    ///
    /// This property cannot be `private` because it is used in another file.
    /// Code outside `Test.Case` should use ``id`` instead.
    var _id = ID()
#endif

    private init(kind: _Kind, body: nonisolated(nonsending) @escaping @Sendable () async throws -> Void) {
      _kind = kind
      _body = body
    }

    /// Initialize a test case for a non-parameterized test function.
    ///
    /// - Parameters:
    ///   - body: The body closure of this test case.
    ///
    /// The resulting test case will have zero arguments.
    init(body: nonisolated(nonsending) @escaping @Sendable () async throws -> Void) {
      self.init(kind: .nonParameterized, body: body)
    }

    /// Initialize a test case by pairing values with their corresponding
    /// parameters to form the ``arguments`` array.
    ///
    /// - Parameters:
    ///   - values: The values passed to the parameters for this test case.
    ///   - parameters: The parameters of the test function for this test case.
    ///   - body: The body closure of this test case.
    init(
      values: [any Sendable],
      parameters: [Parameter],
      body: nonisolated(nonsending) @escaping @Sendable () async throws -> Void
    ) {
#if !hasFeature(Embedded)
      var isStable = true

      let arguments = zip(values, parameters).map { value, parameter in
        var stableArgumentID: Argument.ID?

        // Attempt to get a stable, encoded representation of this value if no
        // such attempts for previous values have failed.
        if isStable {
          do {
            stableArgumentID = try .init(identifying: value, parameter: parameter)
          } catch {
            // FIXME: Capture the error and propagate to the user, not as a test
            // failure but as an advisory warning. A missing stable argument ID
            // will prevent re-running the test case, but isn't a blocking issue.
          }
        }

        let argumentID: Argument.ID
        if let stableArgumentID {
          argumentID = stableArgumentID
        } else {
          // If we couldn't get a stable representation of at least one value,
          // give up and consider the overall test case non-stable. This allows
          // skipping unnecessary work later: if any individual argument doesn't
          // have a stable ID, there's no point encoding the values which _are_
          // encodable.
          isStable = false
          argumentID = .init(bytes: String(describingForTest: value).utf8)
        }

        return Argument(id: argumentID, value: value, parameter: parameter)
      }

      self.init(kind: .parameterized(arguments: arguments, discriminator: 0, isStable: isStable), body: body)
#else
      self.init(kind: .parameterized, body: body)
#endif
    }

    /// Whether or not this test case is from a parameterized test.
    public var isParameterized: Bool {
      switch _kind {
      case .nonParameterized:
        false
      case .parameterized:
        true
      }
    }

    /// The body closure of this test case.
    private var _body: nonisolated(nonsending) @Sendable () async throws -> Void

    /// Invoke the body closure of this test case.
    ///
    /// - Parameters:
    ///   - configuration: The configuration to use for running.
    ///
    /// Do not call this function directly. Always use a ``Runner`` to invoke a
    /// test or test case.
    nonisolated(nonsending) func run(configuration: borrowing Configuration) async throws {
#if !hasFeature(Embedded)
      if let actor = configuration.defaultSynchronousIsolationContext {
        func runIsolated(to actor: isolated some Actor) async throws {
          try await _body()
        }
        return try await runIsolated(to: actor)
      }
#endif
      try await _body()
    }
  }

  /// A type representing a single parameter to a parameterized test function.
  ///
  /// This represents the parameter itself, and does not contain a specific
  /// value that might be passed via this parameter to a test function. To
  /// obtain the arguments of a particular ``Test/Case`` paired with their
  /// corresponding parameters, use ``Test/Case/arguments``.
  @_spi(Experimental) @_spi(ForToolsIntegrationOnly)
  public struct Parameter: Sendable {
    /// The zero-based index of this parameter within its associated test's
    /// parameter list.
    public var index: Int

    /// The first name of this parameter.
    public var firstName: String

    /// The second name of this parameter, if specified.
    public var secondName: String?

    /// Information about the type of this parameter.
    ///
    /// The value of this property represents the type of the parameter, but
    /// arguments passed to this parameter may be of different types. For
    /// example, an argument may be a subclass or conforming type of the
    /// declared parameter type.
    ///
    /// For information about runtime type of an argument to a parameterized
    /// test, use ``TypeInfo/init(describingTypeOf:)``, passing the argument
    /// value obtained by calling ``Test/Case/Argument/value``.
    @_spi(ForToolsIntegrationOnly)
    public var typeInfo: TypeInfo

    init(index: Int, firstName: String, secondName: String? = nil, typeInfo: TypeInfo) {
      self.index = index
      self.firstName = firstName
      self.secondName = secondName
      self.typeInfo = typeInfo
    }

#if !hasFeature(Embedded)
    init(index: Int, firstName: String, secondName: String? = nil, type: Any.Type) {
      self.init(index: index, firstName: firstName, secondName: secondName, typeInfo: TypeInfo(describing: type))
    }
#endif
  }
}

#if !SWT_NO_CODABLE
// MARK: - Codable

extension Test.Parameter: Codable {}
extension Test.Case.Argument.ID: Codable {}
#endif

// MARK: - Equatable, Hashable

#if !hasFeature(Embedded)
extension Test.Parameter: Hashable {}
extension Test.Case.Argument.ID: Hashable {}
#endif

#if !SWT_NO_SNAPSHOT_TYPES
// MARK: - Snapshotting

extension Test.Case {
  /// A serializable snapshot of a ``Test/Case`` instance.
  @_spi(ForToolsIntegrationOnly)
  public struct Snapshot: Sendable, Codable {
    /// The ID of this test case.
    public var id: ID

    /// The arguments passed to this test case.
    public var arguments: [Argument.Snapshot]

    /// Whether or not this test case is from a parameterized test.
    public var isParameterized: Bool {
      !arguments.isEmpty
    }

    /// Initialize an instance of this type by snapshotting the specified test
    /// case.
    ///
    /// - Parameters:
    ///   - testCase: The original test case to snapshot.
    public init(snapshotting testCase: borrowing Test.Case) {
      id = testCase.id
      arguments = if let arguments = testCase.arguments {
        arguments.map(Test.Case.Argument.Snapshot.init)
      } else {
        []
      }
    }
  }
}

extension Test.Case.Argument {
  /// A serializable snapshot of a ``Test/Case/Argument`` instance.
  @_spi(ForToolsIntegrationOnly)
  public struct Snapshot: Sendable, Codable {
    /// The ID of this parameterized test argument, if any.
    public var id: Test.Case.Argument.ID?

    /// A representation of this parameterized test argument's
    /// ``Test/Case/Argument/value`` property.
    public var value: Expression.Value

    /// The parameter of the test function to which this argument was passed.
    public var parameter: Test.Parameter

    /// Initialize an instance of this type by snapshotting the specified test
    /// case argument.
    ///
    /// - Parameters:
    ///   - argument: The original test case argument to snapshot.
    public init(snapshotting argument: Test.Case.Argument) {
      id = argument.id
      value = Expression.Value(reflecting: argument.value) ?? .init(describing: argument.value)
      parameter = argument.parameter
    }
  }
}
#endif
