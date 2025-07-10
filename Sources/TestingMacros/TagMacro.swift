//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

public import SwiftSyntax
import SwiftSyntaxBuilder
public import SwiftSyntaxMacros

/// A type describing the expansion of the `@Tag` attribute macro.
///
/// This type is used to implement the `@Tag` attribute macro. Do not use it
/// directly.
public struct TagMacro: PeerMacro, AccessorMacro, Sendable {
  /// The accessor declarations to emit on error.
  ///
  /// This property is used rather than simply returning the empty array in
  /// order to suppress a compiler diagnostic about not producing any accessors.
  private static var _fallbackAccessorDecls: [AccessorDeclSyntax] {
    [#"get { \#(ExprSyntax.unreachable) }"#]
  }

  public static func expansion(
    of node: AttributeSyntax,
    providingAccessorsOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [AccessorDeclSyntax] {
    // The compiler enforces that this macro is only applied to a single-binding
    // variable declaration, so we don't need to type-check the declaration or
    // count the bindings.
    let variableDecl = declaration.cast(VariableDeclSyntax.self)

    // Get the name of the tag. We assume here that the compiler disallows other
    // kinds of patterns in this position.
    let variableName = variableDecl.bindings.first!.pattern.cast(IdentifierPatternSyntax.self).identifier

    // Figure out what type the tag is declared on. It must be declared on Tag
    // or a type nested in Tag.
    guard let type = context.typeOfLexicalContext else {
      context.diagnose(.nonMemberTagDeclarationNotSupported(variableDecl, whenUsing: node))
      return _fallbackAccessorDecls
    }

    // Check that the tag is declared within Tag's namespace.
    let typeNameTokens: [String] = type.tokens(viewMode: .fixedUp).lazy
      .filter { $0.tokenKind != .period }
      .map(\.textWithoutBackticks)
    guard typeNameTokens.first == "Tag" || typeNameTokens.starts(with: ["Testing", "Tag"]) else {
      context.diagnose(.attributeNotSupportedOutsideTagExtension(node, on: variableDecl))
      return _fallbackAccessorDecls
    }

    // Check that the type of the variable is either Tag, Testing.Tag, or (if
    // the lexical context is Tag and not a contained type) Self. (The compiler
    // might have been able to infer it in some context, so don't fail if the
    // type annotation isn't present.)
    if let variableType = variableDecl.bindings.first?.typeAnnotation?.type {
      if variableType.isNamed("Tag", inModuleNamed: "Testing") {
        // The type of the variable is Tag, so all is well.
      } else if let variableType = variableType.as(IdentifierTypeSyntax.self),
                variableType.name.tokenKind == .keyword(.Self) {
        // The type of the variable is 'Self`. Only allow if the variable is
        // declared directly in an extension to Tag.
        guard type.isNamed("Tag", inModuleNamed: "Testing") else {
          context.diagnose(.mistypedTagDeclarationNotSupported(node, on: variableDecl, declaredType: TypeSyntax(variableType), resolvedType: type))
          return _fallbackAccessorDecls
        }
      } else {
        context.diagnose(.mistypedTagDeclarationNotSupported(node, on: variableDecl, declaredType: variableType))
        return _fallbackAccessorDecls
      }
    }

    // We know the tag is nested in Tag. Now check that it is a static member.
    guard variableDecl.modifiers.map(\.name.tokenKind).contains(.keyword(.static)) else {
      context.diagnose(.nonStaticTagDeclarationNotSupported(node, on: variableDecl))
      return _fallbackAccessorDecls
    }

    return [
      #"""
      get {
        Testing.Tag.__fromStaticMember(of: \#(raw: type).self, \#(literal: variableName.textWithoutBackticks))
      }
      """#
    ]
  }

  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    // The peer macro expansion of this macro is only used to diagnose misuses
    // on symbols that are not variable declarations.
    if !declaration.is(VariableDeclSyntax.self) {
      context.diagnose(.attributeNotSupported(node, on: declaration))
    }
    return []
  }

  public static var formatMode: FormatMode {
    .disabled
  }
}
