//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

private import TestingInternals

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
  sourceLocation: SourceLocation = SourceLocation()
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
  sourceLocation: SourceLocation = SourceLocation()
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
  sourceLocation: SourceLocation = SourceLocation()
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
  sourceLocation: SourceLocation = SourceLocation()
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
  sourceLocation: SourceLocation = SourceLocation(),
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
  sourceLocation: SourceLocation = SourceLocation(),
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
  sourceLocation: SourceLocation = SourceLocation(),
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
  sourceLocation: SourceLocation = SourceLocation(),
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
  sourceLocation: SourceLocation = SourceLocation(),
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
  sourceLocation: SourceLocation = SourceLocation(),
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
  sourceLocation: SourceLocation = SourceLocation(),
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
  sourceLocation: SourceLocation = SourceLocation(),
  performing expression: () async throws -> R,
  throws errorMatcher: (any Error) async throws -> Bool
) = #externalMacro(module: "TestingMacros", type: "RequireMacro")

// MARK: - Exit tests

/// An enumeration describing possible conditions under which an exit test will
/// succeed or fail.
///
/// Values of this type can be passed to
/// ``expect(exitsWith:_:sourceLocation:performing:)`` or
/// ``require(exitsWith:_:sourceLocation:performing:)`` to configure which exit
/// statuses should be considered successful.
@_spi(Experimental)
#if !(os(macOS) || os(Linux) || os(Windows))
@available(*, unavailable, message: "Exit tests are not available on this platform.")
#elseif !SWIFT_PM_SUPPORTS_SWIFT_TESTING
@available(*, unavailable, message: "A newer version of Swift Package Manager is needed to run exit tests.")
#endif
public enum ExitCondition: Sendable {
  /// The process terminated successfully with status `EXIT_SUCCESS`.
  public static var success: Self { .exitCode(EXIT_SUCCESS) }

  /// The process terminated abnormally with any status other than
  /// `EXIT_SUCCESS` or with any signal.
  case failure

  /// The process terminated with the given exit code.
  ///
  /// - Parameters:
  ///   - exitCode: The exit code yielded by the process.
  ///
  /// The C programming language defines two [standard exit codes](https://en.cppreference.com/w/c/program/EXIT_status),
  /// `EXIT_SUCCESS` and `EXIT_FAILURE`. Platforms may additionally define their
  /// own non-standard exit codes:
  ///
  /// | Platform | Header |
  /// |-|-|
  /// | macOS | [`<stdlib.h>`](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/signal.3.html), [`<sysexits.h>`](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/sysexits.3.html) |
  /// | Linux | `<stdlib.h>`, `<sysexits.h>` |
  /// | Windows | [`<stdlib.h>`](https://learn.microsoft.com/en-us/cpp/c-runtime-library/exit-success-exit-failure) |
  ///
  /// On POSIX-like systems including macOS and Linux, only the low unsigned 8
  /// bits (0&ndash;255) of the exit code are reliably preserved and reported to
  /// a parent process.
  case exitCode(_ exitCode: CInt)

  /// The process terminated with the given signal.
  ///
  /// - Parameters:
  ///   - signal: The signal that terminated the process.
  ///
  /// The C programming language defines a number of [standard signals](https://en.cppreference.com/w/c/program/SIG_types).
  /// Platforms may additionally define their own non-standard signal codes:
  ///
  /// | Platform | Header |
  /// |-|-|
  /// | macOS | [`<signal.h>`](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/signal.3.html) |
  /// | Linux | `<signal.h>` |
  /// | Windows | [`<signal.h>`](https://learn.microsoft.com/en-us/cpp/c-runtime-library/signal-constants) |
  case signal(_ signal: CInt)
}

/// Check that an expression causes the process to terminate in a given fashion.
///
/// - Parameters:
///   - exitCondition: The expected exit condition.
///   - comment: A comment describing the expectation.
///   - sourceLocation: The source location to which recorded expectations and
///     issues should be attributed.
///   - expression: The expression to be evaluated.
///
/// Use this overload of `#expect()` when an expression will cause the current
/// process to terminate and the nature of that termination will determine if
/// the test passes or fails. For example, to test that calling `fatalError()`
/// causes a process to terminate:
///
/// ```swift
/// await #expect(exitsWith: .failure) {
///   fatalError()
/// }
/// ```
///
/// - Note: A call to this expectation macro is called an "exit test."
///
/// ## How exit tests are run
///
/// When an exit test is performed at runtime, the testing library starts a new
/// process with the same executable as the current process. The current task is
/// then suspended (as with `await`) and waits for the child process to
/// terminate. `expression` is not called in the parent process.
///
/// Meanwhile, in the child process, the current test function is run again, but
/// when the exit test is performed again, `expression` is finally called. If
/// `expression` does not terminate the child process, the remainder of the test
/// is allowed to execute. If the test function contains other exit tests, they
/// are ignored.
///
/// The standard I/O streams in the child process are forwarded to those of the
/// current process.
///
/// Once the child process terminates, the parent process resumes and compares
/// its exit status against `exitCondition`. If they match, the exit test has
/// passed; otherwise, it has failed and an issue is recorded.
///
/// ## Runtime constraints
///
/// Take care not to place an exit test within a loop. At runtime, the loop will
/// be iterated in the parent process and then in each child process. For
/// example, the following loop will fail because each child process will call
/// `exit(0)` and will not have a chance to call `exit(n)` when `n > 0`:
///
/// ```swift
/// for n in 0 ..< 5 {
///   await #expect(exitsWith: .exitCode(CInt(n))) { // expects 0, 1, ...
///     exit(CInt(n)) // always called with 0 first
///   }
/// }
/// ```
///
/// Additionally, an exit test:
///
/// - _must_ run within a test function (or a function called by one);
/// - cannot run within another exit test;
/// - cannot run within a parameterized test; and
/// - cannot be run on a detached child task, a dispatch queue, or a background
///   thread.
@_spi(Experimental)
#if !(os(macOS) || os(Linux) || os(Windows))
@available(*, unavailable, message: "Exit tests are not available on this platform.")
#elseif !SWIFT_PM_SUPPORTS_SWIFT_TESTING
@available(*, unavailable, message: "A newer version of Swift Package Manager is needed to run exit tests.")
#endif
@freestanding(expression) public macro expect(
  exitsWith exitCondition: ExitCondition,
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = SourceLocation(),
  performing expression: () async throws -> Void
) = #externalMacro(module: "TestingMacros", type: "ExpectMacro")

/// Check that an expression causes the process to terminate in a given fashion
/// and throw an error if it did not.
///
/// - Parameters:
///   - exitCondition: The expected exit condition.
///   - comment: A comment describing the expectation.
///   - sourceLocation: The source location to which recorded expectations and
///     issues should be attributed.
///   - expression: The expression to be evaluated.
///
/// - Throws: An instance of ``ExpectationFailedError`` if `condition` evaluates
///   to `false`.
///
/// Use this overload of `#expect()` when an expression will cause the current
/// process to terminate and the nature of that termination will determine if
/// the test passes or fails. For example, to test that calling `fatalError()`
/// causes a process to terminate:
///
/// ```swift
/// try await #expect(exitsWith: .failure) {
///   fatalError()
/// }
/// ```
///
/// - Note: A call to this expectation macro is called an "exit test."
///
/// ## How exit tests are run
///
/// When an exit test is performed at runtime, the testing library starts a new
/// process with the same executable as the current process. The current task is
/// then suspended (as with `await`) and waits for the child process to
/// terminate. `expression` is not called in the parent process.
///
/// Meanwhile, in the child process, the current test function is run again, but
/// when the exit test is performed again, `expression` is finally called. If
/// `expression` does not terminate the child process, the remainder of the test
/// is allowed to execute. If the test function contains other exit tests, they
/// are ignored.
///
/// The standard I/O streams in the child process are forwarded to those of the
/// current process.
///
/// Once the child process terminates, the parent process resumes and compares
/// its exit status against `exitCondition`. If they match, the exit test has
/// passed; otherwise, it has failed and an issue is recorded.
///
/// ## Runtime constraints
///
/// Take care not to place an exit test within a loop. At runtime, the loop will
/// be iterated in the parent process and then in each child process. For
/// example, the following loop will fail because each child process will call
/// `exit(0)` and will not have a chance to call `exit(n)` when `n > 0`:
///
/// ```swift
/// for n in 0 ..< 5 {
///   try await #require(exitsWith: .exitCode(CInt(n))) { // expects 0, 1, ...
///     exit(CInt(n)) // always called with 0 first
///   }
/// }
/// ```
///
/// Additionally, an exit test:
///
/// - _must_ run within a test function (or a function called by one);
/// - cannot run within another exit test;
/// - cannot run within a parameterized test; and
/// - cannot be run on a detached child task, a dispatch queue, or a background
///   thread.
@_spi(Experimental)
#if !(os(macOS) || os(Linux) || os(Windows))
@available(*, unavailable, message: "Exit tests are not available on this platform.")
#elseif !SWIFT_PM_SUPPORTS_SWIFT_TESTING
@available(*, unavailable, message: "A newer version of Swift Package Manager is needed to run exit tests.")
#endif
@freestanding(expression) public macro require(
  exitsWith exitCondition: ExitCondition,
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = SourceLocation(),
  performing expression: () async throws -> Void
) = #externalMacro(module: "TestingMacros", type: "RequireMacro")
