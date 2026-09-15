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
import SwiftParser

/// A type describing information parsed from a `@Test` or `@Suite` attribute.
struct AttributeInfo {
  /// The attribute node that was parsed to produce this instance.
  var attribute: AttributeSyntax

  /// The declaration to which ``attribute`` was attached.
  var declaration: DeclSyntax

  /// The display name of the attribute, if present.
  var displayName: StringLiteralExprSyntax?

  /// The traits applied to the attribute, if any.
  var traits = [ExprSyntax]()

  /// Test arguments passed to a parameterized test function, if any.
  ///
  /// When non-`nil`, the value of this property is an array beginning with the
  /// argument passed to this attribute for the parameter labeled `arguments:`
  /// followed by all of the remaining, unlabeled arguments.
  var testFunctionArguments: [Argument]?

  /// Whether or not this attribute specifies arguments to the associated test
  /// function.
  var hasFunctionArguments: Bool {
    testFunctionArguments != nil
  }

  /// The source bounds of the attribute.
  ///
  /// When parsing, the testing library uses the start of the attribute's name
  /// as the canonical lower-bound source location of the test or suite and uses
  /// the end of the attached declaration as the upper-bound source location.
  var sourceBounds: ExprSyntax

  /// Flags to apply to the test content record generated from this instance.
  var testContentRecordFlags: UInt32 {
    var result = UInt32(0)

    if declaration.is(FunctionDeclSyntax.self) {
      if hasFunctionArguments {
        result |= 1 << 1 /* is parameterized */
      }
    } else {
      result |= 1 << 0 /* suite decl */
    }

    return result
  }

  /// Create an instance of this type by parsing a `@Test` or `@Suite`
  /// attribute.
  ///
  /// - Parameters:
  ///   - attribute: The attribute whose arguments should be extracted. If this
  ///     attribute is not a `@Test` or `@Suite` attribute, the result is
  ///     unspecified.
  ///   - declaration: The declaration to which `attribute` is attached.
  ///   - context: The macro context in which the expression is being parsed.
  init(byParsing attribute: AttributeSyntax, on declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) {
    self.attribute = attribute
    self.declaration = DeclSyntax(declaration)

    var displayNameArgument: LabeledExprListSyntax.Element?
    var nonDisplayNameArguments: [Argument] = []
    if let arguments = attribute.arguments, case let .argumentList(argumentList) = arguments {
      // If the first argument is an unlabelled string literal, it's the display
      // name of the test or suite. If it's anything else, including a nil
      // literal, the test does not have a display name.
      if let firstArgument = argumentList.first {
        let firstArgumentHasLabel = (firstArgument.label != nil)
        if !firstArgumentHasLabel, let stringLiteral = firstArgument.expression.as(StringLiteralExprSyntax.self) {
          displayName = stringLiteral
          displayNameArgument = firstArgument
          nonDisplayNameArguments = argumentList.dropFirst().map(Argument.init)
        } else if !firstArgumentHasLabel, firstArgument.expression.is(NilLiteralExprSyntax.self) {
          displayNameArgument = firstArgument
          nonDisplayNameArguments = argumentList.dropFirst().map(Argument.init)
        } else {
          nonDisplayNameArguments = argumentList.map(Argument.init)
        }
      }
    }

    // Disallow an explicit display name for tests and suites with raw
    // identifier names as it's redundant and potentially confusing.
    if let namedDecl = declaration.asProtocol((any NamedDeclSyntax).self),
       let rawIdentifier = namedDecl.name.rawIdentifier {
      if let displayName, let displayNameArgument {
        context.diagnose(.declaration(namedDecl, hasExtraneousDisplayName: displayName, fromArgument: displayNameArgument, using: attribute))
      } else {
        displayName = StringLiteralExprSyntax(content: rawIdentifier)
      }
    }

    // If there was a display name but it's completely empty, emit a diagnostic
    // since this can cause confusion isn't generally recommended. Note that
    // this is only possible for string literal display names; the compiler
    // enforces that raw identifiers must be non-empty.
    if let namedDecl = declaration.asProtocol((any NamedDeclSyntax).self),
       let displayName, let displayNameArgument,
        displayName.representedLiteralValue?.isEmpty == true {
      context.diagnose(.declaration(namedDecl, hasEmptyDisplayName: displayName, fromArgument: displayNameArgument, using: attribute))
    }

    // Look for any traits in the remaining arguments and slice them off. Traits
    // are the remaining unlabelled arguments. The first labelled argument (if
    // present) is the start of subsequent context-specific arguments.
    if !nonDisplayNameArguments.isEmpty {
      if let labelledArgumentIndex = nonDisplayNameArguments.firstIndex(where: { $0.label != nil }) {
        // There is an argument with a label, so splice there.
        traits = nonDisplayNameArguments[..<labelledArgumentIndex].map(\.expression)
        testFunctionArguments = Array(nonDisplayNameArguments[labelledArgumentIndex...])
      } else {
        // No argument has a label, so all the remaining arguments are traits.
        traits = nonDisplayNameArguments.map(\.expression)
      }
    }

    // Combine traits from other sources (leading comments and availability
    // attributes) if applicable.
    traits += createCommentTraitExprs(for: declaration)
    if let declaration = declaration.asProtocol((any WithAttributesSyntax).self) {
      traits += createAvailabilityTraitExprs(for: declaration, in: context)
    }

    // Use the start of the test attribute's name as the canonical source
    // location of the test.
    sourceBounds = createSourceBoundsExpr(from: attribute.attributeName, to: declaration, in: context)

    // After this instance is fully initialized, diagnose known issues.
    diagnoseIssuesWithTraits(in: context)
  }

  /// Convert this instance to a series of arguments suitable for passing to a
  /// function like `.__type()` or `.__function()`.
  ///
  /// - Parameters:
  ///   - context: The macro context in which the expression is being parsed.
  ///
  /// - Returns: A copy of `self`, converted to one or more function argument
  ///   syntax nodes.
  func functionArgumentList(in context: some MacroExpansionContext) -> LabeledExprListSyntax {
    var arguments = [Argument]()

    if let displayName {
      arguments.append(Argument(label: .identifier("displayName"), expression: displayName))
    }
    arguments.append(Argument(label: .identifier("traits"), expression: ArrayExprSyntax {
      for traitExpr in traits {
        ArrayElementSyntax(expression: traitExpr).trimmed
      }
    }))

    // If there are any parameterized test function arguments, wrap each in a
    // closure so they may be evaluated lazily at runtime.
    if let testFunctionArguments {
      arguments += testFunctionArguments.enumerated().map { index, argument in
        var copy = argument
        var expr = copy.expression.trimmed
        if let contextualType = _contextualTypeForLiteralArgument(
          at: index,
          for: expr,
          among: testFunctionArguments
        ) {
          expr = ExprSyntax(
            AsExprSyntax(
              expression: expr,
              asKeyword: .keyword(.as, leadingTrivia: .space, trailingTrivia: .space),
              type: contextualType.trimmed
            )
          )
        }
        copy.expression = .init(ClosureExprSyntax { expr })
        return copy
      }
    }

    arguments.append(Argument(label: "sourceBounds", expression: sourceBounds))

    return LabeledExprListSyntax(arguments)
  }

  /// The contextual type to explicitly apply to a literal `arguments:`
  /// expression after it is wrapped in a closure for lazy evaluation.
  ///
  /// Parameterized `@Test` declarations are modeled in terms of the collection
  /// type supplied to the macro, but macro expansion only sees source syntax.
  /// When the `arguments:` parameter is supplied as an array literal, derive
  /// the corresponding array type from the test function's parameters so the
  /// literal retains enough contextual type information after lazy wrapping.
  ///
  /// This applies to both the single-collection form and the overloads where
  /// each `arguments:` expression corresponds directly to one parameter.
  ///
  /// - Parameters:
  ///   - index: The position of `expression` within `testFunctionArguments`.
  ///   - expression: The argument expression being wrapped for lazy evaluation.
  ///   - testFunctionArguments: The full list of argument expressions supplied
  ///     to the parameterized `@Test`.
  ///
  /// - Returns: The array type to apply to `expression`, or `nil` if no
  ///   contextual type reconstruction is needed.
  private func _contextualTypeForLiteralArgument(
    at index: Int,
    for expression: ExprSyntax,
    among testFunctionArguments: [Argument]
  ) -> TypeSyntax? {
    guard let functionDecl = declaration.as(FunctionDeclSyntax.self) else {
      return nil
    }

    let parameters = Array(functionDecl.signature.parameterClause.parameters)
    if parameters.isEmpty {
      return nil
    }

    if expression.is(ArrayExprSyntax.self) {
      if testFunctionArguments.count == parameters.count {
        let parameter = parameters[index]
        return TypeSyntax(
          ArrayTypeSyntax(element: parameter.baseType.trimmed)
        )
      }

      if testFunctionArguments.count == 1 {
        if parameters.count == 1, let parameter = parameters.first {
          // A single-parameter test expects collection elements of the parameter
          // type itself, not tuple-shaped elements.
          return TypeSyntax(
            ArrayTypeSyntax(element: parameter.baseType.trimmed)
          )
        }
        let elementType = TypeSyntax(
          TupleTypeSyntax(elements: TupleTypeElementListSyntax {
            for parameter in parameters {
              TupleTypeElementSyntax(type: parameter.baseType.trimmed)
            }
          })
        )
        return TypeSyntax(ArrayTypeSyntax(element: elementType))
      }
    } else if expression.is(DictionaryExprSyntax.self) {
      if testFunctionArguments.count == 1, parameters.count == 2 {
        return TypeSyntax(
          MemberTypeSyntax(
            baseType: IdentifierTypeSyntax(name: .identifier("Swift")),
            name: .identifier("KeyValuePairs"),
            genericArgumentClause: GenericArgumentClauseSyntax(
              arguments: GenericArgumentListSyntax {
                GenericArgumentSyntax(argument: .type(parameters[0].baseType.trimmed))
                GenericArgumentSyntax(argument: .type(parameters[1].baseType.trimmed))
              }
            )
          )
        )
      }
    }

    return nil
  }
}
