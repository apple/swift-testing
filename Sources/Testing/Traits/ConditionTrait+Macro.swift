//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

extension Trait where Self == ConditionTrait {
  /// Get a string describing a platform and optional version tuple.
  ///
  /// - Parameters:
  ///   - platformName: The name of the platform provided during `@Test` macro
  ///     expansion.
  ///   - version: A platform version tuple as provided during `@Test` macro
  ///     expansion, if any.
  ///
  /// - Returns: A string describing `platformName` and `version` such as
  ///   `"toasterOS 1.0.2"`.
  private static func _description(
    ofPlatformName platformName: String,
    version: (major: UInt64, minor: UInt64?, patch: UInt64?)?
  ) -> String {
    guard let version else {
      return platformName
    }
    guard let minorVersion = version.minor else {
      return "\(platformName) \(version.major)"
    }
    guard let patchVersion = version.patch else {
      return "\(platformName) \(version.major).\(minorVersion)"
    }
    return "\(platformName) \(version.major).\(minorVersion).\(patchVersion)"
  }

  /// Create a trait controlling availability of a test based on an
  /// `@available()` attribute applied to it.
  ///
  /// - Parameters:
  ///   - platformName: The name of the platform specified in the `@available()`
  ///     attribute.
  ///   - version: A platform version tuple specified in the `@available()`
  ///     attribute, if any.
  ///   - message: The `message` parameter of the availability attribute.
  ///   - sourceLocation: The source location of the test.
  ///   - condition: A closure containing the actual `if #available()`
  ///     expression.
  ///
  /// - Returns: A trait.
  ///
  /// - Warning: This function is used to implement the `@Test` macro. Do not
  ///   call it directly.
  public static func __available(
    _ platformName: String,
    introduced version: (major: UInt64, minor: UInt64?, patch: UInt64?)?,
    message: Comment?,
    sourceLocation: SourceLocation,
    _ condition: @escaping @Sendable () -> Bool
  ) -> Self {
    // TODO: Semantic capture of platform name/version (rather than just a comment)
    Self(
      kind: .conditional(condition),
      comments: [message ?? "Requires \(_description(ofPlatformName: platformName, version: version))"],
      sourceLocation: sourceLocation
    )
  }

  /// Create a trait controlling availability of a test based on an
  /// `@available()` attribute applied to it.
  ///
  /// - Parameters:
  ///   - platformName: The name of the platform specified in the `@available()`
  ///     attribute.
  ///   - version: A platform version tuple specified in the `@available()`
  ///     attribute, if any.
  ///   - message: The `message` parameter of the availability attribute.
  ///   - sourceLocation: The source location of the test.
  ///   - condition: A closure containing the actual `if #available()`
  ///     expression.
  ///
  /// - Returns: A trait.
  ///
  /// - Warning: This function is used to implement the `@Test` macro. Do not
  ///   call it directly.
  public static func __available(
    _ platformName: String,
    obsoleted version: (major: UInt64, minor: UInt64?, patch: UInt64?)?,
    message: Comment?,
    sourceLocation: SourceLocation,
    _ condition: @escaping @Sendable () -> Bool
  ) -> Self {
    // TODO: Semantic capture of platform name/version (rather than just a comment)
    let message: Comment = if let message {
      message
    } else if let version {
      "Obsolete as of \(_description(ofPlatformName: platformName, version: version))"
    } else {
      "Unavailable on \(_description(ofPlatformName: platformName, version: nil))"
    }
    return Self(
      kind: .conditional(condition),
      comments: [message],
      sourceLocation: sourceLocation
    )
  }

  /// Create a trait controlling availability of a test based on an
  /// `@available(*, unavailable)` attribute applied to it.
  ///
  /// - Parameters:
  ///   - message: The `message` parameter of the availability attribute.
  ///   - sourceLocation: The source location of the test.
  ///
  /// - Returns: A trait.
  ///
  /// - Warning: This function is used to implement the `@Test` macro. Do not
  ///   call it directly.
  public static func __unavailable(message: Comment?, sourceLocation: SourceLocation) -> Self {
    Self(
      kind: .unconditional(false),
      comments: [message ?? "Marked @available(*, unavailable)"],
      sourceLocation: sourceLocation
    )
  }

  /// Create a trait controlling availability of a test based on an
  /// `@_unavailableInEmbedded` attribute applied to it.
  ///
  /// - Parameters:
  ///   - sourceLocation: The source location of the test.
  ///
  /// - Returns: A trait.
  ///
  /// - Warning: This function is used to implement the `@Test` macro. Do not
  ///   call it directly.
  public static func __unavailableInEmbedded(sourceLocation: SourceLocation) -> Self {
#if hasFeature(Embedded)
    let isEmbedded = true
#else
    let isEmbedded = false
#endif
    return Self(
      kind: .unconditional(!isEmbedded),
      comments: ["Marked @_unavailableInEmbedded"],
      sourceLocation: sourceLocation
    )
  }
}
