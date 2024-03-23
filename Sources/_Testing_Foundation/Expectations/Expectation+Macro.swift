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
public import Foundation

@_spi(Experimental)
@freestanding(expression) public macro expect<E, R>(
  throws exceptionType: E.Type,
  named name: NSExceptionName? = nil,
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = SourceLocation(),
  performing expression: @escaping () throws -> R
) = #externalMacro(module: "TestingMacros", type: "ExpectMacro") where E: NSException

@_spi(Experimental)
@freestanding(expression) public macro require<E, R>(
  throws exceptionType: E.Type,
  named name: NSExceptionName? = nil,
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = SourceLocation(),
  performing expression: @escaping () throws -> R
) = #externalMacro(module: "TestingMacros", type: "RequireMacro") where E: NSException
#endif
