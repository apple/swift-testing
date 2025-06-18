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
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// The result of parsing the condition argument passed to `#expect()` or
/// `#require()`.
struct Condition {
  /// The name of the function to call in the macro expansion (e.g.
  /// `__check()`.)
  var expandedFunctionName: TokenSyntax

  /// The condition as one or more arguments to the evaluation function,
  /// suitable for passing as partial arguments to a call to `__check()`.
  var arguments: [Argument]

  /// The condition's source code as an expression that produces an instance of
  /// the testing library's `__Expression` type.
  var expression: ExprSyntax

  init(_ expandedFunctionName: String, arguments: [Argument], expression: ExprSyntax) {
    self.expandedFunctionName = .identifier(expandedFunctionName)
    self.arguments = arguments
    self.expression = expression
  }

  /// Initialize an instance of this type representing a single expression (i.e.
  /// one that could not be broken down further.)
  ///
  /// - Parameters:
  ///   - expr: The expression.
  ///   - expressionNode: The node from which to derive the `expression`
  ///     property. If `nil`, `expr` is used.
  init(expression expr: some ExprSyntaxProtocol, expressionNode: Syntax? = nil) {
    let expressionNode: Syntax = expressionNode ?? Syntax(expr)
    self.init(
      "__checkValue",
      arguments: [Argument(expression: expr)],
      expression: createExpressionExpr(from: expressionNode)
    )
  }
}

/// Emit a diagnostic if an expression resolves to a trivial boolean literal
/// (e.g. `#expect(true)`.)
///
/// - Parameters:
///   - expr: The condition expression to parse.
///   - macro: The macro expression being expanded.
///   - context: The macro context in which the expression is being parsed.
///
/// If `expr` is a trivial boolean expression, a diagnostic is emitted on the
/// assumption that this is not what the developer intended.
private func _diagnoseTrivialBooleanValue(from expr: ExprSyntax, for macro: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) {
  if let literal = expr.as(BooleanLiteralExprSyntax.self) {
    switch literal.literal.tokenKind {
    case .keyword(.true):
      context.diagnose(.condition(expr, isAlways: true, in: macro))
    case .keyword(.false):
      context.diagnose(.condition(expr, isAlways: false, in: macro))
    default:
      break
    }
  } else if let literal = _negatedExpression(expr)?.0.as(BooleanLiteralExprSyntax.self) {
    // This expression is of the form !true or !false.
    switch literal.literal.tokenKind {
    case .keyword(.true):
      context.diagnose(.condition(expr, isAlways: !true, in: macro))
    case .keyword(.false):
      context.diagnose(.condition(expr, isAlways: !false, in: macro))
    default:
      break
    }
  }
}

/// Extract the expression negated by another expression, assuming that the
/// input expression is the negation operator (`!`).
///
/// - Parameters:
///   - expr: The negation expression.
///
/// - Returns: The expression negated by `expr`, or `nil` if `expr` is not a
///   negation expression.
///
/// This function handles expressions such as `!foo` or `!(bar)`.
private func _negatedExpression(_ expr: ExprSyntax) -> (ExprSyntax, isParenthetical: Bool)? {
  let expr = removeParentheses(from: expr) ?? expr
  if let op = expr.as(PrefixOperatorExprSyntax.self),
     op.operator.tokenKind == .prefixOperator("!") {
    if let negatedExpr = removeParentheses(from: op.expression) {
      return (negatedExpr, true)
    } else {
      return (op.expression, false)
    }
  }

  return nil
}

/// Remove the parentheses surrounding an expression, if present.
///
/// - Parameters:
///   - expr: The parenthesized expression.
///
/// - Returns: The expression parenthesized by `expr`, or `nil` if it wasn't
///   parenthesized.
///
/// This function handles expressions such as `(foo)` or `((foo, bar))`. It does
/// not remove interior parentheses (e.g. `(foo, (bar))`.)
func removeParentheses(from expr: ExprSyntax) -> ExprSyntax? {
  if let tuple = expr.as(TupleExprSyntax.self),
      tuple.elements.count == 1,
     let elementExpr = tuple.elements.first,
     elementExpr.label == nil {
    return removeParentheses(from: elementExpr.expression) ?? elementExpr.expression
  }

  return nil
}

// MARK: -

/// Parse a condition argument from a binary operation expression.
///
/// - Parameters:
///   - expr: The expression to which `lhs` _et al._ belong.
///   - lhs: The left-hand operand expression.
///   - op: The operator expression.
///   - rhs: The right-hand operand expression.
///   - macro: The macro expression being expanded.
///   - context: The macro context in which the expression is being parsed.
///
/// - Returns: An instance of ``Condition`` describing `expr`.
///
/// This function currently only recognizes and converts simple binary operator
/// expressions. More complex expressions are treated as monolithic.
private func _parseCondition(from expr: ExprSyntax, leftOperand lhs: ExprSyntax, operator op: BinaryOperatorExprSyntax, rightOperand rhs: ExprSyntax, for macro: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) -> Condition {
  return Condition(
    "__checkBinaryOperation",
    arguments: [
      Argument(expression: lhs),
      Argument(expression: "{ $0 \(op.trimmed) $1() }"),
      Argument(expression: rhs)
    ],
    expression: createExpressionExprForBinaryOperation(lhs, op, rhs)
  )
}

/// Parse a condition argument from an `is` expression.
///
/// - Parameters:
///   - expr: The `is` expression.
///   - macro: The macro expression being expanded.
///   - context: The macro context in which the expression is being parsed.
///
/// - Returns: An instance of ``Condition`` describing `expr`.
private func _parseCondition(from expr: IsExprSyntax, for macro: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) -> Condition {
  let expression = expr.expression
  let type = expr.type

  return Condition(
    "__checkCast",
    arguments: [
      Argument(expression: expression),
      Argument(label: .identifier("is"), expression: "(\(type.trimmed)).self")
    ],
    expression: createExpressionExprForBinaryOperation(expression, expr.isKeyword, type)
  )
}

/// Parse a condition argument from an `as?` expression.
///
/// - Parameters:
///   - expr: The `as?` expression.
///   - macro: The macro expression being expanded.
///   - context: The macro context in which the expression is being parsed.
///
/// - Returns: An instance of ``Condition`` describing `expr`.
private func _parseCondition(from expr: AsExprSyntax, for macro: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) -> Condition {
  let expression = expr.expression
  let type = expr.type

  switch expr.questionOrExclamationMark?.tokenKind {
  case .postfixQuestionMark:
    return Condition(
      "__checkCast",
      arguments: [
        Argument(expression: expression),
        Argument(label: .identifier("as"), expression: "(\(type.trimmed)).self")
      ],
      expression: createExpressionExprForBinaryOperation(expression, TokenSyntax.unknown("as?"), type)
    )

  case .exclamationMark where !type.isNamed("Bool", inModuleNamed: "Swift") && !type.isOptional:
    // Warn that as! will be evaluated before #expect() or #require(), which is
    // probably not what the developer intended. We suppress the warning for
    // casts to Bool and casts to optional types. Presumably such casts are not
    // being performed for their optional-unwrapping behavior, but because the
    // developer knows the type of the expression better than we do.
    context.diagnose(.asExclamationMarkIsEvaluatedEarly(expr, in: macro))

  default:
    // Only diagnose for `x as! T`. `x as T` is perfectly fine if it otherwise
    // compiles. For example, `#require(x as Int?)` should compile.
    //
    // If the token after "as" is something else entirely and got through the
    // type checker, just leave it alone as we don't recognize it.
    break
  }

  return Condition(expression: expr)
}

/// Parse a condition argument from a closure expression.
///
/// - Parameters:
///   - expr: The closure expression.
///   - macro: The macro expression being expanded.
///   - context: The macro context in which the expression is being parsed.
///
/// - Returns: An instance of ``Condition`` describing `expr`.
private func _parseCondition(from expr: ClosureExprSyntax, for macro: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) -> Condition {
  if expr.signature == nil && expr.statements.count == 1, let item = expr.statements.first?.item {
    // TODO: capture closures as a different kind of Testing.Expression with a
    // separate subexpression per code item.

    // If a closure contains a single statement or declaration, we can't
    // meaningfully break it down as an expression, but we can still capture its
    // source representation.
    return Condition(expression: expr, expressionNode: Syntax(item))
  }

  return Condition(expression: expr)
}

/// A class that walks a syntax tree looking for optional chaining expressions
/// such as `a?.b.c`.
private final class _OptionalChainFinder: SyntaxVisitor {
  /// Whether or not any optional chaining was found.
  var optionalChainFound = false

  override func visit(_ node: OptionalChainingExprSyntax) -> SyntaxVisitorContinueKind {
    optionalChainFound = true
    return .skipChildren
  }
}

/// Extract the underlying expression from an optional-chained expression as
/// well as the number of question marks required to reach it.
///
/// - Parameters:
///   - expr: The expression to examine, typically the `base` expression of a
///     `MemberAccessExprSyntax` instance.
///
/// - Returns: A copy of `expr` with trailing question marks from optional
///   chaining removed, as well as a string containing the number of question
///   marks needed to access a member of `expr` after it has been assigned to
///   another variable. If `expr` does not contain any optional chaining, it is
///   returned verbatim along with the empty string.
///
/// This function is used when expanding member accesses (either functions or
/// properties) that could contain optional chaining expressions such as
/// `foo?.bar()`. Since, in this case, `bar()` is ultimately going to be called
/// on a closure argument (i.e. `$0`), it is necessary to determine the number
/// of question mark characters needed to correctly construct that expression
/// and to capture the underlying expression of `foo?` without question marks so
/// that it remains syntactically correct when used without `bar()`.
private func _exprFromOptionalChainedExpr(_ expr: some ExprSyntaxProtocol) -> (ExprSyntax, questionMarks: String) {
  let originalExpr = expr
  var expr = ExprSyntax(expr)
  var questionMarkCount = 0

  while let optionalExpr = expr.as(OptionalChainingExprSyntax.self) {
    // If the rightmost base expression is an optional-chained member access
    // expression (e.g. "bar?" in the member access expression
    // "foo.bar?.isQuux"), drop the question mark.
    expr = optionalExpr.expression
    questionMarkCount += 1
  }

  // If the rightmost expression is not itself optional-chained, check if any of
  // the member accesses in the expression use optional chaining and, if one
  // does, ensure we preserve optional chaining in the macro expansion.
  if questionMarkCount == 0 {
    let optionalChainFinder = _OptionalChainFinder(viewMode: .sourceAccurate)
    optionalChainFinder.walk(originalExpr)
    if optionalChainFinder.optionalChainFound {
      questionMarkCount = 1
    }
  }

  let questionMarks = String(repeating: "?", count: questionMarkCount)

  return (expr, questionMarks)
}

/// Parse a condition argument from a member function call.
///
/// - Parameters:
///   - expr: The function call expression.
///   - macro: The macro expression being expanded.
///   - context: The macro context in which the expression is being parsed.
///
/// - Returns: An instance of ``Condition`` describing `expr`.
private func _parseCondition(from expr: FunctionCallExprSyntax, for macro: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) -> Condition {
  // We do not support function calls with trailing closures because the
  // transform required to forward them requires more information than is
  // available solely from the syntax tree.
  if expr.trailingClosure != nil {
    return Condition(expression: expr)
  }

  // We also do not support expansion of closure invocations as they are
  // diagnostically uninteresting.
  if expr.calledExpression.is(ClosureExprSyntax.self) {
    return Condition(expression: expr)
  }

  let memberAccessExpr = expr.calledExpression.as(MemberAccessExprSyntax.self)
  let functionName = memberAccessExpr.map(\.declName.baseName).map(Syntax.init) ?? Syntax(expr.calledExpression)
  let argumentList = expr.arguments.map(Argument.init)

  let inOutArguments: [InOutExprSyntax] = argumentList.lazy
    .map(\.expression)
    .compactMap({ $0.as(InOutExprSyntax.self) })
  if inOutArguments.count > 1 {
    // There is more than one inout argument present. This requires that the
    // corresponding __check() function support variadic generics, but there is
    // a compiler bug preventing us from implementing variadic inout support.
    return Condition(expression: expr)
  } else if inOutArguments.count != 0 && inOutArguments.count != argumentList.count {
    // There is a mix of inout and normal arguments. That's not feasible for
    // us to support here, so back out.
    return Condition(expression: expr)
  }

  // Which __check() function are we calling?
  let expandedFunctionName = inOutArguments.isEmpty ? "__checkFunctionCall" : "__checkInoutFunctionCall"

  let indexedArguments = argumentList.lazy
    .enumerated()
    .map { index, argument in
      if argument.expression.is(InOutExprSyntax.self) {
        return Argument(label: argument.label, expression: "&$\(raw: index + 1)")
      }
      return Argument(label: argument.label, expression: "$\(raw: index + 1)")
    }
  let forwardedArguments = argumentList.lazy
    .map(\.expression)
    .map { Argument(expression: $0) }

  var baseExprForExpression: ExprSyntax?
  var conditionArguments = [Argument]()
  if let memberAccessExpr, var baseExpr = memberAccessExpr.base {
    let questionMarks: String
    (baseExpr, questionMarks) = _exprFromOptionalChainedExpr(baseExpr)
    baseExprForExpression = baseExpr

    conditionArguments.append(Argument(expression: "\(baseExpr.trimmed).self")) // BUG: rdar://113152370
    conditionArguments.append(
      Argument(
        label: "calling",
        expression: """
        {
          $0\(raw: questionMarks).\(functionName.trimmed)(\(LabeledExprListSyntax(indexedArguments)))
        }
        """
      )
    )
  } else {
    // Substitute an empty tuple for the self argument, and call the function
    // directly (without having to reorder the numbered closure arguments.) If
    // the function takes zero arguments, we'll also need to suppress $0 in the
    // closure body since it is unused.
    let parameterList = forwardedArguments.isEmpty ? "_ in" : ""
    conditionArguments.append(Argument(expression: "()"))

    // If memberAccessExpr is not nil here, that means it had a nil base
    // expression (i.e. the base is inferred.)
    var dot: TokenSyntax?
    if memberAccessExpr != nil {
      dot = .periodToken()
    }

    conditionArguments.append(
      Argument(
        label: "calling",
        expression: """
        { \(raw: parameterList)
          \(dot)\(functionName.trimmed)(\(LabeledExprListSyntax(indexedArguments)))
        }
        """
      )
    )
  }
  conditionArguments += forwardedArguments
  return Condition(
    expandedFunctionName,
    arguments: conditionArguments,
    expression: createExpressionExprForFunctionCall(baseExprForExpression, functionName, argumentList)
  )
}

/// Parse a condition argument from a property access.
///
/// - Parameters:
///   - expr: The member access expression.
///   - macro: The macro expression being expanded.
///   - context: The macro context in which the expression is being parsed.
///
/// - Returns: An instance of ``Condition`` describing `expr`.
private func _parseCondition(from expr: MemberAccessExprSyntax, for macro: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) -> Condition {
  // Only handle member access expressions where the base expression is known
  // and where there are no argument names (which would otherwise indicate a
  // reference to a member function which wouldn't resolve to anything useful at
  // runtime.)
  guard var baseExpr = expr.base, expr.declName.argumentNames == nil else {
    return Condition(expression: expr)
  }

  let questionMarks: String
  (baseExpr, questionMarks) = _exprFromOptionalChainedExpr(baseExpr)

  return Condition(
    "__checkPropertyAccess",
    arguments: [
      Argument(expression: "\(baseExpr.trimmed).self"),
      Argument(label: "getting", expression: "{ $0\(raw: questionMarks).\(expr.declName.baseName) }")
    ],
    expression: createExpressionExprForPropertyAccess(baseExpr, expr.declName)
  )
}

/// Parse a condition argument from a property access.
///
/// - Parameters:
///   - expr: The expression that was negated.
///   - isParenthetical: Whether or not `expression` was enclosed in
///     parentheses (and the `!` operator was outside it.) This argument
///     affects how this expression is represented as a string.
///   - macro: The macro expression being expanded.
///   - context: The macro context in which the expression is being parsed.
///
/// - Returns: An instance of ``Condition`` describing `expr`.
private func _parseCondition(negating expr: ExprSyntax, isParenthetical: Bool, for macro: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) -> Condition {
  var result = _parseCondition(from: expr, for: macro, in: context)
  result.expression = createExpressionExprForNegation(of: result.expression, isParenthetical: isParenthetical)
  return result
}

/// Parse a condition argument from an arbitrary expression.
///
/// - Parameters:
///   - expr: The condition expression to parse.
///   - macro: The macro expression being expanded.
///   - context: The macro context in which the expression is being parsed.
///
/// - Returns: An instance of ``Condition`` describing `expr`.
private func _parseCondition(from expr: ExprSyntax, for macro: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) -> Condition {
  // Handle closures with a single expression in them (e.g. { $0.foo() })
  if let closureExpr = expr.as(ClosureExprSyntax.self) {
    return _parseCondition(from: closureExpr, for: macro, in: context)
  }

  if let infixOperator = expr.as(InfixOperatorExprSyntax.self),
     let op = infixOperator.operator.as(BinaryOperatorExprSyntax.self) {
    return _parseCondition(from: expr, leftOperand: infixOperator.leftOperand, operator: op, rightOperand: infixOperator.rightOperand, for: macro, in: context)
  }

  // Handle `is` and `as?` expressions.
  if let isExpr = expr.as(IsExprSyntax.self) {
    return _parseCondition(from: isExpr, for: macro, in: context)
  } else if let asExpr = expr.as(AsExprSyntax.self) {
    return _parseCondition(from: asExpr, for: macro, in: context)
  }

  // Handle function calls and member accesses.
  if let functionCallExpr = expr.as(FunctionCallExprSyntax.self) {
    return _parseCondition(from: functionCallExpr, for: macro, in: context)
  } else if let memberAccessExpr = expr.as(MemberAccessExprSyntax.self) {
    return _parseCondition(from: memberAccessExpr, for: macro, in: context)
  }

  // Handle negation.
  if let negatedExpr = _negatedExpression(expr) {
    return _parseCondition(negating: negatedExpr.0, isParenthetical: negatedExpr.isParenthetical, for: macro, in: context)
  }

  // Parentheses are parsed as if they were tuples, so (true && false) appears
  // to the parser as a tuple containing one expression, `true && false`.
  if let expr = removeParentheses(from: expr) {
    return _parseCondition(from: expr, for: macro, in: context)
  }

  return Condition(expression: expr)
}

// MARK: -

/// Parse a condition argument from an arbitrary expression.
///
/// - Parameters:
///   - expr: The condition expression to parse.
///   - macro: The macro expression being expanded.
///   - context: The macro context in which the expression is being parsed.
///
/// - Returns: An instance of ``Condition`` describing `expr`.
func parseCondition(from expr: ExprSyntax, for macro: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) -> Condition {
  // If the condition involves the `unsafe`, `try`, or `await` keywords, assume
  // we cannot expand it.
  let effectKeywordsToApply = findEffectKeywords(in: expr).union(findEffectKeywords(in: context))
  guard effectKeywordsToApply.intersection([.unsafe, .try, .await]).isEmpty else {
    return Condition(expression: expr)
  }

  _diagnoseTrivialBooleanValue(from: expr, for: macro, in: context)
  let result = _parseCondition(from: expr, for: macro, in: context)
  return result
}
