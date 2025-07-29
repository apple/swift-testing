//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024–2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

extension ABI {
  /// A type describing an ABI version number.
  ///
  /// This type implements a subset of the [semantic versioning](https://semver.org)
  /// specification (specifically parsing, displaying, and comparing
  /// `<version core>` values we expect that Swift will need for the foreseeable
  /// future.)
  struct VersionNumber: Sendable {
    /// The major version.
    var majorComponent: Int8

    /// The minor version.
    var minorComponent: Int8

    /// The patch, revision, or bug fix version.
    var patchComponent: Int8 = 0
  }
}

extension ABI.VersionNumber {
  init(_ majorComponent: _const Int8, _ minorComponent: _const Int8, _ patchComponent: _const Int8 = 0) {
    self.init(majorComponent: majorComponent, minorComponent: minorComponent, patchComponent: patchComponent)
  }
}

// MARK: - CustomStringConvertible

extension ABI.VersionNumber: CustomStringConvertible {
  /// Initialize an instance of this type by parsing the given string.
  ///
  /// - Parameters:
  ///   - string: The string to parse, such as `"0"` or `"6.3.0"`.
  ///
  /// @Comment {
  ///   - Bug: We are not able to reuse the logic from swift-syntax's
  ///     `VersionTupleSyntax` type here because we cannot link to swift-syntax
  ///     in this target.
  /// }
  ///
  /// If `string` contains fewer than 3 numeric components, the missing
  /// components are inferred to be `0` (for example, `"1.2"` is equivalent to
  /// `"1.2.0"`.) If `string` contains more than 3 numeric components, the
  /// additional components are ignored.
  init?(_ string: String) {
    // Split the string on "." (assuming it is of the form "1", "1.2", or
    // "1.2.3") and parse the individual components as integers.
    let components = string.split(separator: ".", omittingEmptySubsequences: false)
    func componentValue(_ index: Int) -> Int8? {
      components.count > index ? Int8(components[index]) : 0
    }

    guard let majorComponent = componentValue(0),
          let minorComponent = componentValue(1),
          let patchComponent = componentValue(2) else {
      return nil
    }
    self.init(majorComponent: majorComponent, minorComponent: minorComponent, patchComponent: patchComponent)
  }

  var description: String {
    if majorComponent <= 0 && minorComponent == 0 && patchComponent == 0 {
      // Version 0 and earlier are described as integers for compatibility with
      // Swift 6.2 and earlier.
      return String(describing: majorComponent)
    } else if patchComponent == 0 {
      return "\(majorComponent).\(minorComponent)"
    }
    return "\(majorComponent).\(minorComponent).\(patchComponent)"
  }
}

// MARK: - Equatable, Comparable

extension ABI.VersionNumber: Equatable, Comparable {
  static func <(lhs: Self, rhs: Self) -> Bool {
    if lhs.majorComponent != rhs.majorComponent {
      return lhs.majorComponent < rhs.majorComponent
    } else if lhs.minorComponent != rhs.minorComponent {
      return lhs.minorComponent < rhs.minorComponent
    } else if lhs.patchComponent != rhs.patchComponent {
      return lhs.patchComponent < rhs.patchComponent
    }
    return false
  }
}

// MARK: - Codable

extension ABI.VersionNumber: Codable {
  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let number = try? container.decode(Int8.self) {
      // Allow for version numbers encoded as integers for compatibility with
      // Swift 6.2 and earlier.
      self.init(majorComponent: number, minorComponent: 0)
    } else {
      let string = try container.decode(String.self)
      guard let result = Self(string) else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "Unexpected string '\(string)' (expected an integer or a string of the form '1.2.3')"
          )
        )
      }
      self = result
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    if majorComponent <= 0 && minorComponent == 0 && patchComponent == 0 {
      // Version 0 and earlier are encoded as integers for compatibility with
      // Swift 6.2 and earlier.
      try container.encode(majorComponent)
    } else {
      try container.encode("\(majorComponent).\(minorComponent).\(patchComponent)")
    }
  }
}
