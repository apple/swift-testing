//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#include "GetSymbol.h"

#if !defined(SWT_NO_DYNAMIC_LINKING)
#if __has_include(<dlfcn.h>)
#include <dlfcn.h>
#endif

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <Windows.h>
#include <Psapi.h>

#include <algorithm>
#include <array>

#include "../_ImageryInternals/Image.h"
#endif

void *swt_getFunctionWithName(void *handle, const char *symbolName) {
#if __has_include(<dlfcn.h>)
  if (!handle) {
    handle = RTLD_DEFAULT;
  }
  return dlsym(handle, symbolName);
#elif defined(_WIN32)
  // If the caller supplied a module, use it.
  if (HMODULE hModule = reinterpret_cast<HMODULE>(handle)) {
    return reinterpret_cast<void*>(GetProcAddress(hModule, symbolName));
  }

  void *result = nullptr;

  // Enumerate all modules looking for one containing the given symbol.
  sml_enumerateImages(&result, [] (const SMLImage *image, bool *stop, void *context) {
    auto result = reinterpret_cast<void **>(context);
    if (auto address = GetProcAddress(const_cast<HMODULE>(image->base), symbolName)) {
      *result = reinterpret_cast<void *>(address);
      *stop = true;
    }
  });

  return result;
#else
#warning Platform-specific implementation missing: Dynamic loading unavailable
  return nullptr;
#endif
}
#endif
