//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if !defined(SWT_TESTSUPPORT_H)
#define SWT_TESTSUPPORT_H

/// This header includes symbols that are used by the testing library's own test
/// targets. These symbols are not used by other clients of the testing library.

#include "Defines.h"
#include "Includes.h"

SWT_ASSUME_NONNULL_BEGIN

/// A type used by the testing library's own tests to validate how C
/// enumerations are presented in test output.
enum __attribute__((enum_extensibility(open))) SWTTestEnumeration {
  SWTTestEnumerationA, SWTTestEnumerationB
};

static inline bool swt_pointersNotEqual2(const char *a, const char *b) {
  return a != b;
}

static inline bool swt_pointersNotEqual3(const char *a, const char *b, const char *c) {
  return a != b && b != c;
}

static inline bool swt_pointersNotEqual4(const char *a, const char *b, const char *c, const char *d) {
  return a != b && b != c && c != d;
}

#if defined(_WIN32)
static inline LPCSTR swt_IDI_SHIELD(void) {
  return IDI_SHIELD;
}
#endif

SWT_ASSUME_NONNULL_END

#endif
