//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if !defined(SWT_EXECUTABLE_PATH_H)
#define SWT_EXECUTABLE_PATH_H

#include "Defines.h"
#include "Includes.h"

SWT_ASSUME_NONNULL_BEGIN

#if defined(__OpenBSD__)
/// Get the current working directory as it was set shortly after the process
/// started and before `main()` has been called.
///
/// This function is necessary on OpenBSD so that we can (as correctly as
/// possible) resolve the executable path when the first argument is a relative
/// path (which can occur when manually invoking the test executable.)
SWT_EXTERN const char *_Nullable swt_getEarlyCWD(void);
#endif

SWT_ASSUME_NONNULL_END

#endif
