//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if !defined(SWT_DISCOVERY_H)
#define SWT_DISCOVERY_H

#include "Defines.h"

#include <stdbool.h>

SWT_ASSUME_NONNULL_BEGIN

/// The type of callback called by `swt_enumerateTypes()`.
///
/// - Parameters:
///   - typeMetadata: A type metadata pointer that can be bitcast to `Any.Type`.
///   - stop: A pointer to a boolean variable indicating whether type
///     enumeration should stop after the function returns. Set `*stop` to
///     `true` to stop type enumeration.
///   - context: An arbitrary pointer passed by the caller to
///     `swt_enumerateTypes()`.
typedef void (* SWTTypeEnumerator)(void *typeMetadata, bool *stop, void *_Null_unspecified context);

/// Enumerate all types known to Swift found in the current process.
///
/// - Parameters:
///   - nameSubstring: A string which the names of matching classes all contain.
///   - context: An arbitrary pointer to pass to `body`.
///   - body: A function to invoke, once per matching type.
SWT_EXTERN void swt_enumerateTypesWithNamesContaining(
  const char *nameSubstring,
  void *_Null_unspecified context,
  SWTTypeEnumerator body
) SWT_SWIFT_NAME(swt_enumerateTypes(withNamesContaining:_:_:));

/// A function type for functions that produce tests.
///
/// This type is fully defined by the Swift module as `__TestGetter`. See the
/// declaration of that type for more information.
typedef void (*SWTTestGetter)(void *_Nonnull);

/// The type of callback that is called by `swt_enumerateTestGetters()`.
///
/// - Parameters:
///   - fp: The underlying function pointer to the Swift function that gets the
///     associated test.
///   - context: An arbitrary pointer passed by the caller to
///     `swt_enumerateTestGetters()`.
typedef void (* SWTTestGetterEnumerator)(SWTTestGetter fp, void *_Null_unspecified context);

/// Enumerate all types known to Swift found in the current process.
///
/// - Parameters:
///   - nameFilter: If not `nullptr`, a filtering function that checks if a type
///     name is valid before realizing the type.
///   - body: A function to invoke. `context` is passed to it along with a
///     type metadata pointer (which can be bitcast to `Any.Type`.)
///   - context: An arbitrary pointer to pass to `body`.
///
/// This function may enumerate the same type more than once (for instance, if
/// it is present in an image's metadata table multiple times, or if it is an
/// Objective-C class implemented in Swift.) Callers are responsible for
/// deduping type metadata pointers passed to `body`.
SWT_EXTERN void swt_enumerateTestGetters(void *_Null_unspecified context, SWTTestGetterEnumerator body);

SWT_ASSUME_NONNULL_END

#endif
