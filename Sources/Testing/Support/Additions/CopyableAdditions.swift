//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if !hasFeature(Embedded)
/// A helper protocol for ``boxCopyableValue(_:)``.
private protocol _CopyablePointer {
  /// Load the value at this address into an existential box.
  ///
  /// - Returns: The value at this address.
  func load() -> Any
}

extension UnsafePointer: _CopyablePointer where Pointee: Copyable {
  func load() -> Any {
    pointee
  }
}
#endif

/// Copy a value to an existential box if its type conforms to `Copyable`.
///
/// - Parameters:
///   - value: The value to copy.
///
/// - Returns: A copy of `value` in an existential box, or `nil` if the type of
///   `value` does not conform to `Copyable`.
///
/// When using Embedded Swift, this function always returns `nil`.
#if !hasFeature(Embedded)
@available(_castingWithNonCopyableGenerics, *)
func boxCopyableValue(_ value: borrowing some ~Copyable) -> Any? {
  withUnsafePointer(to: value) { address in
    return (address as? any _CopyablePointer)?.load()
  }
}
#else
func boxCopyableValue(_ value: borrowing some ~Copyable) -> Void? {
  nil
}
#endif
