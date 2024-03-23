//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

private import TestingInternals

@_spi(ForFoundationAndCxxStdlibOnly)
public enum CaughtException {
#if _runtime(_ObjC)
  case objectiveC(AnyObject)
#endif
  case cxx(UnsafeMutableRawPointer)
}

@available(*, unavailable)
extension CaughtException: Sendable {}

@_spi(ForFoundationAndCxxStdlibOnly)
public func withExceptionHandling(_ body: @escaping () -> Void, exceptionHandler: @escaping (borrowing CaughtException) -> Void) {
  struct Context {
    var body: () -> Void
    var exceptionHandler: (borrowing CaughtException) -> Void
  }
  var context = Context(body: body, exceptionHandler: exceptionHandler)
  withUnsafeMutablePointer(to: &context) { context in
#if _runtime(_ObjC)
    swt_withExceptionHandling(context) { context in
      let context = context!.load(as: Context.self)
      context.body()
    } objectiveCExceptionHandler: { context, exceptionPtr in
      let context = context!.load(as: Context.self)
      let exception = Unmanaged<AnyObject>.fromOpaque(exceptionPtr).takeUnretainedValue()
      context.exceptionHandler(.objectiveC(exception))
    } exceptionHandler: { context, exceptionPtr in
      let context = context!.load(as: Context.self)
      context.exceptionHandler(.cxx(exceptionPtr))
    }
#else
    swt_withExceptionHandling(context) { context in
      let context = context!.load(as: Context.self)
      context.body()
    } exceptionHandler: { context, exceptionPtr in
      let context = context!.load(as: Context.self)
      context.exceptionHandler(.cxx(exceptionPtr))
    }
#endif
  }
}

@_spi(ForFoundationAndCxxStdlibOnly)
public func name(ofExceptionPointer ep: UnsafeMutableRawPointer) -> String? {
  let typeName = swt_copyName(ofExceptionPointer: ep)
  defer {
    free(typeName)
  }
  return typeName.flatMap { String(validatingUTF8: $0) }
}
