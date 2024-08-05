//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

/// A type representing a Swift expression captured at compile-time from source
/// code.
///
/// Instances of this type are generally opaque to callers. They can be
/// converted to strings representing their source code (captured at compile
/// time) using `String.init(describing:)`.
///
/// If parsing is needed, use the swift-syntax package to convert an instance of
/// this type to an instance of `ExprSyntax` using a Swift expression such as:
///
/// ```swift
/// let swiftSyntaxExpr: ExprSyntax = "\(testExpr)"
/// ```
///
/// - Warning: This type is used to implement the `#expect(exitsWith:)`
///   macro. Do not use it directly. Tools can use the SPI ``Expression``
///   typealias if needed.
public struct __Expression: Sendable {
  /// An enumeration describing the various kinds of expression that can be
  /// captured.
  ///
  /// This type is not part of the public interface of the testing library.
  enum Kind: Sendable {
    /// The expression represents a single, complete syntax node.
    ///
    /// - Parameters:
    ///   - sourceCode: The source code of the represented expression.
    case generic(_ sourceCode: String)

    /// The expression represents a string literal expression.
    ///
    /// - Parameters:
    ///   - sourceCode: The source code of the represented expression. Note that
    ///     this string is not the _value_ of the string literal, but the string
    ///     literal itself (including leading and trailing quote marks and
    ///     extended punctuation.)
    ///   - stringValue: The value of the string literal.
    case stringLiteral(sourceCode: String, stringValue: String)

    /// The expression represents a binary operation.
    ///
    /// - Parameters:
    ///   - lhs: The left-hand operand.
    ///   - operator: The operator.
    ///   - rhs: The right-hand operand.
    indirect case binaryOperation(lhs: __Expression, `operator`: String, rhs: __Expression)

    /// A type representing an argument to a function call, used by the
    /// `__Expression.Kind.functionCall` case.
    ///
    /// This type is not part of the public interface of the testing library.
    struct FunctionCallArgument: Sendable {
      /// The label, if present, of the argument.
      var label: String?

      /// The value, as an expression, of the argument.
      var value: __Expression
    }

    /// The expression represents a function call.
    ///
    /// - Parameters:
    ///   - value: The value on which the function was called, if any.
    ///   - functionName: The name of the function that was called.
    ///   - arguments: The arguments passed to the function.
    indirect case functionCall(value: __Expression?, functionName: String, arguments: [FunctionCallArgument])

    /// The expression represents a property access.
    ///
    /// - Parameters:
    ///   - value: The value whose property was accessed.
    ///   - keyPath: The key path, relative to `value`, that was accessed, not
    ///     including a leading backslash or period.
    indirect case propertyAccess(value: __Expression, keyPath: String)

    /// The expression negates another expression.
    ///
    /// - Parameters:
    ///   - expression: The expression that was negated.
    ///   - isParenthetical: Whether or not `expression` was enclosed in
    ///     parentheses (and the `!` operator was outside it.) This argument
    ///     affects how this expression is represented as a string.
    ///
    /// Unlike other cases in this enumeration, this case affects the runtime
    /// behavior of the `__check()` family of functions.
    indirect case negation(_ expression: __Expression, isParenthetical: Bool)
  }

  /// The kind of syntax node represented by this instance.
  ///
  /// This property is not part of the public interface of the testing library.
  /// Use `String(describing:)` to access the source code represented by an
  /// instance of this type.
  var kind: Kind

  /// The source code of the original captured expression.
  @_spi(ForToolsIntegrationOnly)
  public var sourceCode: String {
    switch kind {
    case let .generic(sourceCode), let .stringLiteral(sourceCode, _):
      return sourceCode
    case let .binaryOperation(lhs, op, rhs):
      return "\(lhs) \(op) \(rhs)"
    case let .functionCall(value, functionName, arguments):
      let argumentList = arguments.lazy
        .map { argument in
          if let argumentLabel = argument.label {
            return "\(argumentLabel): \(argument.value.sourceCode)"
          }
          return argument.value.sourceCode
        }.joined(separator: ", ")
      if let value {
        return "\(value.sourceCode).\(functionName)(\(argumentList))"
      }
      return "\(functionName)(\(argumentList))"
    case let .propertyAccess(value, keyPath):
      return "\(value.sourceCode).\(keyPath)"
    case let .negation(expression, isParenthetical):
      var sourceCode = expression.sourceCode
      if isParenthetical {
        sourceCode = "(\(sourceCode))"
      }
      return "!\(sourceCode)"
    }
  }

  /// A type which represents an evaluated value, which may include textual
  /// descriptions, type information, substructure, and other information.
  @_spi(ForToolsIntegrationOnly)
  public struct Value: Sendable {
    /// A description of this value, formatted using
    /// ``Swift/String/init(describingForTest:)``.
    public var description: String

    /// A debug description of this value, formatted using
    /// `String(reflecting:)`.
    public var debugDescription: String

    /// Information about the type of this value.
    public var typeInfo: TypeInfo

    /// The label associated with this value, if any.
    ///
    /// For non-child instances, or for child instances of members who do not
    /// have a label (such as elements of a collection), the value of this
    /// property is `nil`.
    public var label: String?

    /// Whether or not this value represents a collection of values.
    public var isCollection: Bool

    /// The children of this value, representing its substructure, if any.
    ///
    /// If the value this instance represents does not contain any substructural
    /// values but ``isCollection`` is `true`, the value of this property is an
    /// empty array. Otherwise, the value of this property is non-`nil` only if
    /// the value it represents contains substructural values.
    public var children: [Self]?

    /// Initialize an instance of this type describing the specified subject and
    /// its children (if any).
    ///
    /// - Parameters:
    ///   - subject: The subject this instance should describe.
    init(reflecting subject: Any) {
      var seenObjects: [ObjectIdentifier: AnyObject] = [:]
      self.init(_reflecting: subject, label: nil, seenObjects: &seenObjects)
    }

    /// Initialize an instance of this type describing the specified subject and
    /// its children (if any), recursively.
    ///
    /// - Parameters:
    ///   - subject: The subject this instance should describe.
    ///   - label: An optional label for this value. This should be a non-`nil`
    ///     value when creating instances of this type which describe
    ///     substructural values.
    ///   - seenObjects: The objects which have been seen so far while calling
    ///     this initializer recursively, keyed by their object identifiers.
    ///     This is used to halt further recursion if a previously-seen object
    ///     is encountered again.
    private init(
        _reflecting subject: Any,
        label: String?,
        seenObjects: inout [ObjectIdentifier: AnyObject]
    ) {
      let mirror = Mirror(reflecting: subject)

      // If the subject being reflected is an instance of a reference type (e.g.
      // a class), keep track of whether it has been seen previously. Later
      // logic uses this to avoid infinite recursion for values which have
      // cyclic object references.
      //
      // This behavior is gated on the display style of the subject's mirror
      // being `.class`. That could be incorrect if a subject implements a
      // custom mirror, but in that situation, the subject type is responsible
      // for avoiding data references.
      //
      // For efficiency, this logic matches previously-seen objects based on
      // their pointer using `ObjectIdentifier`. This requires conditionally
      // down-casting the subject to `AnyObject`, but Swift can downcast any
      // value to `AnyObject`, even value types. To ensure only true reference
      // types are tracked, this checks the metatype of the subject using
      // `type(of:)`, which is inexpensive. The object itself is stored as the
      // value in the dictionary to ensure it is retained for the duration of
      // the recursion.
      var objectIdentifierTeRemove: ObjectIdentifier?
      var shouldIncludeChildren = true
      if mirror.displayStyle == .class, type(of: subject) is AnyObject.Type {
        let object = subject as AnyObject
        let objectIdentifier = ObjectIdentifier(object)
        let oldValue = seenObjects.updateValue(object, forKey: objectIdentifier)
        if oldValue != nil {
          shouldIncludeChildren = false
        }
        objectIdentifierTeRemove = objectIdentifier
      }
      defer {
        if let objectIdentifierTeRemove {
          // Remove the object from the set of previously-seen objects after
          // (potentially) recursing to reflect children. This is so that
          // repeated references to the same object are still included multiple
          // times; only _cyclic_ object references should be avoided.
          seenObjects[objectIdentifierTeRemove] = nil
        }
      }

      description = String(describingForTest: subject)
      debugDescription = String(reflecting: subject)
      typeInfo = TypeInfo(describingTypeOf: subject)
      self.label = label

      isCollection = switch mirror.displayStyle {
      case .some(.collection),
           .some(.dictionary),
           .some(.set):
        true
      default:
        false
      }

      if shouldIncludeChildren && (!mirror.children.isEmpty || isCollection) {
        self.children = mirror.children.map { child in
          Self(_reflecting: child.value, label: child.label, seenObjects: &seenObjects)
        }
      }
    }
  }

  /// A representation of the runtime value of this expression.
  ///
  /// If the runtime value of this expression has not been evaluated, the value
  /// of this property is `nil`.
  @_spi(ForToolsIntegrationOnly)
  public var runtimeValue: Value?

  /// Copy this instance and capture the runtime value corresponding to it.
  ///
  /// - Parameters:
  ///   - value: The captured runtime value.
  ///
  /// - Returns: A copy of `self` with information about the specified runtime
  ///   value captured for future use.
  func capturingRuntimeValue(_ value: (some Any)?) -> Self {
    var result = self
    result.runtimeValue = value.map { Value(reflecting: $0) }
    if case let .negation(subexpression, isParenthetical) = kind, let value = value as? Bool {
      result.kind = .negation(subexpression.capturingRuntimeValue(!value), isParenthetical: isParenthetical)
    }
    return result
  }

  /// Copy this instance and capture the runtime values corresponding to its
  /// subexpressions.
  ///
  /// - Parameters:
  ///   - firstValue: The first captured runtime value.
  ///   - additionalValues: Any additional captured runtime values after the
  ///     first.
  ///
  /// - Returns: A copy of `self` with information about the specified runtime
  ///   values captured for future use.
  ///
  /// If the ``kind`` of `self` is ``Kind/generic`` or ``Kind/stringLiteral``,
  /// this function is equivalent to ``capturingRuntimeValue(_:)``.
  func capturingRuntimeValues<each T>(_ firstValue: (some Any)?, _ additionalValues: repeat (each T)?) -> Self {
    var result = self

    // Convert the variadic generic argument list to an array.
    var additionalValuesArray = [Any?]()
    for additionalValue in repeat each additionalValues {
      additionalValuesArray.append(additionalValue)
    }

    switch kind {
    case .generic, .stringLiteral:
      result = capturingRuntimeValue(firstValue)
    case let .binaryOperation(lhsExpr, op, rhsExpr):
      result.kind = .binaryOperation(
        lhs: lhsExpr.capturingRuntimeValues(firstValue),
        operator: op,
        rhs: rhsExpr.capturingRuntimeValues(additionalValuesArray.first ?? nil)
      )
    case let .functionCall(value, functionName, arguments):
      result.kind = .functionCall(
        value: value?.capturingRuntimeValues(firstValue),
        functionName: functionName,
        arguments: zip(arguments, additionalValuesArray).map { argument, value in
          .init(label: argument.label, value: argument.value.capturingRuntimeValues(value))
        }
      )
    case let .propertyAccess(value, keyPath):
      result.kind = .propertyAccess(
        value: value.capturingRuntimeValues(firstValue),
        keyPath: keyPath
      )
    case let .negation(expression, isParenthetical):
      result.kind = .negation(
        expression.capturingRuntimeValues(firstValue, repeat each additionalValues),
        isParenthetical: isParenthetical
      )
    }

    return result
  }

  /// Get an expanded description of this instance that contains the source
  /// code and runtime value (or values) it represents.
  ///
  /// - Returns: A string describing this instance.
  @_spi(ForToolsIntegrationOnly)
  public func expandedDescription() -> String {
    _expandedDescription(in: _ExpandedDescriptionContext())
  }

  /// Get an expanded description of this instance that contains the source
  /// code and runtime value (or values) it represents.
  ///
  /// - Returns: A string describing this instance.
  ///
  /// This function produces a more detailed description than
  /// ``expandedDescription()``, similar to how `String(reflecting:)` produces
  /// a more detailed description than `String(describing:)`.
  func expandedDebugDescription() -> String {
    var context = _ExpandedDescriptionContext()
    context.includeTypeNames = true
    context.includeParenthesesIfNeeded = false
    return _expandedDescription(in: context)
  }

  /// A structure describing the state tracked while calling
  /// `_expandedDescription(in:)`.
  private struct _ExpandedDescriptionContext {
    /// The depth of recursion at which the function is being called.
    var depth = 0

    /// Whether or not to include type names in output.
    var includeTypeNames = false

    /// Whether or not to enclose the resulting string in parentheses (as needed
    /// depending on what information the resulting string contains.)
    var includeParenthesesIfNeeded = true
  }

  /// Get an expanded description of this instance that contains the source
  /// code and runtime value (or values) it represents.
  ///
  /// - Parameters:
  ///   - context: The context for this call.
  ///
  /// - Returns: A string describing this instance.
  ///
  /// This function provides the implementation of ``expandedDescription()`` and
  /// ``expandedDebugDescription()``.
  private func _expandedDescription(in context: _ExpandedDescriptionContext) -> String {
    // Create a (default) context value to pass to recursive calls for
    // subexpressions.
    var childContext = context
    do {
      // Bump the depth so that recursive calls track the next depth level.
      childContext.depth += 1

      // Subexpressions do not automatically disable parentheses if the parent
      // does; they must opt in.
      childContext.includeParenthesesIfNeeded = true
    }

    var result = ""
    switch kind {
    case let .generic(sourceCode), let .stringLiteral(sourceCode, _):
      result = if context.includeTypeNames, let qualifiedName = runtimeValue?.typeInfo.fullyQualifiedName {
        "\(sourceCode): \(qualifiedName)"
      } else {
        sourceCode
      }
    case let .binaryOperation(lhsExpr, op, rhsExpr):
      result = "\(lhsExpr._expandedDescription(in: childContext)) \(op) \(rhsExpr._expandedDescription(in: childContext))"
    case let .functionCall(value, functionName, arguments):
      var argumentContext = childContext
      argumentContext.includeParenthesesIfNeeded = (arguments.count > 1)
      let argumentList = arguments.lazy
        .map { argument in
          (argument.label, argument.value._expandedDescription(in: argumentContext))
        }.map { label, value in
          if let label {
            return "\(label): \(value)"
          }
          return value
        }.joined(separator: ", ")
      result = if let value {
        "\(value._expandedDescription(in: childContext)).\(functionName)(\(argumentList))"
      } else {
        "\(functionName)(\(argumentList))"
      }
    case let .propertyAccess(value, keyPath):
      result = "\(value._expandedDescription(in: childContext)).\(keyPath)"
    case let .negation(expression, isParenthetical):
      childContext.includeParenthesesIfNeeded = !isParenthetical
      var expandedDescription = expression._expandedDescription(in: childContext)
      if isParenthetical {
        expandedDescription = "(\(expandedDescription))"
      }
      result = "!\(expandedDescription)"
    }

    // If this expression is at the root of the expression graph...
    if context.depth == 0 {
      if runtimeValue == nil {
        // ... and has no value, don't bother reporting the placeholder string
        // for it...
        return result
      } else if let runtimeValue, runtimeValue.typeInfo.describes(Bool.self) {
        // ... or if it is a boolean value, also don't bother (because it can be
        // inferred from context.)
        return result
      }
    }

    let runtimeValueDescription = runtimeValue.map(String.init(describing:)) ?? "<not evaluated>"
    result = if runtimeValueDescription == "(Function)" {
      // Hack: don't print string representations of function calls.
      result
    } else if runtimeValueDescription == result {
      result
    } else if context.includeParenthesesIfNeeded && context.depth > 0 {
      "(\(result) → \(runtimeValueDescription))"
    } else {
      "\(result) → \(runtimeValueDescription)"
    }

    return result
  }

  /// The set of parsed and captured subexpressions contained in this instance.
  @_spi(ForToolsIntegrationOnly)
  public var subexpressions: [Self] {
    switch kind {
    case .generic, .stringLiteral:
      []
    case let .binaryOperation(lhs, _, rhs):
      [lhs, rhs]
    case let .functionCall(value, _, arguments):
      if let value {
        CollectionOfOne(value) + arguments.lazy.map(\.value)
      } else {
        arguments.lazy.map(\.value)
      }
    case let .propertyAccess(value, _):
      [value]
    case let .negation(expression, _):
      [expression]
    }
  }

  /// The string value associated with this instance if it represents a string
  /// literal.
  ///
  /// If this instance represents an expression other than a string literal, the
  /// value of this property is `nil`.
  @_spi(ForToolsIntegrationOnly)
  public var stringLiteralValue: String? {
    if case let .stringLiteral(_, stringValue) = kind {
      return stringValue
    }
    return nil
  }
}

// MARK: - Codable

extension __Expression: Codable {}
extension __Expression.Kind: Codable {}
extension __Expression.Kind.FunctionCallArgument: Codable {}
extension __Expression.Value: Codable {}

// MARK: - CustomStringConvertible, CustomDebugStringConvertible

extension __Expression: CustomStringConvertible, CustomDebugStringConvertible {
  /// Initialize an instance of this type containing the specified source code.
  ///
  /// - Parameters:
  ///   - sourceCode: The source code of the expression being described.
  ///
  /// To get the string value of an expression, pass it to
  /// `String.init(describing:)`.
  ///
  /// This initializer does not attempt to parse `sourceCode`.
  @_spi(ForToolsIntegrationOnly)
  public init(_ sourceCode: String) {
    self.init(kind: .generic(sourceCode))
  }

  public var description: String {
    sourceCode
  }

  public var debugDescription: String {
    String(reflecting: kind)
  }
}

extension __Expression.Value: CustomStringConvertible, CustomDebugStringConvertible {}

/// A type representing a Swift expression captured at compile-time from source
/// code.
///
/// Instances of this type are generally opaque to callers. They can be
/// converted to strings representing their source code (captured at compile
/// time) using `String.init(describing:)`.
///
/// If parsing is needed, use the swift-syntax package to convert an instance of
/// this type to an instance of `ExprSyntax` using a Swift expression such as:
///
/// ```swift
/// let swiftSyntaxExpr: ExprSyntax = "\(testExpr)"
/// ```
@_spi(ForToolsIntegrationOnly)
public typealias Expression = __Expression
