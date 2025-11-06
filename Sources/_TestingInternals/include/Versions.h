//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if !defined(SWT_VERSIONS_H)
#define SWT_VERSIONS_H

#include "Defines.h"
#include "Includes.h"

SWT_ASSUME_NONNULL_BEGIN

/// Get the version of the compiler used to build the testing library.
///
/// - Returns: An integer containing the packed major, minor, and patch
///   components of the compiler version. For more information, see
///   [ClangImporter.cpp](https://github.com/swiftlang/swift/blob/36246a2c8e9501cd29a75f34c9631a8f4e2e1e9b/lib/ClangImporter/ClangImporter.cpp#L647)
///   in the Swift repository.
static inline uint64_t swt_getSwiftCompilerVersion(void) {
#if defined(__SWIFT_COMPILER_VERSION)
  return __SWIFT_COMPILER_VERSION;
#else
  return 0;
#endif
}

/// Get the human-readable version of the testing library.
///
/// - Returns: A human-readable string describing the version of the testing
///   library, or `nullptr` if no version information is available. This
///   string's value and format may vary between platforms, releases, or any
///   other conditions. Do not attempt to parse it.
SWT_EXTERN const char *_Nullable swt_getTestingLibraryVersion(void);

/// Get details of the source control (git) commit from which the testing
/// library was built.
///
/// - Parameters:
///   - outHash: On return, set to a pointer to a string containing the commit
///     hash from which the testing library was built.
///   - outModified: On return, whether or not there were uncommitted changes.
SWT_EXTERN void swt_getTestingLibraryCommit(const char *_Nullable *_Nonnull outHash, bool *outModified);

/// Get the LLVM target triple used to build the testing library.
///
/// - Returns: A string containing the LLVM target triple used to build the
///   testing library, or `nullptr` if that information is not available.
SWT_EXTERN const char *_Nullable swt_getTargetTriple(void);

SWT_ASSUME_NONNULL_END

#endif
