//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if !defined(SML_DEFINES_H)
#define SML_DEFINES_H

#define SML_ASSUME_NONNULL_BEGIN _Pragma("clang assume_nonnull begin")
#define SML_ASSUME_NONNULL_END _Pragma("clang assume_nonnull end")

#if defined(__cplusplus)
#define SML_EXTERN extern "C"
#else
#define SML_EXTERN extern
#endif

#endif
