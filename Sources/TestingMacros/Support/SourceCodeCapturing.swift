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

/// Get a swift-syntax expression initializing an instance of `__Expression`
/// from an arbitrary syntax node.
///
/// - Parameters:
///   - node: A syntax node from which to construct an instance of
///     `__Expression`.
///
/// - Returns: An expression value that initializes an instance of
///   `__Expression` for the specified syntax node.
func createExpressionExpr(from node: any SyntaxProtocol) -> ExprSyntax {
  if let stringLiteralExpr = node.as(StringLiteralExprSyntax.self),
     let stringValue = stringLiteralExpr.representedLiteralValue {
    return ".__fromStringLiteral(\(literal: node.trimmedDescription), \(literal: stringValue))"
  }
  return ".__fromSyntaxNode(\(literal: node.trimmedDescription))"
}

/// Get a swift-syntax expression initializing an instance of `__Expression`
/// from an arbitrary sequence of syntax nodes representing a binary operation.
///
/// - Parameters:
///   - lhs: The left-hand operand.
///   - operator: The operator.
///   - rhs: The right-hand operand.
///
/// - Returns: An expression value that initializes an instance of
///   `__Expression` for the specified syntax nodes.
func createExpressionExprForBinaryOperation(_ lhs: some SyntaxProtocol, _ `operator`: some SyntaxProtocol, _ rhs: some SyntaxProtocol) -> ExprSyntax {
  let arguments = LabeledExprListSyntax {
    LabeledExprSyntax(expression: createExpressionExpr(from: lhs))
    LabeledExprSyntax(expression: StringLiteralExprSyntax(content: `operator`.trimmedDescription))
    LabeledExprSyntax(expression: createExpressionExpr(from: rhs))
  }

  return ".__fromBinaryOperation(\(arguments))"
}

/// Get a swift-syntax expression initializing an instance of `__Expression`
/// from an arbitrary sequence of syntax nodes representing a function call.
///
/// - Parameters:
///   - value: The value on which the member function is being called, if any.
///   - functionName: The name of the member function being called.
///   - arguments: The arguments to the member function.
///
/// - Returns: An expression value that initializes an instance of
///   `__Expression` for the specified syntax nodes.
func createExpressionExprForFunctionCall(_ value: (any SyntaxProtocol)?, _ functionName: some SyntaxProtocol, _ arguments: some Sequence<Argument>) -> ExprSyntax {
  let arguments = LabeledExprListSyntax {
    if let value {
      LabeledExprSyntax(expression: createExpressionExpr(from: value))
    } else {
      LabeledExprSyntax(expression: NilLiteralExprSyntax())
    }
    LabeledExprSyntax(expression: StringLiteralExprSyntax(content: functionName.trimmedDescription))
    for argument in arguments {
      LabeledExprSyntax(expression: TupleExprSyntax {
        if let argumentLabel = argument.label {
          LabeledExprSyntax(expression: StringLiteralExprSyntax(content: argumentLabel.trimmedDescription))
        } else {
          LabeledExprSyntax(expression: NilLiteralExprSyntax())
        }
        LabeledExprSyntax(expression: createExpressionExpr(from: argument.expression))
      })
    }
  }

  return ".__fromFunctionCall(\(arguments))"
}

/// Get a swift-syntax expression initializing an instance of `__Expression`
/// from an arbitrary sequence of syntax nodes representing a property access.
///
/// - Parameters:
///   - value: The value on which the property is being accessed, if any.
///   - keyPath: The name of the property being accessed.
///
/// - Returns: An expression value that initializes an instance of
///   `__Expression` for the specified syntax nodes.
func createExpressionExprForPropertyAccess(_ value: ExprSyntax, _ keyPath: DeclReferenceExprSyntax) -> ExprSyntax {
  let arguments = LabeledExprListSyntax {
    LabeledExprSyntax(expression: createExpressionExpr(from: value))
    LabeledExprSyntax(expression: StringLiteralExprSyntax(content: keyPath.baseName.text))
  }

  return ".__fromPropertyAccess(\(arguments))"
}

/// Get a swift-syntax expression initializing an instance of `__Expression`
/// from an arbitrary sequence of syntax nodes representing the negation of
/// another expression.
///
/// - Parameters:
///   - expression: An expression representing a previously-initialized instance
///     of `__Expression` (that is, not the expression in source, but the result
///     of a call to ``createExpressionExpr(from:)`` etc.)
///   - isParenthetical: Whether or not `expression` was enclosed in
///     parentheses (and the `!` operator was outside it.) This argument
///     affects how this expression is represented as a string.
///
/// - Returns: An expression value that initializes an instance of
///   `__Expression` for the specified syntax nodes.
func createExpressionExprForNegation(of expression: ExprSyntax, isParenthetical: Bool) -> ExprSyntax {
  ".__fromNegation(\(expression.trimmed), \(literal: isParenthetical))"
}
