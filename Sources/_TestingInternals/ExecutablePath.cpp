//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#include "ExecutablePath.h"

#include <atomic>

#if defined(__OpenBSD__)
/// Storage for ``swt_getEarlyCWD()``.
static constinit std::atomic<const char *> earlyCWD { nullptr };

/// At process start (before `main()` is called), capture the current working
/// directory.
///
/// This function is necessary on OpenBSD so that we can (as correctly as
/// possible) resolve the executable path when the first argument is a relative
/// path (which can occur when manually invoking the test executable.)
__attribute__((__constructor__(101), __used__))
static void captureEarlyCWD(void) {
  if (auto cwd = getcwd(nil, 0)) {
    earlyCWD.store(cwd);
  }
}
#endif

const char *swt_getEarlyCWD(void) {
#if defined(__OpenBSD__)
  return earlyCWD.load();
#else
  return nullptr;
#endif
}
