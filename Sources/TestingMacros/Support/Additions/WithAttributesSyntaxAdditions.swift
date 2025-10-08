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

extension WithAttributesSyntax {
  /// The set of availability attributes on this instance.
  var availabilityAttributes: [AttributeSyntax] {
    attributes.lazy
      .compactMap { attribute in
        if case let .attribute(attribute) = attribute {
          return attribute
        }
        return nil
      }.filter { attribute in
        if case .availability = attribute.arguments {
          return true
        }
        return false
      }
  }

  /// Get the set of version-based availability constraints on this instance.
  ///
  /// - Parameters:
  ///   - whenKeyword: The keyword to filter the result by, such as
  ///     `.introduced` or `.deprecated`. If `.introduced` is specified, then
  ///     shorthand `@available` attributes such as `@available(macOS 999.0, *)`
  ///     are included.
  ///
  /// - Returns: An array of structures describing the version-based
  ///   availability constraints on this instance, such as `("macOS", 999.0)`.
  ///
  /// The values in the resulting array can be used to construct expressions
  /// such as `if #available(macOS 999.0, *)`.
  func availability(when whenKeyword: Keyword) -> [Availability] {
    availabilityAttributes.flatMap { attribute -> [Availability] in
      guard case let .availability(specList) = attribute.arguments else {
        return []
      }

      let entries = specList.map(\.argument)

      // First, find the message (if any) to apply to any values produced from
      // this spec list.
      let message = entries.lazy.compactMap { entry in
          if case let .availabilityLabeledArgument(argument) = entry,
             argument.label.tokenKind == .keyword(.message),
             case let .string(message) = argument.value {
            return message
          }
          return nil
        }.first

      var lastPlatformName: TokenSyntax? = nil
      var wildcardEncountered = false
      let hasWildcard = entries.contains(where: \.isWildcard)
      return entries.compactMap { entry in
        switch entry {
        case let .availabilityVersionRestriction(restriction) where whenKeyword == .introduced:
          return Availability(attribute: attribute, platformName: restriction.platform, version: restriction.version, mayNeedTrailingWildcard: hasWildcard, message: message)
        case let .token(token):
          if case .identifier = token.tokenKind {
            lastPlatformName = token
          } else if entry.isWildcard {
            wildcardEncountered = true
            // It is syntactically valid to specify a platform name without a
            // version in an availability declaration, and it's used to resolve
            // a custom availability definition specified via the
            // `-define-availability` compiler flag. So if there was a "last"
            // platform name and we encounter an asterisk token, append it as an
            // `Availability` with a `nil` version.
            if let lastPlatformName, whenKeyword == .introduced {
              return Availability(attribute: attribute, platformName: lastPlatformName, version: nil, message: message)
            }
          } else if case let .keyword(keyword) = token.tokenKind, keyword == whenKeyword {
            if wildcardEncountered {
              // Match the "always this availability" construct, i.e.
              // `@available(*, deprecated)` and `@available(*, unavailable)`.
              return Availability(attribute: attribute, platformName: lastPlatformName, version: nil, message: message)
            } else if keyword == .unavailable {
              return Availability(attribute: attribute, platformName: lastPlatformName, version: nil, message: message)
            }
          }
        case let .availabilityLabeledArgument(argument):
          if argument.label.tokenKind == .keyword(whenKeyword), case let .version(version) = argument.value {
            return Availability(attribute: attribute, platformName: lastPlatformName, version: version, message: message)
          }
        default:
          break
        }

        return nil
      }
    }
  }

  /// The first `@available(*, noasync)` or `@_unavailableFromAsync` attribute
  /// on this instance, if any.
  var noasyncAttribute: AttributeSyntax? {
    availability(when: .noasync).first?.attribute
      ?? attributes(named: "_unavailableFromAsync", inModuleNamed: "Swift").first
  }

  /// The first `@_unavailableInEmbedded` attribute on this instance, if any.
  var unavailableInEmbeddedAttribute: AttributeSyntax? {
    attributes(named: "_unavailableInEmbedded", inModuleNamed: "Swift").first
  }

  /// Find all attributes on this node, if any, with the given name.
  ///
  /// - Parameters:
  ///   - name: The name of the attribute to look for.
  ///   - moduleName: The name of the module that declares the attribute named
  ///     `name`.
  ///
  /// - Returns: An array of `AttributeSyntax` corresponding to the attached
  ///   `@Test` attributes, or the empty array if none is attached.
  func attributes(named name: String, inModuleNamed moduleName: String = "Testing") -> [AttributeSyntax] {
    attributes.lazy.compactMap { attribute in
      if case let .attribute(attribute) = attribute {
        return attribute
      }
      return nil
    }.filter {
      $0.attributeName.isNamed(name, inModuleNamed: moduleName)
    }
  }
}

extension AttributeSyntax {
  /// The text of this attribute's name.
  var attributeNameText: String {
    attributeName
      .tokens(viewMode: .fixedUp)
      .map(\.textWithoutBackticks)
      .joined()
  }
}

extension AvailabilityArgumentSyntax.Argument {
  var isWildcard: Bool {
    if case let .token(token) = self,
       case let .binaryOperator(op) = token.tokenKind, op == "*" {
      return true
    }
    return false
  }
}
