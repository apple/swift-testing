//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

/// A type describing an expectation that has been evaluated.
public struct Expectation: Sendable {
  /// The expression evaluated by this expectation.
  @_spi(ForToolsIntegrationOnly)
  public var evaluatedExpression: Expression

  /// A description of the error mismatch that occurred, if any.
  ///
  /// If this expectation passed, the value of this property is `nil` because no
  /// error mismatch occurred.
  public var mismatchedErrorDescription: String?

  /// A description of the difference between the operands in the expression
  /// evaluated by this expectation, if the difference could be determined.
  ///
  /// If this expectation passed, the value of this property is `nil` because
  /// the difference is only computed when necessary to assist with diagnosing
  /// test failures.
  public var differenceDescription: String?

  /// Whether the expectation passed or failed.
  ///
  /// An expectation is considered to pass when its condition evaluates to
  /// `true`. If it evaluates to `false`, it fails instead.
  public var isPassing: Bool

  /// Whether or not the expectation was required to pass.
  public var isRequired: Bool

  /// The source location where this expectation was evaluated.
  public var sourceLocation: SourceLocation

  ///
  public init(
    mismatchedErrorDescription: String? = nil,
    differenceDescription: String? = nil,
    isPassing: Bool,
    isRequired: Bool,
    sourceLocation: SourceLocation
  ) {
    self.evaluatedExpression = Expression("")
    self.mismatchedErrorDescription = mismatchedErrorDescription
    self.differenceDescription = differenceDescription
    self.isPassing = isPassing
    self.isRequired = isRequired
    self.sourceLocation = sourceLocation
  }

  init(
    evaluatedExpression: Expression,
    mismatchedErrorDescription: String? = nil,
    differenceDescription: String? = nil,
    isPassing: Bool,
    isRequired: Bool,
    sourceLocation: SourceLocation
  ) {
    self.evaluatedExpression = evaluatedExpression
    self.mismatchedErrorDescription = mismatchedErrorDescription
    self.differenceDescription = differenceDescription
    self.isPassing = isPassing
    self.isRequired = isRequired
    self.sourceLocation = sourceLocation
  }
}

/// A type describing an error thrown when an expectation fails during
/// evaluation.
///
/// The testing library throws instances of this type when the `#require()`
/// macro records an issue.
public struct ExpectationFailedError: Error {
  /// The expectation that failed.
  public var expectation: Expectation
}

// MARK: - Snapshotting

extension Expectation {
  /// A serializable type describing an expectation that has been evaluated.
  @_spi(ForToolsIntegrationOnly)
  public struct Snapshot: Sendable, Codable {
    /// The expression evaluated by this expectation.
    public var evaluatedExpression: Expression

    /// A description of the error mismatch that occurred, if any.
    ///
    /// If this expectation passed, the value of this property is `nil` because no
    /// error mismatch occurred.
    public var mismatchedErrorDescription: String?

    /// A description of the difference between the operands in the expression
    /// evaluated by this expectation, if the difference could be determined.
    ///
    /// If this expectation passed, the value of this property is `nil` because
    /// the difference is only computed when necessary to assist with diagnosing
    /// test failures.
    public var differenceDescription: String?

    /// Whether the expectation passed or failed.
    ///
    /// An expectation is considered to pass when its condition evaluates to
    /// `true`. If it evaluates to `false`, it fails instead.
    public var isPassing: Bool

    /// Whether or not the expectation was required to pass.
    public var isRequired: Bool

    /// The source location where this expectation was evaluated.
    public var sourceLocation: SourceLocation

    /// Creates a snapshot expectation from a real ``Expectation``.
    /// - Parameter expectation: The real expectation.
    public init(snapshotting expectation: borrowing Expectation) {
      self.evaluatedExpression = expectation.evaluatedExpression
      self.mismatchedErrorDescription = expectation.mismatchedErrorDescription
      self.differenceDescription = expectation.differenceDescription
      self.isPassing = expectation.isPassing
      self.isRequired = expectation.isRequired
      self.sourceLocation = expectation.sourceLocation
    }
  }
}
