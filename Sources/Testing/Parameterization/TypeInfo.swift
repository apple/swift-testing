//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

/// A description of the type of a value encountered during testing or a
/// parameter of a test function.
@_spi(ForToolsIntegrationOnly)
public struct TypeInfo: Sendable {
  /// An enumeration defining backing storage for an instance of ``TypeInfo``.
  private enum _Kind: Sendable {
    /// The type info represents a concrete metatype.
    ///
    /// - Parameters:
    ///   - type: The concrete metatype.
    case type(_ type: any ~Copyable.Type)

    /// The type info represents a metatype, but a reference to that metatype is
    /// not available at runtime.
    ///
    /// - Parameters:
    ///   - fullyQualifiedComponents: The fully-qualified name components of the
    ///     type.
    ///   - unqualified: The unqualified name of the type.
    ///   - mangled: The mangled name of the type, if available.
    case nameOnly(fullyQualifiedComponents: [String], unqualified: String, mangled: String?)
  }

  /// The kind of type info.
  private var _kind: _Kind

  /// The described type, if available.
  ///
  /// If this instance was created from a type name, or if it was previously
  /// encoded and decoded, the value of this property is `nil`.
  public var type: (any ~Copyable.Type)? {
    if case let .type(type) = _kind {
      return type
    }
    return nil
  }

  /// Initialize an instance of this type with the specified names.
  ///
  /// - Parameters:
  ///   - fullyQualifiedComponents: The fully-qualified name components of the
  ///     type.
  ///   - unqualified: The unqualified name of the type.
  ///   - mangled: The mangled name of the type, if available.
  init(fullyQualifiedNameComponents: [String], unqualifiedName: String, mangledName: String? = nil) {
    _kind = .nameOnly(
      fullyQualifiedComponents: fullyQualifiedNameComponents,
      unqualified: unqualifiedName,
      mangled: mangledName
    )
  }

  /// Initialize an instance of this type with the specified names.
  ///
  /// - Parameters:
  ///   - fullyQualifiedName: The fully-qualified name of the type, with its
  ///     components separated by a period character (`"."`).
  ///   - unqualified: The unqualified name of the type.
  ///   - mangled: The mangled name of the type, if available.
  init(fullyQualifiedName: String, unqualifiedName: String, mangledName: String?) {
    self.init(
      fullyQualifiedNameComponents: Self.fullyQualifiedNameComponents(ofTypeWithName: fullyQualifiedName),
      unqualifiedName: unqualifiedName,
      mangledName: mangledName
    )
  }

  /// Initialize an instance of this type describing the specified type.
  ///
  /// - Parameters:
  ///   - type: The type which this instance should describe.
  init(describing type: any ~Copyable.Type) {
    _kind = .type(type)
  }

  /// Initialize an instance of this type describing the type of the specified
  /// value.
  ///
  /// - Parameters:
  ///   - value: The value whose type this instance should describe.
  init(describingTypeOf value: Any) {
    self.init(describing: Swift.type(of: value))
  }
}

// MARK: - Name

/// Split a string with a separator while respecting raw identifiers and their
/// enclosing backtick characters.
///
/// - Parameters:
///   - string: The string to split.
///   - separator: The character that separates components of `string`.
///   - maxSplits: The maximum number of splits to perform on `string`. The
///     resulting array contains up to `maxSplits + 1` elements.
///
/// - Returns: An array of substrings of `string`.
///
/// Unlike `String.split(separator:maxSplits:omittingEmptySubsequences:)`, this
/// function does not split the string on separator characters that occur
/// between pairs of backtick characters. This is useful when splitting strings
/// containing raw identifiers.
///
/// - Complexity: O(_n_), where _n_ is the length of `string`.
func rawIdentifierAwareSplit<S>(_ string: S, separator: Character, maxSplits: Int = .max) -> [S.SubSequence] where S: StringProtocol {
  var result = [S.SubSequence]()

  var inRawIdentifier = false
  var componentStartIndex = string.startIndex
  for i in string.indices {
    let c = string[i]
    if c == "`" {
      // We are either entering or exiting a raw identifier. While inside a raw
      // identifier, separator characters are ignored.
      inRawIdentifier.toggle()
    } else if c == separator && !inRawIdentifier {
      // Add everything up to this separator as the next component, then start
      // a new component after the separator.
      result.append(string[componentStartIndex ..< i])
      componentStartIndex = string.index(after: i)

      if result.count == maxSplits {
        // We don't need to find more separators. We'll add the remainder of the
        // string outside the loop as the last component, then return.
        break
      }
    }
  }
  result.append(string[componentStartIndex...])

  return result
}

extension TypeInfo {
  /// Replace any non-breaking spaces in the given string with normal spaces.
  ///
  /// - Parameters:
  ///   - rawIdentifier: The string to rewrite.
  ///
  /// - Returns: A copy of `rawIdentifier` with non-breaking spaces (`U+00A0`)
  ///   replaced with normal spaces (`U+0020`).
  ///
  /// When the Swift runtime demangles a raw identifier, it [replaces](https://github.com/swiftlang/swift/blob/d033eec1aa427f40dcc38679d43b83d9dbc06ae7/lib/Basic/Mangler.cpp#L250)
  /// normal ASCII spaces with non-breaking spaces to maintain compatibility
  /// with historical usages of spaces in mangled name forms. Non-breaking
  /// spaces are not otherwise valid in raw identifiers, so this transformation
  /// is reversible.
  private static func _rewriteNonBreakingSpacesAsASCIISpaces(in rawIdentifier: some StringProtocol) -> String? {
    let nbsp = "\u{00A0}" as UnicodeScalar

    // If there are no non-breaking spaces in the string, exit early to avoid
    // any further allocations.
    let unicodeScalars = rawIdentifier.unicodeScalars
    guard unicodeScalars.contains(nbsp) else {
      return nil
    }

    // Replace non-breaking spaces, then construct a new string from the
    // resulting sequence.
    let result = unicodeScalars.lazy.map { $0 == nbsp ? " " : $0 }
    return String(String.UnicodeScalarView(result))
  }

  /// An in-memory cache of fully-qualified type name components.
  private static let _fullyQualifiedNameComponentsCache = Locked<[ObjectIdentifier: [String]]>()

  /// Split the given fully-qualified type name into its components.
  ///
  /// - Parameters:
  ///   - fullyQualifiedName: The string to split.
  ///
  /// - Returns: The components of `fullyQualifiedName` as substrings thereof.
  static func fullyQualifiedNameComponents(ofTypeWithName fullyQualifiedName: String) -> [String] {
    var components = rawIdentifierAwareSplit(fullyQualifiedName, separator: ".")

    // If a type is extended in another module and then referenced by name,
    // its name according to the String(reflecting:) API will be prefixed with
    // "(extension in MODULE_NAME):". For our purposes, we never want to
    // preserve that prefix.
    if let firstComponent = components.first, firstComponent.starts(with: "(extension in "),
       let moduleName = rawIdentifierAwareSplit(firstComponent, separator: ":", maxSplits: 1).last {
      // NOTE: even if the module name is a raw identifier, it comprises a
      // single identifier (no splitting required) so we don't need to process
      // it any further.
      components[0] = moduleName
    }

    return components.lazy
      .filter { component in
        // If a type is private or embedded in a function, its fully qualified
        // name may include "(unknown context at $xxxxxxxx)" as a component.
        // Strip those out as they're uninteresting to us.
        !component.starts(with: "(unknown context at")
      }.map { component in
        // Replace non-breaking spaces with spaces. See the helper function's
        // documentation for more information.
        if let component = _rewriteNonBreakingSpacesAsASCIISpaces(in: component) {
          component[...]
        } else {
          component
        }
      }.map(String.init)
  }

  /// The complete name of this type, with the names of all referenced types
  /// fully-qualified by their module names when possible.
  ///
  /// The value of this property is equal to ``fullyQualifiedName``, but is
  /// split into components. For instance, given the following declaration in
  /// the `Example` module:
  ///
  /// ```swift
  /// struct A {
  ///   struct B {}
  /// }
  /// ```
  ///
  /// The value of this property for the type `A.B` would be
  /// `["Example", "A", "B"]`.
  public var fullyQualifiedNameComponents: [String] {
    switch _kind {
    case let .type(type):
      if let cachedResult = Self._fullyQualifiedNameComponentsCache.rawValue[ObjectIdentifier(type)] {
        return cachedResult
      }

      let result = Self.fullyQualifiedNameComponents(ofTypeWithName: String(reflecting: type))

      Self._fullyQualifiedNameComponentsCache.withLock { fullyQualifiedNameComponentsCache in
        fullyQualifiedNameComponentsCache[ObjectIdentifier(type)] = result
      }

      return result
    case let .nameOnly(fullyQualifiedNameComponents, _, _):
      return fullyQualifiedNameComponents
    }
  }

  /// The complete name of this type, with the names of all referenced types
  /// fully-qualified by their module names when possible.
  ///
  /// The value of this property is equal to ``fullyQualifiedNameComponents``,
  /// but is represented as a single string. For instance, given the following
  /// declaration in the `Example` module:
  ///
  /// ```swift
  /// struct A {
  ///   struct B {}
  /// }
  /// ```
  ///
  /// The value of this property for the type `A.B` would be `"Example.A.B"`.
  public var fullyQualifiedName: String {
    fullyQualifiedNameComponents.joined(separator: ".")
  }

  /// A simplified name of this type, by leaving the names of all referenced
  /// types unqualified, i.e. without module name prefixes.
  ///
  /// The value of this property is equal to the name of the type in isolation.
  /// For instance, given the following declaration in the `Example` module:
  ///
  /// ```swift
  /// struct A {
  ///   struct B {}
  /// }
  /// ```
  ///
  /// The value of this property for the type `A.B` would simply be `"B"`.
  public var unqualifiedName: String {
    switch _kind {
    case let .type(type):
      // Replace non-breaking spaces with spaces. See the helper function's
      // documentation for more information.
      var result = String(describing: type)
      result = Self._rewriteNonBreakingSpacesAsASCIISpaces(in: result) ?? result

      return result
    case let .nameOnly(_, unqualifiedName, _):
      return unqualifiedName
    }
  }

  /// The mangled name of this type as determined by the Swift compiler, if
  /// available.
  ///
  /// This property is used by other members of ``TypeInfo``. It should not be
  /// exposed as API or SPI because the mangled name of a type may include
  /// components derived at runtime that vary between processes. A type's
  /// mangled name should not be used if its unmangled name is sufficient.
  ///
  /// If the underlying Swift interface is unavailable or if the Swift runtime
  /// could not determine the mangled name of the represented type, the value of
  /// this property is `nil`.
  var mangledName: String? {
    guard #available(_mangledTypeNameAPI, *) else {
      return nil
    }
    switch _kind {
    case let .type(type):
      return _mangledTypeName(type)
    case let .nameOnly(_, _, mangledName):
      return mangledName
    }
  }
}

// MARK: - Properties

extension TypeInfo {
  /// Whether or not the described type is a Swift `enum` type.
  ///
  /// Per the [Swift mangling ABI](https://github.com/swiftlang/swift/blob/main/docs/ABI/Mangling.rst),
  /// enumeration types are mangled as `"O"`.
  ///
  /// - Bug: We use the internal Swift standard library function
  ///   `_mangledTypeName()` to derive this information. We should use supported
  ///   API instead. ([swift-#69147](https://github.com/swiftlang/swift/issues/69147))
  var isSwiftEnumeration: Bool {
    mangledName?.last == "O"
  }

  /// Whether or not the described type is imported from C, C++, or Objective-C.
  ///
  /// Per the [Swift mangling ABI](https://github.com/swiftlang/swift/blob/main/docs/ABI/Mangling.rst),
  /// types imported from C-family languages are placed in a single flat `__C`
  /// module. That module has a standardized mangling of `"So"`. The presence of
  /// those characters at the start of a type's mangled name indicates that it
  /// is an imported type.
  ///
  /// - Bug: We use the internal Swift standard library function
  ///   `_mangledTypeName()` to derive this information. We should use supported
  ///   API instead. ([swift-#69146](https://github.com/swiftlang/swift/issues/69146))
  var isImportedFromC: Bool {
    guard let mangledName, mangledName.count > 2 else {
      return false
    }

    let prefixEndIndex = mangledName.index(mangledName.startIndex, offsetBy: 2)
    return mangledName[..<prefixEndIndex] == "So"
  }
}

/// Check if a class is a subclass (or equal to) another class.
///
/// - Parameters:
///   - subclass: The (possible) subclass to check.
///   - superclass The (possible) superclass to check.
///
/// - Returns: Whether `subclass` is a subclass of, or is equal to,
///   `superclass`.
func isClass(_ subclass: AnyClass, subclassOf superclass: AnyClass) -> Bool {
  func open<T, U>(_: T.Type, _: U.Type) -> Bool where T: AnyObject, U: AnyObject {
    T.self is U.Type
  }
  return open(subclass, superclass)
}

// MARK: - CustomStringConvertible, CustomDebugStringConvertible, CustomTestStringConvertible

extension TypeInfo: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String {
    unqualifiedName
  }

  public var debugDescription: String {
    fullyQualifiedName
  }
}

// MARK: - Equatable, Hashable

extension TypeInfo: Hashable {
  /// Check if this instance describes a given type.
  ///
  /// - Parameters:
  ///   - type: The type to compare against.
  ///
  /// - Returns: Whether or not this instance represents `type`.
  public func describes(_ type: Any.Type) -> Bool {
    self == TypeInfo(describing: type)
  }

  public static func ==(lhs: Self, rhs: Self) -> Bool {
    switch (lhs._kind, rhs._kind) {
    case let (.type(lhs), .type(rhs)):
      return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    default:
      return lhs.fullyQualifiedNameComponents == rhs.fullyQualifiedNameComponents
    }
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(fullyQualifiedName)
  }
}

// MARK: - Codable

extension TypeInfo: Codable {
  /// A simplified version of ``TypeInfo`` suitable for encoding and decoding.
  fileprivate struct EncodedForm {
    /// The complete name of this type, with the names of all referenced types
    /// fully-qualified by their module names when possible.
    public var fullyQualifiedName: String

    /// A simplified name of this type, by leaving the names of all referenced
    /// types unqualified, i.e. without module name prefixes.
    public var unqualifiedName: String

    /// The mangled name of this type as determined by the Swift compiler, if
    /// available.
    public var mangledName: String?
  }

  public func encode(to encoder: any Encoder) throws {
    let encodedForm = EncodedForm(fullyQualifiedName: fullyQualifiedName, unqualifiedName: unqualifiedName, mangledName: mangledName)
    try encodedForm.encode(to: encoder)
  }

  public init(from decoder: any Decoder) throws {
    let encodedForm = try EncodedForm(from: decoder)
    self.init(fullyQualifiedName: encodedForm.fullyQualifiedName, unqualifiedName: encodedForm.unqualifiedName, mangledName: encodedForm.mangledName)
  }
}

extension TypeInfo.EncodedForm: Codable {}

// MARK: - Custom casts

/// Cast the given data pointer to a C function pointer.
///
/// - Parameters:
///   - address: The C function pointer as an untyped data pointer.
///   - type: The type of the C function. This type must be a function type with
///     the "C" convention (i.e. `@convention (...) -> ...`).
///
/// - Returns: `address` cast to the given C function type.
///
/// This function serves to make code that casts C function pointers more
/// self-documenting. In debug builds, it checks that `type` is a C function
/// type. In release builds, it behaves the same as `unsafeBitCast(_:to:)`.
func castCFunction<T>(at address: UnsafeRawPointer, to type: T.Type) -> T {
#if DEBUG
  if let mangledName = TypeInfo(describing: T.self).mangledName {
    precondition(mangledName.last == "C", "\(#function) should only be used to cast a pointer to a C function type.")
  }
#endif
  return unsafeBitCast(address, to: type)
}

/// Cast the given C function pointer to a data pointer.
///
/// - Parameters:
///   - function: The C function pointer.
///
/// - Returns: `function` cast to an untyped data pointer.
///
/// This function serves to make code that casts C function pointers more
/// self-documenting. In debug builds, it checks that `function` is a C function
/// pointer. In release builds, it behaves the same as `unsafeBitCast(_:to:)`.
func castCFunction<T>(_ function: T, to _: UnsafeRawPointer.Type) -> UnsafeRawPointer {
#if DEBUG
  if let mangledName = TypeInfo(describing: T.self).mangledName {
    precondition(mangledName.last == "C", "\(#function) should only be used to cast a C function.")
  }
#endif
  return unsafeBitCast(function, to: UnsafeRawPointer.self)
}
