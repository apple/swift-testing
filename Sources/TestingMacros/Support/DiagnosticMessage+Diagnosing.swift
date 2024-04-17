//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

import SwiftDiagnostics
#if compiler(>=5.11)
import SwiftSyntax
import SwiftSyntaxMacros
#else
public import SwiftSyntax
public import SwiftSyntaxMacros
#endif
private import TestingInternals

/// Diagnose issues with the traits in a parsed attribute.
///
/// - Parameters:
///   - traitExprs: An array of trait expressions to examine.
///   - attribute: The `@Test` or `@Suite` attribute.
///   - context: The macro context in which the expression is being parsed.
func diagnoseIssuesWithTraits(in traitExprs: [ExprSyntax], addedTo attribute: AttributeSyntax, in context: some MacroExpansionContext) {
  for traitExpr in traitExprs {
    // At this time, we are only looking for .tags() and .bug() traits in this
    // function.
    guard let functionCallExpr = traitExpr.as(FunctionCallExprSyntax.self),
          let calledExpr = functionCallExpr.calledExpression.as(MemberAccessExprSyntax.self) else {
      continue
    }

    // Check for .tags() traits.
    switch calledExpr.tokens(viewMode: .fixedUp).map(\.textWithoutBackticks).joined() {
    case ".tags", "Tag.List.tags", "Testing.Tag.List.tags":
      _diagnoseIssuesWithTagsTrait(functionCallExpr, addedTo: attribute, in: context)
    case ".bug", "Bug.bug", "Testing.Bug.bug":
      _diagnoseIssuesWithBugTrait(functionCallExpr, addedTo: attribute, in: context)
    default:
      // This is not a trait we can parse.
      break
    }
  }
}

/// Diagnose issues with a `.tags()` trait in a parsed attribute.
///
/// - Parameters:
///   - traitExpr: The `.tags()` expression.
///   - attribute: The `@Test` or `@Suite` attribute.
///   - context: The macro context in which the expression is being parsed.
private func _diagnoseIssuesWithTagsTrait(_ traitExpr: FunctionCallExprSyntax, addedTo attribute: AttributeSyntax, in context: some MacroExpansionContext) {
  // Find tags that are in an unsupported format (only .member and "literal"
  // are allowed.)
  for tagExpr in traitExpr.arguments.lazy.map(\.expression) {
    if tagExpr.is(StringLiteralExprSyntax.self) {
      // String literals are supported tags.
    } else if let tagExpr = tagExpr.as(MemberAccessExprSyntax.self) {
      let joinedTokens = tagExpr.tokens(viewMode: .fixedUp).map(\.textWithoutBackticks).joined()
      if joinedTokens.hasPrefix(".") || joinedTokens.hasPrefix("Tag.") || joinedTokens.hasPrefix("Testing.Tag.") {
        // These prefixes are all allowed as they specify a member access
        // into the Tag type.
      } else {
        context.diagnose(.tagExprNotSupported(tagExpr, in: attribute))
        continue
      }

      // Walk all base expressions and make sure they are exclusively member
      // access expressions.
      func checkForValidDeclReferenceExpr(_ declReferenceExpr: DeclReferenceExprSyntax) {
        // This is the name of a type or symbol. If there are argument names
        // (unexpected in this context), it's a function reference and is
        // unsupported.
        if declReferenceExpr.argumentNames != nil {
          context.diagnose(.tagExprNotSupported(tagExpr, in: attribute))
        }
      }
      func checkForValidBaseExpr(_ baseExpr: ExprSyntax) {
        if let baseExpr = baseExpr.as(MemberAccessExprSyntax.self) {
          checkForValidDeclReferenceExpr(baseExpr.declName)
          if let baseBaseExpr = baseExpr.base {
            checkForValidBaseExpr(baseBaseExpr)
          }
        } else if let baseExpr = baseExpr.as(DeclReferenceExprSyntax.self) {
          checkForValidDeclReferenceExpr(baseExpr)
        } else {
          // The base expression was some other kind of expression and is
          // not supported.
          context.diagnose(.tagExprNotSupported(tagExpr, in: attribute))
        }
      }
      if let baseExpr = tagExpr.base {
        checkForValidBaseExpr(baseExpr)
      }
    } else {
      // This tag is not of a supported expression type.
      context.diagnose(.tagExprNotSupported(tagExpr, in: attribute))
    }
  }
}

/// Diagnose issues with a `.bug()` trait in a parsed attribute.
///
/// - Parameters:
///   - traitExpr: The `.bug()` expression.
///   - attribute: The `@Test` or `@Suite` attribute.
///   - context: The macro context in which the expression is being parsed.
private func _diagnoseIssuesWithBugTrait(_ traitExpr: FunctionCallExprSyntax, addedTo attribute: AttributeSyntax, in context: some MacroExpansionContext) {
  // If the first argument to the .bug() trait is unlabelled and a string
  // literal, check that it can be parsed as a URL or at least as an integer.
  guard let arg = traitExpr.arguments.first.map(Argument.init),
        arg.label == nil,
        let stringLiteralExpr = arg.expression.as(StringLiteralExprSyntax.self),
        let urlString = stringLiteralExpr.representedLiteralValue else {
    return
  }

  if UInt64(urlString) != nil {
    // The entire URL string can be parsed as an integer, so allow it. Although
    // the testing library prefers valid URLs here, some bug-tracking systems
    // might not provide URLs, or might provide excessively long URLs, so we
    // allow numeric identifiers as a fallback.
    return
  }

  if urlString.count > 3 && urlString.starts(with: "FB") && UInt64(urlString.dropFirst(2)) != nil {
    // The string appears to be of the form "FBnnn...". Such strings are used by
    // Apple to indicate issues filed using Feedback Assistant. Although we
    // don't want to special-case every possible bug-tracking system out there,
    // Feedback Assistant is very important to Apple so we're making an
    // exception for it.
    return
  }

  func isURLStringValid(_ urlString: String) -> Bool {
    guard urlString.allSatisfy(\.isASCII),
          let colonIndex = urlString.firstIndex(of: ":") else {
      // This can't be a valid URL as far as we're concerned. Exit early without
      // properly parsing it.
      return false
    }

#if SWT_TARGET_OS_APPLE || os(Linux)
#if !SWT_NO_CURL
    let url = curl_url()
    defer {
      curl_url_cleanup(url)
    }

    // Attempt to parse the URL.
    let flags = CUnsignedInt(CURLU_NON_SUPPORT_SCHEME | CURLU_NO_AUTHORITY)
    switch curl_url_set(url, CURLUPART_URL, urlString, flags) {
    case CURLUE_OK:
      break
    case CURLUE_BAD_SLASHES, CURLUE_BAD_SCHEME:
      // curl does not try to parse URLs without slashes after the colon (see
      // https://github.com/curl/curl/issues/12205). Work around that constraint
      // by inserting slashes after the first colon character, on the assumption
      // we are dealing with a URL like mailto:a@example.com.
      var urlString = urlString
      urlString.insert(contentsOf: "//", at: urlString.index(after: colonIndex))
      return isURLStringValid(urlString)
    default:
      // The URL could not be parsed for some other reason.
      return false
    }

    // Extract the scheme and check that it's not empty.
    var scheme: UnsafeMutablePointer<CChar>?
    guard CURLUE_OK == curl_url_get(url, CURLUPART_SCHEME, &scheme, flags), let scheme else {
      // libcurl won't parse a URL without a scheme given the flags we pass, so
      // this branch is dead code, but it's not worth asserting over.
      return false
    }
    defer {
      curl_free(scheme)
    }
    return scheme[0] != 0
#else
    // libcurl has been disabled.
    return true
#endif

#elseif os(WASI)
    // TODO: URL validation on WASI (this code runs on the host though)
    return true
#elseif os(Windows)
    return urlString.withCString(encodedAs: UTF16.self) { urlString in
      var components = URL_COMPONENTSW()
      // We need to specify the size of the structure before passing it to
      // InternetCrackUrlW(). We also need to reserve space for at least one
      // wchar_t in order to tell the function that we're interested in the
      // scheme: if we pass nil, the function won't bother trying to parse it
      // out and won't give us back a length value to check.
      components.dwStructSize = DWORD(MemoryLayout.size(ofValue: components))
      return withUnsafeTemporaryAllocation(of: wchar_t.self, capacity: 1) { buffer in
        components.lpszScheme = buffer.baseAddress!
        return InternetCrackUrlW(urlString, 0, 0, &components)
          && components.dwSchemeLength > 0
      }
    }
#else
#warning("Platform-specific implementation missing: URL validation unavailable")
    return true
#endif
  }

  if !isURLStringValid(urlString) {
    context.diagnose(.urlExprNotValid(stringLiteralExpr, in: traitExpr, in: attribute))
  }
}

// MARK: -

/// Diagnose issues with a synthesized suite (one without an `@Suite` attribute)
/// containing a declaration.
///
/// - Parameters:
///   - lexicalContext: The single lexical context to inspect.
///   - decl: The declaration to inspect.
///   - attribute: The `@Test` or `@Suite` attribute applied to `decl`.
///
/// - Returns: An array of zero or more diagnostic messages related to the
///   lexical context containing `decl`.
///
/// This function is also used by ``SuiteDeclarationMacro`` for a number of its
/// own diagnostics. The implementation substitutes different diagnostic
/// messages when `suiteDecl` and `decl` are the same syntax node on the
/// assumption that a suite is self-diagnosing.
func diagnoseIssuesWithLexicalContext(
  _ lexicalContext: some SyntaxProtocol,
  containing decl: some DeclSyntaxProtocol,
  attribute: AttributeSyntax
) -> [DiagnosticMessage] {
  var diagnostics = [DiagnosticMessage]()

  // Functions, closures, etc. are not supported as enclosing lexical contexts.
  guard let lexicalContext = lexicalContext.asProtocol((any DeclGroupSyntax).self) else {
    if Syntax(lexicalContext) == Syntax(decl) {
      diagnostics.append(.attributeNotSupported(attribute, on: lexicalContext))
    } else {
      diagnostics.append(.containingNodeUnsupported(lexicalContext, whenUsing: attribute, on: decl))
    }
    return diagnostics
  }

  // Generic suites are not supported.
  if let genericClause = lexicalContext.asProtocol((any WithGenericParametersSyntax).self)?.genericParameterClause {
    diagnostics.append(.genericDeclarationNotSupported(decl, whenUsing: attribute, becauseOf: genericClause))
  } else if let whereClause = lexicalContext.genericWhereClause {
    diagnostics.append(.genericDeclarationNotSupported(decl, whenUsing: attribute, becauseOf: whereClause))
  }

  // Suites that are classes must be final.
  if let classDecl = lexicalContext.as(ClassDeclSyntax.self) {
    if !classDecl.modifiers.lazy.map(\.name.tokenKind).contains(.keyword(.final)) {
      if Syntax(classDecl) == Syntax(decl) {
        diagnostics.append(.nonFinalClassNotSupported(classDecl, whenUsing: attribute))
      } else {
        diagnostics.append(.containingNodeUnsupported(classDecl, whenUsing: attribute, on: decl))
      }
    }
  }

  // Suites cannot be protocols (there's nowhere to put most of the
  // declarations we generate.)
  if let protocolDecl = lexicalContext.as(ProtocolDeclSyntax.self) {
    if Syntax(protocolDecl) == Syntax(decl) {
      diagnostics.append(.attributeNotSupported(attribute, on: protocolDecl))
    } else {
      diagnostics.append(.containingNodeUnsupported(protocolDecl, whenUsing: attribute, on: decl))
    }
  }

  // Check other attributes on the declaration. Note that it should be
  // impossible to reach this point if the declaration can't have attributes.
  if let attributedDecl = lexicalContext.asProtocol((any WithAttributesSyntax).self) {
    // Availability is not supported on suites (we need semantic availability
    // to correctly understand the availability of a suite.)
    let availabilityAttributes = attributedDecl.availabilityAttributes
    if !availabilityAttributes.isEmpty {
      // Diagnose all @available attributes.
      for availabilityAttribute in availabilityAttributes {
        diagnostics.append(.availabilityAttributeNotSupported(availabilityAttribute, on: decl, whenUsing: attribute))
      }
    } else if let noasyncAttribute = attributedDecl.noasyncAttribute {
      // No @available attributes, but we do have an @_unavailableFromAsync
      // attribute and we still need to diagnose that.
      diagnostics.append(.availabilityAttributeNotSupported(noasyncAttribute, on: decl, whenUsing: attribute))
    }
  }

  return diagnostics
}

#if canImport(SwiftSyntax600)
/// Diagnose issues with the lexical context containing a declaration.
///
/// - Parameters:
///   - lexicalContext: The lexical context to inspect.
///   - decl: The declaration to inspect.
///   - attribute: The `@Test` or `@Suite` attribute applied to `decl`.
///
/// - Returns: An array of zero or more diagnostic messages related to the
///   lexical context containing `decl`.
func diagnoseIssuesWithLexicalContext(
  _ lexicalContext: [Syntax],
  containing decl: some DeclSyntaxProtocol,
  attribute: AttributeSyntax
) -> [DiagnosticMessage] {
  lexicalContext.lazy
    .map { diagnoseIssuesWithLexicalContext($0, containing: decl, attribute: attribute) }
    .reduce(into: [], +=)
}
#endif

/// Create a declaration that prevents compilation if it is generic.
///
/// - Parameters:
///   - decl: The declaration that should not be generic.
///   - context: The macro context in which the expression is being parsed.
///
/// - Returns: A declaration that will fail to compile if `decl` is generic. The
///   result declares a static member that should be added to the type
///   containing `decl`. If `decl` is known not to be contained within a type
///   extension, the result is `nil`.
///
/// This function disables the use of tests and suites inside extensions to
/// generic types by adding a static property declaration (which generic types
/// do not support.) This produces a compile-time error (not the perfect
/// diagnostic to emit, but better than building successfully and failing
/// silently at runtime.) ([126018850](rdar://126018850))
func makeGenericGuardDecl(
  guardingAgainst decl: some DeclSyntaxProtocol,
  in context: some MacroExpansionContext
) -> DeclSyntax? {
#if canImport(SwiftSyntax600)
  guard context.lexicalContext.lazy.map(\.kind).contains(.extensionDecl) else {
    // Don't bother emitting a member if the declaration is not in an extension
    // because we'll already be able to emit a better error.
    return nil
  }
#endif
  let genericGuardName = if let functionDecl = decl.as(FunctionDeclSyntax.self) {
    context.makeUniqueName(thunking: functionDecl)
  } else {
    context.makeUniqueName("")
  }
  return """
  private static let \(genericGuardName): Void = ()
  """
}
