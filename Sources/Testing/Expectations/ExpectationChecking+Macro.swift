//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// - Parameters:
///   - condition: The condition to be evaluated.
///   - expression: The expression, corresponding to `condition`, that is being
///     evaluated (if available at compile time.)
///   - expressionWithCapturedRuntimeValues: The expression, corresponding to
///     `condition` and with runtime values captured, that is being evaluated
///     (if available at compile time.)
///   - difference: The difference between the operands in `condition`, if
///     available. Most callers should pass `nil`.
///   - comments: An array of comments describing the expectation. This array
///     may be empty.
///   - isRequired: Whether or not the expectation is required. The value of
///     this argument does not affect whether or not an error is thrown on
///     failure.
///   - sourceLocation: The source location of the expectation.
///
/// - Returns: A `Result<Void, any Error>`. If `condition` is `true`, the result
///   is `.success`. If `condition` is `false`, the result is an instance of
///   ``ExpectationFailedError`` describing the failure.
///
/// If the condition evaluates to `false`, an ``Issue`` is recorded for the test
/// that is running in the current task.
///
/// The odd error-handling convention in this function is necessary so that we
/// don't accidentally suppress errors thrown from subexpressions inside the
/// condition. For example, assuming there is a function
/// `func f() throws -> Bool`, the following calls should _not_ throw an
/// instance of ``ExpectationFailedError``, but should also not prevent an error
/// from being thrown by `f()`:
///
/// ```swift
/// try #expect(f))
/// #expect(try f())
/// ```
///
/// And the following call should generate a compile-time error:
///
/// ```swift
/// #expect(f()) // ERROR: Call can throw but is not marked with 'try'
/// ```
///
/// By _returning_ the error this function "throws", we can customize whether or
/// not we throw that error during macro resolution without affecting any errors
/// thrown by the condition expression passed to it.
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkValue(
  _ condition: Bool,
  expression: __Expression,
  expressionWithCapturedRuntimeValues: @autoclosure () -> __Expression? = nil,
  mismatchedErrorDescription: @autoclosure () -> String? = nil,
  difference: @autoclosure () -> String? = nil,
  mismatchedExitConditionDescription: @autoclosure () -> String? = nil,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) -> Result<Void, any Error> {
  // If the expression being evaluated is a negation (!x instead of x), flip
  // the condition here so that we evaluate it in the correct sense. We loop
  // in case of multiple prefix operators (!!(a == b), for example.)
  var condition = condition
  do {
    var expression: __Expression? = expression
    while case let .negation(subexpression, _) = expression?.kind {
      defer {
        expression = subexpression
      }
      condition = !condition
    }
  }

  // Capture the correct expression in the expectation.
  var expression = expression
  if !condition, let expressionWithCapturedRuntimeValues = expressionWithCapturedRuntimeValues() {
    expression = expressionWithCapturedRuntimeValues
    if expression.runtimeValue == nil, case .negation = expression.kind {
      expression = expression.capturingRuntimeValue(condition)
    }
  }

  // Post an event for the expectation regardless of whether or not it passed.
  // If the current event handler is not configured to handle events of this
  // kind, this event is discarded.
  lazy var expectation = Expectation(evaluatedExpression: expression, isPassing: condition, isRequired: isRequired, sourceLocation: sourceLocation)
  if Configuration.deliverExpectationCheckedEvents {
    Event.post(.expectationChecked(expectation))
  }

  // Early exit if the expectation passed.
  if condition {
    return .success(())
  }

  // Since this expectation failed, populate its optional fields which are
  // only evaluated and included lazily upon failure.
  expectation.mismatchedErrorDescription = mismatchedErrorDescription()
  expectation.differenceDescription = difference()
  expectation.mismatchedExitConditionDescription = mismatchedExitConditionDescription()

  // Ensure the backtrace is captured here so it has fewer extraneous frames
  // from the testing framework which aren't relevant to the user.
  let backtrace = Backtrace.current()
  let issue = Issue(kind: .expectationFailed(expectation), comments: comments(), sourceContext: .init(backtrace: backtrace, sourceLocation: sourceLocation))
  issue.record()

  return .failure(ExpectationFailedError(expectation: expectation))
}

// MARK: - Binary operators

/// Call a binary operator, passing the left-hand and right-hand arguments.
///
/// - Parameters:
///   - lhs: The left-hand argument to `op`.
///   - op: The binary operator to call.
///   - rhs: The right-hand argument to `op`. This closure may be invoked zero
///     or one time, but not twice or more.
///
/// - Returns: A tuple containing the result of calling `op` and the value of
///   `rhs` (or `nil` if it was not evaluated.)
///
/// - Throws: Whatever is thrown by `op`.
private func _callBinaryOperator<T, U, R>(
  _ lhs: T,
  _ op: (T, () -> U) -> R,
  _ rhs: () -> U
) -> (result: R, rhs: U?) {
  // The compiler normally doesn't allow a nonescaping closure to call another
  // nonescaping closure, but our use cases are safe (e.g. `true && false`) and
  // we cannot force one function or the other to be escaping. Use
  // withoutActuallyEscaping() to tell the compiler that what we're doing is
  // okay. SEE: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0176-enforce-exclusive-access-to-memory.md#restrictions-on-recursive-uses-of-non-escaping-closures
  var rhsValue: U?
  let result: R = withoutActuallyEscaping(rhs) { rhs in
    op(lhs, {
      if rhsValue == nil {
        rhsValue = rhs()
      }
      return rhsValue!
    })
  }
  return (result, rhsValue)
}

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload is used by binary operators such as `>`:
///
/// ```swift
/// #expect(2 > 1)
/// ```
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
@_disfavoredOverload public func __checkBinaryOperation<T, U>(
  _ lhs: T, _ op: (T, () -> U) -> Bool, _ rhs: @autoclosure () -> U,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) -> Result<Void, any Error> {
  let (condition, rhs) = _callBinaryOperator(lhs, op, rhs)
  return __checkValue(
    condition,
    expression: expression,
    expressionWithCapturedRuntimeValues: expression.capturingRuntimeValues(lhs, rhs),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

// MARK: - Function calls

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload is used by function calls:
///
/// ```swift
/// #expect(x.update(i))
/// ```
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkFunctionCall<T, each U>(
  _ lhs: T, calling functionCall: (T, repeat each U) throws -> Bool, _ arguments: repeat each U,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) rethrows -> Result<Void, any Error> {
  let condition = try functionCall(lhs, repeat each arguments)
  return __checkValue(
    condition,
    expression: expression,
    expressionWithCapturedRuntimeValues: expression.capturingRuntimeValues(lhs, repeat each arguments),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

#if !SWT_FIXED_122011759
/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload works around a bug in variadic generics that may cause a
/// miscompile when an argument to a function is a C string converted from a
/// Swift string (e.g. the arguments to `fopen("/file/path", "wb")`.)
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkFunctionCall<T, Arg0>(
  _ lhs: T, calling functionCall: (T, Arg0) throws -> Bool, _ argument0: Arg0,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) rethrows -> Result<Void, any Error> {
  let condition = try functionCall(lhs, argument0)
  return __checkValue(
    condition,
    expression: expression,
    expressionWithCapturedRuntimeValues: expression.capturingRuntimeValues(lhs, argument0),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload works around a bug in variadic generics that may cause a
/// miscompile when an argument to a function is a C string converted from a
/// Swift string (e.g. the arguments to `fopen("/file/path", "wb")`.)
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkFunctionCall<T, Arg0, Arg1>(
  _ lhs: T, calling functionCall: (T, Arg0, Arg1) throws -> Bool, _ argument0: Arg0, _ argument1: Arg1,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) rethrows -> Result<Void, any Error> {
  let condition = try functionCall(lhs, argument0, argument1)
  return __checkValue(
    condition,
    expression: expression,
    expressionWithCapturedRuntimeValues: expression.capturingRuntimeValues(lhs, argument0, argument1),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload works around a bug in variadic generics that may cause a
/// miscompile when an argument to a function is a C string converted from a
/// Swift string (e.g. the arguments to `fopen("/file/path", "wb")`.)
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkFunctionCall<T, Arg0, Arg1, Arg2>(
  _ lhs: T, calling functionCall: (T, Arg0, Arg1, Arg2) throws -> Bool, _ argument0: Arg0, _ argument1: Arg1, _ argument2: Arg2,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) rethrows -> Result<Void, any Error> {
  let condition = try functionCall(lhs, argument0, argument1, argument2)
  return __checkValue(
    condition,
    expression: expression,
    expressionWithCapturedRuntimeValues: expression.capturingRuntimeValues(lhs, argument0, argument1, argument2),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload works around a bug in variadic generics that may cause a
/// miscompile when an argument to a function is a C string converted from a
/// Swift string (e.g. the arguments to `fopen("/file/path", "wb")`.)
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkFunctionCall<T, Arg0, Arg1, Arg2, Arg3>(
  _ lhs: T, calling functionCall: (T, Arg0, Arg1, Arg2, Arg3) throws -> Bool, _ argument0: Arg0, _ argument1: Arg1, _ argument2: Arg2, _ argument3: Arg3,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) rethrows -> Result<Void, any Error> {
  let condition = try functionCall(lhs, argument0, argument1, argument2, argument3)
  return __checkValue(
    condition,
    expression: expression,
    expressionWithCapturedRuntimeValues: expression.capturingRuntimeValues(lhs, argument0, argument1, argument2, argument3),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}
#endif

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload is used by function calls where the arguments are all `inout`:
///
/// ```swift
/// #expect(x.update(&i))
/// ```
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkInoutFunctionCall<T, /*each*/ U>(
  _ lhs: T, calling functionCall: (T, inout /*repeat each*/ U) throws -> Bool, _ arguments: inout /*repeat each*/ U,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) rethrows -> Result<Void, any Error> {
  let condition = try functionCall(lhs, /*repeat each*/ &arguments)
  return __checkValue(
    condition,
    expression: expression,
    expressionWithCapturedRuntimeValues: expression.capturingRuntimeValues(lhs, /*repeat each*/ arguments),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload is used to conditionally unwrap optional values produced from
/// expanded function calls:
///
/// ```swift
/// let z = try #require(x.update(i))
/// ```
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkFunctionCall<T, each U, R>(
  _ lhs: T, calling functionCall: (T, repeat each U) throws -> R?, _ arguments: repeat each U,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) rethrows -> Result<R, any Error> {
  let optionalValue = try functionCall(lhs, repeat each arguments)
  return __checkValue(
    optionalValue,
    expression: expression,
    expressionWithCapturedRuntimeValues: expression.capturingRuntimeValues(lhs, repeat each arguments),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

#if !SWT_FIXED_122011759
/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload works around a bug in variadic generics that may cause a
/// miscompile when an argument to a function is a C string converted from a
/// Swift string (e.g. the arguments to `fopen("/file/path", "wb")`.)
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkFunctionCall<T, Arg0, R>(
  _ lhs: T, calling functionCall: (T, Arg0) throws -> R?, _ argument0: Arg0,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) rethrows -> Result<R, any Error> {
  let optionalValue = try functionCall(lhs, argument0)
  return __checkValue(
    optionalValue,
    expression: expression,
    expressionWithCapturedRuntimeValues: expression.capturingRuntimeValues(lhs, argument0),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload works around a bug in variadic generics that may cause a
/// miscompile when an argument to a function is a C string converted from a
/// Swift string (e.g. the arguments to `fopen("/file/path", "wb")`.)
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkFunctionCall<T, Arg0, Arg1, R>(
  _ lhs: T, calling functionCall: (T, Arg0, Arg1) throws -> R?, _ argument0: Arg0, _ argument1: Arg1,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) rethrows -> Result<R, any Error> {
  let optionalValue = try functionCall(lhs, argument0, argument1)
  return __checkValue(
    optionalValue,
    expression: expression,
    expressionWithCapturedRuntimeValues: expression.capturingRuntimeValues(lhs, argument0, argument1),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload works around a bug in variadic generics that may cause a
/// miscompile when an argument to a function is a C string converted from a
/// Swift string (e.g. the arguments to `fopen("/file/path", "wb")`.)
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkFunctionCall<T, Arg0, Arg1, Arg2, R>(
  _ lhs: T, calling functionCall: (T, Arg0, Arg1, Arg2) throws -> R?, _ argument0: Arg0, _ argument1: Arg1, _ argument2: Arg2,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) rethrows -> Result<R, any Error> {
  let optionalValue = try functionCall(lhs, argument0, argument1, argument2)
  return __checkValue(
    optionalValue,
    expression: expression,
    expressionWithCapturedRuntimeValues: expression.capturingRuntimeValues(lhs, argument0, argument1, argument2),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload works around a bug in variadic generics that may cause a
/// miscompile when an argument to a function is a C string converted from a
/// Swift string (e.g. the arguments to `fopen("/file/path", "wb")`.)
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkFunctionCall<T, Arg0, Arg1, Arg2, Arg3, R>(
  _ lhs: T, calling functionCall: (T, Arg0, Arg1, Arg2, Arg3) throws -> R?, _ argument0: Arg0, _ argument1: Arg1, _ argument2: Arg2, _ argument3: Arg3,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) rethrows -> Result<R, any Error> {
  let optionalValue = try functionCall(lhs, argument0, argument1, argument2, argument3)
  return __checkValue(
    optionalValue,
    expression: expression,
    expressionWithCapturedRuntimeValues: expression.capturingRuntimeValues(lhs, argument0, argument1, argument2, argument3),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}
#endif

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload is used to conditionally unwrap optional values produced from
/// expanded function calls where the arguments are all `inout`:
///
/// ```swift
/// let z = try #require(x.update(&i))
/// ```
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkInoutFunctionCall<T, /*each*/ U, R>(
  _ lhs: T, calling functionCall: (T, inout /*repeat each*/ U) throws -> R?, _ arguments: inout /*repeat each*/ U,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) rethrows -> Result<R, any Error> {
  let optionalValue = try functionCall(lhs, /*repeat each*/ &arguments)
  return __checkValue(
    optionalValue,
    expression: expression,
    expressionWithCapturedRuntimeValues: expression.capturingRuntimeValues(lhs, /*repeat each*/ arguments),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

// MARK: - Property access

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload is used by property accesses:
///
/// ```swift
/// #expect(x.isFoodTruck)
/// ```
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkPropertyAccess<T>(
  _ lhs: T, getting memberAccess: (T) -> Bool,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) -> Result<Void, any Error> {
  let condition = memberAccess(lhs)
  return __checkValue(
    condition,
    expression: expression,
    expressionWithCapturedRuntimeValues: expression.capturingRuntimeValues(lhs, condition),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload is used to conditionally unwrap optional values produced from
/// expanded property accesses:
///
/// ```swift
/// let z = try #require(x.nearestFoodTruck)
/// ```
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkPropertyAccess<T, U>(
  _ lhs: T, getting memberAccess: (T) -> U?,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) -> Result<U, any Error> {
  let optionalValue = memberAccess(lhs)
  return __checkValue(
    optionalValue,
    expression: expression,
    expressionWithCapturedRuntimeValues: expression.capturingRuntimeValues(lhs, optionalValue as U??),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

// MARK: - Collection diffing

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload is used to implement difference-reporting support when
/// comparing collections.
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
@_disfavoredOverload public func __checkBinaryOperation<T>(
  _ lhs: T, _ op: (T, () -> T) -> Bool, _ rhs: @autoclosure () -> T,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) -> Result<Void, any Error> where T: BidirectionalCollection, T.Element: Equatable {
  let (condition, rhs) = _callBinaryOperator(lhs, op, rhs)
  func difference() -> String? {
    guard let rhs else {
      return nil
    }
    let difference = lhs.difference(from: rhs)
    let insertions = difference.insertions.map(\.element)
    let removals = difference.removals.map(\.element)
    switch (!insertions.isEmpty, !removals.isEmpty) {
    case (true, true):
      return "inserted \(insertions), removed \(removals)"
    case (true, false):
      return "inserted \(insertions)"
    case (false, true):
      return "removed \(removals)"
    case (false, false):
      return ""
    }
  }

  return __checkValue(
    condition,
    expression: expression,
    expressionWithCapturedRuntimeValues: expression.capturingRuntimeValues(lhs, rhs),
    difference: difference(),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload is necessary because `String` satisfies the requirements for
/// the difference-calculating overload above, but the output from that overload
/// may be unexpectedly complex.
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkBinaryOperation(
  _ lhs: String, _ op: (String, () -> String) -> Bool, _ rhs: @autoclosure () -> String,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) -> Result<Void, any Error> {
  let (condition, rhs) = _callBinaryOperator(lhs, op, rhs)
  return __checkValue(
    condition,
    expression: expression,
    expressionWithCapturedRuntimeValues: expression.capturingRuntimeValues(lhs, rhs),
    difference: nil,
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload is necessary because ranges are collections and satisfy the
/// requirements for the difference-calculating overload above, but it doesn't
/// make sense to diff them and very large ranges can cause overflows or hangs.
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkBinaryOperation<T, U>(
  _ lhs: T, _ op: (T, () -> U) -> Bool, _ rhs: @autoclosure () -> U,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) -> Result<Void, any Error> where T: RangeExpression, U: RangeExpression {
  let (condition, rhs) = _callBinaryOperator(lhs, op, rhs)
  return __checkValue(
    condition,
    expression: expression,
    expressionWithCapturedRuntimeValues: expression.capturingRuntimeValues(lhs, rhs),
    difference: nil,
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload is used for `v is T` expressions.
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkCast<V, T>(
  _ value: V,
  is _: T.Type,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) -> Result<Void, any Error> {
  return __checkValue(
    value is T,
    expression: expression,
    expressionWithCapturedRuntimeValues: expression.capturingRuntimeValues(value, type(of: value as Any)),
    difference: nil,
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

// MARK: - Optional unwrapping

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload is used to conditionally unwrap optional values:
///
/// ```swift
/// let x: Int? = ...
/// let y = try #require(x)
/// ```
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkValue<T>(
  _ optionalValue: T?,
  expression: __Expression,
  expressionWithCapturedRuntimeValues: @autoclosure () -> __Expression? = nil,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) -> Result<T, any Error> {
  // The double-optional below is because capturingRuntimeValue() takes optional
  // values and interprets nil as "no value available". Rather, if optionalValue
  // is `nil`, we want to actually store `nil` as the expression's evaluated
  // value. The outer optional satisfies the generic constraint of
  // capturingRuntimeValue(), and the inner optional represents the actual value
  // (`nil`) that will be captured.
  __checkValue(
    optionalValue != nil,
    expression: expression,
    expressionWithCapturedRuntimeValues: (expressionWithCapturedRuntimeValues() ?? expression).capturingRuntimeValue(optionalValue as T??),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  ).map {
    optionalValue.unsafelyUnwrapped
  }
}

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload is used to conditionally unwrap optional values using the `??`
/// operator:
///
/// ```swift
/// let x: Int? = ...
/// let y: Int? = ...
/// let z = try #require(x ?? y)
/// ```
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
@_disfavoredOverload public func __checkBinaryOperation<T>(
  _ lhs: T?, _ op: (T?, () -> T?) -> T?, _ rhs: @autoclosure () -> T?,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) -> Result<T, any Error> {
  let (optionalValue, rhs) = _callBinaryOperator(lhs, op, rhs)
  return __checkValue(
    optionalValue,
    expression: expression,
    expressionWithCapturedRuntimeValues: expression.capturingRuntimeValues(lhs as T??, rhs as T??),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload is used for `v as? T` expressions.
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkCast<V, T>(
  _ value: V,
  as _: T.Type,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) -> Result<T, any Error> {
  // NOTE: this call to __checkValue() does not go through the optional
  // bottleneck because we do not want to capture the nil value on failure (it
  // looks odd in test output.)
  let optionalValue = value as? T
  return __checkValue(
    optionalValue != nil,
    expression: expression,
    expressionWithCapturedRuntimeValues: expression.capturingRuntimeValues(value, type(of: value as Any)),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  ).map {
    optionalValue.unsafelyUnwrapped
  }
}

// MARK: - Matching errors by type

/// Check that an expression always throws an error.
///
/// This overload is used for `#expect(throws:) { }` invocations that take error
/// types. It is disfavored so that `#expect(throws: Never.self)` preferentially
/// returns `Void`.
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkClosureCall<E>(
  throws errorType: E.Type,
  performing body: () throws -> some Any,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) -> Result<E?, any Error> where E: Error {
  if errorType == Never.self {
    __checkClosureCall(
      throws: Never.self,
      performing: body,
      expression: expression,
      comments: comments(),
      isRequired: isRequired,
      sourceLocation: sourceLocation
    ).map { _ in nil }
  } else {
    __checkClosureCall(
      performing: body,
      throws: { $0 is E },
      mismatchExplanation: { "expected error of type \(errorType), but \(_description(of: $0)) was thrown instead" },
      expression: expression,
      comments: comments(),
      isRequired: isRequired,
      sourceLocation: sourceLocation
    ).map { $0 as? E }
  }
}

/// Check that an expression always throws an error.
///
/// This overload is used for `await #expect(throws:) { }` invocations that take
/// error types. It is disfavored so that `#expect(throws: Never.self)`
/// preferentially returns `Void`.
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkClosureCall<E>(
  throws errorType: E.Type,
  performing body: () async throws -> sending some Any,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  isolation: isolated (any Actor)? = #isolation,
  sourceLocation: SourceLocation
) async -> Result<E?, any Error> where E: Error {
  if errorType == Never.self {
    await __checkClosureCall(
      throws: Never.self,
      performing: body,
      expression: expression,
      comments: comments(),
      isRequired: isRequired,
      isolation: isolation,
      sourceLocation: sourceLocation
    ).map { _ in nil }
  } else {
    await __checkClosureCall(
      performing: body,
      throws: { $0 is E },
      mismatchExplanation: { "expected error of type \(errorType), but \(_description(of: $0)) was thrown instead" },
      expression: expression,
      comments: comments(),
      isRequired: isRequired,
      isolation: isolation,
      sourceLocation: sourceLocation
    ).map { $0 as? E }
  }
}

// MARK: - Matching Never.self

/// Check that an expression never throws an error.
///
/// This overload is used for `#expect(throws: Never.self) { }`. It cannot be
/// implemented directly in terms of the other overloads because it checks for
/// the _absence_ of an error rather than an error that matches some predicate.
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkClosureCall(
  throws _: Never.Type,
  performing body: () throws -> some Any,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) -> Result<Void, any Error> {
  var success = true
  var mismatchExplanationValue: String? = nil
  do {
    _ = try body()
  } catch {
    success = false
    mismatchExplanationValue = "an error was thrown when none was expected: \(_description(of: error))"
  }

  return __checkValue(
    success,
    expression: expression,
    mismatchedErrorDescription: mismatchExplanationValue,
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  ).map { _ in }
}

/// Check that an expression never throws an error.
///
/// This overload is used for `await #expect(throws: Never.self) { }`. It cannot
/// be implemented directly in terms of the other overloads because it checks
/// for the _absence_ of an error rather than an error that matches some
/// predicate.
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkClosureCall(
  throws _: Never.Type,
  performing body: () async throws -> sending some Any,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  isolation: isolated (any Actor)? = #isolation,
  sourceLocation: SourceLocation
) async -> Result<Void, any Error> {
  var success = true
  var mismatchExplanationValue: String? = nil
  do {
    _ = try await body()
  } catch {
    success = false
    mismatchExplanationValue = "an error was thrown when none was expected: \(_description(of: error))"
  }

  return __checkValue(
    success,
    expression: expression,
    mismatchedErrorDescription: mismatchExplanationValue,
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  ).map { _ in }
}

// MARK: - Matching instances of equatable errors

/// Check that an expression always throws an error.
///
/// This overload is used for `#expect(throws:) { }` invocations that take error
/// instances.
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkClosureCall<E>(
  throws error: E,
  performing body: () throws -> some Any,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) -> Result<E?, any Error> where E: Error & Equatable {
  __checkClosureCall(
    performing: body,
    throws: { true == (($0 as? E) == error) },
    mismatchExplanation: { "expected error \(_description(of: error)), but \(_description(of: $0)) was thrown instead" },
    expression: expression,
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  ).map { $0 as? E }
}

/// Check that an expression always throws an error.
///
/// This overload is used for `await #expect(throws:) { }` invocations that take
/// error instances.
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkClosureCall<E>(
  throws error: E,
  performing body: () async throws -> sending some Any,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  isolation: isolated (any Actor)? = #isolation,
  sourceLocation: SourceLocation
) async -> Result<E?, any Error> where E: Error & Equatable {
  await __checkClosureCall(
    performing: body,
    throws: { true == (($0 as? E) == error) },
    mismatchExplanation: { "expected error \(_description(of: error)), but \(_description(of: $0)) was thrown instead" },
    expression: expression,
    comments: comments(),
    isRequired: isRequired,
    isolation: isolation,
    sourceLocation: sourceLocation
  ).map { $0 as? E }
}

// MARK: - Arbitrary error matching

/// Check that an expression always throws an error.
///
/// This overload is used for `#expect { } throws: { }` invocations.
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkClosureCall<R>(
  performing body: () throws -> R,
  throws errorMatcher: (any Error) throws -> Bool,
  mismatchExplanation: ((any Error) -> String)? = nil,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) -> Result<(any Error)?, any Error> {
  var errorMatches = false
  var mismatchExplanationValue: String? = nil
  var expression = expression
  var caughtError: (any Error)?
  do {
    let result = try body()

    var explanation = "an error was expected but none was thrown"
    if R.self != Void.self {
      explanation += " and \"\(result)\" was returned"
    }
    mismatchExplanationValue = explanation
  } catch {
    caughtError = error
    expression = expression.capturingRuntimeValues(error)
    let secondError = Issue.withErrorRecording(at: sourceLocation) {
      errorMatches = try errorMatcher(error)
    }
    if let secondError {
      mismatchExplanationValue = "a second error \(_description(of: secondError)) was thrown when checking error \(_description(of: error))"
    } else if !errorMatches {
      mismatchExplanationValue = mismatchExplanation?(error) ?? "unexpected error \(_description(of: error)) was thrown"
    }
  }

  return __checkValue(
    errorMatches,
    expression: expression,
    mismatchedErrorDescription: mismatchExplanationValue,
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  ).map { caughtError }
}

/// Check that an expression always throws an error.
///
/// This overload is used for `await #expect { } throws: { }` invocations.
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkClosureCall<R>(
  performing body: () async throws -> sending R,
  throws errorMatcher: (any Error) async throws -> Bool,
  mismatchExplanation: ((any Error) -> String)? = nil,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  isolation: isolated (any Actor)? = #isolation,
  sourceLocation: SourceLocation
) async -> Result<(any Error)?, any Error> {
  var errorMatches = false
  var mismatchExplanationValue: String? = nil
  var expression = expression
  var caughtError: (any Error)?
  do {
    let result = try await body()

    var explanation = "an error was expected but none was thrown"
    if R.self != Void.self {
      explanation += " and \"\(result)\" was returned"
    }
    mismatchExplanationValue = explanation
  } catch {
    caughtError = error
    expression = expression.capturingRuntimeValues(error)
    let secondError = await Issue.withErrorRecording(at: sourceLocation) {
      errorMatches = try await errorMatcher(error)
    }
    if let secondError {
      mismatchExplanationValue = "a second error \(_description(of: secondError)) was thrown when checking error \(_description(of: error))"
    } else if !errorMatches {
      mismatchExplanationValue = mismatchExplanation?(error) ?? "unexpected error \(_description(of: error)) was thrown"
    }
  }

  return __checkValue(
    errorMatches,
    expression: expression,
    mismatchedErrorDescription: mismatchExplanationValue,
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  ).map { caughtError }
}

// MARK: - Exit tests

#if !SWT_NO_EXIT_TESTS
/// Check that an expression always exits (terminates the current process) with
/// a given status.
///
/// This overload is used for `await #expect(processExitsWith:) { }` invocations
/// that do not capture any state.
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkClosureCall(
  identifiedBy exitTestID: (UInt64, UInt64, UInt64, UInt64),
  processExitsWith expectedExitCondition: ExitTest.Condition,
  observing observedValues: [any PartialKeyPath<ExitTest.Result> & Sendable] = [],
  performing _: @convention(c) () -> Void,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  isolation: isolated (any Actor)? = #isolation,
  sourceLocation: SourceLocation
) async -> Result<ExitTest.Result?, any Error> {
  await callExitTest(
    identifiedBy: exitTestID,
    encodingCapturedValues: [],
    processExitsWith: expectedExitCondition,
    observing: observedValues,
    expression: expression,
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

/// Check that an expression always exits (terminates the current process) with
/// a given status.
///
/// This overload is used for `await #expect(processExitsWith:) { }` invocations
/// that capture some values with an explicit capture list.
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
#if SWT_FIXED_154221449
@_spi(Experimental)
public func __checkClosureCall<each T>(
  identifiedBy exitTestID: (UInt64, UInt64, UInt64, UInt64),
  encodingCapturedValues capturedValues: (repeat each T),
  processExitsWith expectedExitCondition: ExitTest.Condition,
  observing observedValues: [any PartialKeyPath<ExitTest.Result> & Sendable] = [],
  performing _: @convention(c) () -> Void,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  isolation: isolated (any Actor)? = #isolation,
  sourceLocation: SourceLocation
) async -> Result<ExitTest.Result?, any Error> where repeat each T: Codable & Sendable {
  await callExitTest(
    identifiedBy: exitTestID,
    encodingCapturedValues: Array(repeat each capturedValues),
    processExitsWith: expectedExitCondition,
    observing: observedValues,
    expression: expression,
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}
#else
@_spi(Experimental)
public func __checkClosureCall<each T>(
  identifiedBy exitTestID: (UInt64, UInt64, UInt64, UInt64),
  encodingCapturedValues capturedValues: repeat each T,
  processExitsWith expectedExitCondition: ExitTest.Condition,
  observing observedValues: [any PartialKeyPath<ExitTest.Result> & Sendable] = [],
  performing _: @convention(c) () -> Void,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  isolation: isolated (any Actor)? = #isolation,
  sourceLocation: SourceLocation
) async -> Result<ExitTest.Result?, any Error> where repeat each T: Codable & Sendable {
  await callExitTest(
    identifiedBy: exitTestID,
    encodingCapturedValues: Array(repeat each capturedValues),
    processExitsWith: expectedExitCondition,
    observing: observedValues,
    expression: expression,
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}
#endif
#endif

// MARK: -

/// Generate a description of an error that includes its type name if not
/// already present.
///
/// - Parameters:
///   - error: The error to describe.
///
/// - Returns: A string equivalent to `String(describing: error)` with
///   information about its type added if not already present.
private func _description(of error: some Error) -> String {
  let errorDescription = "\"\(error)\""
  let errorType = type(of: error as Any)
  if #available(_regexAPI, *) {
    if errorDescription.contains(String(describing: errorType)) {
      return errorDescription
    }
  }
  return "\(errorDescription) of type \(errorType)"
}
