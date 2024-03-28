//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

import SwiftDiagnostics
#if compiler(>=5.11)
import SwiftSyntax
import SwiftSyntaxMacros
#else
public import SwiftSyntax
public import SwiftSyntaxMacros
#endif

/// Diagnose issues with the traits in a parsed attribute.
///
/// - Parameters:
///   - traitExprs: An array of trait expressions to examine.
///   - attribute: The `@Test` or `@Suite` attribute.
///   - context: The macro context in which the expression is being parsed.
func diagnoseIssuesWithTags(in traitExprs: [ExprSyntax], addedTo attribute: AttributeSyntax, in context: some MacroExpansionContext) {
  // Find tags that are in an unsupported format (only .member and "literal"
  // are allowed.)
  for traitExpr in traitExprs {
    // At this time, we are only looking for .tags() traits in this function.
    guard let functionCallExpr = traitExpr.as(FunctionCallExprSyntax.self),
          let calledExpr = functionCallExpr.calledExpression.as(MemberAccessExprSyntax.self) else {
      continue
    }

    // Check for .tags() traits.
    switch calledExpr.tokens(viewMode: .fixedUp).map(\.textWithoutBackticks).joined() {
    case ".tags", "Tag.List.tags", "Testing.Tag.List.tags":
      for tagExpr in functionCallExpr.arguments.lazy.map(\.expression) {
        if tagExpr.is(StringLiteralExprSyntax.self) {
          // String literals are supported tags.
        } else if let tagExpr = tagExpr.as(MemberAccessExprSyntax.self) {
          let joinedTokens = tagExpr.tokens(viewMode: .fixedUp).map(\.textWithoutBackticks).joined()
          if joinedTokens.hasPrefix(".") || joinedTokens.hasPrefix("Tag.") || joinedTokens.hasPrefix("Testing.Tag.") {
            // These prefixes are all allowed as they specify a member access
            // into the Tag type.
          } else {
            context.diagnose(.tagExprNotSupported(tagExpr, in: attribute))
            continue
          }

          // Walk all base expressions and make sure they are exclusively member
          // access expressions.
          func checkForValidDeclReferenceExpr(_ declReferenceExpr: DeclReferenceExprSyntax) {
            // This is the name of a type or symbol. If there are argument names
            // (unexpected in this context), it's a function reference and is
            // unsupported.
            if declReferenceExpr.argumentNames != nil {
              context.diagnose(.tagExprNotSupported(tagExpr, in: attribute))
            }
          }
          func checkForValidBaseExpr(_ baseExpr: ExprSyntax) {
            if let baseExpr = baseExpr.as(MemberAccessExprSyntax.self) {
              checkForValidDeclReferenceExpr(baseExpr.declName)
              if let baseBaseExpr = baseExpr.base {
                checkForValidBaseExpr(baseBaseExpr)
              }
            } else if let baseExpr = baseExpr.as(DeclReferenceExprSyntax.self) {
              checkForValidDeclReferenceExpr(baseExpr)
            } else {
              // The base expression was some other kind of expression and is
              // not supported.
              context.diagnose(.tagExprNotSupported(tagExpr, in: attribute))
            }
          }
          if let baseExpr = tagExpr.base {
            checkForValidBaseExpr(baseExpr)
          }
        } else {
          // This tag is not of a supported expression type.
          context.diagnose(.tagExprNotSupported(tagExpr, in: attribute))
        }
      }
    default:
      // This is not a tag list (as far as we know.)
      break
    }
  }
}

#if canImport(SwiftSyntax600)
/// Diagnose issues with the lexical context containing a declaration.
///
/// - Parameters:
///   - decl: The declaration to inspect.
///   - testAttribute: The `@Test` attribute applied to `decl`.
///   - context: The macro context in which the expression is being parsed.
///
/// - Returns: An array of zero or more diagnostic messages related to the
///   lexical context containing `decl`.
func diagnoseIssuesWithLexicalContext(
  containing decl: some DeclSyntaxProtocol,
  attribute: AttributeSyntax,
  in context: some MacroExpansionContext
) -> [DiagnosticMessage] {
  context.lexicalContext
    .filter { !$0.isProtocol((any DeclGroupSyntax).self) }
    .map { .containingNodeUnsupported($0, whenUsing: attribute) }
}
#endif
