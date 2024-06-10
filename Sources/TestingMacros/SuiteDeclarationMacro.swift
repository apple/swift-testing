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

/// A type describing the expansion of the `@Suite` attribute macro.
///
/// This type is used to implement the `@Suite` attribute macro. Do not use it
/// directly.
public struct SuiteDeclarationMacro: MemberMacro, PeerMacro, Sendable {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard _diagnoseIssues(with: declaration, suiteAttribute: node, in: context) else {
      return []
    }
    return _createTestContainerDecls(for: declaration, suiteAttribute: node, in: context)
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

    // Suites inheriting from XCTestCase are not supported.
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

  /// Create a declaration for a type that conforms to the `__TestContainer`
  /// protocol and which contains the given suite type.
  ///
  /// - Parameters:
  ///   - declaration: The type declaration the result should encapsulate.
  ///   - suiteAttribute: The `@Suite` attribute applied to `declaration`.
  ///   - context: The macro context in which the expression is being parsed.
  ///
  /// - Returns: An array of declarations providing runtime information about
  ///   the test suite type `declaration`.
  private static func _createTestContainerDecls(
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
    let typeName = declaration.type.tokens(viewMode: .fixedUp).map(\.textWithoutBackticks).joined()

    let testGetterFunctionName = context.makeUniqueName(typeName)
    result.append(
      """
      @available(*, deprecated)
      @Sendable private static func \(testGetterFunctionName)() async -> Testing.Test {
        .__type(
          \(declaration.type.trimmed).self,
          \(raw: attributeInfo.functionArgumentList(in: context))
        )
      }
      """
    )

    // The emitted type must be public or the compiler can optimize it away
    // (since it is not actually used anywhere that the compiler can see.)
    //
    // The emitted type must be deprecated to avoid causing warnings in client
    // code since it references the suite metatype, which may be deprecated
    // to allow test functions to validate deprecated APIs. The emitted type is
    // also annotated unavailable, since it's meant only for use by the testing
    // library at runtime. The compiler does not allow combining 'unavailable'
    // and 'deprecated' into a single availability attribute: rdar://111329796
    let enumName = context.makeUniqueName("__🟠$test_container__suite__\(typeName)")
    result.append(
      """
      #if !hasFeature(SymbolLinkageMarkers)
      @available(*, deprecated, message: "This type is an implementation detail of the testing library. Do not use it directly.")
      enum \(enumName): Testing.__TestContainer {
        static var __tests: [Testing.Test] {
          get async {
            [await \(testGetterFunctionName)()]
          }
        }
      }
      #endif
      """
    )

    let exportedSymbolName = context.makeUniqueName(typeName)
    result.append(
      """
      #if hasFeature(SymbolLinkageMarkers)
      @available(*, deprecated)
      private enum \(enumName) {
        @_used
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        @_section("__DATA_CONST,__swift5_tests")
        #elseif os(Linux)
        @_section("swift5_tests")
        #elseif os(Windows)
        @_section(".sw5test$B")
        #endif
        private static let \(exportedSymbolName): Testing.__TestGetter = {
          let taskGroup = $0.assumingMemoryBound(to: _Concurrency.TaskGroup<[Testing.Test]>.self)
          taskGroup.pointee.addTask {
            [await \(testGetterFunctionName)()]
          }
        }
      }
      #endif
      """
    )

    return result
  }
}
