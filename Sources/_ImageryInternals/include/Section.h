//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if !defined(SML_SECTION_H)
#define SML_SECTION_H

#include "Defines.h"

#include <stddef.h>
#include <stdint.h>

SML_ASSUME_NONNULL_BEGIN

/// A type representing a section in an image.
typedef struct SMLSection {
  /// The start of the section in memory.
  const void *start;

  /// The length, in bytes, of the section.
  size_t size;
} SMLSection;

/// Find a section in this image by name.
///
/// - Parameters:
///   - image: The image in which to search.
///   - sectionName: The name of the section to find.
///   - outSection: On successful return, set to an instance of ``SMLSection``
///     representing the requested section. On failure, undefined.
///
/// - Returns: Whether or not a matching section was found.
SML_EXTERN bool sml_findSection(const SMLImage *image, const char *sectionName, SMLSection *outSection);

SML_ASSUME_NONNULL_END

#endif
