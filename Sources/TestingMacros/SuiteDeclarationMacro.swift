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
public import SwiftSyntax
import SwiftSyntaxBuilder
public import SwiftSyntaxMacros

#if !hasFeature(SymbolLinkageMarkers) && SWT_NO_LEGACY_TEST_DISCOVERY
#error("Platform-specific misconfiguration: either SymbolLinkageMarkers or legacy test discovery is required to expand @Suite")
#endif

/// A type describing the expansion of the `@Suite` attribute macro.
///
/// This type is used to implement the `@Suite` attribute macro. Do not use it
/// directly.
public struct SuiteDeclarationMacro: MemberMacro, PeerMacro, Sendable {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard _diagnoseIssues(with: declaration, suiteAttribute: node, in: context) else {
      return []
    }
    return _createSuiteDecls(for: declaration, suiteAttribute: node, in: context)
  }

  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    // The peer macro expansion of this macro is only used to diagnose misuses
    // on symbols that are not decl groups.
    if !declaration.isProtocol((any DeclGroupSyntax).self) {
      _ = _diagnoseIssues(with: declaration, suiteAttribute: node, in: context)
    }
    return []
  }

  public static var formatMode: FormatMode {
    .disabled
  }

  /// Diagnose issues with a `@Suite` declaration.
  ///
  /// - Parameters:
  ///   - declaration: The type declaration to diagnose.
  ///   - suiteAttribute: The `@Suite` attribute applied to `declaration`.
  ///   - context: The macro context in which the expression is being parsed.
  ///
  /// - Returns: Whether or not macro expansion should continue (i.e. stopping
  ///   if a fatal error was diagnosed.)
  private static func _diagnoseIssues(
    with declaration: some DeclSyntaxProtocol,
    suiteAttribute: AttributeSyntax,
    in context: some MacroExpansionContext
  ) -> Bool {
    var diagnostics = [DiagnosticMessage]()
    defer {
      context.diagnose(diagnostics)
    }

    // Check if the lexical context is appropriate for a suite or test.
    diagnostics += diagnoseIssuesWithLexicalContext(context.lexicalContext, containing: declaration, attribute: suiteAttribute)
    diagnostics += diagnoseIssuesWithLexicalContext(declaration, containing: declaration, attribute: suiteAttribute)

    // Suites inheriting from XCTestCase are not supported. This check is
    // duplicated in TestDeclarationMacro but is not part of
    // diagnoseIssuesWithLexicalContext() because it doesn't need to recurse
    // across the entire lexical context list, just the innermost type
    // declaration.
    if let declaration = declaration.asProtocol((any DeclGroupSyntax).self),
       declaration.inherits(fromTypeNamed: "XCTestCase", inModuleNamed: "XCTest") {
      diagnostics.append(.xcTestCaseNotSupported(declaration, whenUsing: suiteAttribute))
    }

    // @Suite cannot be applied to a type extension (although a type extension
    // can still contain test functions and test suites.)
    if let extensionDecl = declaration.as(ExtensionDeclSyntax.self) {
      diagnostics.append(.attributeHasNoEffect(suiteAttribute, on: extensionDecl))
    }

    // Check other attributes on the declaration. Note that it should be
    // impossible to reach this point if the declaration can't have attributes.
    if let attributedDecl = declaration.asProtocol((any WithAttributesSyntax).self) {
      // Only one @Suite attribute is supported.
      let suiteAttributes = attributedDecl.attributes(named: "Suite")
      if suiteAttributes.count > 1 {
        diagnostics.append(.multipleAttributesNotSupported(suiteAttributes, on: declaration))
      }
    }

    return !diagnostics.lazy.map(\.severity).contains(.error)
  }

  /// Create the declarations necessary to discover a suite at runtime.
  ///
  /// - Parameters:
  ///   - declaration: The type declaration the result should encapsulate.
  ///   - suiteAttribute: The `@Suite` attribute applied to `declaration`.
  ///   - context: The macro context in which the expression is being parsed.
  ///
  /// - Returns: An array of declarations providing runtime information about
  ///   the test suite type `declaration`.
  private static func _createSuiteDecls(
    for declaration: some DeclGroupSyntax,
    suiteAttribute: AttributeSyntax,
    in context: some MacroExpansionContext
  ) -> [DeclSyntax] {
    var result = [DeclSyntax]()

    if declaration.is(ExtensionDeclSyntax.self) {
      // No declaration is emitted for an extension. One can be synthesized at
      // runtime if one is not available for the type declaration itself.
      return []
    }

    if let genericGuardDecl = makeGenericGuardDecl(guardingAgainst: declaration, in: context) {
      result.append(genericGuardDecl)
    }

    // Parse the @Suite attribute.
    let attributeInfo = AttributeInfo(byParsing: suiteAttribute, on: declaration, in: context)

    let generatorName = context.makeUniqueName("generator")
    result.append(
      """
      @available(*, deprecated, message: "This property is an implementation detail of the testing library. Do not use it directly.")
      @Sendable private static func \(generatorName)() async -> Testing.Test {
        .__type(
          \(declaration.type.trimmed).self,
          \(raw: attributeInfo.functionArgumentList(in: context))
        )
      }
      """
    )

    let accessorName = context.makeUniqueName("accessor")
    result.append(
      """
      @available(*, deprecated, message: "This property is an implementation detail of the testing library. Do not use it directly.")
      private nonisolated static let \(accessorName): Testing.__TestContentRecordAccessor = { outValue, type, _, _ in
        Testing.Test.__store(\(generatorName), into: outValue, asTypeAt: type)
      }
      """
    )

    let testContentRecordName = context.makeUniqueName("testContentRecord")
    result.append(
      makeTestContentRecordDecl(
        named: testContentRecordName,
        in: declaration.type,
        ofKind: .testDeclaration,
        accessingWith: accessorName,
        context: attributeInfo.testContentRecordFlags
      )
    )

#if !SWT_NO_LEGACY_TEST_DISCOVERY
    // Emit a type that contains a reference to the test content record.
    let enumName = context.makeUniqueName("__🟡$")
    result.append(
      """
      @available(*, deprecated, message: "This type is an implementation detail of the testing library. Do not use it directly.")
      enum \(enumName): Testing.__TestContentRecordContainer {
        nonisolated static var __testContentRecord: Testing.__TestContentRecord {
          unsafe \(testContentRecordName)
        }
      }
      """
    )
#endif

    return result
  }
}
