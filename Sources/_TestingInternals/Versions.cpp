//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#include "Versions.h"

#include <array>
#include <algorithm>
#include <iterator>
#include <mutex>

const char *swt_getTestingLibraryVersion(void) {
#if defined(SWT_TESTING_LIBRARY_VERSION)
  // The current environment explicitly specifies a version string to return.
  // All CMake builds should take this path (see CompilerSettings.cmake.)
  return SWT_TESTING_LIBRARY_VERSION;
#elif __clang_major__ >= 17 && defined(__has_embed)
#if __has_embed("../../VERSION.txt")
  // Read the version from version.txt at the root of the package's repo.
  static char version[] = {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wc23-extensions"
#embed "../../VERSION.txt" suffix(, '\0')
#pragma clang diagnostic pop
  };

  // Zero out the newline character and anything after it.
  static std::once_flag once;
  std::call_once(once, [] {
    auto i = std::find_if(std::begin(version), std::end(version), [] (char c) {
      return c == '\r' || c == '\n';
    });
    std::fill(i, std::end(version), '\0');
  });

  return version;
#else
#warning SWT_TESTING_LIBRARY_VERSION not defined and VERSION.txt not found: testing library version is unavailable
  return nullptr;
#endif
#elif defined(__OpenBSD__)
  // OpenBSD's version of clang doesn't support __has_embed or #embed.
  return nullptr;
#else
#warning SWT_TESTING_LIBRARY_VERSION not defined and could not read from VERSION.txt at compile time: testing library version is unavailable
  return nullptr;
#endif
}

void swt_getTestingLibraryCommit(const char *_Nullable *_Nonnull outHash, bool *outModified) {
#if defined(SWT_TESTING_LIBRARY_COMMIT_HASH)
  *outHash = SWT_TESTING_LIBRARY_COMMIT_HASH;
#else
  *outHash = nullptr;
#endif
#if defined(SWT_TESTING_LIBRARY_COMMIT_MODIFIED)
  *outModified = (SWT_TESTING_LIBRARY_COMMIT_MODIFIED != 0);
#else
  *outModified = false;
#endif
}

const char *swt_getTargetTriple(void) {
#if defined(SWT_TARGET_TRIPLE)
  return SWT_TARGET_TRIPLE;
#else
  // If we're here, we're presumably building as a package. Swift Package
  // Manager does not provide a way to get the target triple from within the
  // package manifest. SEE: swift-package-manager-#7929
  //
  // clang has __is_target_*() intrinsics, but we don't want to play a game of
  // Twenty Questions in order to synthesize the triple (and still potentially
  // get it wrong.) SEE: rdar://134933385
  return nullptr;
#endif
}
