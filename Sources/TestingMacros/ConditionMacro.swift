//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

public import SwiftSyntax
public import SwiftSyntaxMacros

/// A protocol containing the common implementation for the expansions of the
/// `#expect()` and `#require()` macros.
///
/// This type is used to implement the `#expect()` and `#require()` macros. Do
/// not use it directly.
///
/// ## Macro arguments
///
/// Overloads of these macros that evaluate an expression take exactly three
/// arguments: a "condition" argument, a `Comment?`-typed argument with no
/// label, and an optional `SourceLocation`-typed argument with the label
/// `sourceLocation`. The "condition" argument may be expanded into additional
/// arguments based on its representation in the syntax tree.
///
/// ## Macro arguments with trailing closures
///
/// Overloads of these macros that take trailing closures are expected to use
/// the label `"performing"` to identify the (first) trailing closure. By using
/// a consistent label, we can eliminate ambiguity during parsing.
///
/// The `__check()` function that implements expansions of these macros must
/// take any developer-supplied arguments _before_ the ones inserted during
/// macro expansion (starting with the `"expression"` argument.)
public protocol ConditionMacro: ExpressionMacro, Sendable {
  /// Whether or not the macro's expansion may throw an error.
  static var isThrowing: Bool { get }
}

// MARK: -

/// The token used as the label of the source location argument passed to
/// `#expect()` and `#require()`.
private var _sourceLocationLabel: TokenSyntax { .identifier("sourceLocation") }

/// The token used as a mandatory label on any (first) trailing closure used
/// with `#expect()` or `#require()`.
private var _trailingClosureLabel: TokenSyntax { .identifier("performing") }

extension ConditionMacro {
  public static func expansion(
    of macro: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> ExprSyntax {
    // Reconstruct an argument list that includes any trailing closures.
    let macroArguments = _argumentList(of: macro, in: context)

    // Figure out important argument indices.
    let trailingClosureIndex = macroArguments.firstIndex { $0.label?.tokenKind == _trailingClosureLabel.tokenKind }
    var commentIndex: [Argument].Index?
    if let trailingClosureIndex {
      // Assume that the comment, if present is the last argument in the
      // argument list prior to the trailing closure that has no label.
      commentIndex = macroArguments[..<trailingClosureIndex].lastIndex { $0.label == nil }
    } else if macroArguments.count > 1 {
      // If there is no trailing closure argument and there is more than one
      // argument, then the comment is the last argument with no label (and also
      // never the first argument.)
      commentIndex = macroArguments.dropFirst().lastIndex { $0.label == nil }
    }
    let sourceLocationArgumentIndex = macroArguments.lazy
      .compactMap(\.label)
      .firstIndex { $0.tokenKind == _sourceLocationLabel.tokenKind }

    // Construct the argument list to __check().
    let expandedFunctionName: TokenSyntax
    var checkArguments = [Argument]()
    do {
      if let trailingClosureIndex {

        // Include all arguments other than the "comment" and "sourceLocation"
        // arguments here.
        checkArguments += macroArguments.indices.lazy
          .filter { $0 != commentIndex }
          .filter { $0 != sourceLocationArgumentIndex }
          .map { macroArguments[$0] }

        // The trailing closure should be the focus of the source code capture.
        let sourceCode = parseCondition(from: macroArguments[trailingClosureIndex].expression, for: macro, in: context).expression
        checkArguments.append(Argument(label: "expression", expression: sourceCode))

        expandedFunctionName = .identifier("__checkClosureCall")

      } else {
        // Get the condition expression and extract its parsed form and source
        // code. The first argument is always the condition argument if there is
        // no trailing closure argument.
        let conditionArgument = parseCondition(from: macroArguments.first!.expression, for: macro, in: context)
        checkArguments += conditionArgument.arguments

        // Include all arguments other than the "condition", "comment", and
        // "sourceLocation" arguments here.
        checkArguments += macroArguments.dropFirst().indices.lazy
          .filter { $0 != commentIndex }
          .filter { $0 != sourceLocationArgumentIndex }
          .map { macroArguments[$0] }

        checkArguments.append(Argument(label: "expression", expression: conditionArgument.expression))

        expandedFunctionName = conditionArgument.expandedFunctionName
      }

      // Capture any comments as well (either in source or as a macro argument.)
      checkArguments.append(Argument(
        label: "comments",
        expression: ArrayExprSyntax {
          for commentTraitExpr in createCommentTraitExprs(for: macro) {
            ArrayElementSyntax(expression: commentTraitExpr)
          }
          if let commentIndex {
            ArrayElementSyntax(expression: macroArguments[commentIndex].expression.trimmed)
          }
        }
      ))

      checkArguments.append(Argument(label: "isRequired", expression: BooleanLiteralExprSyntax(isThrowing)))

      if let sourceLocationArgumentIndex {
        checkArguments.append(macroArguments[sourceLocationArgumentIndex])
      } else {
        checkArguments.append(Argument(label: _sourceLocationLabel, expression: createSourceLocationExpr(of: macro, context: context)))
      }
    }

    // Construct and return the call to __check().
    let call: ExprSyntax = "\(expandedFunctionName)(\(LabeledExprListSyntax(checkArguments)))"
    if isThrowing {
      return "\(call).__required()"
    }
    return "\(call).__expected()"
  }

  /// Get the complete argument list for a given macro, including any trailing
  /// closures.
  ///
  /// - Parameters:
  ///   - macro: The macro being inspected.
  ///   - context: The macro context in which the expression is being parsed.
  ///
  /// - Returns: A copy of the argument list of `macro` with trailing closures
  ///   included.
  private static func _argumentList(
    of macro: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) -> [Argument] {
    var result = [Argument]()

    // NOTE: An #expect() or #require() invocation can have a condition argument
    // OR a trailing closure, but not both. If it has both, then that makes it
    // ambiguous to parse an invocation with a comment argument such as:
    //
    // #expect(x) { ... }
    //
    // Since we do not have enough context during macro expansion to know if the
    // "x" argument is the condition or a comment. Additional labelled arguments
    // are allowed.

    // Include the original arguments first.
    result += macro.arguments.lazy.map(Argument.init)

    if let trailingClosure = macro.trailingClosure {
      // Since a trailing closure does not (syntactically) include a label, we
      // assume that the argument has the mandatory label described above.
      result.append(Argument(label: _trailingClosureLabel, expression: trailingClosure))
    }

    // Include any additional trailing closures. These trailing closures will
    // always have labels.

    result += macro.additionalTrailingClosures.lazy.map(Argument.init)

    return result
  }
}

// MARK: -

/// A type describing the expansion of the `#expect()` macro.
public struct ExpectMacro: ConditionMacro {
  public static var isThrowing: Bool {
    false
  }
}

// MARK: -

/// A type describing the expansion of the `#require()` macro.
public struct RequireMacro: ConditionMacro {
  public static var isThrowing: Bool {
    true
  }
}

/// A type describing the expansion of the `#require()` macro when it is
/// ambiguous whether it refers to a boolean check or optional unwrapping.
///
/// This type is otherwise exactly equivalent to ``RequireMacro``.
public struct AmbiguousRequireMacro: ConditionMacro {
  public static func expansion(
    of macro: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> ExprSyntax {
    if let argument = macro.arguments.first {
      _checkAmbiguousArgument(argument.expression, in: context)
    }

    // Perform the normal macro expansion for #require().
    return try RequireMacro.expansion(of: macro, in: context)
  }

  /// Check for an ambiguous argument to the `#require()` macro and emit the
  /// appropriate diagnostics.
  ///
  /// - Parameters:
  ///   - argument: The ambiguous argument.
  ///   - context: The macro context in which the expression is being parsed.
  private static func _checkAmbiguousArgument(_ argument: ExprSyntax, in context: some MacroExpansionContext) {
    // If the argument is wrapped in parentheses, strip them before continuing.
    if let argumentWithoutParentheses = removeParentheses(from: argument) {
      return _checkAmbiguousArgument(argumentWithoutParentheses, in: context)
    }

    // If the argument is explicitly an as? cast already, do not diagnose.
    if argument.is(AsExprSyntax.self) {
      return
    }

    // If we reach this point, then the argument appears to be an ambiguous
    // expression and we aren't sure if the developer intended to unwrap a Bool?
    // or check the value of the wrapped Bool.
    context.diagnose(.optionalBoolExprIsAmbiguous(argument))
  }

  public static var isThrowing: Bool {
    true
  }
}
