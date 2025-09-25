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
  sourceLocation: SourceLocation = #_sourceLocation
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
  sourceLocation: SourceLocation = #_sourceLocation
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
  sourceLocation: SourceLocation = #_sourceLocation
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
@freestanding(expression)
@_documentation(visibility: private)
public macro require(
  _ optionalValue: Bool?,
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = #_sourceLocation
) -> Bool = #externalMacro(module: "TestingMacros", type: "AmbiguousRequireMacro")

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
///
/// This overload of ``require(_:_:sourceLocation:)-6w9oo`` is used when a
/// non-optional, non-`Bool` value is passed to `#require()`. It emits a warning
/// diagnostic indicating that the expectation is redundant.
@freestanding(expression)
@_documentation(visibility: private)
public macro require<T>(
  _ optionalValue: T,
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = #_sourceLocation
) -> T = #externalMacro(module: "TestingMacros", type: "NonOptionalRequireMacro")

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
/// - Returns: If the expectation passes, the instance of `errorType` that was
///   thrown by `expression`. If the expectation fails, the result is `nil`.
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
/// - Note: If you use this macro with a Swift compiler version lower than 6.1,
///   it doesn't return a value.
///
/// If the thrown error need only equal another instance of [`Error`](https://developer.apple.com/documentation/swift/error),
/// use ``expect(throws:_:sourceLocation:performing:)-7du1h`` instead.
///
/// ## Expressions that should never throw
///
/// If the expression `expression` should _never_ throw any error, you can pass
/// [`Never.self`](https://developer.apple.com/documentation/swift/never):
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
@discardableResult
@freestanding(expression)
@_documentation(visibility: private)
public macro expect<E, R>(
  throws errorType: E.Type,
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = #_sourceLocation,
  performing expression: () throws -> R
) -> E? = #externalMacro(module: "TestingMacros", type: "ExpectMacro") where E: Error

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
/// - Returns: If the expectation passes, the instance of `errorType` that was
///   thrown by `expression`. If the expectation fails, the result is `nil`.
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
/// - Note: If you use this macro with a Swift compiler version lower than 6.1,
///   it doesn't return a value.
///
/// If the thrown error need only equal another instance of [`Error`](https://developer.apple.com/documentation/swift/error),
/// use ``expect(throws:_:sourceLocation:performing:)-7du1h`` instead.
///
/// ## Expressions that should never throw
///
/// If the expression `expression` should _never_ throw any error, you can pass
/// [`Never.self`](https://developer.apple.com/documentation/swift/never):
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
@discardableResult
@freestanding(expression) public macro expect<E, R>(
  throws errorType: E.Type,
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = #_sourceLocation,
  performing expression: () async throws -> R
) -> E? = #externalMacro(module: "TestingMacros", type: "ExpectMacro") where E: Error

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
/// - Returns: The instance of `errorType` that was thrown by `expression`.
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
/// - Note: If you use this macro with a Swift compiler version lower than 6.1,
///   it doesn't return a value.
///
/// If the thrown error need only equal another instance of [`Error`](https://developer.apple.com/documentation/swift/error),
/// use ``require(throws:_:sourceLocation:performing:)-4djuw`` instead.
///
/// If `expression` should _never_ throw, simply invoke the code without using
/// this macro. The test will then fail if an error is thrown.
@discardableResult
@freestanding(expression)
@_documentation(visibility: private)
public macro require<E, R>(
  throws errorType: E.Type,
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = #_sourceLocation,
  performing expression: () throws -> R
) -> E = #externalMacro(module: "TestingMacros", type: "RequireThrowsMacro") where E: Error

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
/// - Returns: The instance of `errorType` that was thrown by `expression`.
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
/// - Note: If you use this macro with a Swift compiler version lower than 6.1,
///   it doesn't return a value.
///
/// If the thrown error need only equal another instance of [`Error`](https://developer.apple.com/documentation/swift/error),
/// use ``require(throws:_:sourceLocation:performing:)-4djuw`` instead.
///
/// If `expression` should _never_ throw, simply invoke the code without using
/// this macro. The test will then fail if an error is thrown.
@discardableResult
@freestanding(expression) public macro require<E, R>(
  throws errorType: E.Type,
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = #_sourceLocation,
  performing expression: () async throws -> R
) -> E = #externalMacro(module: "TestingMacros", type: "RequireThrowsMacro") where E: Error

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
@freestanding(expression)
@_documentation(visibility: private)
public macro require<R>(
  throws _: Never.Type,
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = #_sourceLocation,
  performing expression: () throws -> R
) = #externalMacro(module: "TestingMacros", type: "RequireThrowsNeverMacro")

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
@freestanding(expression)
@_documentation(visibility: private)
public macro require<R>(
  throws _: Never.Type,
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = #_sourceLocation,
  performing expression: () async throws -> R
) = #externalMacro(module: "TestingMacros", type: "RequireThrowsNeverMacro")

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
/// - Returns: If the expectation passes, the instance of `E` that was thrown by
///   `expression` and is equal to `error`. If the expectation fails, the result
///   is `nil`.
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
/// - Note: If you use this macro with a Swift compiler version lower than 6.1,
///   it doesn't return a value.
///
/// If the thrown error need only be an instance of a particular type, use
/// ``expect(throws:_:sourceLocation:performing:)-1hfms`` instead.
@discardableResult
@freestanding(expression)
@_documentation(visibility: private)
public macro expect<E, R>(
  throws error: E,
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = #_sourceLocation,
  performing expression: () throws -> R
) -> E? = #externalMacro(module: "TestingMacros", type: "ExpectMacro") where E: Error & Equatable

/// Check that an expression always throws a specific error.
///
/// - Parameters:
///   - error: The error that is expected to be thrown.
///   - comment: A comment describing the expectation.
///   - sourceLocation: The source location to which recorded expectations and
///     issues should be attributed.
///   - expression: The expression to be evaluated.
///
/// - Returns: If the expectation passes, the instance of `E` that was thrown by
///   `expression` and is equal to `error`. If the expectation fails, the result
///   is `nil`.
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
/// - Note: If you use this macro with a Swift compiler version lower than 6.1,
///   it doesn't return a value.
///
/// If the thrown error need only be an instance of a particular type, use
/// ``expect(throws:_:sourceLocation:performing:)-1hfms`` instead.
@discardableResult
@freestanding(expression) public macro expect<E, R>(
  throws error: E,
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = #_sourceLocation,
  performing expression: () async throws -> R
) -> E? = #externalMacro(module: "TestingMacros", type: "ExpectMacro") where E: Error & Equatable

/// Check that an expression always throws a specific error, and throw an error
/// if it does not.
///
/// - Parameters:
///   - error: The error that is expected to be thrown.
///   - comment: A comment describing the expectation.
///   - sourceLocation: The source location to which recorded expectations and
///     issues should be attributed.
///   - expression: The expression to be evaluated.

/// - Returns: The instance of `E` that was thrown by `expression` and is equal
///   to `error`.
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
/// - Note: If you use this macro with a Swift compiler version lower than 6.1,
///   it doesn't return a value.
///
/// If the thrown error need only be an instance of a particular type, use
/// ``require(throws:_:sourceLocation:performing:)-7n34r`` instead.
@discardableResult
@freestanding(expression)
@_documentation(visibility: private)
public macro require<E, R>(
  throws error: E,
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = #_sourceLocation,
  performing expression: () throws -> R
) -> E = #externalMacro(module: "TestingMacros", type: "RequireMacro") where E: Error & Equatable

/// Check that an expression always throws a specific error, and throw an error
/// if it does not.
///
/// - Parameters:
///   - error: The error that is expected to be thrown.
///   - comment: A comment describing the expectation.
///   - sourceLocation: The source location to which recorded expectations and
///     issues should be attributed.
///   - expression: The expression to be evaluated.

/// - Returns: The instance of `E` that was thrown by `expression` and is equal
///   to `error`.
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
/// - Note: If you use this macro with a Swift compiler version lower than 6.1,
///   it doesn't return a value.
///
/// If the thrown error need only be an instance of a particular type, use
/// ``require(throws:_:sourceLocation:performing:)-7n34r`` instead.
@discardableResult
@freestanding(expression) public macro require<E, R>(
  throws error: E,
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = #_sourceLocation,
  performing expression: () async throws -> R
) -> E = #externalMacro(module: "TestingMacros", type: "RequireMacro") where E: Error & Equatable

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
/// - Returns: If the expectation passes, the error that was thrown by
///   `expression`. If the expectation fails, the result is `nil`.
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
/// ``expect(throws:_:sourceLocation:performing:)-1hfms`` instead. If the thrown
/// error need only equal another instance of [`Error`](https://developer.apple.com/documentation/swift/error),
/// use ``expect(throws:_:sourceLocation:performing:)-7du1h`` instead.
///
/// @Metadata {
///   @Available(Swift, introduced: 6.0)
///   @Available(Xcode, introduced: 16.0)
/// }
///
/// @DeprecationSummary { <!-- Warning when compiling DocC: rdar://141785948 -->
///   Examine the result of ``expect(throws:_:sourceLocation:performing:)-7du1h``
///   or ``expect(throws:_:sourceLocation:performing:)-1hfms`` instead:
///
///   ```swift
///   let error = #expect(throws: FoodTruckError.self) {
///     ...
///   }
///   #expect(error?.napkinCount == 0)
///   ```
/// }
@available(swift, deprecated: 100000.0, message: "Examine the result of '#expect(throws:)' instead.")
@discardableResult
@freestanding(expression)
@_documentation(visibility: private)
public macro expect<R>(
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = #_sourceLocation,
  performing expression: () throws -> R,
  throws errorMatcher: (any Error) throws -> Bool
) -> (any Error)? = #externalMacro(module: "TestingMacros", type: "ExpectMacro")

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
/// - Returns: If the expectation passes, the error that was thrown by
///   `expression`. If the expectation fails, the result is `nil`.
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
/// ``expect(throws:_:sourceLocation:performing:)-1hfms`` instead. If the thrown
/// error need only equal another instance of [`Error`](https://developer.apple.com/documentation/swift/error),
/// use ``expect(throws:_:sourceLocation:performing:)-7du1h`` instead.
///
/// @Metadata {
///   @Available(Swift, introduced: 6.0)
///   @Available(Xcode, introduced: 16.0)
/// }
///
/// @DeprecationSummary { <!-- Warning when compiling DocC: rdar://141785948 -->
///   Examine the result of ``expect(throws:_:sourceLocation:performing:)-7du1h``
///   or ``expect(throws:_:sourceLocation:performing:)-1hfms`` instead:
///
///   ```swift
///   let error = #expect(throws: FoodTruckError.self) {
///     ...
///   }
///   #expect(error?.napkinCount == 0)
///   ```
/// }
@available(swift, deprecated: 100000.0, message: "Examine the result of '#expect(throws:)' instead.")
@discardableResult
@freestanding(expression) public macro expect<R>(
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = #_sourceLocation,
  performing expression: () async throws -> R,
  throws errorMatcher: (any Error) async throws -> Bool
) -> (any Error)? = #externalMacro(module: "TestingMacros", type: "ExpectMacro")

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
/// - Returns: The error that was thrown by `expression`.
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
/// ``require(throws:_:sourceLocation:performing:)-7n34r`` instead. If the thrown error need
/// only equal another instance of [`Error`](https://developer.apple.com/documentation/swift/error),
/// use ``require(throws:_:sourceLocation:performing:)-4djuw`` instead.
///
/// If `expression` should _never_ throw, simply invoke the code without using
/// this macro. The test will then fail if an error is thrown.
///
/// @Metadata {
///   @Available(Swift, introduced: 6.0)
///   @Available(Xcode, introduced: 16.0)
/// }
///
/// @DeprecationSummary { <!-- Warning when compiling DocC: rdar://141785948 -->
///   Examine the result of ``expect(throws:_:sourceLocation:performing:)-7du1h``
///   or ``expect(throws:_:sourceLocation:performing:)-1hfms`` instead:
///
///   ```swift
///   let error = try #require(throws: FoodTruckError.self) {
///     ...
///   }
///   #expect(error.napkinCount == 0)
///   ```
/// }
@available(swift, deprecated: 100000.0, message: "Examine the result of '#require(throws:)' instead.")
@discardableResult
@freestanding(expression)
@_documentation(visibility: private)
public macro require<R>(
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = #_sourceLocation,
  performing expression: () throws -> R,
  throws errorMatcher: (any Error) throws -> Bool
) -> any Error = #externalMacro(module: "TestingMacros", type: "RequireMacro")

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
/// - Returns: The error that was thrown by `expression`.
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
/// ``require(throws:_:sourceLocation:performing:)-7n34r`` instead. If the thrown error need
/// only equal another instance of [`Error`](https://developer.apple.com/documentation/swift/error),
/// use ``require(throws:_:sourceLocation:performing:)-4djuw`` instead.
///
/// If `expression` should _never_ throw, simply invoke the code without using
/// this macro. The test will then fail if an error is thrown.
///
/// @Metadata {
///   @Available(Swift, introduced: 6.0)
///   @Available(Xcode, introduced: 16.0)
/// }
///
/// @DeprecationSummary { <!-- Warning when compiling DocC: rdar://141785948 -->
///   Examine the result of ``expect(throws:_:sourceLocation:performing:)-7du1h``
///   or ``expect(throws:_:sourceLocation:performing:)-1hfms`` instead:
///
///   ```swift
///   let error = try #require(throws: FoodTruckError.self) {
///     ...
///   }
///   #expect(error.napkinCount == 0)
///   ```
/// }
@available(swift, deprecated: 100000.0, message: "Examine the result of '#require(throws:)' instead.")
@discardableResult
@freestanding(expression) public macro require<R>(
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = #_sourceLocation,
  performing expression: () async throws -> R,
  throws errorMatcher: (any Error) async throws -> Bool
) -> any Error = #externalMacro(module: "TestingMacros", type: "RequireMacro")

// MARK: - Exit tests

/// Check that an expression causes the process to terminate in a given fashion.
///
/// - Parameters:
///   - expectedExitCondition: The expected exit condition.
///   - observedValues: An array of key paths representing results from within
///     the exit test that should be observed and returned by this macro. The
///     ``ExitTest/Result/exitStatus`` property is always returned.
///   - comment: A comment describing the expectation.
///   - sourceLocation: The source location to which recorded expectations and
///     issues should be attributed.
///   - expression: The expression to be evaluated.
///
/// - Returns: If the exit test passes, an instance of ``ExitTest/Result``
///   describing the state of the exit test when it exited. If the exit test
///   fails, the result is `nil`.
///
/// Use this overload of `#expect()` when an expression will cause the current
/// process to terminate and the nature of that termination will determine if
/// the test passes or fails. For example, to test that calling `fatalError()`
/// causes a process to terminate:
///
/// ```swift
/// await #expect(processExitsWith: .failure) {
///   fatalError()
/// }
/// ```
///
/// @Metadata {
///   @Available(Swift, introduced: 6.2)
///   @Available(Xcode, introduced: 26.0)
/// }
@freestanding(expression)
@discardableResult
#if SWT_NO_EXIT_TESTS
@_unavailableInEmbedded
@available(*, unavailable, message: "Exit tests are not available on this platform.")
#endif
public macro expect(
  processExitsWith expectedExitCondition: ExitTest.Condition,
  observing observedValues: [any PartialKeyPath<ExitTest.Result> & Sendable] = [],
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = #_sourceLocation,
  performing expression: @escaping @Sendable () async throws -> Void
) -> ExitTest.Result? = #externalMacro(module: "TestingMacros", type: "ExitTestExpectMacro")

/// Check that an expression causes the process to terminate in a given fashion
/// and throw an error if it did not.
///
/// - Parameters:
///   - expectedExitCondition: The expected exit condition.
///   - observedValues: An array of key paths representing results from within
///     the exit test that should be observed and returned by this macro. The
///     ``ExitTest/Result/exitStatus`` property is always returned.
///   - comment: A comment describing the expectation.
///   - sourceLocation: The source location to which recorded expectations and
///     issues should be attributed.
///   - expression: The expression to be evaluated.
///
/// - Returns: An instance of ``ExitTest/Result`` describing the state of the
///   exit test when it exited.
///
/// - Throws: An instance of ``ExpectationFailedError`` if the exit condition of
///   the child process does not equal `expectedExitCondition`.
///
/// Use this overload of `#require()` when an expression will cause the current
/// process to terminate and the nature of that termination will determine if
/// the test passes or fails. For example, to test that calling `fatalError()`
/// causes a process to terminate:
///
/// ```swift
/// try await #require(processExitsWith: .failure) {
///   fatalError()
/// }
/// ```
///
/// @Metadata {
///   @Available(Swift, introduced: 6.2)
///   @Available(Xcode, introduced: 26.0)
/// }
@freestanding(expression)
@discardableResult
#if SWT_NO_EXIT_TESTS
@_unavailableInEmbedded
@available(*, unavailable, message: "Exit tests are not available on this platform.")
#endif
public macro require(
  processExitsWith expectedExitCondition: ExitTest.Condition,
  observing observedValues: [any PartialKeyPath<ExitTest.Result> & Sendable] = [],
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = #_sourceLocation,
  performing expression: @escaping @Sendable () async throws -> Void
) -> ExitTest.Result = #externalMacro(module: "TestingMacros", type: "ExitTestRequireMacro")

/// Capture a sendable and codable value to pass to an exit test.
///
/// - Parameters:
///   - value: The captured value.
///   - name: The name of the capture list item corresponding to `value`.
///   - expectedType: The type of `value`.
///
/// - Returns: `value` verbatim.
///
/// - Warning: This macro is used to implement the `#expect(processExitsWith:)`
///   macro. Do not use it directly.
@freestanding(expression)
public macro __capturedValue<T>(
  _ value: T,
  _ name: String,
  _ expectedType: T.Type
) -> T = #externalMacro(module: "TestingMacros", type: "ExitTestCapturedValueMacro") where T: Sendable & Codable

/// Emit a compile-time diagnostic when an unsupported value is captured by an
/// exit test.
///
/// - Parameters:
///   - value: The captured value.
///   - name: The name of the capture list item corresponding to `value`.
///   - expectedType: The type of `value`.
///
/// - Returns: The result of a call to `fatalError()`. `value` is discarded at
///   compile time.
///
/// - Warning: This macro is used to implement the `#expect(processExitsWith:)`
///   macro. Do not use it directly.
@freestanding(expression)
public macro __capturedValue<T>(
  _ value: borrowing T,
  _ name: String,
  _ expectedType: T.Type
) -> Never = #externalMacro(module: "TestingMacros", type: "ExitTestBadCapturedValueMacro") where T: ~Copyable & ~Escapable

/// Emit a compile-time diagnostic when a value is captured by an exit test but
/// we inferred the wrong type.
///
/// - Parameters:
///   - value: The captured value.
///   - name: The name of the capture list item corresponding to `value`.
///   - expectedType: The _expected_ type of `value`, which will differ from the
///     _actual_ type of `value`.
///
/// - Returns: The result of a call to `fatalError()`. `value` is discarded at
///   compile time.
///
/// - Warning: This macro is used to implement the `#expect(processExitsWith:)`
///   macro. Do not use it directly.
@freestanding(expression)
public macro __capturedValue<T, U>(
  _ value: borrowing T,
  _ name: String,
  _ expectedType: U.Type
) -> T = #externalMacro(module: "TestingMacros", type: "ExitTestIncorrectlyCapturedValueMacro") where T: ~Copyable & ~Escapable, U: ~Copyable & ~Escapable
