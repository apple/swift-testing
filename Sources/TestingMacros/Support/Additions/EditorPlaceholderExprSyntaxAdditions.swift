//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

import SwiftSyntax
import SwiftSyntaxBuilder

extension EditorPlaceholderExprSyntax {
  /// Initialize an instance of this type with the given placeholder string and
  /// optional type.
  ///
  /// - Parameters:
  ///   - placeholder: The placeholder string, not including surrounding angle
  ///     brackets or pound characters.
  ///   - type: The type which this placeholder have, if any. When non-`nil`,
  ///     the expression will use typed placeholder syntax.
  init(_ placeholder: String, type: String? = nil) {
    let placeholderContent = if let type {
      // These use typed placeholder syntax, which allows the compiler to
      // type-check the expression successfully. The resulting code still does
      // not compile due to the placeholder, but it makes the diagnostic more
      // clear. See
      // https://developer.apple.com/documentation/swift-playgrounds/specifying-editable-regions-in-a-playground-page#Mark-Editable-Areas-with-Placeholder-Tokens
      if placeholder == type {
        // When the placeholder string is exactly the same as the type string,
        // use the shorter typed placeholder format.
        "T##\(placeholder)"
      } else {
        "T##\(placeholder)##\(type)"
      }
    } else {
      placeholder
    }

    // Manually concatenate the string to avoid it being interpreted as a
    // placeholder when editing this file.
    self.init(placeholder: .identifier(_editorPlaceholder(containing: placeholderContent)))
  }

  /// Initialize an instance of this type with the given type, using that as the
  /// placeholder string.
  ///
  /// - Parameters:
  ///   - type: The type to use both as the placeholder text and as the
  ///     expression's type.
  init(type: String) {
    self.init(type, type: type)
  }
}

extension TypeSyntax {
  /// Construct a type syntax node containing a placeholder string.
  ///
  /// - Parameters:
  ///   - placeholder: The placeholder string, not including surrounding angle
  ///     brackets or pound characters.
  ///
  /// - Returns: A new `TypeSyntax` instance representing a placeholder.
  static func placeholder(_ placeholder: String) -> Self {
    Self(IdentifierTypeSyntax(name: .identifier(_editorPlaceholder(containing: placeholder))))
  }
}

extension StringLiteralExprSyntax {
  /// Construct a string literal expression syntax node containing an editor
  /// placeholder string.
  ///
  /// - Parameters
  ///   - placeholder: The placeholder string, not including surrounding angle
  ///     brackets or pound characters.
  init(placeholder: String) {
    self.init(content: _editorPlaceholder(containing: placeholder))
  }
}

/// Format a source editor placeholder string with the specified content.
///
/// - Parameters:
///   - content: The placeholder string, not including surrounding angle
///     brackets or pound characters
///
/// - Returns: A fully-formatted formatted editor placeholder string, including
///   necessary surrounding punctuation.
private func _editorPlaceholder(containing content: String) -> String {
  // Manually concatenate the string to avoid it being interpreted as a
  // placeholder when editing this file.
  "<#\(content)#" + ">"
}
