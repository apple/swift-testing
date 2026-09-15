//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if !SWT_NO_CODABLE
/// A protocol for customizing how arguments passed to parameterized tests are
/// encoded, which is used to match against when running specific arguments.
///
/// The testing library checks whether a test argument conforms to this
/// protocol, or any of several other known protocols, when running selected
/// test cases. When a test argument conforms to this protocol, that conformance
/// takes highest priority, and the testing library will then call
/// ``encodeTestArgument(to:)`` on the argument. A type that conforms to this
/// protocol is not required to conform to either `Encodable` or `Decodable`.
///
/// See <doc:ParameterizedTesting> for a list of the other supported ways to
/// allow running selected test cases.
///
/// ## See Also
///
/// - <doc:ParameterizedTesting>
public protocol CustomTestArgumentEncodable: Sendable {
  /// Encode this test argument.
  ///
  /// - Parameters:
  ///   - encoder: The encoder to write data to.
  ///
  /// - Throws: Any error encountered during encoding.
  ///
  /// The encoded form of a test argument should be stable and unique to allow
  /// re-running specific test cases of a parameterized test function. For
  /// optimal performance, large values which are not necessary to uniquely
  /// identify the test argument later should be omitted. Encoded values do not
  /// need to be human-readable.
  ///
  /// For more information on how to implement this function, see the
  /// documentation for [`Encodable`](https://developer.apple.com/documentation/swift/encodable).
  func encodeTestArgument(to encoder: some Encoder) throws
}
#endif

#if !hasFeature(Embedded)
extension Test.Case.Argument.ID {
  /// Initialize an ID instance with the specified test argument value.
  ///
  /// - Parameters:
  ///   - value: The value of a test argument for which to get an ID.
  ///   - parameter: The parameter of the test function to which this argument
  ///     value was passed.
  ///
  /// - Returns: `nil` if a stable ID cannot be formed from the specified test
  ///   argument value.
  ///
  /// - Throws: Any error encountered while attempting to encode `value`.
  ///
  /// If a stable representation of `value` can be encoded successfully, the
  /// value of this instance's `bytes` property will be the the bytes of that
  /// encoded JSON representation and this instance may be considered stable. If
  /// no stable representation of `value` can be obtained, `nil` is returned. If
  /// a stable representation was obtained but failed to encode, the error
  /// resulting from the encoding attempt is thrown.
  ///
  /// This function is not part of the public interface of the testing library.
  ///
  /// ## See Also
  ///
  /// - ``CustomTestArgumentEncodable``
  init?(identifying value: some Sendable, parameter: Test.Parameter) throws {
#if !SWT_NO_CODABLE
    func customArgumentWrapper(for value: some CustomTestArgumentEncodable) -> some Encodable {
      CustomArgumentWrapper(rawValue: value)
    }

    let encodableValue: (any Encodable)? = if let customEncodable = value as? any CustomTestArgumentEncodable {
      customArgumentWrapper(for: customEncodable)
    } else if let rawRepresentable = value as? any RawRepresentable, let encodableRawValue = rawRepresentable.rawValue as? any Encodable {
      encodableRawValue
    } else if let encodable = value as? any Encodable {
      encodable
    } else if let identifiable = value as? any Identifiable, let encodableID = identifiable.id as? any Encodable {
      encodableID
    } else {
      nil
    }

    guard let encodableValue else {
      return nil
    }

    self.init(bytes: try Self._encode(encodableValue, parameter: parameter))
#else
    nil
#endif
  }
}

extension Test.Case.Argument.ID {
  /// Initialize an ID from the IDs of a test case's arguments.
  ///
  /// - Parameters:
  ///   - argumentIDs: The argument IDs to combine, in order.
  ///
  /// The argument IDs are concatenated and hashed to form a single ID. A stable
  /// argument's ID is itself a fixed-size hash, so the concatenation is
  /// unambiguous. A single argument's ID already identifies the case, so it is
  /// used directly rather than combined.
  init(combining argumentIDs: some Collection<Test.Case.Argument.ID>) {
    if let argumentID = argumentIDs.first, argumentIDs.count == 1 {
      self = argumentID
    } else {
      self.init(bytes: SHA256.hash(argumentIDs.flatMap { $0.bytes }))
    }
  }
}

#if !SWT_NO_CODABLE
extension Test.Case.Argument.ID {
  /// Encode the specified test argument value and store its encoded
  /// representation as an array of bytes suitable for storing in an instance of
  /// ``Test/Case/Argument/ID-swift.struct``.
  ///
  /// - Parameters:
  ///   - value: The value to encode.
  ///   - parameter: The parameter of the test function to which this argument
  ///     value was passed.
  ///
  /// - Returns: An array of bytes containing the encoded representation.
  ///
  /// - Throws: Any error encountered during encoding.
  private static func _encode(_ value: some Encodable, parameter: Test.Parameter) throws -> [UInt8] {
    /// The encoded representation of an argument is the SHA256 hash of its Codable JSON representation.
    try JSON.withEncoding(of: value, userInfo: [._testParameterUserInfoKey: parameter]) { buffer in
      SHA256.hash(buffer)
    }
  }
}

/// A encodable type which wraps a ``CustomTestArgumentEncodable`` value.
struct CustomArgumentWrapper<T>: RawRepresentable, Encodable where T: CustomTestArgumentEncodable {
  /// The value this instance wraps, which implements custom test argument
  /// encoding logic.
  var rawValue: T

  init?(rawValue: T) {
    self.rawValue = rawValue
  }

  func encode(to encoder: any Encoder) throws {
    try rawValue.encodeTestArgument(to: encoder)
  }
}

// MARK: - Additional coding user info

extension CodingUserInfoKey {
  /// A coding user info key whose value is a ``Test/Parameter``.
  fileprivate static var _testParameterUserInfoKey: Self {
    Self(rawValue: "org.swift.testing.coding-user-info-key.parameter")!
  }
}

extension Encoder {
  /// The test parameter which the test argument being encoded was passed to, if
  /// any.
  ///
  /// The value of this property is non-`nil` when this encoder is being used to
  /// encode an argument passed to a parameterized test function.
  @_spi(Experimental)
  public var testParameter: Test.Parameter? {
    userInfo[._testParameterUserInfoKey] as? Test.Parameter
  }
}
#endif
#endif
