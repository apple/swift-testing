//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023–2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

private import _TestingInternals

@_spi(ForToolsIntegrationOnly)
#if SWT_NO_EXIT_TESTS
@available(*, unavailable, message: "Exit tests are not available on this platform.")
#endif
extension ExitTest {
  /// A type representing a value captured by an exit test's body.
  ///
  /// An instance of this type may represent the actual value that was captured
  /// when the exit test was invoked. In the child process created by the
  /// current exit test handler, instances will initially only have the type of
  /// the value, but not the value itself.
  ///
  /// Instances of this type are created automatically by the testing library
  /// for all elements in an exit test body's capture list and are stored in the
  /// exit test's ``capturedValues`` property. For example, given the following
  /// exit test:
  ///
  /// ```swift
  /// await #expect(processExitsWith: .failure) { [a = a as T, b = b as U, c = c as V] in
  ///   ...
  /// }
  /// ```
  ///
  /// There are three captured values in its ``capturedValues`` property. These
  /// values are captured at the time the exit test is called, as they would be
  /// if the closure were called locally.
  ///
  /// The current exit test handler is responsible for encoding and decoding
  /// instances of this type. When the handler is called, it is passed an
  /// instance of ``ExitTest``. The handler encodes the values in that
  /// instance's ``capturedValues`` property, then passes the encoded forms of
  /// those values to the child process. The encoding format and message-passing
  /// interface are implementation details of the exit test handler.
  ///
  /// When the child process calls ``ExitTest/find(identifiedBy:)``, it receives
  /// an instance of ``ExitTest`` whose ``capturedValues`` property contains
  /// type information but no values. The child process decodes the values it
  /// encoded in the parent process and then updates the ``wrappedValue``
  /// property of each element in the array before calling the exit test's body.
  public struct CapturedValue: Sendable {
#if !SWT_NO_EXIT_TESTS
    /// An enumeration of the different states a captured value can have.
    private enum _Kind: Sendable {
      /// The runtime value of the captured value is known.
      case wrappedValue(any Codable & Sendable)

      /// Only the type of the captured value is known.
      case typeOnly(any (Codable & Sendable).Type)
    }

    /// The current state of this instance.
    private var _kind: _Kind

    init(wrappedValue: some Codable & Sendable) {
      _kind = .wrappedValue(wrappedValue)
    }

    init(typeOnly type: (some Codable & Sendable).Type) {
      _kind = .typeOnly(type)
    }
#endif

    /// The underlying value captured by this instance at runtime.
    ///
    /// In a child process created by the current exit test handler, the value
    /// of this property is `nil` until the entry point sets it.
    public var wrappedValue: (any Codable & Sendable)? {
      get {
#if !SWT_NO_EXIT_TESTS
        if case let .wrappedValue(wrappedValue) = _kind {
          return wrappedValue
        }
        return nil
#else
        swt_unreachable()
#endif
      }

      set {
#if !SWT_NO_EXIT_TESTS
        let type = typeOfWrappedValue

        func validate<T, U>(_ newValue: T, is expectedType: U.Type) {
          assert(newValue is U, "Attempted to set a captured value to an instance of '\(String(describingForTest: T.self))', but an instance of '\(String(describingForTest: U.self))' was expected.")
        }
        validate(newValue, is: type)

        if let newValue {
          _kind = .wrappedValue(newValue)
        } else {
          _kind = .typeOnly(type)
        }
#else
        swt_unreachable()
#endif
      }
    }

    /// The type of the underlying value captured by this instance.
    ///
    /// This type is known at compile time and is always available, even before
    /// this instance's ``wrappedValue`` property is set.
    public var typeOfWrappedValue: any (Codable & Sendable).Type {
#if !SWT_NO_EXIT_TESTS
      switch _kind {
      case let .wrappedValue(wrappedValue):
        type(of: wrappedValue)
      case let .typeOnly(type):
        type
      }
#else
      swt_unreachable()
#endif
    }
  }
}

#if !SWT_NO_EXIT_TESTS
// MARK: - Collection conveniences

extension Array where Element == ExitTest.CapturedValue {
  init<each T>(_ wrappedValues: repeat each T) where repeat each T: Codable & Sendable {
    self.init()
    repeat self.append(ExitTest.CapturedValue(wrappedValue: each wrappedValues))
  }

  init<each T>(_ typesOfWrappedValues: repeat (each T).Type) where repeat each T: Codable & Sendable {
    self.init()
    repeat self.append(ExitTest.CapturedValue(typeOnly: (each typesOfWrappedValues).self))
  }
}

extension Collection where Element == ExitTest.CapturedValue {
  /// Cast the elements in this collection to a tuple of their wrapped values.
  ///
  /// - Returns: A tuple containing the wrapped values of the elements in this
  ///   collection.
  ///
  /// - Throws: If an expected value could not be found or was not of the
  ///   type the caller expected.
  ///
  /// This function assumes that the entry point function has already set the
  /// ``wrappedValue`` property of each element in this collection.
  func takeCapturedValues<each T>() throws -> (repeat each T) {
    func nextValue<U>(
      as type: U.Type,
      from capturedValues: inout SubSequence
    ) throws -> U {
      // Get the next captured value in the collection. If we run out of values
      // before running out of parameter pack elements, then something in the
      // exit test handler or entry point is likely broken.
      guard let wrappedValue = capturedValues.first?.wrappedValue else {
        let actualCount = self.count
        let expectedCount = parameterPackCount(repeat (each T).self)
        fatalError("Found fewer captured values (\(actualCount)) than expected (\(expectedCount)) when passing them to the current exit test.")
      }

      // Next loop, get the next element. (We're mutating a subsequence, not
      // self, so this is generally an O(1) operation.)
      capturedValues = capturedValues.dropFirst()

      // Make sure the value is of the correct type. If it's not, that's also
      // probably a problem with the exit test handler or entry point.
      guard let wrappedValue = wrappedValue as? U else {
        fatalError("Expected captured value at index \(capturedValues.startIndex) with type '\(String(describingForTest: U.self))', but found an instance of '\(String(describingForTest: Swift.type(of: wrappedValue)))' instead.")
      }
      
      return wrappedValue
    }

    var capturedValues = self[...]
    return (repeat try nextValue(as: (each T).self, from: &capturedValues))
  }
}
#endif

