//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if !defined(SML_INTERFACE_H)
#define SML_INTERFACE_H

#include "Defines.h"

#include <stdbool.h>

SML_ASSUME_NONNULL_BEGIN

/// A type representing a binary image such as an executable or dynamic library.
typedef struct SMLImage {
  /// The base address of the loaded image.
  const void *base;

  /// The name of the image, if it was available when this instance was created.
  ///
  /// This field is unused on Windows, but is still defined to keep the wrapping
  /// Swift code simpler.
  const char *_Nullable name;
} SMLImage;

/// Get the main executable image in the current process.
///
/// - Parameters:
///   - outImage: On return, set to an instance of ``SMLImage`` representing the
///     main image of the current process.
SML_EXTERN void sml_getMainImage(SMLImage *outImage);

/// The type of callback called by `sml_enumerateImages()`.
///
/// - Parameters:
///   - image: A pointer to an instance of ``SMLImage`` representing an image
///     loaded into the current process.
///   - stop: A pointer to a boolean variable indicating whether image
///     enumeration should stop after the function returns. Set `*stop` to
///     `true` to stop image enumeration.
///   - context: An arbitrary pointer passed by the caller to
///     `sml_enumerateImages()`.
typedef void (* SMLImageEnumerator)(const SMLImage *image, bool *stop, void *_Null_unspecified context);

/// Enumerate over all images loaded into the current process.
///
/// - Parameters:
///   - context: An arbitrary pointer to pass to `body`.
///   - body: A function to call. For each image loaded into the current
///     process, an instance of ``Image`` is passed to this function.
SML_EXTERN void sml_enumerateImages(void *_Null_unspecified context, SMLImageEnumerator body);

/// Find the loaded image that contains an arbitrary address in memory.
///
/// - Parameters:
///   - address: The address whose containing image is needed.
///   - outImage: On successful return, set to an instance of ``SMLImage``
///     representing the image that contains `address`. On failure, undefined.
///
/// - Returns: Whether or not an image containing `address` was found.
SML_EXTERN bool sml_getImageContainingAddress(const void *address, SMLImage *outImage);

// MARK: -

/// The type of callback called by `sml_withImageName()`.
///
/// - Parameters:
///   - image: A pointer to an instance of ``SMLImage`` representing an image
///     loaded into the current process.
///   - name: The name of `image`, if available. This pointer is valid only for
///     the lifetime of the callback and must be copied if the caller needs it
///     for a longer timeframe.
///   - context: An arbitrary pointer passed by the caller to
///     `sml_withImageName()`.
#if defined(_WIN32)
typedef void (* SMLImageNameCallback)(const SMLImage *image, const wchar_t *_Nullable name, void *_Null_unspecified context);
#else
typedef void (* SMLImageNameCallback)(const SMLImage *image, const char *_Nullable name, void *_Null_unspecified context);
#endif

/// Get the name of an image.
///
/// - Parameters:
///   - image: The image whose name is needed.
///   - context: An arbitrary pointer to pass to `body`.
///   - body: A function to call with the name of `image`.
///
/// This function acts as a scoped accessor to the name of `image` to avoid
/// unnecessarily copying it.
SML_EXTERN void sml_withImageName(const SMLImage *image, void *_Null_unspecified context, SMLImageNameCallback body);

SML_ASSUME_NONNULL_END

#endif
