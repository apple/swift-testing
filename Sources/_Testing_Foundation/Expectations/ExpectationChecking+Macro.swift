//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if canImport(Foundation) && _runtime(_ObjC) && !SWT_NO_EXCEPTIONS
@_spi(ForFoundationAndCxxStdlibOnly) public import Testing
public import Foundation

/// Check that an expression always throws an exception.
///
/// This overload is used for `#expect(throws:) { }` invocations that take
/// `NSException` subclasses.
///
/// - Note: `body` is necessarily `@escaping` because when it throws an
///   exception, the instruction pointer will trampoline out of the local
///   callback before any cleanup code can be run. (One of the hazards of doing
///   something wholly unsupported by the language.)
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
@_spi(Experimental)
@inline(never) public func __checkClosureCall<E>(
  throws exceptionType: E.Type,
  named name: NSExceptionName? = nil,
  performing body: @escaping () -> some Any,
  expression: Expression,
  comments: @escaping @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) -> Result<Void, any Error> where E: NSException {
  var result: Result<Void, any Error> = .success(())

  withExceptionHandling {
    _ = body()

    // If we reach this point, an exception was not thrown.
    result = __checkValue(
      false,
      expression: expression,
      comments: comments() + CollectionOfOne("Expected an exception would be thrown, but here we are."),
      isRequired: isRequired,
      sourceLocation: sourceLocation
    )
  } exceptionHandler: { exception in
    switch exception {
#if _runtime(_ObjC)
    case let .objectiveC(object):
      // Check if the thrown exception was of the correct type.
      result = __checkValue(
        object.isKind(of: exceptionType),
        expression: expression,
        comments: comments() + CollectionOfOne("Expected an exception of class \(exceptionType), but got \(object) instead."),
        isRequired: isRequired,
        sourceLocation: sourceLocation
      )

      if case .success = result, let name {
        result = __checkValue(
          (object as? NSException)?.name == name,
          expression: expression,
          comments: comments() + CollectionOfOne(#"Expected an exception with name "\#(name)", but got \#(object) instead."#),
          isRequired: isRequired,
          sourceLocation: sourceLocation
        )
      }
#endif
    case let .cxx(ep):
      let typeName = Testing.name(ofExceptionPointer: ep) ?? "an unknown exception"
      result = __checkValue(
        false,
        expression: expression,
        comments: comments() + CollectionOfOne("Expected an exception of class \(exceptionType), but got \(typeName) instead."),
        isRequired: isRequired,
        sourceLocation: sourceLocation
      )
    }
  }

  return result
}
#endif
