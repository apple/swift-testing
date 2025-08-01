//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if !defined(SWT_STUBS_H)
#define SWT_STUBS_H

#include "Defines.h"
#include "Includes.h"

SWT_ASSUME_NONNULL_BEGIN

/// Mark a code path as unreachable.
///
/// This function is necessary because Swift does not have an equivalent of
/// `__builtin_unreachable()`.
__attribute__((always_inline, noreturn))
static inline void swt_unreachable(void) {
  __builtin_unreachable();
}

#if !SWT_NO_FILE_IO
/// The C file handle type.
///
/// This typedef is necessary because `FILE *` may be imported into Swift as
/// either `OpaquePointer` or `UnsafeMutablePointer<FILE>` depending on the
/// current platform.
typedef FILE *SWT_FILEHandle;

/// Get the standard output stream.
///
/// This function is provided because directly accessing `stdout` from Swift
/// triggers concurrency warnings on some platforms about accessing shared
/// mutable state.
static SWT_FILEHandle swt_stdout(void) {
  return stdout;
}

/// Get the standard error stream.
///
/// This function is provided because directly accessing `stderr` from Swift
/// triggers concurrency warnings on some platforms about accessing shared
/// mutable state.
static SWT_FILEHandle swt_stderr(void) {
  return stderr;
}
#endif

/// Get the current C error.
///
/// This function is provided because `errno` is a complex macro on some
/// platforms and cannot be imported directly into Swift.
static int swt_errno(void) {
  return errno;
}

#if !SWT_NO_FILE_IO
#if __has_include(<sys/stat.h>) && defined(S_ISFIFO)
/// Check if a given `mode_t` value indicates that a file is a pipe (FIFO.)
///
/// This function is exactly equivalent to the `S_ISFIFO()` macro. It is
/// necessary because the mode flag macros are not imported into Swift
/// consistently across platforms.
static bool swt_S_ISFIFO(mode_t mode) {
  return S_ISFIFO(mode);
}
#endif
#endif

#if defined(__APPLE__) && !SWT_NO_MACH_PORTS
/// Get a Mach port representing the current task (process.)
///
/// This function is provided because `mach_task_self()` is a complex macro, but
/// directly accessing `mach_task_self_` from Swift triggers concurrency
/// warnings about accessing shared mutable state.
static mach_port_t swt_mach_task_self(void) {
  return mach_task_self();
}
#endif

#if defined(_WIN32)
/// Make a Win32 language ID.
///
/// This function is provided because `MAKELANGID()` is a complex macro and
/// cannot be imported directly into Swift.
static LANGID swt_MAKELANGID(int p, int s) {
  return MAKELANGID(p, s);
}

/// Get the value of `PROC_THREAD_ATTRIBUTE_HANDLE_LIST`.
///
/// This function is provided because `PROC_THREAD_ATTRIBUTE_HANDLE_LIST` is a
/// complex macro and cannot be imported directly into Swift.
static DWORD_PTR swt_PROC_THREAD_ATTRIBUTE_HANDLE_LIST(void) {
  return PROC_THREAD_ATTRIBUTE_HANDLE_LIST;
}

/// Get the first section in an NT image.
///
/// This function is provided because `IMAGE_FIRST_SECTION()` is a complex macro
/// and cannot be imported directly into Swift.
static const IMAGE_SECTION_HEADER *_Null_unspecified swt_IMAGE_FIRST_SECTION(const IMAGE_NT_HEADERS *ntHeader) {
  return IMAGE_FIRST_SECTION(ntHeader);
}

#if defined(__cplusplus)
/// Add a reference to (retain) a COM object.
///
/// This function is provided because `IUnknown::AddRef()` is a virtual member
/// function and cannot be imported directly into Swift. 
static inline ULONG swt_IUnknown_AddRef(IUnknown *object) {
  return object->AddRef();
}

/// Release a COM object.
///
/// This function is provided because `IUnknown::Release()` is a virtual member
/// function and cannot be imported directly into Swift. 
static inline ULONG swt_IUnknown_Release(IUnknown *object) {
  return object->Release();
}
#endif
#endif

#if defined(__linux__) || defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__ANDROID__)
/// The environment block.
///
/// By POSIX convention, the environment block variable is declared in client
/// code rather than in a header.
SWT_EXTERN char *_Nullable *_Null_unspecified environ;

/// Get the environment block.
///
/// This function is provided because directly accessing `environ` from Swift
/// triggers concurrency warnings about accessing shared mutable state.
static char *_Nullable *_Null_unspecified swt_environ(void) {
  return environ;
}
#endif

#if !defined(__ANDROID__)
#if __has_include(<signal.h>) && defined(si_pid)
/// Get the value of the `si_pid` field of a `siginfo_t` structure.
///
/// This function is provided because `si_pid` is a complex macro on some
/// platforms and cannot be imported directly into Swift. It is renamed back to
/// `siginfo_t.si_pid` in Swift.
SWT_SWIFT_NAME(getter:siginfo_t.si_pid(self:))
static pid_t swt_siginfo_t_si_pid(const siginfo_t *siginfo) {
  return siginfo->si_pid;
}
#endif

#if __has_include(<signal.h>) && defined(si_status)
/// Get the value of the `si_status` field of a `siginfo_t` structure.
///
/// This function is provided because `si_status` is a complex macro on some
/// platforms and cannot be imported directly into Swift. It is renamed back to
/// `siginfo_t.si_status` in Swift.
SWT_SWIFT_NAME(getter:siginfo_t.si_status(self:))
static int swt_siginfo_t_si_status(const siginfo_t *siginfo) {
  return siginfo->si_status;
}
#endif
#endif

/// Get the value of `EEXIST`.
///
/// This function is provided because `EEXIST` is a complex macro in wasi-libc
/// and cannot be imported directly into Swift.
static int swt_EEXIST(void) {
  return EEXIST;
}

#if defined(F_GETFD)
/// Call `fcntl(F_GETFD)`.
///
/// This function is provided because `fcntl()` is a variadic function and
/// cannot be imported directly into Swift.
static int swt_getfdflags(int fd) {
  return fcntl(fd, F_GETFD);
}
#endif

#if defined(F_SETFD)
/// Call `fcntl(F_SETFD)`.
///
/// This function is provided because `fcntl()` is a variadic function and
/// cannot be imported directly into Swift.
static int swt_setfdflags(int fd, int flags) {
  return fcntl(fd, F_SETFD, flags);
}
#endif

SWT_ASSUME_NONNULL_END

#endif
