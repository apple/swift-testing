//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#include "ExceptionHandling.h"

#include <exception>

#if defined(__OBJC2__)
void swt_withExceptionHandling(
  void *context,
  void (* body)(void *context),
  void (* objCExceptionHandler)(void *context, void *exceptionObject),
  void (* exceptionHandler)(void *context, void *exceptionPointer)
) {
  try {
    (* body)(context);
  } catch (id object) {
    (* objCExceptionHandler)(context, (__bridge void *)object);
  } catch (...) {
    auto ep = std::current_exception();
    (* exceptionHandler)(context, &ep);
  }
}
#endif
