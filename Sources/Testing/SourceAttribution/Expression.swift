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
/// - Warning: This type is used to implement the `#expect()` macro. Do not use
///   it directly. Tools can use the SPI ``Expression`` typealias if needed.
public struct __Expression: Sendable {
  /// An enumeration describing the various kinds of expression that can be
  /// captured.
  ///
  /// This type is not part of the public interface of the testing library.
  /// Although it only has one case, removing it causes Xcode&nbsp;16 to fail to
  /// decode events of kind `issueRecorded`.
  enum Kind: Sendable {
    /// The expression represents a single, complete syntax node.
    ///
    /// - Parameters:
    ///   - sourceCode: The source code of the represented expression.
    case generic(_ sourceCode: String)
  }

  /// The kind of syntax node represented by this instance.
  ///
  /// This property is not part of the public interface of the testing library.
  /// Use `String(describing:)` to access the source code represented by an
  /// instance of this type.
  var kind: Kind

#if !hasFeature(Embedded)
  init(
    _ sourceCode: String,
    isNegated: Bool = false,
    runtimeValue: Value? = nil,
    subexpressions: [Self] = []
  ) {
    self.kind = .generic(sourceCode)
    self.isNegated = isNegated
    self.runtimeValue = runtimeValue
    self._subexpressions = subexpressions
  }
#else
  init(
    _ sourceCode: String,
    isNegated: Bool = false,
    subexpressions: [Self] = []
  ) {
    self.kind = .generic(sourceCode)
    self.isNegated = isNegated
    self._subexpressions = subexpressions
  }
#endif

  /// Whether or not this instance represents a negated expression (`!foo`).
  var isNegated = false

  /// The source code of the original captured expression.
  @_spi(ForToolsIntegrationOnly)
  public var sourceCode: String {
    switch kind {
    case let .generic(sourceCode):
      return sourceCode
    }
  }

#if !hasFeature(Embedded)
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

    /// Whether or not the values of certain properties of this instance have
    /// been truncated for brevity.
    ///
    /// If the value of this property is `true`, this instance does not
    /// represent its original value completely because doing so would exceed
    /// the maximum allowed data collection settings of the ``Configuration`` in
    /// effect. When this occurs, the value ``children`` is not guaranteed to be
    /// accurate or complete.
    public var isTruncated: Bool = false

    /// Whether or not this value represents a collection of values.
    public var isCollection: Bool

    /// The children of this value, representing its substructure, if any.
    ///
    /// If the value this instance represents does not contain any substructural
    /// values but ``isCollection`` is `true`, the value of this property is an
    /// empty array. Otherwise, the value of this property is non-`nil` only if
    /// the value it represents contains substructural values.
    public var children: [Self]?

    /// Initialize an instance of this type describing the specified subject.
    ///
    /// - Parameters:
    ///   - subject: The subject this instance should describe.
    init(describing subject: Any) {
      description = String(describingForTest: subject)
      debugDescription = String(reflecting: subject)
      typeInfo = TypeInfo(describingTypeOf: subject)

      let mirror = Mirror(reflectingForTest: subject)
      isCollection = mirror.displayStyle?.isCollection ?? false
    }

    /// Initialize an instance of this type with a previously-generated
    /// description of some subject.
    ///
    /// - Parameters:
    ///   - description: A description of the subject.
    ///   - typeInfo: The type of the subject.
    ///
    /// This initializer is only used when decoding an instance of
    /// ``ABI/EncodedExpression``. Callers should prefer other initializers
    /// where possible.
    init(description: String, typeInfo: TypeInfo) {
      self.description = description
      self.debugDescription = description
      self.typeInfo = typeInfo
      self.isCollection = false
    }

    /// Initialize an instance of this type with the specified description.
    ///
    /// - Parameters:
    ///   - description: The value to use for this instance's `description`
    ///     property.
    ///
    /// Unlike ``init(describing:)``, this initializer does not use
    /// ``String/init(describingForTest:)`` to form a description.
    private init(_description description: String) {
      self.description = description
      self.debugDescription = description
      typeInfo = TypeInfo(describing: String.self)
      isCollection = false
    }

    /// Initialize an instance of this type describing the specified subject and
    /// its children (if any).
    ///
    /// - Parameters:
    ///   - subject: The subject this instance should reflect.
    init?(reflecting subject: Any) {
      let configuration = Configuration.current ?? .init()
      guard let options = configuration.valueReflectionOptions else {
        return nil
      }

      var seenObjects: [ObjectIdentifier: AnyObject] = [:]
      self.init(_reflecting: subject, label: nil, seenObjects: &seenObjects, depth: 0, options: options)
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
    ///   - depth: The depth of this recursive call.
    ///   - options: The configuration options to use when deciding how to
    ///     reflect `subject`.
    private init(
      _reflecting subject: Any,
      label: String?,
      seenObjects: inout [ObjectIdentifier: AnyObject],
      depth: Int,
      options: Configuration.ValueReflectionOptions
    ) {
      // Stop recursing if we've reached the maximum allowed depth for
      // reflection. Instead, return a node describing this value instead and
      // set `isTruncated` to `true`.
      if depth >= options.maximumChildDepth {
        self = Self(describing: subject)
        isTruncated = true
        return
      }

      self.init(describing: subject)
      self.label = label

      let mirror = Mirror(reflectingForTest: subject)

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
      var objectIdentifierToRemove: ObjectIdentifier?
      var shouldIncludeChildren = true
      if mirror.displayStyle == .class, type(of: subject) is AnyObject.Type {
        let object = subject as AnyObject
        let objectIdentifier = ObjectIdentifier(object)
        let oldValue = seenObjects.updateValue(object, forKey: objectIdentifier)
        if oldValue != nil {
          shouldIncludeChildren = false
        } else {
          objectIdentifierToRemove = objectIdentifier
        }
      }
      defer {
        if let objectIdentifierToRemove {
          // Remove the object from the set of previously-seen objects after
          // (potentially) recursing to reflect children. This is so that
          // repeated references to the same object are still included multiple
          // times; only _cyclic_ object references should be avoided.
          seenObjects[objectIdentifierToRemove] = nil
        }
      }

      if shouldIncludeChildren && (!mirror.children.isEmpty || isCollection) {
        var children: [Self] = []
        for (index, child) in mirror.children.enumerated() {
          if isCollection && index >= options.maximumCollectionCount {
            isTruncated = true
            let message = "(\(mirror.children.count - index) out of \(mirror.children.count) elements omitted for brevity)"
            children.append(Self(_description: message))
            break
          }

          children.append(Self(_reflecting: child.value, label: child.label, seenObjects: &seenObjects, depth: depth + 1, options: options))
        }
        self.children = children
      }
    }
  }

  /// A representation of the runtime value of this expression.
  ///
  /// If the runtime value of this expression has not been evaluated, the value
  /// of this property is `nil`.
  @_spi(ForToolsIntegrationOnly)
  public var runtimeValue: Value?

  /// Capture the runtime value corresponding to this instance.
  ///
  /// - Parameters:
  ///   - value: The captured runtime value.
  private mutating func _captureRuntimeValue(_ value: (some Any)?) {
    runtimeValue = value.flatMap(Value.init(reflecting:))
    if isNegated, let value = value as? Bool {
      subexpressions[0]._captureRuntimeValue(!value)
    }
  }

  /// Capture the runtime values corresponding to this instance and its
  /// subexpressions.
  ///
  /// - Parameters:
  ///   - firstValue: The first captured runtime value.
  ///   - additionalValues: Any additional captured runtime values after the
  ///     first.
  private mutating func _captureRuntimeValues<each T>(_ firstValue: (some Any)?, _ additionalValues: repeat (each T)?) {
    if isNegated {
      // A negated expression has an additional level of indirection between it
      // and any additional values.
      subexpressions[0]._captureRuntimeValues(nil as Any? /* discarded */, repeat each additionalValues)
    } else {
      var i = subexpressions.startIndex
      let endIndex = subexpressions.endIndex
      for value in repeat each additionalValues {
        guard i < endIndex else {
          break
        }
        defer { i = subexpressions.index(after: i) }
        subexpressions[i]._captureRuntimeValue(value)
      }
    }
    _captureRuntimeValue(firstValue)
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
    result._captureRuntimeValues(firstValue, repeat each additionalValues)
    return result
  }
#endif

  /// Get an expanded description of this instance that contains the source
  /// code and runtime value (or values) it represents.
  ///
  /// - Returns: A string describing this instance.
  @_spi(ForToolsIntegrationOnly)
  public func expandedDescription() -> String {
    expandedDescription(verbose: false)
  }

  /// Get an expanded description of this instance that contains the source
  /// code and runtime value (or values) it represents.
  ///
  /// - Parameters:
  ///   - verbose: Whether or not to include more verbose output.
  ///
  /// - Returns: A string describing this instance.
  ///
  /// This function provides the implementation of ``expandedDescription()``
  /// with additional options used by ``Event/HumanReadableOutputRecorder``.
  func expandedDescription(verbose: Bool) -> String {
    var result = sourceCode

#if !hasFeature(Embedded)
    if verbose, let qualifiedName = runtimeValue?.typeInfo.fullyQualifiedName {
      result = "\(result): \(qualifiedName)"
    }

    if let runtimeValue {
      let runtimeValueDescription = String(describingForTest: runtimeValue)
      // Hack: don't print string representations of function calls.
      if runtimeValueDescription != "(Function)" && runtimeValueDescription != result {
        result = "\(result) → \(runtimeValueDescription)"
      }
    } else {
      result = "\(result) → <not evaluated>"
    }
#endif

    return result
  }

  /// Storage for ``subexpressions``.
  private var _subexpressions = [Self]()

  /// The set of parsed and captured subexpressions contained in this instance.
  @_spi(ForToolsIntegrationOnly)
  public internal(set) var subexpressions: [Self] {
    get {
      if !_subexpressions.isEmpty {
        return _subexpressions
      }

#if !hasFeature(Embedded)
      // If there were no explicitly-added subexpressions, look for any
      // subexpressions captured via reflection instead.
      if let children = runtimeValue?.children {
        return children.compactMap { child in
          guard let label = child.label else {
            return nil
          }
          return __Expression(label, runtimeValue: child)
        }
      }
#endif

      return []
    }
    set {
      _subexpressions = newValue
    }
  }

  /// A description of the difference between the operands in this expression,
  /// if that difference could be determined.
  ///
  /// The value of this property is set for the binary operators `==` and `!=`
  /// when used to compare collections.
  ///
  /// If the containing expectation passed, the value of this property is `nil`
  /// because the difference is only computed when necessary to assist with
  /// diagnosing test failures.
  @_spi(Experimental) @_spi(ForToolsIntegrationOnly)
  public internal(set) var differenceDescription: String?

  @_spi(ForToolsIntegrationOnly)
  @available(*, deprecated, message: "The value of this property is always nil.")
  public var stringLiteralValue: String? {
    nil
  }
}

#if !SWT_NO_CODABLE
// MARK: - Codable

extension __Expression: Codable {}
extension __Expression.Kind: Codable {}
extension __Expression.Value: Codable {}
#endif

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
    self.init(sourceCode, isNegated: false)
  }

  public var description: String {
    sourceCode
  }

  public var debugDescription: String {
    sourceCode
  }
}

#if !hasFeature(Embedded)
extension __Expression.Value: CustomStringConvertible, CustomDebugStringConvertible {}
#endif

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

#if !hasFeature(Embedded)
extension Mirror.DisplayStyle {
  /// Whether or not this display style represents a collection of values.
  fileprivate var isCollection: Bool {
    switch self {
    case .collection,
         .dictionary,
         .set:
      true
    default:
      false
    }
  }
}
#endif
