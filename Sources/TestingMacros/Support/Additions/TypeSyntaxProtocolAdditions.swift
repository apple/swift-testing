//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

import SwiftSyntax

extension TypeSyntaxProtocol {
  /// Whether or not this type is an optional type (`T?`, `Optional<T>`, etc.)
  var isOptional: Bool {
    if `is`(OptionalTypeSyntax.self) {
      return true
    } else if `is`(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
      return true
    }
    return isNamed("Optional", inModuleNamed: "Swift")
  }

  /// Whether or not this type is equivalent to `Void`.
  var isVoid: Bool {
    if let tuple = `as`(TupleTypeSyntax.self) {
      return tuple.elements.isEmpty
    }
    return isNamed("Void", inModuleNamed: "Swift")
  }

  /// Whether or not this type is `some T` or a type derived from such a type.
  var isSome: Bool {
    tokens(viewMode: .fixedUp).lazy
      .map(\.tokenKind)
      .contains(.keyword(.some))
  }

  /// Whether or not this type is `any T` or a type derived from such a type.
  var isAny: Bool {
    tokens(viewMode: .fixedUp).lazy
      .map(\.tokenKind)
      .contains(.keyword(.any))
  }

  /// Check whether or not this type is named with the specified name and
  /// module.
  ///
  /// The type name is checked both without and with the specified module name
  /// as a prefix to allow for either syntax. When comparing the type name,
  /// generic type parameters are ignored.
  ///
  /// - Parameters:
  ///   - name: The `"."`-separated type name to compare against.
  ///   - moduleName: The module the specified type is declared in.
  ///
  /// - Returns: Whether or not this type has the given name.
  func isNamed(_ name: String, inModuleNamed moduleName: String) -> Bool {
    // Form a string of the fixed-up tokens representing the type name,
    // omitting any generic type parameters.
    let nameWithoutGenericParameters = tokens(viewMode: .fixedUp)
      .prefix { $0.tokenKind != .leftAngle }
      .filter { $0.tokenKind != .period }
      .filter { $0.tokenKind != .leftParen && $0.tokenKind != .rightParen }
      .map(\.textWithoutBackticks)
      .joined(separator: ".")

    return nameWithoutGenericParameters == name || nameWithoutGenericParameters == "\(moduleName).\(name)"
  }
}
