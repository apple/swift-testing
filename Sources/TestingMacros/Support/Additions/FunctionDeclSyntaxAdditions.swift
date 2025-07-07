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

extension FunctionDeclSyntax {
  /// Whether or not this function a `static` or `class` function.
  var isStaticOrClass: Bool {
    modifiers.lazy
      .map(\.name.tokenKind)
      .contains { $0 == .keyword(.class) || $0 == .keyword(.static) }
  }

  /// Whether or not this function is a `mutating` function.
  var isMutating: Bool {
    modifiers.lazy
      .map(\.name.tokenKind)
      .contains(.keyword(.mutating))
  }

  /// Whether or not this function is a `nonisolated` function.
  var isNonisolated: Bool {
    modifiers.lazy
      .map(\.name.tokenKind)
      .contains(.keyword(.nonisolated))
  }

  /// Whether or not this function declares an operator.
  var isOperator: Bool {
    switch name.tokenKind {
    case .binaryOperator, .prefixOperator, .postfixOperator:
      true
    default:
      false
    }
  }

  /// The name of this function including parentheses, parameter labels, and
  /// colons.
  var completeName: DeclReferenceExprSyntax {
    func possiblyRaw(_ token: TokenSyntax) -> TokenSyntax {
      if let rawIdentifier = token.rawIdentifier {
        return .identifier("`\(rawIdentifier)`")
      }
      return .identifier(token.textWithoutBackticks)
    }

    return DeclReferenceExprSyntax(
      baseName: possiblyRaw(name),
      argumentNames: DeclNameArgumentsSyntax(
        arguments: DeclNameArgumentListSyntax {
          for parameter in signature.parameterClause.parameters {
            DeclNameArgumentSyntax(name: possiblyRaw(parameter.firstName))
          }
        }
      )
    )
  }

  /// An array of tuples representing this function's parameters.
  var testFunctionParameterList: ArrayExprSyntax {
    ArrayExprSyntax {
      for parameter in signature.parameterClause.parameters {
        ArrayElementSyntax(expression: parameter.testFunctionParameter)
      }
    }
  }

  /// The selector corresponding to this function's name.
  ///
  /// - Note: This property does not support synthesizing a selector for
  ///   functions that take arguments. If the function takes any arguments, the
  ///   value of this property is `nil`.
  ///
  /// - Note: This property does not validate that a function declaration
  ///   actually has a corresponding selector or can be called from Objective-C.
  ///   That information can only be determined at runtime.
  var xcTestCompatibleSelector: ObjCSelectorPieceListSyntax? {
    // First, look for an @objc attribute with an explicit selector, and use
    // that if found.
    let objcAttribute = attributes.lazy
      .compactMap {
        if case let .attribute(attribute) = $0 {
          return attribute
        }
        return nil
      }.first { $0.attributeNameText == "objc" }
    if let objcAttribute, case let .objCName(objCName) = objcAttribute.arguments {
      if true == objCName.first?.name?.textWithoutBackticks.hasPrefix("test") {
        return objCName
      }
      return nil
    }

    // If the function has no arguments and its name starts with "test", it can
    // be discovered by XCTest, so derive its name (taking async/throws into
    // consideration.)
    if signature.parameterClause.parameters.isEmpty {
      var selector = name.textWithoutBackticks
      guard selector.starts(with: "test") else {
        return nil
      }

      // Apply the standard effect-based suffixes.
      var colonToken: TokenSyntax?
      if signature.effectSpecifiers?.asyncSpecifier != nil {
        selector += "WithCompletionHandler"
        colonToken = .colonToken()
      } else {
        let hasThrowsSpecifier: Bool
        hasThrowsSpecifier = signature.effectSpecifiers?.throwsClause != nil
        if hasThrowsSpecifier {
          selector += "AndReturnError"
          colonToken = .colonToken()
        }
      }
      return ObjCSelectorPieceListSyntax {
        ObjCSelectorPieceSyntax(name: .identifier(selector), colon: colonToken)
      }
    }

    return nil
  }
}

// MARK: -

extension FunctionParameterSyntax {
  /// A tuple containing this parameter's name(s) and type.
  ///
  /// This is meant to be included in an array of parameters and passed along
  /// with other test function details.
  ///
  /// ## See Also
  ///
  /// - ``FunctionDeclSyntax/testFunctionParameterList``
  fileprivate var testFunctionParameter: TupleExprSyntax {
    TupleExprSyntax {
      LabeledExprSyntax(label: "firstName", expression: StringLiteralExprSyntax(content: firstName.textWithoutBackticks))

      if let secondName {
        LabeledExprSyntax(label: "secondName", expression: StringLiteralExprSyntax(content: secondName.textWithoutBackticks))
      } else {
        LabeledExprSyntax(label: "secondName", expression: NilLiteralExprSyntax())
      }

      LabeledExprSyntax(label: "type", expression: typeMetatypeExpression)
    }
  }

  /// An expression which refers to the metatype of this parameter's type.
  ///
  /// For example, for the parameter `y` of `func x(y: Int)`, the value of this
  /// property is an expression equivalent to `Int.self`.
  private var typeMetatypeExpression: some ExprSyntaxProtocol {
    // Construct a member access expression, referencing the base type name.
    let baseTypeDeclReferenceExpr = DeclReferenceExprSyntax(baseName: .identifier(baseTypeName))

    // Enclose the base type declaration reference in a 1-element tuple, e.g.
    // `(<baseType>)`. It will be used in a member access expression below, and
    // some types (such as function types) require this.
    //
    // Intentionally avoid using the result builder variant of these APIs due to
    // a bug which affected a range of Swift compilers (including the one
    // currently used to build swift-syntax in the toolchain) and caused one of
    // these APIs to have an incorrect representation in the module interface.
    let metatypeMemberAccessBase = TupleExprSyntax(elements: [LabeledExprSyntax(expression: baseTypeDeclReferenceExpr)])

    return MemberAccessExprSyntax(base: metatypeMemberAccessBase, name: .identifier("self"))
  }
}

extension FunctionParameterSyntax {
  /// The base type name of this parameter.
  var baseTypeName: String {
    // Discard any specifiers such as `inout` or `borrowing`, since we're only
    // trying to obtain the base type to reference it in an expression.
    let baseType = type.as(AttributedTypeSyntax.self)?.baseType ?? type
    return baseType.trimmedDescription
  }
}
