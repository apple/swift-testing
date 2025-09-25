//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if _runtime(_ObjC)
public import ObjectiveC

/// An XCTest-compatible Objective-C selector.
///
/// - Warning: This type alias is used to implement the `@Test` macro. Do not
///   use it directly.
public typealias __XCTestCompatibleSelector = Selector
#else
/// Unused.
///
/// - Warning: This type alias is used to implement the `@Test` macro. Do not
///   use it directly.
public typealias __XCTestCompatibleSelector = Never
#endif

/// Make an XCTest-compatible Objective-C selector from a string.
///
/// - Parameters:
///   - selector: The string representation of the selector.
///
/// - Returns: A selector equivalent to `selector`. On platforms without
///   Objective-C interop, this function always returns `nil`.
///
/// - Warning: This function is used to implement the `@Test` macro. Do not use
///   it directly.
@inlinable public func __xcTestCompatibleSelector(_ selector: String) -> __XCTestCompatibleSelector? {
#if _runtime(_ObjC)
  __XCTestCompatibleSelector(selector)
#else
  nil
#endif
}

/// This file provides support for the `@Test` macro. Other than the macro
/// itself, the symbols in this file should not be used directly and are subject
/// to change as the testing library evolves.

// MARK: - @Suite

/// Declare a test suite.
///
/// - Parameters:
///   - traits: Zero or more traits to apply to this test suite.
///
/// A test suite is a type that contains one or more test functions. Any
/// escapable type (that is, any type that is not marked `~Escapable`) may be a
/// test suite.
///
/// The use of the `@Suite` attribute is optional; types are recognized as test
/// suites even if they do not have the `@Suite` attribute applied to them.
///
/// When adding test functions to a type extension, do not use the `@Suite`
/// attribute. Only a type's primary declaration may have the `@Suite` attribute
/// applied to it.
///
/// ## See Also
///
/// - <doc:OrganizingTests>
@attached(member) @attached(peer)
@_documentation(visibility: private)
public macro Suite(
  _ traits: any SuiteTrait...
) = #externalMacro(module: "TestingMacros", type: "SuiteDeclarationMacro")

/// Declare a test suite.
///
/// - Parameters:
///   - displayName: The customized display name of this test suite. If the
///     value of this argument is `nil`, the display name of the test is derived
///     from the associated type's name.
///   - traits: Zero or more traits to apply to this test suite.
///
/// A test suite is a type that contains one or more test functions. Any
/// escapable type (that is, any type that is not marked `~Escapable`) may be a
/// test suite.
///
/// The use of the `@Suite` attribute is optional; types are recognized as test
/// suites even if they do not have the `@Suite` attribute applied to them.
///
/// When adding test functions to a type extension, do not use the `@Suite`
/// attribute. Only a type's primary declaration may have the `@Suite` attribute
/// applied to it.
///
/// ## See Also
///
/// - <doc:OrganizingTests>
@attached(member) @attached(peer) public macro Suite(
  _ displayName: _const String? = nil,
  _ traits: any SuiteTrait...
) = #externalMacro(module: "TestingMacros", type: "SuiteDeclarationMacro")

extension Test {
  /// Create an instance of ``Test`` for a suite type.
  ///
  /// - Warning: This function is used to implement the `@Suite` macro. Do not
  ///   call it directly.
  public static func __type(
    _ containingType: any ~Copyable.Type,
    displayName: String? = nil,
    traits: [any SuiteTrait],
    sourceLocation: SourceLocation
  ) -> Self {
    let containingTypeInfo = TypeInfo(describing: containingType)
    return Self(displayName: displayName, traits: traits, sourceLocation: sourceLocation, containingTypeInfo: containingTypeInfo)
  }
}

// MARK: - @Test

/// This macro declaration is necessary to help the compiler disambiguate
/// display names from traits, but it does not need to be documented separately.
///
/// ## See Also
///
/// - ``Test(_:_:)``
@attached(peer)
@_documentation(visibility: private)
public macro Test(
  _ traits: any TestTrait...
) = #externalMacro(module: "TestingMacros", type: "TestDeclarationMacro")

/// Declare a test.
///
/// - Parameters:
///   - displayName: The customized display name of this test. If the value of
///     this argument is `nil`, the display name of the test is derived from the
///     associated function's name.
///   - traits: Zero or more traits to apply to this test.
///
/// ## See Also
///
/// - <doc:DefiningTests>
@attached(peer) public macro Test(
  _ displayName: _const String? = nil,
  _ traits: any TestTrait...
) = #externalMacro(module: "TestingMacros", type: "TestDeclarationMacro")

extension Test {
  /// Information about a parameter to a test function.
  ///
  /// - Warning: This type alias is used to implement the `@Test` macro. Do not
  ///   use it directly.
  public typealias __Parameter = (firstName: String, secondName: String?, type: Any.Type)

  /// Create an instance of ``Test`` for a function.
  ///
  /// - Warning: This function is used to implement the `@Test` macro. Do not
  ///   call it directly.
  public static func __function<S>(
    named testFunctionName: String,
    in containingType: S.Type?,
    xcTestCompatibleSelector: __XCTestCompatibleSelector?,
    displayName: String? = nil,
    traits: [any TestTrait],
    sourceLocation: SourceLocation,
    parameters: [__Parameter] = [],
    testFunction: @escaping @Sendable () async throws -> Void
  ) -> Self where S: ~Copyable {
    // Don't use Optional.map here due to a miscompile/crash. Expand out to an
    // if expression instead. SEE: rdar://134280902
    let containingTypeInfo: TypeInfo? = if let containingType {
      TypeInfo(describing: containingType)
    } else {
      nil
    }
    let caseGenerator = { @Sendable in Case.Generator(testFunction: testFunction) }
    return Self(name: testFunctionName, displayName: displayName, traits: traits, sourceLocation: sourceLocation, containingTypeInfo: containingTypeInfo, xcTestCompatibleSelector: xcTestCompatibleSelector, testCases: caseGenerator, parameters: [])
  }
}

extension [Test.__Parameter] {
  /// An array of ``Test/Parameter`` values based on this array of parameter
  /// tuples.
  ///
  /// This conversion derives the value of the `index` property of the resulting
  /// parameter instances from the position of the tuple in the original array.
  fileprivate var parameters: [Test.Parameter] {
    enumerated().map { index, parameter in
      Test.Parameter(index: index, firstName: parameter.firstName, secondName: parameter.secondName, type: parameter.type)
    }
  }
}

// MARK: - @Test(arguments:)

/// This macro declaration is necessary to help the compiler disambiguate
/// display names from traits, but it does not need to be documented separately.
///
/// ## See Also
///
/// - ``Test(_:arguments:)-35dat``
@attached(peer)
@_documentation(visibility: private)
public macro Test<C>(
  _ traits: any TestTrait...,
  arguments collection: C
) = #externalMacro(module: "TestingMacros", type: "TestDeclarationMacro") where C: Collection & Sendable, C.Element: Sendable

/// Declare a test parameterized over a collection of values.
///
/// - Parameters:
///   - displayName: The customized display name of this test. If the value of
///     this argument is `nil`, the display name of the test is derived from the
///     associated function's name.
///   - traits: Zero or more traits to apply to this test.
///   - collection: A collection of values to pass to the associated test
///     function.
///
/// You can prefix the expression you pass to `collection` with `try` or `await`.
/// The testing library evaluates the expression lazily only if it determines
/// that the associated test will run. During testing, the testing library calls
/// the associated test function once for each element in `collection`.
///
/// @Comment {
///   - Bug: The testing library should support variadic generics.
///     ([103416861](rdar://103416861))
/// }
///
/// ## See Also
///
/// - <doc:DefiningTests>
@attached(peer) public macro Test<C>(
  _ displayName: _const String? = nil,
  _ traits: any TestTrait...,
  arguments collection: C
) = #externalMacro(module: "TestingMacros", type: "TestDeclarationMacro") where C: Collection & Sendable, C.Element: Sendable

extension Test {
  /// Create an instance of ``Test`` for a parameterized function.
  ///
  /// - Warning: This function is used to implement the `@Test` macro. Do not
  ///   call it directly.
  public static func __function<S, C>(
    named testFunctionName: String,
    in containingType: S.Type?,
    xcTestCompatibleSelector: __XCTestCompatibleSelector?,
    displayName: String? = nil,
    traits: [any TestTrait],
    arguments collection: @escaping @Sendable () async throws -> C,
    sourceLocation: SourceLocation,
    parameters paramTuples: [__Parameter],
    testFunction: @escaping @Sendable (C.Element) async throws -> Void
  ) -> Self where S: ~Copyable, C: Collection & Sendable, C.Element: Sendable {
    let containingTypeInfo: TypeInfo? = if let containingType {
      TypeInfo(describing: containingType)
    } else {
      nil
    }
    let parameters = paramTuples.parameters
    let caseGenerator = { @Sendable in Case.Generator(arguments: try await collection(), parameters: parameters, testFunction: testFunction) }
    return Self(name: testFunctionName, displayName: displayName, traits: traits, sourceLocation: sourceLocation, containingTypeInfo: containingTypeInfo, xcTestCompatibleSelector: xcTestCompatibleSelector, testCases: caseGenerator, parameters: parameters)
  }
}

// MARK: - @Test(arguments:_:)

/// Declare a test parameterized over two collections of values.
///
/// - Parameters:
///   - traits: Zero or more traits to apply to this test.
///   - collection1: A collection of values to pass to `testFunction`.
///   - collection2: A second collection of values to pass to `testFunction`.
///
/// You can prefix the expressions you pass to `collection1` or `collection2`
/// with `try` or `await`. The testing library evaluates the expressions lazily
/// only if it determines that the associated test will run. During testing, the
/// testing library calls the associated test function once for each pair of
/// elements in `collection1` and `collection2`.
///
/// @Comment {
///   - Bug: The testing library should support variadic generics.
///     ([103416861](rdar://103416861))
/// }
///
/// ## See Also
///
/// - <doc:DefiningTests>
@attached(peer)
@_documentation(visibility: private)
public macro Test<C1, C2>(
  _ traits: any TestTrait...,
  arguments collection1: C1, _ collection2: C2
) = #externalMacro(module: "TestingMacros", type: "TestDeclarationMacro") where C1: Collection & Sendable, C1.Element: Sendable, C2: Collection & Sendable, C2.Element: Sendable

/// Declare a test parameterized over two collections of values.
///
/// - Parameters:
///   - displayName: The customized display name of this test. If the value of
///     this argument is `nil`, the display name of the test is derived from the
///     associated function's name.
///   - traits: Zero or more traits to apply to this test.
///   - collection1: A collection of values to pass to `testFunction`.
///   - collection2: A second collection of values to pass to `testFunction`.
///
/// You can prefix the expressions you pass to `collection1` or `collection2`
/// with `try` or `await`. The testing library evaluates the expressions lazily
/// only if it determines that the associated test will run. During testing, the
/// testing library calls the associated test function once for each pair of
/// elements in `collection1` and `collection2`.
///
/// @Comment {
///   - Bug: The testing library should support variadic generics.
///     ([103416861](rdar://103416861))
/// }
///
/// ## See Also
///
/// - <doc:DefiningTests>
@attached(peer) public macro Test<C1, C2>(
  _ displayName: _const String? = nil,
  _ traits: any TestTrait...,
  arguments collection1: C1, _ collection2: C2
) = #externalMacro(module: "TestingMacros", type: "TestDeclarationMacro") where C1: Collection & Sendable, C1.Element: Sendable, C2: Collection & Sendable, C2.Element: Sendable

// MARK: - @Test(arguments: zip(...))

/// Declare a test parameterized over two zipped collections of values.
///
/// - Parameters:
///   - traits: Zero or more traits to apply to this test.
///   - zippedCollections: Two zipped collections of values to pass to
///     `testFunction`.
///
/// You can prefix the expression you pass to `zippedCollections` with `try` or
/// `await`. The testing library evaluates the expression lazily only if it
/// determines that the associated test will run. During testing, the testing
/// library calls the associated test function once for each element in
/// `zippedCollections`.
///
/// @Comment {
///   - Bug: The testing library should support variadic generics.
///     ([103416861](rdar://103416861))
/// }
///
/// ## See Also
///
/// - <doc:DefiningTests>
@attached(peer)
@_documentation(visibility: private)
public macro Test<C1, C2>(
  _ traits: any TestTrait...,
  arguments zippedCollections: Zip2Sequence<C1, C2>
) = #externalMacro(module: "TestingMacros", type: "TestDeclarationMacro") where C1: Collection & Sendable, C1.Element: Sendable, C2: Collection & Sendable, C2.Element: Sendable

/// Declare a test parameterized over two zipped collections of values.
///
/// - Parameters:
///   - displayName: The customized display name of this test. If the value of
///     this argument is `nil`, the display name of the test is derived from the
///     associated function's name.
///   - traits: Zero or more traits to apply to this test.
///   - zippedCollections: Two zipped collections of values to pass to
///     `testFunction`.
///
/// You can prefix the expression you pass to `zippedCollections` with `try` or
/// `await`. The testing library evaluates the expression lazily only if it
/// determines that the associated test will run. During testing, the testing
/// library calls the associated test function once for each element in
/// `zippedCollections`.
///
/// @Comment {
///   - Bug: The testing library should support variadic generics.
///     ([103416861](rdar://103416861))
/// }
///
/// ## See Also
///
/// - <doc:DefiningTests>
@attached(peer) public macro Test<C1, C2>(
  _ displayName: _const String? = nil,
  _ traits: any TestTrait...,
  arguments zippedCollections: Zip2Sequence<C1, C2>
) = #externalMacro(module: "TestingMacros", type: "TestDeclarationMacro") where C1: Collection & Sendable, C1.Element: Sendable, C2: Collection & Sendable, C2.Element: Sendable

extension Test {
  /// Create an instance of ``Test`` for a parameterized function.
  ///
  /// - Warning: This function is used to implement the `@Test` macro. Do not
  ///   call it directly.
  public static func __function<S, C1, C2>(
    named testFunctionName: String,
    in containingType: S.Type?,
    xcTestCompatibleSelector: __XCTestCompatibleSelector?,
    displayName: String? = nil,
    traits: [any TestTrait],
    arguments collection1: @escaping @Sendable () async throws -> C1, _ collection2: @escaping @Sendable () async throws -> C2,
    sourceLocation: SourceLocation,
    parameters paramTuples: [__Parameter],
    testFunction: @escaping @Sendable (C1.Element, C2.Element) async throws -> Void
  ) -> Self where S: ~Copyable, C1: Collection & Sendable, C1.Element: Sendable, C2: Collection & Sendable, C2.Element: Sendable {
    let containingTypeInfo: TypeInfo? = if let containingType {
      TypeInfo(describing: containingType)
    } else {
      nil
    }
    let parameters = paramTuples.parameters
    let caseGenerator = { @Sendable in try await Case.Generator(arguments: collection1(), collection2(), parameters: parameters, testFunction: testFunction) }
    return Self(name: testFunctionName, displayName: displayName, traits: traits, sourceLocation: sourceLocation, containingTypeInfo: containingTypeInfo, xcTestCompatibleSelector: xcTestCompatibleSelector, testCases: caseGenerator, parameters: parameters)
  }

  /// Create an instance of ``Test`` for a parameterized function.
  ///
  /// This initializer overload is specialized for collections of 2-tuples to
  /// efficiently de-structure their elements when appropriate.
  ///
  /// - Warning: This function is used to implement the `@Test` macro. Do not
  ///   call it directly.
  public static func __function<S, C, E1, E2>(
    named testFunctionName: String,
    in containingType: S.Type?,
    xcTestCompatibleSelector: __XCTestCompatibleSelector?,
    displayName: String? = nil,
    traits: [any TestTrait],
    arguments collection: @escaping @Sendable () async throws -> C,
    sourceLocation: SourceLocation,
    parameters paramTuples: [__Parameter],
    testFunction: @escaping @Sendable ((E1, E2)) async throws -> Void
  ) -> Self where S: ~Copyable, C: Collection & Sendable, C.Element == (E1, E2), E1: Sendable, E2: Sendable {
    let containingTypeInfo: TypeInfo? = if let containingType {
      TypeInfo(describing: containingType)
    } else {
      nil
    }
    let parameters = paramTuples.parameters
    let caseGenerator = { @Sendable in Case.Generator(arguments: try await collection(), parameters: parameters, testFunction: testFunction) }
    return Self(name: testFunctionName, displayName: displayName, traits: traits, sourceLocation: sourceLocation, containingTypeInfo: containingTypeInfo, xcTestCompatibleSelector: xcTestCompatibleSelector, testCases: caseGenerator, parameters: parameters)
  }

  /// Create an instance of ``Test`` for a parameterized function.
  ///
  /// This initializer overload is specialized for dictionary collections, to
  /// efficiently de-structure their elements (which are known to be 2-tuples)
  /// when appropriate. This overload is distinct from those for other
  /// collections of 2-tuples because the `Element` tuple type for
  /// `Dictionary` includes labels (`(key: Key, value: Value)`).
  ///
  /// - Warning: This function is used to implement the `@Test` macro. Do not
  ///   call it directly.
  public static func __function<S, Key, Value>(
    named testFunctionName: String,
    in containingType: S.Type?,
    xcTestCompatibleSelector: __XCTestCompatibleSelector?,
    displayName: String? = nil,
    traits: [any TestTrait],
    arguments dictionary: @escaping @Sendable () async throws -> Dictionary<Key, Value>,
    sourceLocation: SourceLocation,
    parameters paramTuples: [__Parameter],
    testFunction: @escaping @Sendable ((Key, Value)) async throws -> Void
  ) -> Self where S: ~Copyable, Key: Sendable, Value: Sendable {
    let containingTypeInfo: TypeInfo? = if let containingType {
      TypeInfo(describing: containingType)
    } else {
      nil
    }
    let parameters = paramTuples.parameters
    let caseGenerator = { @Sendable in Case.Generator(arguments: try await dictionary(), parameters: parameters, testFunction: testFunction) }
    return Self(name: testFunctionName, displayName: displayName, traits: traits, sourceLocation: sourceLocation, containingTypeInfo: containingTypeInfo, xcTestCompatibleSelector: xcTestCompatibleSelector, testCases: caseGenerator, parameters: parameters)
  }

  /// Create an instance of ``Test`` for a parameterized function.
  ///
  /// - Warning: This function is used to implement the `@Test` macro. Do not
  ///   call it directly.
  public static func __function<S, C1, C2>(
    named testFunctionName: String,
    in containingType: S.Type?,
    xcTestCompatibleSelector: __XCTestCompatibleSelector?,
    displayName: String? = nil,
    traits: [any TestTrait],
    arguments zippedCollections: @escaping @Sendable () async throws -> Zip2Sequence<C1, C2>,
    sourceLocation: SourceLocation,
    parameters paramTuples: [__Parameter],
    testFunction: @escaping @Sendable (C1.Element, C2.Element) async throws -> Void
  ) -> Self where S: ~Copyable, C1: Collection & Sendable, C1.Element: Sendable, C2: Collection & Sendable, C2.Element: Sendable {
    let containingTypeInfo: TypeInfo? = if let containingType {
      TypeInfo(describing: containingType)
    } else {
      nil
    }
    let parameters = paramTuples.parameters
    let caseGenerator = { @Sendable in
      Case.Generator(arguments: try await zippedCollections(), parameters: parameters) {
        try await testFunction($0, $1)
      }
    }
    return Self(name: testFunctionName, displayName: displayName, traits: traits, sourceLocation: sourceLocation, containingTypeInfo: containingTypeInfo, xcTestCompatibleSelector: xcTestCompatibleSelector, testCases: caseGenerator, parameters: parameters)
  }
}

// MARK: - Test pragmas

/// A macro used similarly to `#pragma` in C or `@_semantics` in the standard
/// library.
///
/// - Parameters:
///   - arguments: Zero or more context-specific arguments.
///
/// The use cases for this macro are subject to change over time as the needs of
/// the testing library change. The implementation of this macro in the
/// TestingMacros target determines how different arguments are handled.
///
/// - Note: This macro has compile-time effects _only_ and should not affect a
///   compiled test target.
///
/// - Warning: This macro is used to implement other macros declared by the
///   testing library. Do not use it directly.
@attached(peer) public macro __testing(
  semantics arguments: _const String...
) = #externalMacro(module: "TestingMacros", type: "PragmaMacro")

/// A macro used similarly to `#warning()` but in a position where only an
/// attribute is valid.
///
/// - Parameters:
///   - message: A string to emit as a warning.
///
/// - Warning: This macro is used to implement other macros declared by the
///   testing library. Do not use it directly.
@attached(peer) public macro __testing(
  warning message: _const String
) = #externalMacro(module: "TestingMacros", type: "PragmaMacro")

// MARK: - Helper functions

/// A function that abstracts away whether or not the `try` keyword is needed on
/// an expression.
///
/// - Warning: This function is used to implement the `@Test` macro. Do not use
///   it directly.
@inlinable public func __requiringTry<T>(_ value: consuming T) throws -> T where T: ~Copyable {
  value
}

/// A function that abstracts away whether or not the `await` keyword is needed
/// on an expression.
///
/// - Warning: This function is used to implement the `@Test` macro. Do not use
///   it directly.
@inlinable public func __requiringAwait<T>(_ value: consuming T, isolation: isolated (any Actor)? = #isolation) async -> T where T: ~Copyable {
  value
}

/// A function that abstracts away whether or not the `unsafe` keyword is needed
/// on an expression.
///
/// - Warning: This function is used to implement the `@Test` macro. Do not use
///   it directly.
@unsafe @inlinable public func __requiringUnsafe<T>(_ value: consuming T) -> T where T: ~Copyable {
  value
}

/// The current default isolation context.
///
/// - Warning: This property is used to implement the `@Test` macro. Do not call
///   it directly.
public var __defaultSynchronousIsolationContext: (any Actor)? {
  Configuration.current?.defaultSynchronousIsolationContext ?? #isolation
}

/// Run a test function as an `XCTestCase`-compatible method.
///
/// This overload is used for types that are not classes. It always returns
/// `false`.
///
/// - Warning: This function is used to implement the `@Test` macro. Do not call
///   it directly.
@inlinable public func __invokeXCTestCaseMethod<T>(
  _ selector: __XCTestCompatibleSelector?,
  onInstanceOf type: T.Type,
  sourceLocation: SourceLocation
) async throws -> Bool where T: ~Copyable {
  false
}

// TODO: implement a hook in XCTest that __invokeXCTestCaseMethod() can call to
// run an XCTestCase nested in the current @Test function.

/// The `XCTestCase` Objective-C class.
let xcTestCaseClass: AnyClass? = {
#if _runtime(_ObjC)
  objc_getClass("XCTestCase") as? AnyClass
#else
  _typeByName("6XCTest0A4CaseC") as? AnyClass // _mangledTypeName(XCTest.XCTestCase.self)
#endif
}()

/// Run a test function as an `XCTestCase`-compatible method.
///
/// This overload is used for types that are classes. If the type is not a
/// subclass of `XCTestCase`, or if XCTest is not loaded in the current process,
/// this function returns immediately.
///
/// - Warning: This function is used to implement the `@Test` macro. Do not call
///   it directly.
public func __invokeXCTestCaseMethod<T>(
  _ selector: __XCTestCompatibleSelector?,
  onInstanceOf xcTestCaseSubclass: T.Type,
  sourceLocation: SourceLocation
) async throws -> Bool where T: AnyObject {
  // All classes will end up on this code path, so only record an issue if it is
  // really an XCTestCase subclass.
  guard let xcTestCaseClass, isClass(xcTestCaseSubclass, subclassOf: xcTestCaseClass) else {
    return false
  }
  let issue = Issue(
    kind: .apiMisused,
    comments: ["The @Test attribute cannot be applied to methods on a subclass of XCTestCase."],
    sourceContext: .init(backtrace: nil, sourceLocation: sourceLocation)
  )
  issue.record()
  return true
}
