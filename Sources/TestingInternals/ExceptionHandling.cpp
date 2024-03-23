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

#if !SWT_NO_EXCEPTIONS
#include <cxxabi.h>
#include <exception>
#include <stdexcept>
#include <string.h>
#include <typeinfo>
#include <stdio.h>

void swt_cxxOnly_withExceptionHandling(
  void *context,
  void (* body)(void *context),
  void (* exceptionHandler)(void *context, void *exceptionPointer)
) {
  try {
    (* body)(context);
  } catch (...) {
    auto ep = std::current_exception();
    (* exceptionHandler)(context, &ep);
  }
}

char *swt_copyNameOfExceptionPointer(void *ep) {
  try {
    std::rethrow_exception(*reinterpret_cast<std::exception_ptr *>(ep));
  } catch (...) {
#if defined(__APPLE__) || defined(__linux__)
    if (auto type = __cxxabiv1::__cxa_current_exception_type()) {
      auto mangledName = type->name();
      int status = 0;
      if (auto demangledName = abi::__cxa_demangle(mangledName, nullptr, 0, &status)) {
        return demangledName;
      }
      return strdup(mangledName);
    }
#endif
  }

  return nullptr;
}

// MARK: - Test support

void swt_throwNumber(int value) {
  throw value;
}

void swt_throwCxxException(const char *what) {
  throw std::range_error(what);
}
#endif
