//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if os(Windows)
internal import WinSDK

extension GUID {
  /// A type that wraps `GUID` instances and conforms to various Swift
  /// protocols.
  ///
  /// - Bug: This type will become obsolete once we can use the `Equatable` and
  ///   `Hashable` conformances added to the WinSDK module in Swift 6.3.
#if compiler(>=6.3.1) && DEBUG
  @available(*, deprecated, message: "GUID.Wrapper is no longer needed and can be removed.")
#endif
  struct Wrapper: Sendable, RawRepresentable {
    var rawValue: GUID
  }
}

// MARK: -

extension GUID.Wrapper: Equatable, Hashable, CustomStringConvertible {
  init(_ rawValue: GUID) {
    self.init(rawValue: rawValue)
  }

#if compiler(<6.3.1)
  private var _uint128Value: UInt128 {
    withUnsafeBytes(of: rawValue) { buffer in
      buffer.baseAddress!.loadUnaligned(as: UInt128.self)
    }
  }

  static func ==(lhs: Self, rhs: Self) -> Bool {
    lhs._uint128Value == rhs._uint128Value
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(_uint128Value)
  }

  var description: String {
    String(describing: rawValue)
  }
#endif
}
#endif
