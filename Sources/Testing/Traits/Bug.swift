//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

/// A type representing a bug report tracked by a test.
///
/// To add this trait to a test, use one of the following functions:
///
/// - ``Trait/bug(_:relationship:)-duvt``
/// - ``Trait/bug(_:relationship:)-40riy``
public struct Bug {
  /// The identifier of this bug in the associated bug-tracking system.
  ///
  /// For more information on how the testing library interprets bug
  /// identifiers, see <doc:interpreting-bug-identifiers>.
  public var identifier: String

  /// An enumeration describing the relationship of a bug to a test.
  ///
  /// For more information on how the testing library uses bug relationships,
  /// see <doc:associating-bugs-with-tests>.
  public enum Relationship: Sendable, Equatable, Hashable {
    /// The relationship between the test and this bug is unspecified.
    ///
    /// Use this relationship to describe a bug that is related to a test, but
    /// not in any specific way.
    case unspecified

    /// The test uncovered this bug.
    ///
    /// Use this relationship to describe a bug that was filed as a result of a
    /// test failing.
    case uncoveredBug

    /// The test reproduces the bug.
    ///
    /// Use this relationship to describe a bug that the test is able to
    /// reproduce consistently.
    case reproducesBug

    /// The test verifies that the bug has been fixed.
    ///
    /// Use this relationship when the associated test is meant to verify that
    /// the bug has been fixed.
    case verifiesFix

    /// The test is failing because of the bug.
    ///
    /// Use this relationship when the associated test is not directly related
    /// to the bug, but is failing because the bug has not been fixed yet.
    case failingBecauseOfBug
  }

  /// The relationship between the bug and the associated test.
  ///
  /// For more information on how the testing library uses bug relationships,
  /// see <doc:associating-bugs-with-tests>.
  public var relationship: Relationship
}

// MARK: - Equatable, Hashable, Comparable

extension Bug: Equatable, Hashable, Comparable {
  public static func ==(lhs: Self, rhs: Self) -> Bool {
    lhs.identifier == rhs.identifier
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(identifier)
  }

  public static func <(lhs: Self, rhs: Self) -> Bool {
    lhs.identifier < rhs.identifier
  }
}

// MARK: - Trait, TestTrait, SuiteTrait

extension Bug: TestTrait, SuiteTrait {}

extension Trait where Self == Bug {
  /// Construct a bug to track with a test.
  ///
  /// - Parameters:
  ///   - identifier: The identifier of this bug in the associated bug-tracking
  ///     system. For more information on how this value is interpreted, see the
  ///     documentation for ``Bug``.
  ///   - relationship: The relationship between the bug and the associated
  ///     test. The default value is
  ///     ``Bug/Relationship-swift.enum/unspecified``.
  ///
  /// - Returns: An instance of ``Bug`` representing the specified bug.
  public static func bug(_ identifier: String, relationship: Bug.Relationship = .unspecified) -> Self {
    Self(identifier: identifier, relationship: relationship)
  }

  /// Construct a bug to track with a test.
  ///
  /// - Parameters:
  ///   - identifier: The identifier of this bug in the associated bug-tracking
  ///     system. For more information on how this value is interpreted, see the
  ///     documentation for ``Bug``.
  ///   - relationship: The relationship between the bug and the associated
  ///     test. The default value is
  ///     ``Bug/Relationship-swift.enum/unspecified``.
  ///
  /// - Returns: An instance of ``Bug`` representing the specified bug.
  public static func bug(_ identifier: some Numeric, relationship: Bug.Relationship = .unspecified) -> Self {
    Self(identifier: String(describing: identifier), relationship: relationship)
  }
}

// MARK: -

extension Test {
  /// The set of bugs associated with this test.
  ///
  /// For information on how to associate a bug with a test, see the
  /// documentation for ``Bug``.
  public var associatedBugs: [Bug] {
    traits.compactMap { $0 as? Bug }
  }
}
