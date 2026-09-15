//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if !defined(SWT_EMBEDDED_PLATFORM_H)
#define SWT_EMBEDDED_PLATFORM_H

#include "Defines.h"
#include "Includes.h"

SWT_ASSUME_NONNULL_BEGIN

/// This header includes declarations, but not definitions, of functions that
/// the testing library needs defined when built for Embedded Swift.
///
/// This header augments the set of declarations in the Swift runtime's Platform
/// Abstraction Layer, which can be found [here](https://github.com/swiftlang/swift/blob/main/stdlib/public/EmbeddedPlatform/swift/EmbeddedPlatform.h).

// MARK: - System metadata

/// Get information about the embedded system on which (or for which) Swift
/// Testing has been built and is running.
///
/// - Returns: A UTF-8-encoded C string representing some human-readable
///   information identifying the current system. Whether this string represents
///   the system's hardware, software, or other defining characteristics is
///   implementation-defined. If no meaningful information is available, returns
///   `NULL`. The string must remain valid for the lifetime of the process, and
///   the caller is not responsible for deallocating it.
///
/// The testing library uses this function to describe the embedded system it
/// is running on. This information is used for diagnostic purposes only.
///
/// An implementation may choose to return a constant string, a string stored in
/// statically-allocated memory, or a string allocated at runtime. The return
/// value is implementation-defined, but where possible should include useful
/// information about the system. For example, an implementation on a
/// 68040-based Macintosh might return something like `"Quadra 950 (System 7.5.5)"`.
///
/// ### Reference implementations
///
/// On POSIX-compliant targets, this function can be implemented as a call to
/// `uname()`:
///
/// ```c
/// const char *_swift_testing_getEmbeddedTargetInfo(void) {
///   static const char *result = NULL;
///
///   if (!result) {
///     struct utsname name {};
///     if (0 == uname(&name)) {
///       (void)asprintf(&result, "%s (%s)", name.release, name.version);
///     }
///   }
///
///   return result;
/// }
/// ```
///
/// ### Concurrency support
///
/// The testing library calls this function at most once during the lifetime of
/// a test process.
SWT_EXTERN const char *_Nullable _swift_testing_getEmbeddedTargetInfo(void);

// MARK: - Console output

/// A type describing the capabilities of the current system's console output.
typedef struct swift_testing_console_capabilities_t {
  /// Whether or not the testing library should add ANSI escape codes to its
  /// console output.
  ///
  /// ## See Also
  ///
  /// - ``Event/ConsoleOutputRecorder/Options/useANSIEscapeCodes``
  unsigned int useANSIEscapeCodes : 1;

  /// The bit depth of ANSI colors supported by the current system's console.
  ///
  /// For example, black-and-white output has a bit depth of `1`, and true color
  /// output has a bit depth of `24`. Values of `1`, `4`, `8`, and `24` are
  /// supported. `0` is treated as equivalent to `1`, while all other values are
  /// rounded down to the nearest supported value.
  ///
  /// ## See Also
  ///
  /// - ``Event/ConsoleOutputRecorder/Options/ansiColorBitDepth``
  unsigned int ansiColorBitDepth : 5;
} swift_testing_console_capabilities_t;

/// Get the capabilities of the current system's console output.
///
/// - Parameters:
///   - outConsoleCapabilities: A pointer to memory large enough to hold an
///     instance of the ``swift_testing_console_capabilities_t`` structure. On
///     return, initialized to an instance of that type that describes the
///     capabilities of the console `_swift_testing_writeToConsole()` writes to.
///
/// - Returns: Whether or not `outConsoleCapabilities` was successfully
///   initialized. If it was not, the testing library assumes the system console
///   has none of the supported capabilities.
///
/// The testing library uses this function to determine what, if any,
/// capabilities the system console has.
///
/// - Important: The testing library may add additional fields to the
///   ``swift_testing_console_capabilities_t`` structure in the future. To
///   ensure source compatibility if the structure changes, be sure to
///   initialize the entire structure:
///
///   ```c
///   swift_testing_console_capabilities_t good = {};
///   swift_testing_console_capabilities_t bad;
///   ```
///
/// ### Reference implementations
///
/// This function can be implemented to simply return `false` if the current
/// system's console has none of the supported capabilities:
///
/// ```c
/// bool _swift_testing_getConsoleCapabilities(swift_testing_console_capabilities_t *outConsoleCapabilities) {
///   return false;
/// }
/// ```
///
/// ### Concurrency support
///
/// This function's implementation must be concurrency-safe unless the system is
/// single-threaded.
SWT_EXTERN SWT_NODISCARD bool _swift_testing_getConsoleCapabilities(swift_testing_console_capabilities_t *outConsoleCapabilities);

/// Writes a sequence of UTF-8 code points to the current system's console.
///
/// - Parameters:
///   - chars: The UTF-8 code points to write. It is not `NULL`-terminated.
///   - count: The number of UTF-8 code points at `chars`.
///
/// The testing library uses this function to write a _human-readable_
/// transcript of a test run. If possible, the implementation should write
/// output to the standard error stream. Calls to the Swift standard library's
/// `print()` function (or similar interfaces) do not use this function.
///
/// - Important: If the `_swift_testing_getConsoleCapabilities()` function
///   returns `true` and configures any of the supported capabilities, then
///   `chars` may contain ANSI escape codes or other metacontent in addition to
///   human-readable text. If the current system's console only supports plain
///   text, make sure your implementation of that function returns `false`.
///
/// ### Reference implementations
///
/// This function can be implemented as a call to `fwrite()`:
///
/// ```c
/// void _swift_testing_writeToConsole(const uint8_t *chars, size_t count) {
///   fwrite(chars, 1, count, stderr);
/// }
/// ```
///
/// If you want to redirect output from the testing library to the same place
/// that the standard library directs output from `print()`, you can call
/// `_swift_writeToStandardOutput()`:
///
/// ```c
/// extern void _swift_writeToStandardOutput(const unsigned char *, size_t);
///
/// void _swift_testing_writeToConsole(const uint8_t *chars, size_t count) {
///   _swift_writeToStandardOutput(chars, count);
/// }
/// ```
///
/// If the current system's console only supports ASCII output rather than
/// UTF-8, the implementation must take care to filter out or transform
/// non-ASCII code points:
///
/// ```c
/// void _swift_testing_writeToConsole(const uint8_t *chars, size_t count) {
///   flockfile(stderr); {
///     for (size_t i = 0; i < count; i++) {
///       char c = chars[i];
///       if (isascii(c)) {
///         fputc(c, stderr);
///       } else {
///         fputc('?', stderr);
///       }
///     }
///   } funlockfile(stderr);
/// }
/// ```
///
/// If your platform does not support any form of human-readable console output,
/// you can implement this function as a no-op.
///
/// ### Concurrency support
///
/// This function's implementation must be concurrency-safe unless the system is
/// single-threaded. In the reference example above, you can substitute
/// platform-specific equivalents for `flockfile()` and `funlockfile()` if
/// needed, or omit them entirely in single-threaded environments.
SWT_EXTERN void _swift_testing_writeToConsole(const uint8_t *chars, size_t count);

// MARK: - JSON output

/// Writes a JSON object.
///
/// - Parameters:
///   - json: The JSON bytes to write. It is not `NULL`-terminated.
///   - count: The number of bytes at `json`.
///   - terminator: If not `NULL`, a pointer to a single byte to write
///     immediately after writing `json`. This byte is not included in `json` to
///     avoid creating unnecessary copies of `json` in memory.
///
/// The testing library uses this function to write the JSON event stream on
/// targets that do not support file I/O. The destination is
/// implementation-defined. When built for non-Embedded Swift, or when built
/// with support for file I/O, the testing library writes JSON to files and
/// pipes specified by its caller in e.g. the command line arguments to
/// `swift test`.
///
/// ### Reference implementations
///
/// This function can be implemented with the following algorithm:
///
/// ```c
/// FILE *f = ...;
/// flockfile(f); {
///   fwrite(json, 1, count, f);
///   if (terminator) {
///     fputc(*terminator, f);
///   }
/// } funlockfile(f);
/// ```
///
/// If your platform does not support writing JSON or consuming it later, you
/// can implement this function as a no-op.
///
/// ### Concurrency support
///
/// This function's implementation must be concurrency-safe unless the system is
/// single-threaded. In the reference example above, you can substitute
/// platform-specific equivalents for `flockfile()` and `funlockfile()` if
/// needed, or omit them entirely in single-threaded environments.
SWT_EXTERN void _swift_testing_writeJSON(const uint8_t *json, size_t count, const uint8_t terminator[_Nullable 1]);

// MARK: - Test timing

/// Get the amount of time that has passed since the system's epoch.
///
/// - Parameters:
///   - outSeconds: On successful return, set to the number of whole seconds
///     since the system's epoch.
///   - outNanoseconds: On successful return, set to the number of nanoseconds
///     since the system's epoch (less the number of seconds returned in
///     `outSeconds`). The value should be less than `1000000000`.
///
/// - Returns: Whether or not `*outSeconds` and `*outNanoseconds` were
///   successfully initialized. If they were not, their values are undefined and
///   the testing library assumes a time of `0`.
///
/// The testing library uses this function to determine how long tests take to
/// run.
///
/// The system's epoch is typically the time when it booted or the time the
/// current process started. Avoid using the UNIX epoch (1970-01-01 00:00:00 UT)
/// or another realtime (wall-clock) epoch as the realtime clock can be adjusted
/// at runtime and may unexpectedly decrease. The epoch time itself does not
/// need to be representable in Swift.
///
/// The result of this function should have at least millisecond resolution. If
/// the platform does not support millisecond resolution or finer, the
/// implementation should still be as precise as possible. If the platform only
/// supports one-second resolution or coarser, the implementation must set
/// `*outNanoseconds` to `0` before successfully returning.
///
/// - Note: Where possible, the implementation should use a suspending clock
///   rather than a continuous clock (that is, time the system spends asleep
///   should not, ideally, count toward the result of this function).
///
/// ### Reference implementations
///
/// On systems with the POSIX `clock_gettime()`, this function can be
/// implemented with the following algorithm:
///
/// ```c
/// bool _swift_testing_getTimeSinceSystemEpoch(uint32_t *outSeconds, uint32_t *outNanoseconds) {
///   struct timespec ts = {};
///   if (0 != clock_gettime(CLOCK_MONOTONIC, &ts)) {
///     return false;
///   }
///   *outSeconds = (uint32_t)ts.tv_sec;
///   *outNanoseconds = (uint32_t)ts.tv_nsec;
///   return true;
/// }
/// ```
///
/// - Note: POSIX-compliant systems implement a variety of different clocks, and
///   they do not all implement `CLOCK_MONOTONIC`. Consult your platform's
///   documentation to determine the correct clock constant to pass to
///   `clock_gettime()`.
///
/// The implementation can also use system-specific interfaces to compute the
/// current time. For example, if the target is an Arduino board, you could use
/// the [`millis()`](https://docs.arduino.cc/language-reference/en/functions/time/millis/)
/// function:
///
/// ```c
/// bool _swift_testing_getTimeSinceSystemEpoch(uint32_t *outSeconds, uint32_t *outNanoseconds) {
///   unsigned long ms = millis();
///   *outSeconds = ms / 1000;
///   *outNanoseconds = (ms % 1000) * 1000000; // ns per ms
///   return true;
/// }
/// ```
///
/// If the platform does not provide any high-level interfaces for computing the
/// current time, it may still provide lower-level interfaces for querying the
/// system counter, which can then be divided by the CPU's frequency to get a
/// time value. The implementation of this logic is left as an exercise for the
/// reader.
///
/// This function can be implemented to simply return `false` if the platform
/// has no way to get the current time:
///
/// ```c
/// bool _swift_testing_getTimeSinceSystemEpoch(uint32_t *outSeconds, uint32_t *outNanoseconds) {
///   return false;
/// }
/// ```
///
/// ### Concurrency support
///
/// This function's implementation must be concurrency-safe unless the system is
/// single-threaded.
SWT_EXTERN SWT_NODISCARD bool _swift_testing_getTimeSinceSystemEpoch(uint32_t *outSeconds, uint32_t *outNanoseconds);

SWT_ASSUME_NONNULL_END
#endif
