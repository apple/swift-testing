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
}

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
    lazy var valueTypeInfo = TypeInfo(describingTypeOf: value)
    if let value = value as? any CustomTestStringConvertible {
      self = value.testDescription
    } else if let value = value as? any CustomStringConvertible {
      self.init(describing: value)
    } else if let value = value as? any TextOutputStreamable {
      self.init(describing: value)
    } else if let value = value as? any CustomDebugStringConvertible {
      self.init(reflecting: value)
    } else if let value = value as? any Any.Type {
      self = _testDescription(of: value)
    } else if let value = value as? any RawRepresentable, let type = valueTypeInfo.type, valueTypeInfo.isImportedFromC {
      // Present raw-representable C types, which we assume to be imported
      // enumerations, in a consistent fashion. The case names of C enumerations
      // are not statically visible, so instead present the enumeration type's
      // name along with the raw value of `value`.
      let typeName = String(describingForTest: type)
      self = "\(typeName)(rawValue: \(String(describingForTest: value.rawValue)))"
    } else if valueTypeInfo.isSwiftEnumeration {
      // Add a leading period to enumeration cases to more closely match their
      // source representation. SEE: _adHocPrint_unlocked() in the stdlib.
      self = ".\(value)"
    } else {
      // Use the generic description of the value.
      self.init(describing: value)
    }
  }
}

// MARK: - Built-in implementations

/// The _de facto_ implementation of ``CustomTestStringConvertible`` for a
/// metatype value.
///
/// - Parameters:
///   - type: The type to describe.
///
/// - Returns: The description of `type`, as produced by
///   ``Swift/String/init(describingForTest:)``.
private func _testDescription(of type: any Any.Type) -> String {
  TypeInfo(describing: type).unqualifiedName
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

// MARK: - Strings

extension CustomTestStringConvertible where Self: StringProtocol {
  public var testDescription: String {
    "\"\(self)\""
  }
}

extension String: CustomTestStringConvertible {}
extension Substring: CustomTestStringConvertible {}

// MARK: - Ranges

extension ClosedRange: CustomTestStringConvertible {
  public var testDescription: String {
    "\(String(describingForTest: lowerBound)) ... \(String(describingForTest: upperBound))"
  }
}

extension PartialRangeFrom: CustomTestStringConvertible {
  public var testDescription: String {
    "\(String(describingForTest: lowerBound))..."
  }
}

extension PartialRangeThrough: CustomTestStringConvertible {
  public var testDescription: String {
    "...\(String(describingForTest: upperBound))"
  }
}

extension PartialRangeUpTo: CustomTestStringConvertible {
  public var testDescription: String {
    "..<\(String(describingForTest: upperBound))"
  }
}

extension Range: CustomTestStringConvertible {
  public var testDescription: String {
    "\(String(describingForTest: lowerBound)) ..< \(String(describingForTest: upperBound))"
  }
}
