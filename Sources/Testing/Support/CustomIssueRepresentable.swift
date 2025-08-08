//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024–2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

/// A protocol that provides instances of conforming types with the ability to
/// record themselves as test issues.
///
/// When a type conforms to this protocol, values of that type can be passed to
/// ``Issue/record(_:severity:sourceLocation:)``. The testing library then calls the
/// ``customize(_:)`` function and passes it an instance of ``Issue`` that will
/// be used to represent the value. The function can then reconfigure or replace
/// the issue as needed.
///
/// This protocol may become part of the testing library's public interface in
/// the future. There's not really anything _requiring_ it to conform to `Error`
/// but all our current use cases are error types. If we want to allow other
/// types to be represented as issues, we will need to add an overload of
/// `Issue.record()` that takes `some CustomIssueRepresentable`.
protocol CustomIssueRepresentable: Error {
  /// Customize the issue that will represent this value.
  ///
  /// - Parameters:
  ///   - issue: The issue to customize. The function consumes this value.
  ///
  /// - Returns: A customized copy of `issue`.
  func customize(_ issue: consuming Issue) -> Issue
}

// MARK: - Internal error types

/// A type representing an error in the testing library or its underlying
/// infrastructure.
///
/// When an error of this type is thrown and caught by the testing library, it
/// is recorded as an issue of kind ``Issue/Kind/system`` rather than
/// ``Issue/Kind/errorCaught(_:)``.
///
/// This type is not part of the public interface of the testing library.
/// External callers should generally record issues by throwing their own errors
/// or by calling ``Issue/record(_:severity:sourceLocation:)``.
struct SystemError: Error, CustomStringConvertible, CustomIssueRepresentable {
  var description: String

  func customize(_ issue: consuming Issue) -> Issue {
    issue.kind = .system
    issue.comments.append("\(self)")
    return issue
  }
}

/// A type representing misuse of testing library API.
///
/// When an error of this type is thrown and caught by the testing library, it
/// is recorded as an issue of kind ``Issue/Kind/apiMisused`` rather than
/// ``Issue/Kind/errorCaught(_:)``.
///
/// This type is not part of the public interface of the testing library.
/// External callers should generally record issues by throwing their own errors
/// or by calling ``Issue/record(_:severity:sourceLocation:)``.
struct APIMisuseError: Error, CustomStringConvertible, CustomIssueRepresentable {
  var description: String

  func customize(_ issue: consuming Issue) -> Issue {
    issue.kind = .apiMisused
    issue.comments.append("\(self)")
    return issue
  }
}

extension ExpectationFailedError: CustomIssueRepresentable {
  func customize(_ issue: consuming Issue) -> Issue {
    // Instances of this error type are thrown by `#require()` after an issue of
    // kind `.expectationFailed` has already been recorded. Code that rethrows
    // this error does not generate a new issue, but code that passes this error
    // to Issue.record() is misbehaving.
    issue.kind = .apiMisused
    issue.comments.append("Recorded an error of type \(Self.self) representing an expectation that failed and was already recorded: \(expectation)")
    return issue
  }
}
