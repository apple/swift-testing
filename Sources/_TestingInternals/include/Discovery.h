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
#include <stddef.h>
#include <stdint.h>

SWT_ASSUME_NONNULL_BEGIN

#if !defined(__APPLE__)
/// Specifies the address range corresponding to a section.
typedef struct MetadataSectionRange {
  uintptr_t start;
  size_t length;
} MetadataSectionRange;

/// Identifies the address space ranges for the Swift metadata required by the
/// Swift runtime.
typedef struct MetadataSections {
  uintptr_t version;
  const void *baseAddress;

  void *unused0;
  void *unused1;

  MetadataSectionRange swift5_protocols;
  MetadataSectionRange swift5_protocol_conformances;
  MetadataSectionRange swift5_type_metadata;
  MetadataSectionRange swift5_typeref;
  MetadataSectionRange swift5_reflstr;
  MetadataSectionRange swift5_fieldmd;
  MetadataSectionRange swift5_assocty;
  MetadataSectionRange swift5_replace;
  MetadataSectionRange swift5_replac2;
  MetadataSectionRange swift5_builtin;
  MetadataSectionRange swift5_capture;
  MetadataSectionRange swift5_mpenum;
  MetadataSectionRange swift5_accessible_functions;
} MetadataSections;

/// A function exported by the Swift runtime that enumerates all metadata
/// sections loaded into the current process.
SWT_IMPORT_FROM_STDLIB void swift_enumerateAllMetadataSections(
  bool (* body)(const MetadataSections *sections, void *context),
  void *context
);
#endif

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
///   - sectionStart: The start of the section to examine.
///   - sectionLength: The length, in bytes, of the section to examine.
///   - context: An arbitrary pointer to pass to `body`.
///   - body: A function to invoke, once per matching type.
SWT_EXTERN void swt_enumerateTypesWithNamesContaining(
  const char *nameSubstring,
  const void *sectionStart,
  size_t sectionLength,
  void *_Null_unspecified context,
  SWTTypeEnumerator body
) SWT_SWIFT_NAME(swt_enumerateTypes(withNamesContaining:inSectionStartingAt:byteCount:_:_:));

SWT_ASSUME_NONNULL_END

#endif
