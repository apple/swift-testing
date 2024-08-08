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
import SwiftSyntaxMacros

/// A structure describing a single platform/version pair from an `@available()`
/// attribute.
struct Availability {
  /// The attribute from which this instance was generated.
  var attribute: AttributeSyntax

  /// The platform name, such as `"macOS"`, if any.
  var platformName: TokenSyntax?

  /// The platform version, such as 1.2.3, if any.
  var version: VersionTupleSyntax?

  /// The `message` argument to the attribute, if any.
  var message: SimpleStringLiteralExprSyntax?

  /// An instance of `PlatformVersionSyntax` representing the same availability
  /// as this instance, if this instance can be represented as an instance of
  /// that type.
  var platformVersion: PlatformVersionSyntax? {
    platformName.map { platformName in
      PlatformVersionSyntax(
        platform: platformName.trimmed.with(\.trailingTrivia, .space),
        version: version?.trimmed
      )
    }
  }

  /// Whether or not this instance represents Swift language availability.
  var isSwift: Bool {
    platformName?.textWithoutBackticks == "swift"
  }
}

// MARK: -

/// Create an expression that contains a test trait for availability (i.e.
/// `.enabled(if: ...)`) for a given availability version.
///
/// - Parameters:
///   - availability: The value to convert to a trait. The `platformName`
///     property of this value must not be `nil`, but the `version` property may
///     be `nil`.
///   - whenKeyword: The keyword that controls how `availability` is
///     interpreted. Pass either `.introduced` or `.obsoleted`.
///   - context: The macro context in which the expression is being parsed.
///
/// - Returns: An instance of `ExprSyntax` representing an instance of
///   ``Trait`` that can be used to prevent a test from running if the
///   availability constraint in `availability` is not met.
private func _createAvailabilityTraitExpr(
  from availability: Availability,
  when whenKeyword: Keyword,
  in context: some MacroExpansionContext
) -> ExprSyntax {
  let version: ExprSyntax = availability.version.map(\.componentValues).map { components in
    "(\(literal: components.major), \(literal: components.minor), \(literal: components.patch))"
  } ?? "nil"
  let message = availability.message.map(\.trimmed).map(ExprSyntax.init) ?? "nil"
  let sourceLocationExpr = createSourceLocationExpr(of: availability.attribute, context: context)

  switch (whenKeyword, availability.isSwift) {
  case (.introduced, false):
    return """
    .__available(\(literal: availability.platformName!.textWithoutBackticks), introduced: \(version), message: \(message), sourceLocation: \(sourceLocationExpr)) {
      if #available(\(availability.platformVersion!), *) {
        return true
      }
      return false
    }
    """

  case (.obsoleted, false):
    return """
    .__available(\(literal: availability.platformName!.textWithoutBackticks), obsoleted: \(version), message: \(message), sourceLocation: \(sourceLocationExpr)) {
      if #unavailable(\(availability.platformVersion!)) {
        return true
      }
      return false
    }
    """

  case (.introduced, true):
    return """
    .__available("Swift", introduced: \(version), message: \(message), sourceLocation: \(sourceLocationExpr)) {
      #if swift(>=\(availability.version!))
      return true
      #else
      return false
      #endif
    }
    """

  case (.obsoleted, true):
    return """
    .__available("Swift", obsoleted: \(version), message: \(message), sourceLocation: \(sourceLocationExpr)) {
      #if swift(<\(availability.version!))
      return true
      #else
      return false
      #endif
    }
    """

  case (.unavailable, _):
    return ".__unavailable(message: \(message), sourceLocation: \(sourceLocationExpr))"

  default:
    fatalError("Unsupported keyword \(whenKeyword) passed to \(#function). Please file a bug report at https://github.com/swiftlang/swift-testing/issues/new")
  }
}

/// Create an expression that contains test traits for availability (i.e.
/// `.enabled(if: ...)`).
///
/// - Parameters:
///   - decl: The expression annotated with availability attributes.
///   - context: The macro context in which the expression is being parsed.
///
/// - Returns: An array of expressions producing ``Trait`` instances that can be
///   used to prevent a test from running if any availability constraints are
///   not met. If `decl` has no `@available` attributes, an empty array is
///   returned.
func createAvailabilityTraitExprs(
  for decl: some WithAttributesSyntax,
  in context: some MacroExpansionContext
) -> [ExprSyntax] {
  var result = [ExprSyntax]()

  result += decl.availability(when: .unavailable).lazy.map { unavailability in
    _createAvailabilityTraitExpr(from: unavailability, when: .unavailable, in: context)
  }

  result += decl.availability(when: .introduced).lazy.map { availability in
    _createAvailabilityTraitExpr(from: availability, when: .introduced, in: context)
  }

  result += decl.availability(when: .obsoleted).lazy.map { availability in
    _createAvailabilityTraitExpr(from: availability, when: .obsoleted, in: context)
  }

  return result
}

/// Create a syntax node that checks for availability based on a declaration
/// and, either invokes some other syntax node or exits early.
///
/// - Parameters:
///   - decl: The declaration annotated with availability attributes.
///   - node: The node to evaluate if `decl` is available at runtime. This node
///     may be any arbitrary syntax.
///   - exitStatement: The scope-exiting statement to evaluate if `decl` is
///     unavailable at runtime. The default expression is `return`.
///   - context: The macro context in which the expression is being parsed.
///
/// - Returns: A syntax node containing one or more `guard`, `if`, and/or `#if`
///   statements that test availability based on the attributes on `decl` and
///   exit early with `exitStatement` if any availability constraints are not
///   met. If `decl` has no `@available` attributes, a copy of `node` is
///   returned.
func createSyntaxNode(
  guardingForAvailabilityOf decl: some DeclSyntaxProtocol & WithAttributesSyntax,
  beforePerforming node: some SyntaxProtocol,
  orExitingWith exitStatement: StmtSyntax = StmtSyntax(ReturnStmtSyntax()),
  in context: some MacroExpansionContext
) -> CodeBlockItemListSyntax {
  var result: CodeBlockItemListSyntax = "\(node)"

  // Create an expression that acts as an availability guard (i.e.
  // `guard #available(...) else { ... }`). The expression is evaluated before
  // `node` to allow for early exit.
  do {
    let availableExprs: [ExprSyntax] = decl.availability(when: .introduced).lazy
      .filter { !$0.isSwift }
      .compactMap(\.platformVersion)
      .map { "#available(\($0), *)" }
    if !availableExprs.isEmpty {
      let conditionList = ConditionElementListSyntax {
        for availableExpr in availableExprs {
          availableExpr
        }
      }
      result = """
      guard \(conditionList) else {
        \(exitStatement)
      }
      \(result)
      """
    }
  }

  // As above, but for unavailability (`#unavailable(...)`.)
  do {
    let unavailableExprs: [ExprSyntax] = decl.availability(when: .obsoleted).lazy
      .filter { !$0.isSwift }
      .compactMap(\.platformVersion)
      .map { "#unavailable(\($0))" }
    if !unavailableExprs.isEmpty {
      let conditionList = ConditionElementListSyntax {
        for unavailableExpr in unavailableExprs {
          unavailableExpr
        }
      }
      result = """
      guard \(conditionList) else {
        \(exitStatement)
      }
      \(result)
      """
    }
  }

  // If this function has a minimum or maximum Swift version requirement, we
  // need to scope its body with #if/#endif.
  do {
    let introducedVersion = decl.availability(when: .introduced).lazy
      .filter(\.isSwift)
      .compactMap(\.version?.componentValues)
      .max()
    let obsoletedVersion = decl.availability(when: .obsoleted).lazy
      .filter(\.isSwift)
      .compactMap(\.version?.componentValues)
      .min()

    let swiftVersionGuardExpr: ExprSyntax? = switch (introducedVersion, obsoletedVersion) {
    case let (.some(introducedVersion), .some(obsoletedVersion)):
      "swift(>=\(raw: introducedVersion)) && swift(<\(raw: obsoletedVersion))"
    case let (.some(introducedVersion), _):
      "swift(>=\(raw: introducedVersion))"
    case let (_, .some(obsoletedVersion)):
      "swift(<\(raw: obsoletedVersion))"
    default:
      nil
    }
    if let swiftVersionGuardExpr {
      result = """
      #if \(swiftVersionGuardExpr)
      \(result)
      #else
      \(exitStatement)
      #endif
      """
    }
  }

  return result
}
