//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

public import SwiftSyntax
public import SwiftSyntaxMacros

/// A type describing the expansion of the `#currentSourceLocation` macro.
///
/// This type is used to implement the `#currentSourceLocation` attribute macro.
/// Do not use it directly.
public struct CurrentSourceLocationMacro: ExpressionMacro, Sendable {
  public static func expansion(
    of macro: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> ExprSyntax {
    createSourceLocationExpr(of: macro, context: context)
  }
}
