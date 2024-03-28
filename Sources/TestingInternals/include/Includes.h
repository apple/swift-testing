//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if !defined(SWT_INCLUDES_H)
#define SWT_INCLUDES_H

/// This header includes other headers (either those from the C standard library
/// or platform-specific headers) that are used by the testing library.
///
/// Include any headers here from the C standard library that are needed by the
/// testing library. Because the C standard library cannot be directly imported
/// into Swift without introducing a module dependency (and because the name of
/// that module varies on a platform-by-platform basis), we instead include C
/// standard library headers _à la carte_. Symbols from these headers are then
/// imported into Swift when a Swift file imports the `TestingInternals` module.
///
/// Also include any platform-specific headers here that are needed by the
/// testing library.
///
/// - Note: Avoid including headers that aren't actually used.

#include <errno.h>
#if __has_include(<signal.h>)
#include <signal.h>
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#if __has_include(<unistd.h>)
#include <unistd.h>
#endif

#if __has_include(<sys/stat.h>)
#include <sys/stat.h>
#endif

#if __has_include(<sys/sysctl.h>)
#include <sys/sysctl.h>
#endif

#if __has_include(<sys/utsname.h>)
#include <sys/utsname.h>
#endif

#if __has_include(<execinfo.h>)
#include <execinfo.h>
#endif

#if __has_include(<pthread.h>)
#include <pthread.h>
#endif

#if __has_include(<pty.h>)
#include <pty.h>
#endif

#if __has_include(<limits.h>)
#include <limits.h>
#endif

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <Windows.h>
#endif

#endif
