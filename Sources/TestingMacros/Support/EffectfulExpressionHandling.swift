//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// MARK: - Finding effect keywords and expressions

/// Get the effect keyword corresponding to a given syntax node, if any.
///
/// - Parameters:
/// 	- expr: The syntax node that may represent an effectful expression.
///
/// - Returns: The effect keyword corresponding to `expr`, if any.
private func _effectKeyword(for expr: ExprSyntax) -> Keyword? {
  switch expr.kind {
  case .tryExpr:
    return .try
  case .awaitExpr:
    return .await
  case .consumeExpr:
    return .consume
  case .borrowExpr:
    return .borrow
  case .unsafeExpr:
    return .unsafe
  default:
    return nil
  }
}

/// Determine how to descend further into a syntax node tree from a given node.
///
/// - Parameters:
///   - node: The syntax node currently being walked.
///
/// - Returns: Whether or not to descend into `node` and visit its children.
private func _continueKind(for node: Syntax) -> SyntaxVisitorContinueKind {
  switch node.kind {
  case .tryExpr, .awaitExpr, .consumeExpr, .borrowExpr, .unsafeExpr:
    // If this node represents an effectful expression, look inside it for
    // additional such expressions.
    return .visitChildren
  case .closureExpr, .functionDecl:
    // Do not delve into closures or function declarations.
    return .skipChildren
  case .variableDecl:
    // Delve into variable declarations.
    return .visitChildren
  default:
    // Do not delve into declarations other than variables.
    if node.isProtocol((any DeclSyntaxProtocol).self) {
      return .skipChildren
    }
  }

  // Recurse into everything else.
  return .visitChildren
}

/// A syntax visitor class that looks for effectful keywords in a given
/// expression.
private final class _EffectFinder: SyntaxAnyVisitor {
  /// The effect keywords discovered so far.
  var effectKeywords: Set<Keyword> = []

  override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
    if let expr = node.as(ExprSyntax.self), let keyword = _effectKeyword(for: expr) {
      effectKeywords.insert(keyword)
    }

    return _continueKind(for: node)
  }
}

/// Find effectful keywords in a syntax node.
///
/// - Parameters:
///   - node: The node to inspect.
///
/// - Returns: A set of effectful keywords such as `await` that are present in
///   `node`.
///
/// This function does not descend into function declarations or closure
/// expressions because they represent distinct lexical contexts and their
/// effects are uninteresting in the context of `node` unless they are called.
func findEffectKeywords(in node: some SyntaxProtocol) -> Set<Keyword> {
  let effectFinder = _EffectFinder(viewMode: .sourceAccurate)
  effectFinder.walk(node)
  return effectFinder.effectKeywords
}

/// Find effectful keywords in a macro's lexical context.
///
/// - Parameters:
///   - context: The macro context in which the expression is being parsed.
///
/// - Returns: A set of effectful keywords such as `await` that are present in
///   `context` and would apply to an expression macro during its expansion.
func findEffectKeywords(in context: some MacroExpansionContext) -> Set<Keyword> {
  let result = context.lexicalContext.reversed().lazy
    .prefix { _continueKind(for: $0) == .visitChildren }
    .compactMap { $0.as(ExprSyntax.self) }
    .compactMap(_effectKeyword(for:))
  return Set(result)
}

extension BidirectionalCollection<Syntax> {
  /// The suffix of syntax nodes in this collection which are effectful
  /// expressions, such as those for `try` or `await`.
  var trailingEffectExpressions: some Collection<Syntax> {
    reversed()
      .prefix { node in
        // This could be simplified if/when swift-syntax introduces a protocol
        // which all effectful expression syntax node types conform to.
        // See https://github.com/swiftlang/swift-syntax/issues/3040
        node.is(TryExprSyntax.self) || node.is(AwaitExprSyntax.self) || node.is(UnsafeExprSyntax.self)
      }
      .reversed()
  }
}

// MARK: - Inserting effect keywords/thunks

/// Whether or not the `unsafe` expression keyword is supported.
var isUnsafeKeywordSupported: Bool {
  // The 'unsafe' keyword was introduced in 6.2 as part of SE-0458. Older
  // toolchains are not aware of it.
#if compiler(>=6.2)
  true
#else
  false
#endif
}

/// Make a function call expression to an effectful thunk function provided by
/// the testing library.
///
/// - Parameters:
///   - thunkName: The unqualified name of the thunk function to call. This
///     token must be the name of a function in the `Testing` module.
///   - expr: The expression to thunk.
///
/// - Returns: An expression representing a call to the function named
///   `thunkName`, passing `expr`.
private func _makeCallToEffectfulThunk(_ thunkName: TokenSyntax, passing expr: some ExprSyntaxProtocol) -> ExprSyntax {
  ExprSyntax(
    FunctionCallExprSyntax(
      calledExpression: MemberAccessExprSyntax(
        base: DeclReferenceExprSyntax(baseName: .identifier("Testing")),
        declName: DeclReferenceExprSyntax(baseName: thunkName)
      ),
      leftParen: .leftParenToken(),
      rightParen: .rightParenToken()
    ) {
      LabeledExprSyntax(expression: expr.trimmed)
    }
  )
}

/// Apply the given effectful keywords (i.e. `try` and `await`) to an expression
/// using thunk functions provided by the testing library.
///
/// - Parameters:
///   - effectfulKeywords: The effectful keywords to apply.
///   - expr: The expression to apply the keywords and thunk functions to.
///   - insertThunkCalls: Whether or not to also insert calls to thunks to
///   	ensure the inserted keywords do not generate warnings. If you aren't
///     sure whether thunk calls are needed, pass `true`.
///
/// - Returns: A copy of `expr` if no changes are needed, or an expression that
///   adds the keywords in `effectfulKeywords` to `expr`.
func applyEffectfulKeywords(_ effectfulKeywords: Set<Keyword>, to expr: some ExprSyntaxProtocol, insertThunkCalls: Bool = true) -> ExprSyntax {
  let originalExpr = expr
  var expr = ExprSyntax(expr.trimmed)

  let needAwait = effectfulKeywords.contains(.await) && !expr.is(AwaitExprSyntax.self)
  let needTry = effectfulKeywords.contains(.try) && !expr.is(TryExprSyntax.self)

  let needUnsafe = isUnsafeKeywordSupported && effectfulKeywords.contains(.unsafe) && !expr.is(UnsafeExprSyntax.self)

  // First, add thunk function calls.
  if insertThunkCalls {
    if needAwait {
      expr = _makeCallToEffectfulThunk(.identifier("__requiringAwait"), passing: expr)
    }
    if needTry {
      expr = _makeCallToEffectfulThunk(.identifier("__requiringTry"), passing: expr)
    }
    if needUnsafe {
      expr = _makeCallToEffectfulThunk(.identifier("__requiringUnsafe"), passing: expr)
    }
  }

  // Then add keyword expressions. (We do this separately so we end up writing
  // `try await __r(__r(self))` instead of `try __r(await __r(self))` which is
  // less accepted by the compiler.)
  if needAwait {
    expr = ExprSyntax(
      AwaitExprSyntax(
        awaitKeyword: .keyword(.await, trailingTrivia: .space),
        expression: expr
      )
    )
  }
  if needTry {
    expr = ExprSyntax(
      TryExprSyntax(
        tryKeyword: .keyword(.try, trailingTrivia: .space),
        expression: expr
      )
    )
  }
  if needUnsafe {
    expr = ExprSyntax(
      UnsafeExprSyntax(
        unsafeKeyword: .keyword(.unsafe, trailingTrivia: .space),
        expression: expr
      )
    )
  }

  expr.leadingTrivia = originalExpr.leadingTrivia
  expr.trailingTrivia = originalExpr.trailingTrivia

  return expr
}
