//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
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
import SwiftSyntaxMacroExpansion

/// A type describing diagnostic messages emitted by this module's macro during
/// evaluation.
struct DiagnosticMessage: SwiftDiagnostics.DiagnosticMessage {
  /// Create a diagnostic message for the macro with the specified name
  /// stating that its condition will always pass or fail.
  ///
  /// - Parameters:
  ///   - condition: The condition expression being diagnosed.
  ///   - value: The value that this condition always evaluates to.
  ///   - macro: The macro expression.
  ///
  /// - Returns: A diagnostic message.
  static func condition(_ condition: ExprSyntax, isAlways value: Bool, in macro: some FreestandingMacroExpansionSyntax) -> Self {
    let action = value ? "pass" : "fail"
    return Self(
      syntax: Syntax(condition),
      message: "\(_macroName(macro)) will always \(action) here; use 'Bool(\(condition))' to silence this warning",
      severity: value ? .note : .warning
    )
  }

  /// Create a diagnostic message stating that a macro should be used with
  /// `as?`, not `as!`.
  ///
  /// - Parameters:
  ///   - expr: The `as!` expression being diagnosed.
  ///   - macro: The macro expression.
  ///
  /// - Returns: A diagnostic message.
  static func asExclamationMarkIsEvaluatedEarly(_ expr: AsExprSyntax, in macro: some FreestandingMacroExpansionSyntax) -> Self {
    return Self(
      syntax: Syntax(expr.asKeyword),
      message: "Expression '\(expr.trimmed)' will be evaluated before \(_macroName(macro)) is invoked; use 'as?' instead of 'as!' to silence this warning",
      severity: .warning
    )
  }

  /// Get the human-readable name of the given freestanding macro.
  ///
  /// - Parameters:
  ///   - macro: The freestanding macro node to name.
  ///
  /// - Returns: The name of the macro as understood by a developer, such as
  ///   `"'#expect(_:_:)'"`. Includes single quotes.
  private static func _macroName(_ macro: some FreestandingMacroExpansionSyntax) -> String {
    var labels = ["_", "_"]
    if let firstArgumentLabel = macro.arguments.first?.label?.textWithoutBackticks {
      labels[0] = firstArgumentLabel
    }
    let argumentLabels = labels.map { "\($0):" }.joined()
    return "'#\(macro.macroName.textWithoutBackticks)(\(argumentLabels))'"
  }

  /// Get the human-readable name of the given attached macro.
  ///
  /// - Parameters:
  ///   - attribute: The attached macro node to name.
  ///
  /// - Returns: The name of the macro as understood by a developer, such as
  ///   `"'@Test'"`. Include single quotes.
  private static func _macroName(_ attribute: AttributeSyntax) -> String {
    // SEE: https://github.com/swiftlang/swift/blob/main/docs/Diagnostics.md?plain=1#L44
    "'\(attribute.attributeNameText)'"
  }

  /// Get a string corresponding to the specified syntax node (for instance,
  /// `"function"` for a function declaration.)
  ///
  /// - Parameters:
  ///   - node: The node of interest.
  ///   - includeA: Whether or not to include "a" or "an".
  ///
  /// - Returns: A string describing the kind of `node`, or `"symbol"` in the
  ///   fallback case.
  private static func _kindString(for node: some SyntaxProtocol, includeA: Bool = false) -> String {
    let result: (value: String, article: String)
    switch node.kind {
    case .functionDecl:
      if node.cast(FunctionDeclSyntax.self).isOperator {
        result = ("operator", "an")
      } else {
        result = ("function", "a")
      }
    case .classDecl:
      result = ("class", "a")
    case .structDecl:
      result = ("structure", "a")
    case .enumDecl:
      result = ("enumeration", "an")
    case .actorDecl:
      result = ("actor", "an")
    case .variableDecl:
      // This string could be "variable" in some contexts but none we're
      // currently looking at.
      result = ("property", "a")
    case .initializerDecl:
      result = ("initializer", "an")
    case .deinitializerDecl:
      result = ("deinitializer", "a")
    case .subscriptDecl:
      result = ("subscript", "a")
    case .enumCaseDecl:
      result = ("enumeration case", "an")
    case .typeAliasDecl:
      result = ("typealias", "a")
    case .macroDecl:
      result = ("macro", "a")
    case .protocolDecl:
      result = ("protocol", "a")
    case .closureExpr:
      result = ("closure", "a")
    default:
      result = ("declaration", "this")
    }

    if includeA {
      return "\(result.article) \(result.value)"
    }
    return result.value
  }

  /// Create a diagnostic message stating that the `@Test` or `@Suite` attribute
  /// cannot be applied to a declaration multiple times.
  ///
  /// - Parameters:
  ///   - attributes: The conflicting attributes. This array must not be empty.
  ///   - decl: The declaration in question.
  ///
  /// - Returns: A diagnostic message.
  static func multipleAttributesNotSupported(_ attributes: [AttributeSyntax], on decl: some SyntaxProtocol) -> Self {
    precondition(!attributes.isEmpty)
    return Self(
      syntax: Syntax(attributes.last!),
      message: "Attribute \(_macroName(attributes.last!)) cannot be applied to \(_kindString(for: decl, includeA: true)) more than once",
      severity: .error
    )
  }

  /// Create a diagnostic message stating that the `@Test` or `@Suite` attribute
  /// cannot be applied to a generic declaration.
  ///
  /// - Parameters:
  ///   - decl: The generic declaration in question.
  ///   - attribute: The `@Test` or `@Suite` attribute.
  ///   - genericClause: The child node on `genericDecl` that makes it generic.
  ///   - genericDecl: The generic declaration to which `genericClause` is
  ///     attached, possibly equal to `decl`.
  ///
  /// - Returns: A diagnostic message.
  static func genericDeclarationNotSupported(_ decl: some SyntaxProtocol, whenUsing attribute: AttributeSyntax, becauseOf genericClause: some SyntaxProtocol, on genericDecl: some SyntaxProtocol) -> Self {
    if Syntax(decl) != Syntax(genericDecl), genericDecl.isProtocol((any DeclGroupSyntax).self) {
      return .containingNodeUnsupported(genericDecl, genericBecauseOf: Syntax(genericClause), whenUsing: attribute, on: decl)
    } else {
      // Avoid using a syntax node from a lexical context (it won't have source
      // location information.)
      let syntax = (genericClause.root != decl.root) ? Syntax(decl) : Syntax(genericClause)
      return Self(
        syntax: syntax,
        message: "Attribute \(_macroName(attribute)) cannot be applied to a generic \(_kindString(for: decl))",
        severity: .error
      )
    }
  }

  /// Create a diagnostic message stating that the `@Test` or `@Suite` attribute
  /// cannot be applied to a type that also has an availability attribute.
  ///
  /// - Parameters:
  ///   - availabilityAttribute: The `@available` attribute in question.
  ///   - decl: The declaration in question.
  ///   - attribute: The `@Test` or `@Suite` attribute.
  ///
  /// - Returns: A diagnostic message.
  ///
  /// - Bug: This combination of attributes requires the ability to resolve
  ///   semantic availability and fully-qualified names for types at macro
  ///   expansion time. ([104081994](rdar://104081994))
  static func availabilityAttributeNotSupported(_ availabilityAttribute: AttributeSyntax, on decl: some SyntaxProtocol, whenUsing attribute: AttributeSyntax) -> Self {
    // Avoid using a syntax node from a lexical context (it won't have source
    // location information.)
    let syntax = (availabilityAttribute.root != decl.root) ? Syntax(decl) : Syntax(availabilityAttribute)
    return Self(
      syntax: syntax,
      message: "Attribute \(_macroName(attribute)) cannot be applied to this \(_kindString(for: decl)) because it has been marked '\(availabilityAttribute.trimmed)'",
      severity: .error
    )
  }

  /// Create a diagnostic message stating that the given attribute cannot be
  /// applied to the given declaration.
  ///
  /// - Parameters:
  ///   - attribute: The `@Test` or `@Suite` attribute.
  ///   - decl: The declaration in question.
  ///
  /// - Returns: A diagnostic message.
  static func attributeNotSupported(_ attribute: AttributeSyntax, on decl: some SyntaxProtocol) -> Self {
    Self(
      syntax: Syntax(decl),
      message: "Attribute \(_macroName(attribute)) cannot be applied to \(_kindString(for: decl, includeA: true))",
      severity: .error
    )
  }

  /// Create a diagnostic message stating that the given attribute can only be
  /// applied to `static` properties.
  ///
  /// - Parameters:
  ///   - attribute: The `@Tag` attribute.
  ///   - decl: The declaration in question.
  ///
  /// - Returns: A diagnostic message.
  static func nonStaticTagDeclarationNotSupported(_ attribute: AttributeSyntax, on decl: VariableDeclSyntax) -> Self {
    var declCopy = decl
    declCopy.modifiers = DeclModifierListSyntax {
      for modifier in decl.modifiers {
        modifier
      }
      DeclModifierSyntax(name: .keyword(.static))
    }.with(\.trailingTrivia, .space)

    return Self(
      syntax: Syntax(decl),
      message: "Attribute \(_macroName(attribute)) cannot be applied to an instance property",
      severity: .error,
      fixIts: [
        FixIt(
          message: MacroExpansionFixItMessage("Add 'static'"),
          changes: [.replace(oldNode: Syntax(decl), newNode: Syntax(declCopy)),]
        ),
      ]
    )
  }

  /// Create a diagnostic message stating that the given attribute cannot be
  /// applied to global variables.
  ///
  /// - Parameters:
  ///   - decl: The declaration in question.
  ///   - attribute: The `@Tag` attribute.
  ///
  /// - Returns: A diagnostic message.
  static func nonMemberTagDeclarationNotSupported(_ decl: VariableDeclSyntax, whenUsing attribute: AttributeSyntax) -> Self {
    var declCopy = decl
    declCopy.modifiers = DeclModifierListSyntax {
      for modifier in decl.modifiers {
        modifier
      }
      DeclModifierSyntax(name: .keyword(.static))
    }.with(\.trailingTrivia, .space)
    let replacementDecl: DeclSyntax = """
    extension Tag {
      \(declCopy.trimmed)
    }
    """

    return Self(
      syntax: Syntax(decl),
      message: "Attribute \(_macroName(attribute)) cannot be applied to a global variable",
      severity: .error,
      fixIts: [
        FixIt(
          message: MacroExpansionFixItMessage("Declare in an extension to 'Tag'"),
          changes: [.replace(oldNode: Syntax(decl), newNode: Syntax(replacementDecl)),]
        ),
        FixIt(
          message: MacroExpansionFixItMessage("Remove attribute \(_macroName(attribute))"),
          changes: [.replace(oldNode: Syntax(attribute), newNode: Syntax("" as ExprSyntax))]
        ),
      ]
    )
  }

  /// Create a diagnostic message stating that the given attribute cannot be
  /// applied to global variables.
  ///
  /// - Parameters:
  ///   - attribute: The `@Tag` attribute.
  ///   - decl: The declaration in question.
  ///   - declaredType: The type of `decl` as specified by it.
  ///   - resolvedType: The _actual_ type of `decl`, if known and differing from
  ///     `declaredType` (i.e. if `type` is `Self`.)
  ///
  /// - Returns: A diagnostic message.
  static func mistypedTagDeclarationNotSupported(_ attribute: AttributeSyntax, on decl: VariableDeclSyntax, declaredType: TypeSyntax, resolvedType: TypeSyntax? = nil) -> Self {
    let resolvedType = resolvedType ?? declaredType
    return Self(
      syntax: Syntax(decl),
      message: "Attribute \(_macroName(attribute)) cannot be applied to \(_kindString(for: decl, includeA: true)) of type '\(resolvedType.trimmed)'",
      severity: .error,
      fixIts: [
        FixIt(
          message: MacroExpansionFixItMessage("Change type to 'Tag'"),
          changes: [.replace(oldNode: Syntax(declaredType), newNode: Syntax("Tag" as TypeSyntax))]
        ),
        FixIt(
          message: MacroExpansionFixItMessage("Remove attribute \(_macroName(attribute))"),
          changes: [.replace(oldNode: Syntax(attribute), newNode: Syntax("" as ExprSyntax))]
        ),
      ]
    )
  }

  /// Create a diagnostic message stating that the given attribute cannot be
  /// used within a lexical context.
  ///
  /// - Parameters:
  ///   - node: The lexical context preventing the use of `attribute`.
  ///   - genericClause: If not `nil`, a syntax node that causes `node` to be
  ///     generic.
  ///   - attribute: The `@Test` or `@Suite` attribute.
  ///   - decl: The declaration in question (contained in `node`.)
  ///   - escapableNonConformance: The suppressed conformance to `Escapable` for
  ///     `decl`, if present.
  ///
  /// - Returns: A diagnostic message.
  static func containingNodeUnsupported(_ node: some SyntaxProtocol, genericBecauseOf genericClause: Syntax? = nil, whenUsing attribute: AttributeSyntax, on decl: some SyntaxProtocol, withSuppressedConformanceToEscapable escapableNonConformance: SuppressedTypeSyntax? = nil) -> Self {
    // Avoid using a syntax node from a lexical context (it won't have source
    // location information.)
    let syntax: Syntax = if let genericClause, attribute.root == genericClause.root {
      // Prefer the generic clause if available as the root cause.
      genericClause
    } else if let escapableNonConformance, attribute.root == escapableNonConformance.root {
      // Then the ~Escapable conformance if present.
      Syntax(escapableNonConformance)
    } else if attribute.root == node.root {
      // Next best choice is the unsupported containing node.
      Syntax(node)
    } else {
      // Finally, fall back to the attribute, which we assume is not detached.
      Syntax(attribute)
    }

    // Figure out the message to present.
    var message = "Attribute \(_macroName(attribute)) cannot be applied to \(_kindString(for: decl, includeA: true))"
    let generic = if genericClause != nil {
      " generic"
    } else {
      ""
    }
    if let functionDecl = node.as(FunctionDeclSyntax.self) {
      message += " within\(generic) function '\(functionDecl.completeName)'"
    } else if let namedDecl = node.asProtocol((any NamedDeclSyntax).self) {
      message += " within\(generic) \(_kindString(for: node)) '\(namedDecl.name.textWithoutBackticks)'"
    } else if let extensionDecl = node.as(ExtensionDeclSyntax.self) {
      // Subtly different phrasing from the NamedDeclSyntax case above.
      if genericClause != nil {
        message += " within a generic extension to type '\(extensionDecl.extendedType.trimmedDescription)'"
      } else {
        message += " within an extension to type '\(extensionDecl.extendedType.trimmedDescription)'"
      }
    } else {
      if genericClause != nil {
        message += " within a generic \(_kindString(for: node))"
      } else {
        message += " within \(_kindString(for: node, includeA: true))"
      }
    }
    if escapableNonConformance != nil {
      message += " because its conformance to 'Escapable' has been suppressed"
    }

    return Self(syntax: syntax, message: message, severity: .error)
  }

  /// Create a diagnostic message stating that the given attribute cannot be
  /// applied to the given declaration outside the scope of an extension to
  /// `Tag`.
  ///
  /// - Parameters:
  ///   - attribute: The `@Tag` attribute.
  ///   - decl: The declaration in question.
  ///
  /// - Returns: A diagnostic message.
  static func attributeNotSupportedOutsideTagExtension(_ attribute: AttributeSyntax, on decl: VariableDeclSyntax) -> Self {
    Self(
      syntax: Syntax(decl),
      message: "Attribute \(_macroName(attribute)) cannot be applied to \(_kindString(for: decl, includeA: true)) except in an extension to 'Tag'",
      severity: .error
    )
  }

  /// Create a diagnostic message stating that the given attribute has no effect
  /// when applied to the given extension declaration.
  ///
  /// - Parameters:
  ///   - attribute: The `@Test` or `@Suite` attribute.
  ///   - decl: The extension declaration in question.
  ///
  /// - Returns: A diagnostic message.
  static func attributeHasNoEffect(_ attribute: AttributeSyntax, on decl: ExtensionDeclSyntax) -> Self {
    Self(
      syntax: Syntax(decl),
      message: "Attribute \(_macroName(attribute)) has no effect when applied to an extension",
      severity: .error,
      fixIts: [
        FixIt(
          message: MacroExpansionFixItMessage("Remove attribute \(_macroName(attribute))"),
          changes: [.replace(oldNode: Syntax(attribute), newNode: Syntax("" as ExprSyntax))]
        ),
      ]
    )
  }

  /// Create a diagnostic message stating that the given attribute has the wrong
  /// number of arguments when applied to the given function declaration.
  ///
  /// - Parameters:
  ///   - attribute: The `@Test` attribute.
  ///   - functionDecl: The declaration in question.
  ///
  /// - Returns: A diagnostic message.
  static func attributeArgumentCountIncorrect(_ attribute: AttributeSyntax, on functionDecl: FunctionDeclSyntax) -> Self {
    let expectedArgumentCount = functionDecl.signature.parameterClause.parameters.count
    if expectedArgumentCount == 0 {
      return Self(
        syntax: Syntax(functionDecl),
        message: "Attribute \(_macroName(attribute)) cannot specify arguments when used with function '\(functionDecl.completeName)' because it does not take any",
        severity: .error
      )
    } else {
      return Self(
        syntax: Syntax(functionDecl),
        message: "Attribute \(_macroName(attribute)) must specify arguments when used with function '\(functionDecl.completeName)'",
        severity: .error,
        fixIts: _addArgumentsFixIts(for: attribute, given: functionDecl.signature.parameterClause.parameters)
      )
    }
  }

  /// Create fix-its for a diagnostic stating that the given attribute must
  /// specify arguments since it is applied to a function which has parameters.
  ///
  /// - Parameters:
  ///   - attribute: The `@Test` attribute.
  ///   - parameters: The parameter list of the function `attribute` is applied
  ///     to.
  ///
  /// - Returns: An array of fix-its to include in a diagnostic.
  private static func _addArgumentsFixIts(for attribute: AttributeSyntax, given parameters: FunctionParameterListSyntax) -> [FixIt] {
    let baseArguments: LabeledExprListSyntax
    if let existingArguments = attribute.arguments {
      guard case var .argumentList(existingLabeledArguments) = existingArguments else {
        // If there are existing arguments but they are of an unexpected type,
        // don't attempt to provide any fix-its.
        return []
      }

      // If the existing argument list is non-empty, ensure the last argument
      // has a trailing comma and space.
      if !existingLabeledArguments.isEmpty {
        let lastIndex = existingLabeledArguments.index(before: existingLabeledArguments.endIndex)
        existingLabeledArguments[lastIndex].trailingComma = .commaToken(trailingTrivia: .space)
      }

      baseArguments = existingLabeledArguments
    } else {
      baseArguments = .init()
    }

    var fixIts: [FixIt] = []
    func addFixIt(_ message: String, appendingArguments arguments: some Collection<LabeledExprSyntax>) {
      var newAttribute = attribute
      newAttribute.leftParen = .leftParenToken()
      newAttribute.arguments = .argumentList(baseArguments + arguments)
      let trailingTrivia = newAttribute.rightParen?.trailingTrivia
        ?? newAttribute.attributeName.as(IdentifierTypeSyntax.self)?.name.trailingTrivia
        ?? .space
      newAttribute.rightParen = .rightParenToken(trailingTrivia: trailingTrivia)
      newAttribute.attributeName = newAttribute.attributeName.trimmed

      fixIts.append(FixIt(
        message: MacroExpansionFixItMessage(message),
        changes: [.replace(oldNode: Syntax(attribute), newNode: Syntax(newAttribute))]
      ))
    }

    // Fix-It to add 'arguments:' with one collection. If the function has 2 or
    // more parameters, the elements of the placeholder collection are of tuple
    // type.
    do {
      let argumentsCollectionType = if parameters.count == 1, let parameter = parameters.first {
        "[\(parameter.baseTypeName)]"
      } else {
        "[(\(parameters.map(\.baseTypeName).joined(separator: ", ")))]"
      }

      addFixIt(
        "Add 'arguments:' with one collection",
        appendingArguments: [LabeledExprSyntax(label: "arguments", expression: EditorPlaceholderExprSyntax(type: argumentsCollectionType))]
      )
    }

    // Fix-It to add 'arguments:' with all combinations of <N> collections,
    // where <N> is the count of the function's parameters. Only offered for
    // functions with 2 parameters.
    if parameters.count == 2 {
      let additionalArguments = parameters.indices.map { index in
        let label = index == parameters.startIndex ? "arguments" : nil
        let argumentsCollectionType = "[\(parameters[index].baseTypeName)]"
        return LabeledExprSyntax(
          label: label.map { .identifier($0) },
          colon: label == nil ? nil : .colonToken(trailingTrivia: .space),
          expression: EditorPlaceholderExprSyntax(type: argumentsCollectionType),
          trailingComma: parameters.index(after: index) < parameters.endIndex ? .commaToken(trailingTrivia: .space) : nil
        )
      }
      addFixIt("Add 'arguments:' with all combinations of \(parameters.count) collections", appendingArguments: additionalArguments)
    }

    return fixIts
  }

  /// Create a diagnostic message stating that `@Test` or `@Suite` is
  /// incompatible with `XCTestCase` and its subclasses.
  ///
  /// - Parameters:
  ///   - decl: The expression or declaration referring to the unsupported
  ///     XCTest symbol.
  ///   - attribute: The `@Test` or `@Suite` attribute.
  ///
  /// - Returns: A diagnostic message.
  static func xcTestCaseNotSupported(_ decl: some SyntaxProtocol, whenUsing attribute: AttributeSyntax) -> Self {
    Self(
      syntax: Syntax(decl),
      message: "Attribute \(_macroName(attribute)) cannot be applied to a subclass of 'XCTestCase'",
      severity: .error
    )
  }

  /// Create a diagnostic message stating that a parameter to a test function
  /// cannot be marked with the given specifier (such as `inout`).
  ///
  /// - Parameters:
  ///   - specifier: The invalid specifier token.
  ///   - parameter: The incorrectly-specified parameter.
  ///   - attribute: The `@Test` or `@Suite` attribute.
  ///
  /// - Returns: A diagnostic message.
  static func specifierNotSupported(_ specifier: TokenSyntax, on parameter: FunctionParameterSyntax, whenUsing attribute: AttributeSyntax) -> Self {
    Self(
      syntax: Syntax(parameter),
      message: "Attribute \(_macroName(attribute)) cannot be applied to a function with a parameter marked '\(specifier.textWithoutBackticks)'",
      severity: .error
    )
  }

  /// Create a diagnostic message stating that a test function should not return
  /// a result.
  ///
  /// - Parameters:
  ///   - returnType: The unsupported return type.
  ///   - decl: The declaration with an unsupported return type.
  ///   - attribute: The `@Test` or `@Suite` attribute.
  ///
  /// - Returns: A diagnostic message.
  static func returnTypeNotSupported(_ returnType: TypeSyntax, on decl: some SyntaxProtocol, whenUsing attribute: AttributeSyntax) -> Self {
    Self(
      syntax: Syntax(returnType),
      message: "The result of this \(_kindString(for: decl)) will be discarded during testing",
      severity: .warning
    )
  }

  /// Create a diagnostic message stating that the expression used to declare a
  /// tag on a test or suite is not supported.
  ///
  /// - Parameters:
  ///   - tagExpr: The unsupported tag expression.
  ///   - attribute: The `@Test` or `@Suite` attribute.
  ///
  /// - Returns: A diagnostic message.
  static func tagExprNotSupported(_ tagExpr: some SyntaxProtocol, in attribute: AttributeSyntax) -> Self {
    Self(
      syntax: Syntax(tagExpr),
      message: "Tag '\(tagExpr.trimmed)' cannot be used with attribute \(_macroName(attribute)); pass a member of 'Tag' or a string literal instead",
      severity: .error
    )
  }

  /// Create a diagnostic message stating that the URL string passed to a trait
  /// is not a valid URL.
  ///
  /// - Parameters:
  ///   - urlExpr: The unsupported URL string.
  ///   - traitExpr: The trait expression containing `urlExpr`.
  ///   - attribute: The `@Test` or `@Suite` attribute.
  ///
  /// - Returns: A diagnostic message.
  static func urlExprNotValid(_ urlExpr: StringLiteralExprSyntax, in traitExpr: FunctionCallExprSyntax, in attribute: AttributeSyntax) -> Self {
    // We do not currently expect anything other than "[...].bug()" here, so
    // force-cast to MemberAccessExprSyntax to get the name of the trait.
    let traitName = traitExpr.calledExpression.cast(MemberAccessExprSyntax.self).declName
    let urlString = urlExpr.representedLiteralValue!

    return Self(
      syntax: Syntax(urlExpr),
      message: #"URL "\#(urlString)" is invalid and cannot be used with trait '\#(traitName.trimmed)' in attribute \#(_macroName(attribute))"#,
      severity: .warning,
      fixIts: [
        FixIt(
          message: MacroExpansionFixItMessage(#"Replace "\#(urlString)" with URL"#),
          changes: [.replace(oldNode: Syntax(urlExpr), newNode: Syntax(EditorPlaceholderExprSyntax("url", type: "String")))]
        ),
        FixIt(
          message: MacroExpansionFixItMessage("Remove trait '\(traitName.trimmed)'"),
          changes: [.replace(oldNode: Syntax(traitExpr), newNode: Syntax("" as ExprSyntax))]
        ),
      ]
    )
  }

  /// Create a diagnostic message stating that a trait has no effect on a given
  /// attribute (assumed to be a non-parameterized `@Test` attribute.)
  ///
  /// - Parameters:
  ///   - traitExpr: The unsupported trait expression.
  ///   - attribute: The `@Test` or `@Suite` attribute.
  ///
  /// - Returns: A diagnostic message.
  static func traitHasNoEffect(_ traitExpr: some ExprSyntaxProtocol, in attribute: AttributeSyntax) -> Self {
    Self(
      syntax: Syntax(traitExpr),
      message: "Trait '\(traitExpr.trimmed)' has no effect when used with a non-parameterized test function",
      severity: .warning
    )
  }

  /// Create a diagnostic message stating that a declaration has two display
  /// names.
  ///
  /// - Parameters:
  ///   - decl: The declaration that has two display names.
  ///   - displayNameFromAttribute: The display name provided by the `@Test` or
  ///     `@Suite` attribute.
  ///   - argumentContainingDisplayName: The argument node containing the node
  ///     `displayNameFromAttribute`.
  ///   - attribute: The `@Test` or `@Suite` attribute.
  ///
  /// - Returns: A diagnostic message.
  static func declaration(
    _ decl: some NamedDeclSyntax,
    hasExtraneousDisplayName displayNameFromAttribute: StringLiteralExprSyntax,
    fromArgument argumentContainingDisplayName: LabeledExprListSyntax.Element,
    using attribute: AttributeSyntax
  ) -> Self {
    // If the name of the ambiguously-named symbol should be derived from a raw
    // identifier, this situation is an error. If the name is not raw but is
    // still surrounded by backticks (e.g. "func `foo`()" or "struct `if`") then
    // lower the severity to a warning. That way, existing code structured this
    // way doesn't suddenly fail to build.
    let severity: DiagnosticSeverity = (decl.name.rawIdentifier != nil) ? .error : .warning
    return Self(
      syntax: Syntax(decl),
      message: "Attribute \(_macroName(attribute)) specifies display name '\(displayNameFromAttribute.representedLiteralValue!)' for \(_kindString(for: decl)) with implicit display name '\(decl.name.textWithoutBackticks)'",
      severity: severity,
      fixIts: [
        FixIt(
          message: MacroExpansionFixItMessage("Remove '\(displayNameFromAttribute.representedLiteralValue!)'"),
          changes: [.replace(oldNode: Syntax(argumentContainingDisplayName), newNode: Syntax("" as ExprSyntax))]
        ),
        FixIt(
          message: MacroExpansionFixItMessage("Rename '\(decl.name.textWithoutBackticks)'"),
          changes: [.replace(oldNode: Syntax(decl.name), newNode: Syntax(EditorPlaceholderExprSyntax("name")))]
        ),
      ]
    )
  }

  /// Create a diagnostic messages stating that the expression passed to
  /// `#require()` is ambiguous.
  ///
  /// - Parameters:
  ///   - boolExpr: The ambiguous optional boolean expression.
  ///
  /// - Returns: A diagnostic message.
  static func optionalBoolExprIsAmbiguous(_ boolExpr: ExprSyntax) -> Self {
    Self(
      syntax: Syntax(boolExpr),
      message: "Requirement '\(boolExpr.trimmed)' is ambiguous",
      severity: .warning,
      fixIts: [
        FixIt(
          message: MacroExpansionFixItMessage("To unwrap an optional value, add 'as Bool?'"),
          changes: [.replace(oldNode: Syntax(boolExpr), newNode: Syntax("\(boolExpr) as Bool?" as ExprSyntax))]
        ),
        FixIt(
          message: MacroExpansionFixItMessage("To check if a value is true, add '?? false'"),
          changes: [.replace(oldNode: Syntax(boolExpr), newNode: Syntax("\(boolExpr) ?? false" as ExprSyntax))]
        ),
      ]
    )
  }

  /// Create a diagnostic messages stating that the expression passed to
  /// `#require()` is not optional and the macro is redundant.
  ///
  /// - Parameters:
  ///   - expr: The non-optional expression.
  ///
  /// - Returns: A diagnostic message.
  static func nonOptionalRequireIsRedundant(_ expr: ExprSyntax, in macro: some FreestandingMacroExpansionSyntax) -> Self {
    // We do not provide fix-its because we cannot see the leading "try" keyword
    // so we can't provide a valid fix-it to remove the macro either. We can
    // provide a fix-it to add "as Optional", but only providing that fix-it may
    // confuse or mislead developers (and that's presumably usually the *wrong*
    // fix-it to select anyway.)
    Self(
      syntax: Syntax(expr),
      message: "\(_macroName(macro)) is redundant because '\(expr.trimmed)' never equals 'nil'",
      severity: .warning
    )
  }

  /// Create a diagnostic messages stating that `#require(throws: Never.self)`
  /// is redundant.
  ///
  /// - Parameters:
  ///   - expr: The error type expression.
  ///
  /// - Returns: A diagnostic message.
  static func requireThrowsNeverIsRedundant(_ expr: ExprSyntax, in macro: some FreestandingMacroExpansionSyntax) -> Self {
    // We do not provide fix-its because we cannot see the leading "try" keyword
    // so we can't provide a valid fix-it to remove the macro either. We can
    // provide a fix-it to add "as Optional", but only providing that fix-it may
    // confuse or mislead developers (and that's presumably usually the *wrong*
    // fix-it to select anyway.)
    Self(
      syntax: Syntax(expr),
      message: "Passing '\(expr.trimmed)' to \(_macroName(macro)) is redundant; invoke non-throwing test code directly instead",
      severity: .warning
    )
  }

  var syntax: Syntax

  // MARK: - DiagnosticMessage

  var message: String
  var diagnosticID = MessageID(domain: "org.swift.testing", id: "macros")
  var severity: DiagnosticSeverity
  var fixIts: [FixIt] = []
}

// MARK: - Captured values

extension DiagnosticMessage {
  /// Create a diagnostic message stating that a specifier keyword cannot be
  /// used with a given closure capture list item.
  ///
  /// - Parameters:
  ///   - specifier: The invalid specifier.
  ///   - capture: The closure capture list item.
  ///
  /// - Returns: A diagnostic message.
  static func specifierUnsupported(_ specifier: ClosureCaptureSpecifierSyntax, on capture: ClosureCaptureSyntax) -> Self {
    Self(
      syntax: Syntax(specifier),
      message: "Specifier '\(specifier.trimmed)' cannot be used with captured value '\(capture.name.textWithoutBackticks)'",
      severity: .error,
      fixIts: [
        FixIt(
          message: MacroExpansionFixItMessage("Remove '\(specifier.trimmed)'"),
          changes: [
            .replace(
              oldNode: Syntax(capture),
              newNode: Syntax(capture.with(\.specifier, nil))
            )
          ]
        ),
      ]
    )
  }

  /// Create a diagnostic message stating that a closure capture list item's
  /// type is ambiguous and must be made explicit.
  ///
  /// - Parameters:
  ///   - capture: The closure capture list item.
  ///   - initializerClause: The existing initializer clause, if any.
  ///
  /// - Returns: A diagnostic message.
  static func typeOfCaptureIsAmbiguous(_ capture: ClosureCaptureSyntax, initializedWith initializerClause: InitializerClauseSyntax? = nil) -> Self {
    let castValueExpr: some ExprSyntaxProtocol = if let initializerClause {
      ExprSyntax(initializerClause.value.trimmed)
    } else {
      ExprSyntax(DeclReferenceExprSyntax(baseName: capture.name.trimmed))
    }
    let initializerValueExpr = ExprSyntax(
      AsExprSyntax(
        expression: castValueExpr,
        asKeyword: .keyword(.as, leadingTrivia: .space, trailingTrivia: .space),
        type: TypeSyntax.placeholder("T")
      )
    )
    let placeholderInitializerClause = if let initializerClause {
      initializerClause.with(\.value, initializerValueExpr)
    } else {
      InitializerClauseSyntax(
        equal: .equalToken(leadingTrivia: .space, trailingTrivia: .space),
        value: initializerValueExpr
      )
    }

    return Self(
      syntax: Syntax(capture),
      message: "Type of captured value '\(capture.name.textWithoutBackticks)' is ambiguous",
      severity: .error,
      fixIts: [
        FixIt(
          message: MacroExpansionFixItMessage("Add '= \(castValueExpr) as T'"),
          changes: [
            .replace(
              oldNode: Syntax(capture),
              newNode: Syntax(capture.with(\.initializer, placeholderInitializerClause))
            )
          ]
        ),
      ]
    )
  }

  /// Create a diagnostic message stating that a captured value must conform to
  /// `Sendable` and `Codable`.
  ///
  /// - Parameters:
  ///   - valueExpr: The captured value.
  ///   - nameExpr: The name of the capture list item corresponding to
  ///     `valueExpr`.
  ///
  /// - Returns: A diagnostic message.
  static func capturedValueMustBeSendableAndCodable(_ valueExpr: ExprSyntax, name nameExpr: StringLiteralExprSyntax) -> Self {
    let name = nameExpr.representedLiteralValue ?? valueExpr.trimmedDescription
    return Self(
      syntax: Syntax(valueExpr),
      message: "Type of captured value '\(name)' must conform to 'Sendable' and 'Codable'",
      severity: .error
    )
  }

  /// Create a diagnostic message stating that a capture clause cannot be used
  /// in an exit test.
  ///
  /// - Parameters:
  ///   - captureClause: The invalid capture clause.
  ///   - closure: The closure containing `captureClause`.
  ///   - exitTestMacro: The containing exit test macro invocation.
  ///
  /// - Returns: A diagnostic message.
  static func captureClauseUnsupported(_ captureClause: ClosureCaptureClauseSyntax, in closure: ClosureExprSyntax, inExitTest exitTestMacro: some FreestandingMacroExpansionSyntax) -> Self {
    let changes: [FixIt.Change]
    if let signature = closure.signature,
       Array(signature.with(\.capture, nil).tokens(viewMode: .sourceAccurate)).count == 1 {
      // The only remaining token in the signature is `in`, so remove the whole
      // signature tree instead of just the capture clause.
      changes = [
        .replaceTrailingTrivia(token: closure.leftBrace, newTrivia: ""),
        .replace(
          oldNode: Syntax(signature),
          newNode: Syntax("" as ExprSyntax)
        )
      ]
    } else {
      changes = [
        .replace(
          oldNode: Syntax(captureClause),
          newNode: Syntax("" as ExprSyntax)
        )
      ]
    }

    return Self(
      syntax: Syntax(captureClause),
      message: "Cannot specify a capture clause in closure passed to \(_macroName(exitTestMacro))",
      severity: .error,
      fixIts: [
        FixIt(
          message: MacroExpansionFixItMessage("Remove '\(captureClause.trimmed)'"),
          changes: changes
        ),
      ]
    )
  }

  /// Create a diagnostic message stating that an expression macro is not
  /// supported in a generic context.
  ///
  /// - Parameters:
  ///   - macro: The invalid macro.
  ///   - genericClause: The child node on `genericDecl` that makes it generic.
  ///   - genericDecl: The generic declaration to which `genericClause` is
  ///     attached, possibly equal to `decl`.
  ///
  /// - Returns: A diagnostic message.
  static func expressionMacroUnsupported(_ macro: some FreestandingMacroExpansionSyntax, inGenericContextBecauseOf genericClause: some SyntaxProtocol, on genericDecl: some SyntaxProtocol) -> Self {
    if let functionDecl = genericDecl.as(FunctionDeclSyntax.self) {
      return Self(
        syntax: Syntax(macro),
        message: "Cannot call macro '\(_macroName(macro))' within generic function '\(functionDecl.completeName)'",
        severity: .error
      )
    } else if let namedDecl = genericDecl.asProtocol((any NamedDeclSyntax).self) {
      return Self(
        syntax: Syntax(macro),
        message: "Cannot call macro '\(_macroName(macro))' within generic \(_kindString(for: genericDecl)) '\(namedDecl.name.trimmed)'",
        severity: .error
      )
    } else {
      return Self(
        syntax: Syntax(macro),
        message: "Cannot call macro '\(_macroName(macro))' within a generic \(_kindString(for: genericDecl))",
        severity: .error
      )
    }
  }
}
