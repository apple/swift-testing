//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if !defined(SWT_GDIPLUS_H)
#define SWT_GDIPLUS_H

/// This header includes thunk functions for various GDI+ functions that the
/// Swift importer is currently unable to import. As such, I haven't documented
/// each function individually; refer to the GDI+ documentation for more
/// information about the thunked functions.

#if defined(_WIN32) && defined(__cplusplus)
#include "../include/Defines.h"
#include "../include/Includes.h"

#include <Gdiplus.h>

SWT_ASSUME_NONNULL_BEGIN

static inline Gdiplus::Status swt_GdiplusStartup(
  ULONG_PTR *token,
  const Gdiplus::GdiplusStartupInput *input,
  Gdiplus::GdiplusStartupOutput *_Nullable output
) {
  return Gdiplus::GdiplusStartup(token, input, output);
}

static inline void swt_GdiplusShutdown(ULONG_PTR token) {
  Gdiplus::GdiplusShutdown(token);
}

static inline Gdiplus::Image *swt_GdiplusImageFromHBITMAP(HBITMAP bitmap, HPALETTE _Nullable palette) {
  return Gdiplus::Bitmap::FromHBITMAP(bitmap, palette);
}

static inline Gdiplus::Image *swt_GdiplusImageFromHICON(HICON icon) {
  return Gdiplus::Bitmap::FromHICON(icon);
}

static inline Gdiplus::Image *swt_GdiplusImageClone(Gdiplus::Image *image) {
  return image->Clone();
}

static inline void swt_GdiplusImageDelete(Gdiplus::Image *image) {
  delete image;
}

static inline Gdiplus::Status swt_GdiplusImageSave(
  Gdiplus::Image *image,
  IStream *stream,
  const CLSID *format,
  const Gdiplus::EncoderParameters *_Nullable encoderParams
) {
  return image->Save(stream, format, encoderParams);
}

static inline GUID swt_GdiplusEncoderQuality(void) {
  return Gdiplus::EncoderQuality;
}

SWT_ASSUME_NONNULL_END

#endif
#endif
