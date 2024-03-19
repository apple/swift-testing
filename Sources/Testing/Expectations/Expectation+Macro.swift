//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

// MARK: Boolean expression checking

/// Check that an expectation has passed after a condition has been evaluated.
///
/// - Parameters:
///   - condition: The condition to be evaluated.
///   - comment: A comment describing the expectation.
///   - sourceLocation: The source location to which recorded expectations and
///     issues should be attributed.
///
/// If `condition` evaluates to `false`, an ``Issue`` is recorded for the test
/// that is running in the current task.
@freestanding(expression) public macro expect(
  _ condition: Bool,
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = #currentSourceLocation
) = #externalMacro(module: "TestingMacros", type: "ExpectMacro")

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// - Parameters:
///   - condition: The condition to be evaluated.
///   - comment: A comment describing the expectation.
///   - sourceLocation: The source location to which recorded expectations and
///     issues should be attributed.
///
/// - Throws: An instance of ``ExpectationFailedError`` if `condition` evaluates
///   to `false`.
///
/// If `condition` evaluates to `false`, an ``Issue`` is recorded for the test
/// that is running in the current task and an instance of
/// ``ExpectationFailedError`` is thrown.
@freestanding(expression) public macro require(
  _ condition: Bool,
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = #currentSourceLocation
) = #externalMacro(module: "TestingMacros", type: "RequireMacro")

// MARK: - Optional checking

/// Unwrap an optional value or, if it is `nil`, fail and throw an error.
///
/// - Parameters:
///   - optionalValue: The optional value to be unwrapped.
///   - comment: A comment describing the expectation.
///   - sourceLocation: The source location to which recorded expectations and
///     issues should be attributed.
///
/// - Returns: The unwrapped value of `optionalValue`.
///
/// - Throws: An instance of ``ExpectationFailedError`` if `optionalValue` is
///   `nil`.
///
/// If `optionalValue` is `nil`, an ``Issue`` is recorded for the test that is
/// running in the current task and an instance of ``ExpectationFailedError`` is
/// thrown.
@freestanding(expression) public macro require<T>(
  _ optionalValue: T?,
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = #currentSourceLocation
) -> T = #externalMacro(module: "TestingMacros", type: "RequireMacro")

/// Unwrap an optional boolean value or, if it is `nil`, fail and throw an
/// error.
///
/// - Parameters:
///   - optionalValue: The optional value to be unwrapped.
///   - comment: A comment describing the expectation.
///   - sourceLocation: The source location to which recorded expectations and
///     issues should be attributed.
///
/// - Returns: The unwrapped value of `optionalValue`.
///
/// - Throws: An instance of ``ExpectationFailedError`` if `optionalValue` is
///   `nil`.
///
/// If `optionalValue` is `nil`, an ``Issue`` is recorded for the test that is
/// running in the current task and an instance of ``ExpectationFailedError`` is
/// thrown.
///
/// This overload of ``require(_:_:sourceLocation:)-6w9oo`` checks if
/// `optionalValue` may be ambiguous (i.e. it is unclear if the developer
/// intended to check for a boolean value or unwrap an optional boolean value)
/// and provides additional compile-time diagnostics when it is.
@_documentation(visibility: private)
@freestanding(expression) public macro require(
  _ optionalValue: Bool?,
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = #currentSourceLocation
) -> Bool = #externalMacro(module: "TestingMacros", type: "AmbiguousRequireMacro")

// MARK: - Matching errors by type

/// Check that an expression always throws an error of a given type.
///
/// - Parameters:
///   - errorType: The type of error that is expected to be thrown. If
///     `expression` could throw _any_ error, or the specific type of thrown
///     error is unimportant, pass `(any Error).self`.
///   - comment: A comment describing the expectation.
///   - sourceLocation: The source location to which recorded expectations and
///     issues should be attributed.
///   - expression: The expression to be evaluated.
///
/// Use this overload of `#expect()` when the expression `expression` _should_
/// throw an error of a given type:
///
/// ```swift
/// #expect(throws: EngineFailureError.self) {
///   FoodTruck.shared.engine.batteryLevel = 0
///   try FoodTruck.shared.engine.start()
/// }
/// ```
///
/// If `expression` does not throw an error, or if it throws an error that is
/// not an instance of `errorType`, an ``Issue`` is recorded for the test that
/// is running in the current task. Any value returned by `expression` is
/// discarded.
///
/// If the thrown error need only equal another instance of [`Error`](https://developer.apple.com/documentation/swift/error),
/// use ``expect(throws:_:sourceLocation:performing:)-1xr34`` instead. If
/// `expression` should _never_ throw any error, use
/// ``expect(throws:_:sourceLocation:performing:)-5lzjz`` instead.
@freestanding(expression) public macro expect<E, R>(
  throws errorType: E.Type,
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = #currentSourceLocation,
  performing expression: () async throws -> R
) = #externalMacro(module: "TestingMacros", type: "ExpectMacro") where E: Error

/// Check that an expression never throws an error.
///
/// - Parameters:
///   - comment: A comment describing the expectation.
///   - sourceLocation: The source location to which recorded expectations and
///     issues should be attributed.
///   - expression: The expression to be evaluated.
///
/// Use this overload of `#expect()` when the expression `expression` should
/// _never_ throw any error:
///
/// ```swift
/// #expect(throws: Never.self) {
///   FoodTruck.shared.engine.batteryLevel = 100
///   try FoodTruck.shared.engine.start()
/// }
/// ```
///
/// If `expression` throws an error, an ``Issue`` is recorded for the test that
/// is running in the current task. Any value returned by `expression` is
/// discarded.
///
/// Test functions can be annotated with `throws` and can throw errors which are
/// then recorded as issues when the test runs. If the intent is for a test to
/// fail when an error is thrown by `expression`, rather than to explicitly
/// check that an error is _not_ thrown by it, do not use this macro. Instead,
/// simply call the code in question and allow it to throw an error naturally.
///
/// If the thrown error need only be an instance of a particular type, use
/// ``expect(throws:_:sourceLocation:performing:)-79piu`` instead. If the thrown
/// error need only equal another instance of [`Error`](https://developer.apple.com/documentation/swift/error),
/// use ``expect(throws:_:sourceLocation:performing:)-1xr34`` instead.
@freestanding(expression) public macro expect<R>(
  throws _: Never.Type,
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = #currentSourceLocation,
  performing expression: () async throws -> R
) = #externalMacro(module: "TestingMacros", type: "ExpectMacro")

/// Check that an expression always throws an error of a given type, and throw
/// an error if it does not.
///
/// - Parameters:
///   - errorType: The type of error that is expected to be thrown. If
///     `expression` could throw _any_ error, or the specific type of thrown
///     error is unimportant, pass `(any Error).self`.
///   - comment: A comment describing the expectation.
///   - sourceLocation: The source location to which recorded expectations and
///     issues should be attributed.
///   - expression: The expression to be evaluated.
///
/// - Throws: An instance of ``ExpectationFailedError`` if `expression` does not
///   throw a matching error. The error thrown by `expression` is not rethrown.
///
/// Use this overload of `#require()` when the expression `expression` _should_
/// throw an error of a given type:
///
/// ```swift
/// try #require(throws: EngineFailureError.self) {
///   FoodTruck.shared.engine.batteryLevel = 0
///   try FoodTruck.shared.engine.start()
/// }
/// ```
///
/// If `expression` does not throw an error, or if it throws an error that is
/// not an instance of `errorType`, an ``Issue`` is recorded for the test that
/// is running in the current task and an instance of ``ExpectationFailedError``
/// is thrown. Any value returned by `expression` is discarded.
///
/// If the thrown error need only equal another instance of [`Error`](https://developer.apple.com/documentation/swift/error),
/// use ``require(throws:_:sourceLocation:performing:)-7v83e`` instead.
///
/// If `expression` should _never_ throw, simply invoke the code without using
/// this macro. The test will then fail if an error is thrown.
@freestanding(expression) public macro require<E, R>(
  throws errorType: E.Type,
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = #currentSourceLocation,
  performing expression: () async throws -> R
) = #externalMacro(module: "TestingMacros", type: "RequireMacro") where E: Error

/// Check that an expression never throws an error, and throw an error if it
/// does.
///
/// - Parameters:
///   - comment: A comment describing the expectation.
///   - sourceLocation: The source location to which recorded expectations and
///     issues should be attributed.
///   - expression: The expression to be evaluated.
///
/// - Throws: An instance of ``ExpectationFailedError`` if `expression` throws
///   any error. The error thrown by `expression` is not rethrown.
@available(*, deprecated, message: "try #require(throws: Never.self) is redundant. Invoke non-throwing test code directly instead.")
@freestanding(expression) public macro require<R>(
  throws _: Never.Type,
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = #currentSourceLocation,
  performing expression: () async throws -> R
) = #externalMacro(module: "TestingMacros", type: "RequireMacro")

// MARK: - Matching instances of equatable errors

/// Check that an expression always throws a specific error.
///
/// - Parameters:
///   - error: The error that is expected to be thrown.
///   - comment: A comment describing the expectation.
///   - sourceLocation: The source location to which recorded expectations and
///     issues should be attributed.
///   - expression: The expression to be evaluated.
///
/// Use this overload of `#expect()` when the expression `expression` _should_
/// throw a specific error:
///
/// ```swift
/// #expect(throws: EngineFailureError.batteryDied) {
///   FoodTruck.shared.engine.batteryLevel = 0
///   try FoodTruck.shared.engine.start()
/// }
/// ```
///
/// If `expression` does not throw an error, or if it throws an error that is
/// not equal to `error`, an ``Issue`` is recorded for the test that is running
/// in the current task. Any value returned by `expression` is discarded.
///
/// If the thrown error need only be an instance of a particular type, use
/// ``expect(throws:_:sourceLocation:performing:)-79piu`` instead. If
/// `expression` should _never_ throw any error, use
/// ``expect(throws:_:sourceLocation:performing:)-5lzjz`` instead.
@freestanding(expression) public macro expect<E, R>(
  throws error: E,
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = #currentSourceLocation,
  performing expression: () async throws -> R
) = #externalMacro(module: "TestingMacros", type: "ExpectMacro") where E: Error & Equatable

/// Check that an expression always throws a specific error, and throw an error
/// if it does not.
///
/// - Parameters:
///   - error: The error that is expected to be thrown.
///   - comment: A comment describing the expectation.
///   - sourceLocation: The source location to which recorded expectations and
///     issues should be attributed.
///   - expression: The expression to be evaluated.
///
/// - Throws: An instance of ``ExpectationFailedError`` if `expression` does not
///   throw a matching error. The error thrown by `expression` is not rethrown.
///
/// Use this overload of `#require()` when the expression `expression` _should_
/// throw a specific error:
///
/// ```swift
/// try #require(throws: EngineFailureError.batteryDied) {
///   FoodTruck.shared.engine.batteryLevel = 0
///   try FoodTruck.shared.engine.start()
/// }
/// ```
///
/// If `expression` does not throw an error, or if it throws an error that is
/// not equal to `error`, an ``Issue`` is recorded for the test that is running
/// in the current task and an instance of ``ExpectationFailedError`` is thrown.
/// Any value returned by `expression` is discarded.
///
/// If the thrown error need only be an instance of a particular type, use
/// ``require(throws:_:sourceLocation:performing:)-76bjn`` instead.
@freestanding(expression) public macro require<E, R>(
  throws error: E,
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = #currentSourceLocation,
  performing expression: () async throws -> R
) = #externalMacro(module: "TestingMacros", type: "RequireMacro") where E: Error & Equatable

// MARK: - Arbitrary error matching

/// Check that an expression always throws an error matching some condition.
///
/// - Parameters:
///   - comment: A comment describing the expectation.
///   - sourceLocation: The source location to which recorded expectations and
///     issues should be attributed.
///   - expression: The expression to be evaluated.
///   - errorMatcher: A closure to invoke when `expression` throws an error that
///     indicates if it matched or not.
///
/// Use this overload of `#expect()` when the expression `expression` _should_
/// throw an error, but the logic to determine if the error matches is complex:
///
/// ```swift
/// #expect {
///   FoodTruck.shared.engine.batteryLevel = 0
///   try FoodTruck.shared.engine.start()
/// } throws: { error in
///   return error == EngineFailureError.batteryDied
///     || error == EngineFailureError.stillCharging
/// }
/// ```
///
/// If `expression` does not throw an error, if it throws an error that is
/// not matched by `errorMatcher`, or if `errorMatcher` throws an error
/// (including the error passed to it), an ``Issue`` is recorded for the test
/// that is running in the current task. Any value returned by `expression` is
/// discarded.
///
/// If the thrown error need only be an instance of a particular type, use
/// ``expect(throws:_:sourceLocation:performing:)-79piu`` instead. If the thrown
/// error need only equal another instance of [`Error`](https://developer.apple.com/documentation/swift/error),
/// use ``expect(throws:_:sourceLocation:performing:)-1xr34`` instead. If an
/// error should _never_ be thrown, use
/// ``expect(throws:_:sourceLocation:performing:)-5lzjz`` instead.
@freestanding(expression) public macro expect<R>(
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = #currentSourceLocation,
  performing expression: () async throws -> R,
  throws errorMatcher: (any Error) async throws -> Bool
) = #externalMacro(module: "TestingMacros", type: "ExpectMacro")

/// Check that an expression always throws an error matching some condition, and
/// throw an error if it does not.
///
/// - Parameters:
///   - comment: A comment describing the expectation.
///   - sourceLocation: The source location to which recorded expectations and
///     issues should be attributed.
///   - expression: The expression to be evaluated.
///   - errorMatcher: A closure to invoke when `expression` throws an error that
///     indicates if it matched or not.
///
/// - Throws: An instance of ``ExpectationFailedError`` if `expression` does not
///   throw a matching error. The error thrown by `expression` is not rethrown.
///
/// Use this overload of `#require()` when the expression `expression` _should_
/// throw an error, but the logic to determine if the error matches is complex:
///
/// ```swift
/// #expect {
///   FoodTruck.shared.engine.batteryLevel = 0
///   try FoodTruck.shared.engine.start()
/// } throws: { error in
///   return error == EngineFailureError.batteryDied
///     || error == EngineFailureError.stillCharging
/// }
/// ```
///
/// If `expression` does not throw an error, if it throws an error that is
/// not matched by `errorMatcher`, or if `errorMatcher` throws an error
/// (including the error passed to it), an ``Issue`` is recorded for the test
/// that is running in the current task and an instance of
/// ``ExpectationFailedError`` is thrown. Any value returned by `expression` is
/// discarded.
///
/// If the thrown error need only be an instance of a particular type, use
/// ``require(throws:_:sourceLocation:performing:)-76bjn`` instead. If the thrown error need
/// only equal another instance of [`Error`](https://developer.apple.com/documentation/swift/error),
/// use ``require(throws:_:sourceLocation:performing:)-7v83e`` instead.
///
/// If `expression` should _never_ throw, simply invoke the code without using
/// this macro. The test will then fail if an error is thrown.
@freestanding(expression) public macro require<R>(
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = #currentSourceLocation,
  performing expression: () async throws -> R,
  throws errorMatcher: (any Error) async throws -> Bool
) = #externalMacro(module: "TestingMacros", type: "RequireMacro")
