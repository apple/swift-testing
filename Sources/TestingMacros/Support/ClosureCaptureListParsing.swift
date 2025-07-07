//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023–2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// A type representing a value extracted from a closure's capture list.
struct CapturedValueInfo {
  /// The original instance of `ClosureCaptureSyntax` used to create this value.
  var capture: ClosureCaptureSyntax

  /// The name of the captured value.
  var name: TokenSyntax {
    let text = capture.name.textWithoutBackticks
    if text.isValidSwiftIdentifier(for: .variableName) {
      return capture.name
    }
    return .identifier("`\(text)`")
  }

  /// The expression to assign to the captured value.
  var expression: ExprSyntax

  /// The type of the captured value.
  var type: TypeSyntax

  /// The expression to assign to the captured value with type-checking applied.
  var typeCheckedExpression: ExprSyntax {
    #"#__capturedValue(\#(expression.trimmed), \#(literal: name.trimmedDescription), (\#(type.trimmed)).self)"#
  }

  init(_ capture: ClosureCaptureSyntax, in context: some MacroExpansionContext) {
    self.capture = capture
    self.expression = .unreachable
    self.type = "Swift.Never"

    // We don't support capture specifiers at this time.
    if let specifier = capture.specifier {
      context.diagnose(.specifierUnsupported(specifier, on: capture))
      return
    }

    if let (expr, type) = Self._inferExpressionAndType(of: capture, in: context) {
      self.expression = expr
      self.type = type
    } else {
      // Not enough contextual information to derive the type here.
      context.diagnose(.typeOfCaptureIsAmbiguous(capture))
    }
  }

  /// Infer the captured expression and the type of a closure capture list item.
  ///
  /// - Parameters:
  ///   - capture: The closure capture list item to inspect.
  ///   - context: The macro context in which the expression is being parsed.
  ///
  /// - Returns: A tuple containing the expression and type of `capture`, or
  ///   `nil` if they could not be inferred.
  private static func _inferExpressionAndType(of capture: ClosureCaptureSyntax, in context: some MacroExpansionContext) -> (ExprSyntax, TypeSyntax)? {
    if let initializer = capture.initializer {
      // Found an initializer clause. Extract the expression it captures.
      let finder = _ExprTypeFinder(in: context)
      finder.walk(initializer.value)
      if let inferredType = finder.inferredType {
        return (initializer.value, inferredType)
      }
    } else if capture.name.tokenKind == .keyword(.self),
              let typeNameOfLexicalContext = Self._inferSelf(from: context) {
      // Capturing self.
      return (ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.self))), typeNameOfLexicalContext)
    } else if let parameterType = Self._findTypeOfParameter(named: capture.name, in: context.lexicalContext) {
      return (ExprSyntax(DeclReferenceExprSyntax(baseName: capture.name.trimmed)), parameterType)
    }

    return nil
  }

  private final class _ExprTypeFinder<C>: SyntaxAnyVisitor where C: MacroExpansionContext {
    var context: C

    /// The type that was inferred from the visited syntax tree, if any.
    ///
    /// This type has not been fixed up yet. Use ``inferredType`` for the final
    /// derived type.
    private var _inferredType: TypeSyntax?

    /// Whether or not the inferred type has been made optional by e.g. `try?`.
    private var _needsOptionalApplied = false

    /// The type that was inferred from the visited syntax tree, if any.
    var inferredType: TypeSyntax? {
      _inferredType.flatMap { inferredType in
        if inferredType.isSome || inferredType.isAny {
          // `some` and `any` types are not concrete and cannot be inferred.
          nil
        } else if _needsOptionalApplied {
          TypeSyntax(OptionalTypeSyntax(wrappedType: inferredType.trimmed))
        } else {
          inferredType
        }
      }
    }

    init(in context: C) {
      self.context = context
      super.init(viewMode: .sourceAccurate)
    }

    override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
      if inferredType != nil {
        // Another part of the syntax tree has already provided a type. Stop.
        return .skipChildren
      }

      switch node.kind {
      case .asExpr:
        let asExpr = node.cast(AsExprSyntax.self)
        if let type = asExpr.type.as(IdentifierTypeSyntax.self), type.name.tokenKind == .keyword(.Self) {
          // `Self` should resolve to the lexical context's type.
          _inferredType = CapturedValueInfo._inferSelf(from: context)
        } else if asExpr.questionOrExclamationMark?.tokenKind == .postfixQuestionMark {
          // If the caller is using as?, make the type optional.
          _inferredType = TypeSyntax(OptionalTypeSyntax(wrappedType: asExpr.type.trimmed))
        } else {
          _inferredType = asExpr.type
        }
        return .skipChildren

      case .awaitExpr, .unsafeExpr:
        // These effect keywords do not affect the type of the expression.
        return .visitChildren

      case .tryExpr:
        let tryExpr = node.cast(TryExprSyntax.self)
        if tryExpr.questionOrExclamationMark?.tokenKind == .postfixQuestionMark {
          // The resulting type from the inner expression will be optionalized.
          _needsOptionalApplied = true
        }
        return .visitChildren

      case .tupleExpr:
        // If the tuple contains exactly one element, it's just parentheses
        // around that expression.
        let tupleExpr = node.cast(TupleExprSyntax.self)
        if tupleExpr.elements.count == 1 {
          return .visitChildren
        }

        // Otherwise, we need to try to compose the type as a tuple type from
        // the types of all elements in the tuple expression. Note that tuples
        // do not conform to Sendable or Codable, so our current use of this
        // code in exit tests will still diagnose an error, but the error ("must
        // conform") will be more useful than "couldn't infer".
        let elements = tupleExpr.elements.compactMap { element in
          let finder = Self(in: context)
          finder.walk(element.expression)
          return finder.inferredType.map { type in
            TupleTypeElementSyntax(firstName: element.label?.trimmed, type: type.trimmed)
          }
        }
        if elements.count == tupleExpr.elements.count {
          _inferredType = TypeSyntax(
            TupleTypeSyntax(elements: TupleTypeElementListSyntax { elements })
          )
        }
        return .skipChildren

      case .declReferenceExpr:
        // If the reference is to `self` without any arguments, its type can be
        // inferred from the lexical context.
        let expr = node.cast(DeclReferenceExprSyntax.self)
        if expr.baseName.tokenKind == .keyword(.self), expr.argumentNames == nil {
          _inferredType = CapturedValueInfo._inferSelf(from: context)
        }
        return .skipChildren

      case .integerLiteralExpr:
        _inferredType = TypeSyntax(IdentifierTypeSyntax(name: .identifier("IntegerLiteralType")))
        return .skipChildren

      case .floatLiteralExpr:
        _inferredType = TypeSyntax(IdentifierTypeSyntax(name: .identifier("FloatLiteralType")))
        return .skipChildren

      case .booleanLiteralExpr:
        _inferredType = TypeSyntax(IdentifierTypeSyntax(name: .identifier("BooleanLiteralType")))
        return .skipChildren

      case .stringLiteralExpr, .simpleStringLiteralExpr:
        _inferredType = TypeSyntax(IdentifierTypeSyntax(name: .identifier("StringLiteralType")))
        return .skipChildren

      default:
        // We don't know how to infer a type from this syntax node, so do not
        // proceed further.
        return .skipChildren
      }
    }
  }

  /// Get the type of `self` inferred from the given context.
  ///
  /// - Parameters:
  ///   - context: The macro context in which the expression is being parsed.
  ///
  /// - Returns: The type in `lexicalContext` corresponding to `Self`, or `nil`
  ///   if it could not be determined.
  private static func _inferSelf(from context: some MacroExpansionContext) -> TypeSyntax? {
    let lexicalContext = context.lexicalContext.drop { !$0.isProtocol((any DeclGroupSyntax).self) }
    return context.type(ofLexicalContext: lexicalContext)
  }

  /// Find a function or closure parameter in the given lexical context with a
  /// given name and return its type.
  ///
  /// - Parameters:
  ///   - parameterName: The name of the parameter of interest.
  ///   - lexicalContext: The lexical context to examine.
  ///
  /// - Returns: The Swift type of first parameter found whose name matches, or
  ///   `nil` if none was found. The lexical context is searched in the order
  ///   provided which, by default, starts with the innermost scope.
  private static func _findTypeOfParameter(named parameterName: TokenSyntax, in lexicalContext: [Syntax]) -> TypeSyntax? {
    for lexicalContext in lexicalContext {
      var parameterType: TypeSyntax?
      if let functionDecl = lexicalContext.as(FunctionDeclSyntax.self) {
        parameterType = functionDecl.signature.parameterClause.parameters
          .first { ($0.secondName ?? $0.firstName).tokenKind == parameterName.tokenKind }
          .map(\.type)
      } else if let closureExpr = lexicalContext.as(ClosureExprSyntax.self) {
        if case let .parameterClause(parameterClause) = closureExpr.signature?.parameterClause {
          parameterType = parameterClause.parameters
            .first { ($0.secondName ?? $0.firstName).tokenKind == parameterName.tokenKind }
            .flatMap(\.type)
        }
      } else if lexicalContext.is(DeclSyntax.self) {
        // If we've reached any other enclosing declaration, then any parameters
        // beyond it won't be capturable and thus it isn't possible to infer
        // types from them (any capture of `x`, for instance, must refer to some
        // more-local variable with that name, not to a parameter named `x`.)
        return nil
      }

      if let parameterType {
        return parameterType
      }
    }

    return nil
  }
}
