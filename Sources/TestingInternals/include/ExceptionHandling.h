//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if !defined(SWT_EXCEPTIONHANDLING_H)
#define SWT_EXCEPTIONHANDLING_H

#include "Defines.h"

SWT_ASSUME_NONNULL_BEGIN

#if !SWT_NO_EXCEPTIONS
SWT_EXTERN void swt_cxxOnly_withExceptionHandling(
  void *_Null_unspecified context,
  void (* body)(void *_Null_unspecified context),
  void (* exceptionHandler)(void *_Null_unspecified context, void *exceptionPointer)
) SWT_SWIFT_NAME(swt_withExceptionHandling(_:_:exceptionHandler:)) SWT_NOINLINE;

#if defined(__OBJC2__)
SWT_EXTERN void swt_withExceptionHandling(
  void *_Null_unspecified context,
  void (* body)(void *_Null_unspecified context),
  void (* objCExceptionHandler)(void *_Null_unspecified context, void *exceptionObject),
  void (* exceptionHandler)(void *_Null_unspecified context, void *exceptionPointer)
) SWT_SWIFT_NAME(swt_withExceptionHandling(_:_:objectiveCExceptionHandler:exceptionHandler:)) SWT_NOINLINE;
#endif

SWT_EXTERN char *_Nullable swt_copyNameOfExceptionPointer(void *ep) SWT_SWIFT_NAME(swt_copyName(ofExceptionPointer:));

// MARK: - Test support

SWT_EXTERN void swt_throwNumber(int value);
SWT_EXTERN void swt_throwCxxException(const char *what);
#endif

SWT_ASSUME_NONNULL_END

#endif
