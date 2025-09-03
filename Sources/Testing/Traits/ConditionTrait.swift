//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

/// A type that defines a condition which must be satisfied for the testing
/// library to enable a test.
///
/// To add this trait to a test, use one of the following functions:
///
/// - ``Trait/enabled(if:_:sourceLocation:)``
/// - ``Trait/enabled(_:sourceLocation:_:)``
/// - ``Trait/disabled(_:sourceLocation:)``
/// - ``Trait/disabled(if:_:sourceLocation:)``
/// - ``Trait/disabled(_:sourceLocation:_:)``
public struct ConditionTrait: TestTrait, SuiteTrait {
  /// An enumeration that describes the conditions that an instance of this type
  /// can represent.
  enum Kind: Sendable {
    /// Enabling the test is conditional on the result of calling a function.
    ///
    /// - Parameters:
    ///   - body: The function to call. The result of this function determines
    ///     if the condition is satisfied or not.
    case conditional(_ body: @Sendable () async throws -> Bool)

    /// The trait is unconditional and always has the same result.
    ///
    /// - Parameters:
    ///   - value: Whether or not the test is enabled.
    case unconditional(_ value: Bool)
  }

  /// The kind of condition represented by this trait.
  var kind: Kind

  /// Whether this trait's condition is constant, or evaluated at runtime.
  ///
  /// If this trait was created using a function such as
  /// ``disabled(_:sourceLocation:)`` that unconditionally enables or disables a
  /// test, the value of this property is `true`.
  ///
  /// If this trait was created using a function such as
  /// ``enabled(if:_:sourceLocation:)`` that is evaluated at runtime, the value
  /// of this property is `false`.
  @_spi(ForToolsIntegrationOnly)
  public var isConstant: Bool {
    switch kind {
    case .conditional:
      return false
    case .unconditional:
      return true
    }
  }

  public var comments: [Comment]

  /// The source location where this trait is specified.
  public var sourceLocation: SourceLocation
  
  /// Evaluate this instance's underlying condition.
  ///
  /// - Returns: The result of evaluating this instance's underlying condition.
  ///
  /// The evaluation is performed each time this function is called, and is not
  /// cached.
  /// 
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.2)
  ///   @Available(Xcode, introduced: 26.0)
  /// }
  public func evaluate() async throws -> Bool {
    switch kind {
    case let .conditional(condition):
      try await condition()
    case let .unconditional(unconditionalValue):
      unconditionalValue
    }
  }

  public func prepare(for test: Test) async throws {
    let isEnabled = try await evaluate()
    if !isEnabled {
      // We don't need to consider including a backtrace here because it will
      // primarily contain frames in the testing library, not user code. If an
      // error was thrown by a condition evaluated above, the caller _should_
      // attempt to get the backtrace of the caught error when creating an issue
      // for it, however.
      try Test.cancel(comments.first, sourceLocation: sourceLocation)
    }
  }

  public var isRecursive: Bool {
    true
  }
}

// MARK: -

extension Trait where Self == ConditionTrait {
  /// Constructs a condition trait that disables a test if it returns `false`.
  ///
  /// - Parameters:
  ///   - condition: A closure that contains the trait's custom condition logic.
  ///     If this closure returns `true`, the trait allows the test to run.
  ///     Otherwise, the testing library skips the test.
  ///   - comment: An optional comment that describes this trait.
  ///   - sourceLocation: The source location of the trait.
  ///
  /// - Returns: An instance of ``ConditionTrait`` that evaluates the
  ///   closure you provide.
  ///
  /// @Comment {
  ///   - Bug: `condition` cannot be `async` without making this function
  ///     `async` even though `condition` is not evaluated locally.
  ///     ([103037177](rdar://103037177))
  /// }
  public static func enabled(
    if condition: @autoclosure @escaping @Sendable () throws -> Bool,
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
  ) -> Self {
    Self(kind: .conditional(condition), comments: Array(comment), sourceLocation: sourceLocation)
  }

  /// Constructs a condition trait that disables a test if it returns `false`.
  ///
  /// - Parameters:
  ///   - comment: An optional comment that describes this trait.
  ///   - sourceLocation: The source location of the trait.
  ///   - condition: A closure that contains the trait's custom condition logic.
  ///     If this closure returns `true`, the trait allows the test to run.
  ///     Otherwise, the testing library skips the test.
  ///
  /// - Returns: An instance of ``ConditionTrait`` that evaluates the
  ///   closure you provide.
  public static func enabled(
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: @escaping @Sendable () async throws -> Bool
  ) -> Self {
    Self(kind: .conditional(condition), comments: Array(comment), sourceLocation: sourceLocation)
  }

  /// Constructs a condition trait that disables a test unconditionally.
  ///
  /// - Parameters:
  ///   - comment: An optional comment that describes this trait.
  ///   - sourceLocation: The source location of the trait.
  ///
  /// - Returns: An instance of ``ConditionTrait`` that always disables the
  ///   test to which it is added.
  public static func disabled(
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
  ) -> Self {
    Self(kind: .unconditional(false), comments: Array(comment), sourceLocation: sourceLocation)
  }

  /// Constructs a condition trait that disables a test if its value is true.
  ///
  /// - Parameters:
  ///   - condition: A closure that contains the trait's custom condition logic.
  ///     If this closure returns `false`, the trait allows the test to run.
  ///     Otherwise, the testing library skips the test.
  ///   - comment: An optional comment that describes this trait.
  ///   - sourceLocation: The source location of the trait.
  ///
  /// - Returns: An instance of ``ConditionTrait`` that evaluates the
  ///   closure you provide.
  ///
  /// @Comment {
  ///   - Bug: `condition` cannot be `async` without making this function
  ///     `async` even though `condition` is not evaluated locally.
  ///     ([103037177](rdar://103037177))
  /// }
  public static func disabled(
    if condition: @autoclosure @escaping @Sendable () throws -> Bool,
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
  ) -> Self {
    Self(kind: .conditional { !(try condition()) }, comments: Array(comment), sourceLocation: sourceLocation)
  }

  /// Constructs a condition trait that disables a test if its value is true.
  ///
  /// - Parameters:
  ///   - comment: An optional comment that describes this trait.
  ///   - sourceLocation: The source location of the trait.
  ///   - condition: A closure that contains the trait's custom condition logic.
  ///     If this closure returns `false`, the trait allows the test to run.
  ///     Otherwise, the testing library skips the test.
  ///
  /// - Returns: An instance of ``ConditionTrait`` that evaluates the
  ///   specified closure.
  public static func disabled(
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: @escaping @Sendable () async throws -> Bool
  ) -> Self {
    Self(kind: .conditional { !(try await condition()) }, comments: Array(comment), sourceLocation: sourceLocation)
  }
}
