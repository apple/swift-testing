//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

/// A protocol describing types with a custom string representation when
/// presented as part of a test's output.
///
/// Values whose types conform to this protocol use it to describe themselves
/// when they are present as part of the output of a test. For example, this
/// protocol affects the display of values that are passed as arguments to test
/// functions or that are elements of an expectation failure.
///
/// By default, the testing library converts values to strings using
/// `String(describing:)`. The resulting string may be inappropriate for some
/// types and their values. If the type of the value is made to conform to
/// ``CustomTestStringConvertible``, then the value of its ``testDescription``
/// property will be used instead.
///
/// For example, consider the following type:
///
/// ```swift
/// enum Food: CaseIterable {
///   case paella, oden, ragu
/// }
/// ```
///
/// If an array of cases from this enumeration is passed to a parameterized test
/// function:
///
/// ```swift
/// @Test(arguments: Food.allCases)
/// func isDelicious(_ food: Food) { ... }
/// ```
///
/// Then the values in the array need to be presented in the test output, but
/// the default description of a value may not be adequately descriptive:
///
/// ```
/// ◇ Passing argument food → .paella to isDelicious(_:)
/// ◇ Passing argument food → .oden to isDelicious(_:)
/// ◇ Passing argument food → .ragu to isDelicious(_:)
/// ```
///
/// By adopting ``CustomTestStringConvertible``, customized descriptions can be
/// included:
///
/// ```swift
/// extension Food: CustomTestStringConvertible {
///   var testDescription: String {
///     switch self {
///     case .paella:
///       "paella valenciana"
///     case .oden:
///       "おでん"
///     case .ragu:
///       "ragù alla bolognese"
///     }
///   }
/// }
/// ```
///
/// The presentation of these values will then reflect the value of the
/// ``testDescription`` property:
///
/// ```
/// ◇ Passing argument food → paella valenciana to isDelicious(_:)
/// ◇ Passing argument food → おでん to isDelicious(_:)
/// ◇ Passing argument food → ragù alla bolognese to isDelicious(_:)
/// ```
///
/// ## See Also
///
/// - ``Swift/String/init(describingForTest:)``
public protocol CustomTestStringConvertible {
  /// A description of this instance to use when presenting it in a test's
  /// output.
  ///
  /// Do not use this property directly. To get the test description of a value,
  /// use ``Swift/String/init(describingForTest:)``.
  var testDescription: String { get }

  /// A description of this instance to use when comparing it to another value
  /// after an expectation fails.
  ///
  /// The default implementation of this property uses `Mirror` to get a
  /// multi-line description of this instance. If the value of this property is
  /// `nil`, the testing library uses the value of the ``testDescription``
  /// property instead.
  ///
  /// This protocol requirement is not (yet) part of the public interface of the
  /// testing library.
  var _testDescriptionForComparison: String? { get }
}

// MARK: -

extension String {
  /// Initialize this instance so that it can be presented in a test's output.
  ///
  /// - Parameters:
  ///   - value: The value to describe.
  ///
  /// ## See Also
  ///
  /// - ``CustomTestStringConvertible``
  public init(describingForTest value: some Any) {
    // The mangled type name SPI doesn't handle generic types very well, so we
    // ask for the dynamic type of `value` (type(of:)) instead of just T.self.
    lazy var valueType = type(of: value as Any)
    if let value = value as? any CustomTestStringConvertible {
      self = value.testDescription
    } else if let value = value as? any CustomStringConvertible {
      self.init(describing: value)
    } else if let value = value as? any TextOutputStreamable {
      self.init(describing: value)
    } else if let value = value as? any CustomDebugStringConvertible {
      self.init(reflecting: value)
    } else if #available(_mangledTypeNameAPI, *), let value = value as? any RawRepresentable, isImportedFromC(valueType) {
      // Present raw-representable C types, which we assume to be imported
      // enumerations, in a consistent fashion. The case names of C enumerations
      // are not statically visible, so instead present the enumeration type's
      // name along with the raw value of `value`.
      self = "\(valueType)(rawValue: \(String(describingForTest: value.rawValue)))"
    } else if #available(_mangledTypeNameAPI, *), isSwiftEnumeration(valueType) {
      // Add a leading period to enumeration cases to more closely match their
      // source representation. SEE: _adHocPrint_unlocked() in the stdlib.
      self = ".\(value)"
    } else {
      // Use the generic description of the value.
      self.init(describing: value)
    }
  }

  /// Initialize this instance so that it can be presented in a test's output as
  /// part of a comparison of different values.
  ///
  /// - Parameters:
  ///   - value: The value to describe.
  ///
  /// If `value` conforms to ``CustomTestStringConvertible`` and the value of
  /// its `_testDescriptionForComparison` property is `nil`, `nil` is returned.
  ///
  /// This initializer is not part of the public interface of the testing
  /// library.
  ///
  /// ## See Also
  ///
  /// - ``init(describingForTest:)``
  /// - ``CustomTestStringConvertible``
  init(describingForTestComparison value: some Any) {
    let description = if let value = value as? any CustomTestStringConvertible {
      value._testDescriptionForComparison ?? value.testDescription
    } else {
      _reflect(value) ?? String(describingForTest: value)
    }
    self = description
  }
}

// MARK: - Built-in implementations

extension CustomTestStringConvertible {
  public var _testDescriptionForComparison: String? {
    _reflect(self)
  }
}

extension Optional: CustomTestStringConvertible {
  public var testDescription: String {
    switch self {
    case let .some(unwrappedValue):
      String(describingForTest: unwrappedValue)
    case nil:
      "nil"
    }
  }
}

extension _OptionalNilComparisonType: CustomTestStringConvertible {
  public var testDescription: String {
    "nil"
  }
}

extension CustomTestStringConvertible where Self: StringProtocol {
  public var testDescription: String {
    "\"\(self)\""
  }

  public var _testDescriptionForComparison: String? {
    String(self)
  }
}

extension String: CustomTestStringConvertible {}
extension Substring: CustomTestStringConvertible {}

// MARK: -

/// Get a string reflecting a value, similar to how it might have been
/// initialized and suitable for display as part of a difference.
///
/// - Parameters:
///   - value: The value to reflect.
///
/// - Returns: A string reflecting `value`, or `nil` if its reflection is
///   trivial.
///
/// This function uses `Mirror`, so if the type of `value` conforms to
/// `CustomReflectable`, the resulting string will be derived from the value's
/// custom mirror.
private func _reflect<T>(_ value: T) -> String? {
  let mirror = Mirror(reflecting: value)
  let mirrorChildren = mirror.children
  if mirrorChildren.isEmpty {
    return nil
  }

  let children = mirrorChildren.lazy
    .map { child in
      // TODO: handle multi-line descriptions elegantly
      if let label = child.label {
        "  \(label): \(String(describingForTest: child.value))"
      } else {
        "  \(String(describingForTest: child.value))"
      }
    }.joined(separator: "\n")

  switch mirror.displayStyle {
  case .tuple:
    return """
      (
      \(children)
      )
      """
  case .collection, .set, .dictionary:
    return """
      [
      \(children)
      ]
      """
  default:
    let typeName = _typeName(T.self, qualified: true)
    return """
    \(typeName)(
    \(children)
    )
    """
  }
}
