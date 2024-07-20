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
    case type(_ type: Any.Type)

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
  public var type: Any.Type? {
    if case let .type(type) = _kind {
      return type
    }
    return nil
  }

  init(fullyQualifiedName: String, unqualifiedName: String, mangledName: String?) {
    _kind = .nameOnly(
      fullyQualifiedComponents: fullyQualifiedName.split(separator: ".").map(String.init),
      unqualified: unqualifiedName,
      mangled: mangledName
    )
  }

  /// Initialize an instance of this type describing the specified type.
  ///
  /// - Parameters:
  ///   - type: The type which this instance should describe.
  init(describing type: Any.Type) {
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

extension TypeInfo {
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
      var result = String(reflecting: type)
        .split(separator: ".")
        .map(String.init)

      // If a type is extended in another module and then referenced by name,
      // its name according to the String(reflecting:) API will be prefixed with
      // "(extension in MODULE_NAME):". For our purposes, we never want to
      // preserve that prefix.
      if let firstComponent = result.first, firstComponent.starts(with: "(extension in ") {
        result[0] = String(firstComponent.split(separator: ":", maxSplits: 1).last!)
      }

      // If a type is private or embedded in a function, its fully qualified
      // name may include "(unknown context at $xxxxxxxx)" as a component. Strip
      // those out as they're uninteresting to us.
      result = result.filter { !$0.starts(with: "(unknown context at") }

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
      String(describing: type)
    case let .nameOnly(_, unqualifiedName, _):
      unqualifiedName
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
  /// Per the [Swift mangling ABI](https://github.com/apple/swift/blob/main/docs/ABI/Mangling.rst),
  /// enumeration types are mangled as `"O"`.
  ///
  /// - Bug: We use the internal Swift standard library function
  ///   `_mangledTypeName()` to derive this information. We should use supported
  ///   API instead. ([swift-#69147](https://github.com/apple/swift/issues/69147))
  var isSwiftEnumeration: Bool {
    mangledName?.last == "O"
  }

  /// Whether or not the described type is imported from C, C++, or Objective-C.
  ///
  /// Per the [Swift mangling ABI](https://github.com/apple/swift/blob/main/docs/ABI/Mangling.rst),
  /// types imported from C-family languages are placed in a single flat `__C`
  /// module. That module has a standardized mangling of `"So"`. The presence of
  /// those characters at the start of a type's mangled name indicates that it
  /// is an imported type.
  ///
  /// - Bug: We use the internal Swift standard library function
  ///   `_mangledTypeName()` to derive this information. We should use supported
  ///   API instead. ([swift-#69146](https://github.com/apple/swift/issues/69146))
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
  if subclass == superclass {
    true
  } else if let subclassImmediateSuperclass = _getSuperclass(subclass) {
    isClass(subclassImmediateSuperclass, subclassOf: superclass)
  } else {
    false
  }
}

// MARK: - Containing types

extension TypeInfo {
  /// An instance of this type representing the type immediately containing the
  /// described type.
  ///
  /// For instance, given the following declaration in the `Example` module:
  ///
  /// ```swift
  /// struct A {
  ///   struct B {}
  /// }
  /// ```
  ///
  /// The value of this property for the type `A.B` would describe `A`, while
  /// the value for `A` would be `nil` because it has no enclosing type.
  var containingTypeInfo: Self? {
    let fqnComponents = fullyQualifiedNameComponents
    if fqnComponents.count > 2 { // the module is not a type
      let fqn = fqnComponents.dropLast().joined(separator: ".")
#if false // currently non-functional
      if let type = _typeByName(fqn) {
        return Self(describing: type)
      }
#endif
      let name = fqnComponents[fqnComponents.count - 2]
      return Self(fullyQualifiedName: fqn, unqualifiedName: name, mangledName: nil)
    }
    return nil
  }
}

extension Test {
  /// A sequence of ``TypeInfo`` instances representing the types that
  /// recursively contain this test, if any.
  ///
  /// If a test is associated with a global function or static function, the
  /// value of this property is `nil`.
  var allContainingTypeInfo: some Sequence<TypeInfo> {
    sequence(first: containingTypeInfo) { element in
      element?.containingTypeInfo
    }.compactMap { $0 }
  }
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
      return lhs == rhs
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
