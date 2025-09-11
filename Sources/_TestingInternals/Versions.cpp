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

const char *swt_getTestingLibraryVersion(void) {
#if defined(SWT_TESTING_LIBRARY_VERSION)
  return SWT_TESTING_LIBRARY_VERSION;
#else
#warning SWT_TESTING_LIBRARY_VERSION not defined: testing library version is unavailable
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
