//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

import SwiftParser
public import SwiftSyntax
import SwiftSyntaxBuilder
public import SwiftSyntaxMacros

/// The implementation of the `#__capturedValue()` macro when the value conforms
/// to the necessary protocols.
///
/// This type is used to implement the `#__capturedValue()` macro. Do not use it
/// directly.
public struct ExitTestCapturedValueMacro: ExpressionMacro, Sendable {
  public static func expansion(
    of macro: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> ExprSyntax {
    let arguments = Array(macro.arguments)
    let expr = arguments[0].expression

    // No additional processing is required as this expression's type meets our
    // requirements.

    return expr
  }
}

/// The implementation of the `#__capturedValue()` macro when the value does
/// _not_ conform to the necessary protocols.
///
/// This type is used to implement the `#__capturedValue()` macro. Do not use it
/// directly.
public struct ExitTestBadCapturedValueMacro: ExpressionMacro, Sendable {
  public static func expansion(
    of macro: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> ExprSyntax {
    let arguments = Array(macro.arguments)
    let expr = arguments[0].expression
    let nameExpr = arguments[1].expression.cast(StringLiteralExprSyntax.self)

    // Diagnose that the type of 'expr' is invalid.
    context.diagnose(.capturedValueMustBeSendableAndCodable(expr, name: nameExpr))

    return .unreachable
  }
}

/// The implementation of the `#__capturedValue()` macro when the type we
/// inferred for the value was incorrect.
///
/// This type is used to implement the `#__capturedValue()` macro. Do not use it
/// directly.
public struct ExitTestIncorrectlyCapturedValueMacro: ExpressionMacro, Sendable {
  public static func expansion(
    of macro: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> ExprSyntax {
    let arguments = Array(macro.arguments)
    let expr = arguments[0].expression
    let nameExpr = arguments[1].expression.cast(StringLiteralExprSyntax.self)

    // Diagnose that the type of 'expr' is invalid.
    let name = nameExpr.representedLiteralValue ?? expr.trimmedDescription
    let capture = ClosureCaptureSyntax(name: .identifier(name))
    context.diagnose(.typeOfCaptureIsAmbiguous(capture))

    return expr
  }
}
