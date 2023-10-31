//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

/// A type that describes the difference between two values as a sequence of
/// insertions, deletions, or unmodified elements.
/// 
/// To ensure that ``Difference`` can always conform to `Sendable`, the elements
/// in an instance of this type are stored as strings rather than as their
/// original types. They are converted to strings using
/// ``Swift/String/init(describingForTest:)``. Types can implement
/// ``CustomTestStringConvertible`` to customize how they appear in the
/// description of an instance of this type.
@_spi(ExperimentalEventHandling)
public struct Difference: Sendable {
  /// A type representing an element of a collection that may have been changed
  /// after diffing was applied.
  ///
  /// This type roughly approximates `CollectionDifference.Change`, however it
  /// is used to track _all_ elements in the collection, not just those that
  /// have changed, allowing for insertion of "marker" elements where removals
  /// occurred.
  enum Element: Sendable {
    /// The element did not change during diffing.
    case unchanged(String)

    /// The element was inserted.
    case inserted(String)

    /// The element was removed.
    case removed(String)

    /// The element replaced a previous value.
    ///
    /// - Parameters:
    ///   - oldValue: The old value at this position.
    ///   - with: The new value at this position.
    case replaced(_ oldValue: String, with: String)
  }

  /// The changed elements from the comparison.
  var elements = [Element]()

  /// Initialize an instance of this type by comparing two collections.
  ///
  /// - Parameters:
  ///   - lhs: The "old" state of the collection to compare.
  ///   - rhs: The "new" state of the collection to compare.
  init?<T, U>(from lhs: T, to rhs: U) {
    let lhsDump = String(describingForTestComparison: lhs)
      .split(whereSeparator: \.isNewline)
      .map(String.init)
    let rhsDump = String(describingForTestComparison: rhs)
      .split(whereSeparator: \.isNewline)
      .map(String.init)

    guard lhsDump.count > 1 || rhsDump.count > 1 else {
      return nil
    }

    // Compute the difference between the two elements. Sort the resulting set
    // of changes by their offsets, and ensure that insertions come before
    // removals located at the same offset. This helps to ensure that the offset
    // values do not drift as we walk the changeset.
    let difference = rhsDump.difference(from: lhsDump)

    // Walk the initial string and slowly transform it into the final string.
    // Add an additional "scratch" string that is used to store a removal marker
    // if the last character is removed.
    var result = lhsDump.map { [Element.unchanged($0)] } + CollectionOfOne([])
    for change in difference.removals.reversed() {
      // Remove the character at the specified index, then re-insert it into the
      // slot at the next index (with the marker character applied.) The next
      // index will then contain whatever character it already contained after
      // the character representing this removal.
      result.remove(at: change.offset)
      result[change.offset].insert(.removed(change.element), at: 0)
    }
    for change in difference.insertions {
      // Insertions can occur verbatim by inserting a new substring at the
      // specified offset.
      result.insert([.inserted(change.element)], at: change.offset)
    }

    // Flatten the arrays of arrays of elements into a single array, then merge
    // pairs of removals/insertions (i.e. where an element was replaced with
    // another element) because it's easier to do after the array of arrays has
    // been flatted.
    elements = result.lazy
      .flatMap { $0 }
      .reduce(into: []) { result, element in
        if case let .removed(removedValue) = element, let previous = result.last, case let .inserted(insertedValue) = previous {
          result[result.index(before: result.endIndex)] = .replaced(removedValue, with: insertedValue)
        } else {
          result.append(element)
        }
      }
  }
}

// MARK: - Equatable

extension Difference.Element: Equatable {}

// MARK: - Codable

extension Difference: Codable {}
extension Difference.Element: Codable {}

// MARK: - CustomStringConvertible

extension Difference: CustomStringConvertible {
  public var description: String {
    // Show individual lines of the text with leading + or - characters to
    // indicate insertions and removals respectively.
    // FIXME: better descriptive output for one-line strings.
    let diffCount = elements.lazy
      .filter { element in
        if case .unchanged = element {
          return false
        }
        return true
      }.count.counting("change")

    return "\(diffCount):\n" + elements.lazy
      .flatMap { element in
        switch element {
        case let .unchanged(value):
          ["  \(value)"]
        case let .inserted(value):
          ["+ \(value)"]
        case let .removed(value):
          ["- \(value)"]
        case let .replaced(oldValue, with: newValue):
          [
            "- \(oldValue)",
            "+ \(newValue)"
          ]
        }
      }.joined(separator: "\n")
  }
}
