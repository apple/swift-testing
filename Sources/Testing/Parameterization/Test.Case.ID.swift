//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if canImport(Synchronization)
private import Synchronization
#endif

extension Test.Case {
  /// The ID of a test case.
  ///
  /// Instances of this type are considered unique within the scope of a given
  /// parameterized test function. They are not necessarily unique across two
  /// different ``Test`` instances.
  @_spi(ForToolsIntegrationOnly)
  public struct ID: Sendable {
#if !hasFeature(Embedded)
    /// The IDs of the arguments of this instance's associated ``Test/Case``.
    ///
    /// For a parameterized test case, this array contains a single element: an
    /// ``Test/Case/Argument/ID-swift.struct`` that combines the IDs of every
    /// argument. The value of this property is `nil` for the ID of the single
    /// test case associated with a non-parameterized test function.
    public var argumentIDs: [Argument.ID]?

    /// A number used to distinguish this test case from others associated with
    /// the same parameterized test function whose arguments have the same ID.
    ///
    /// The value of this property is `nil` for the ID of the single test case
    /// associated with a non-parameterized test function.
    ///
    /// ## See Also
    ///
    /// - ``Test/Case/discriminator``
    public var discriminator: Int?

    /// Whether or not this test case ID is considered stable across successive
    /// runs.
    public var isStable: Bool

    init(argumentIDs: [Argument.ID]?, discriminator: Int?, isStable: Bool) {
      precondition((argumentIDs == nil) == (discriminator == nil))

      self.argumentIDs = argumentIDs
      self.discriminator = discriminator
      self.isStable = isStable
    }
#else
    /// The next ID's sequence number.
    private static let _nextSequenceNumber = Atomic<Int>(0)

    /// The sequence number of this instance.
    private var _sequenceNumber: Int

    init() {
      _sequenceNumber = Self._nextSequenceNumber.add(1, ordering: .sequentiallyConsistent).oldValue
    }

    public var isStable: Bool {
      false
    }
#endif
  }

  @_spi(ForToolsIntegrationOnly)
  public var id: ID {
#if !hasFeature(Embedded)
    let argumentIDs = arguments.map { [Argument.ID(combining: $0.map { $0.id })] }
    return ID(argumentIDs: argumentIDs, discriminator: discriminator, isStable: isStable)
#else
    _id
#endif
  }
}

// MARK: - CustomStringConvertible

extension Test.Case.ID: CustomStringConvertible {
  public var description: String {
#if !hasFeature(Embedded)
    if let argumentIDs, let discriminator {
      "Parameterized test case ID: argumentIDs: \(argumentIDs), discriminator: \(discriminator), isStable: \(isStable)"
    } else {
      "Non-parameterized test case ID"
    }
#else
    "Test case ID \(_sequenceNumber)"
#endif
  }
}

#if !SWT_NO_CODABLE
// MARK: - Codable

extension Test.Case.ID: Codable {
  private enum CodingKeys: String, CodingKey {
    /// A coding key for ``Test/Case/ID/argumentIDs``.
    ///
    /// This case's string value is non-standard because a previous legacy argument ID
    /// key used it, and clients have adjusted to this one.
    case argumentIDs = "argIDs"

    /// A coding key for ``Test/Case/ID/discriminator``.
    case discriminator

    /// A coding key for ``Test/Case/ID/isStable``.
    case isStable
  }
}
#endif

// MARK: - Equatable, Hashable

extension Test.Case.ID: Equatable, Hashable {}
