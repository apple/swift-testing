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
  /// The source code of the expression evaluated by this expectation, if
  /// available at compile time.
  public var sourceCode: SourceCode?

  /// A description of the error mismatch that occurred, if any.
  ///
  /// If this expectation passed, the value of this property is `nil` because no
  /// error mismatch occurred.
  @_spi(ExperimentalEventHandling)
  public var mismatchedErrorDescription: String?

  /// A description of the expression evaluated by this expectation, expanded
  /// to include the values of any evaluated sub-expressions, if the source code
  /// was available at compile time.
  ///
  /// If this expectation passed, the value of this property is `nil` because
  /// source code expansion is only performed when necessary to assist with
  /// diagnosing test failures.
  @_spi(ExperimentalEventHandling)
  public var expandedExpressionDescription: String?

  /// An opaque value that describes the difference between two values or
  /// collections that have been compared.
  ///
  /// If this expectation did not involve the comparison of two values or
  /// collections, the value of this property is `nil`.
  ///
  /// If this expectation passed, the value of this property will be `nil`
  /// because the difference is only computed when necessary to assist with
  /// diagnosing failures.
  @_spi(ExperimentalEventHandling)
  public var difference: Difference?

  /// Whether the expectation passed or failed.
  ///
  /// An expectation is considered to pass when its condition evaluates to
  /// `true`. If it evaluates to `false`, it fails instead.
  public var isPassing: Bool

  /// Whether or not the expectation was required to pass.
  public var isRequired: Bool

  /// The source location where this expectation was evaluated.
  public var sourceLocation: SourceLocation
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

// MARK: - Snapshot

extension Expectation {
  /// A serializable type describing an expectation that has been evaluated.
  @_spi(ExperimentalSnapshotting)
  public struct Snapshot: Sendable, Codable {
    /// The source code description (as a String) of the expression evaluated by
    /// this expectation, if available at compile time.
    public var sourceCodeDescription: String?

    /// A description of the error mismatch that occurred, if any.
    ///
    /// If this expectation passed, the value of this property is `nil` because no
    /// error mismatch occurred.
    @_spi(ExperimentalEventHandling)
    public var mismatchedErrorDescription: String?

    /// A description of the expression evaluated by this expectation, expanded
    /// to include the values of any evaluated sub-expressions, if the source code
    /// was available at compile time.
    ///
    /// If this expectation passed, the value of this property is `nil` because
    /// source code expansion is only performed when necessary to assist with
    /// diagnosing test failures.
    @_spi(ExperimentalEventHandling)
    public var expandedExpressionDescription: String?

    /// A description of the difference between the operands in the expression
    /// evaluated by this expectation, if the difference could be determined.
    ///
    /// If this expectation passed, the value of this property is `nil` because
    /// the difference is only computed when necessary to assist with diagnosing
    /// test failures.
    @_spi(ExperimentalEventHandling)
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
    public init(snapshotting expectation: Expectation) {
      self.sourceCodeDescription = String(describing: expectation.sourceCode)
      self.mismatchedErrorDescription = expectation.mismatchedErrorDescription
      self.expandedExpressionDescription = expectation.expandedExpressionDescription
      self.differenceDescription = expectation.differenceDescription
      self.isPassing = expectation.isPassing
      self.isRequired = expectation.isRequired
      self.sourceLocation = expectation.sourceLocation
    }
  }
}
