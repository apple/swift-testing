//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

internal import _TestingInternals

#if !SWT_NO_PIPES
#if SWT_NO_FILE_IO
#error("Platform-specific misconfiguration: support for (anonymous) pipes requires support for file I/O")
#endif
#endif

#if !SWT_NO_FILE_IO
/// A type representing a file handle.
///
/// Instances of this type abstract away the C `FILE *` type for Swift.
///
/// Whether or not a particular C file handle is safe to use concurrently is
/// platform- and file-specific. The testing library assumes that the standard
/// I/O file handles are generally concurrency-safe as implemented on supported
/// platforms.
///
/// This type is not part of the public interface of the testing library.
struct FileHandle: ~Copyable, Sendable {
  /// The underlying C file handle.
  private nonisolated(unsafe) var _fileHandle: SWT_FILEHandle

  /// Whether or not to close `_fileHandle` when this instance is deinitialized.
  private var _closeWhenDone: Bool

  // The value of stdout or stderr might change over time on some platforms, so
  // these properties need to be computed each time. Fortunately, creating a new
  // instance of this type from an existing C file handle is cheap.

  /// The C standard output stream.
  static var stdout: Self {
    Self(unsafeCFILEHandle: swt_stdout(), closeWhenDone: false)
  }

  /// The C standard error stream.
  static var stderr: Self {
    Self(unsafeCFILEHandle: swt_stderr(), closeWhenDone: false)
  }

  /// Initialize an instance of this type by opening a file at the given path
  /// with the given mode.
  ///
  /// - Parameters:
  ///   - path: The path to open.
  ///   - mode: The mode to open `path` with, such as `"wb"`.
  ///
  /// - Throws: Any error preventing the stream from being opened.
  init(atPath path: String, mode: String) throws {
#if os(Windows)
    // Special-case CONOUT$ to map to stdout. This way, if somebody specifies
    // CONOUT$ as the target path for XML or JSON output from `swift test`,
    // output will be correctly interleaved with writes to `stdout`. If we don't
    // do this, the file will open successfully but will be opened in text mode
    // (even if we ask for binary mode), will wrap at the virtual console's
    // column limit, and won't share a file lock with the C `stdout` handle.
    //
    // To our knowledge, this sort of special-casing is not required on
    // POSIX-like platforms (i.e. when opening "/dev/stdout"), but it can be
    // adapted for use there if some POSIX-like platform does need it.
    if path == "CONOUT$" && mode.contains("w") {
      self = .stdout
      return
    }

    // On Windows, "N" is used rather than "e" to signify that a file handle is
    // not inherited.
    var mode = mode
    if let eIndex = mode.firstIndex(of: "e") {
      mode.replaceSubrange(eIndex ... eIndex, with: "N")
    }

    // Windows deprecates fopen() as insecure, so call _wfopen_s() instead.
    let fileHandle = try path.withCString(encodedAs: UTF16.self) { path in
      try mode.withCString(encodedAs: UTF16.self) { mode in
        var file: SWT_FILEHandle?
        let result = _wfopen_s(&file, path, mode)
        guard let file, result == 0 else {
          throw CError(rawValue: result)
        }
        return file
      }
    }
#else
    guard let fileHandle = fopen(path, mode) else {
      throw CError(rawValue: swt_errno())
    }
#endif
    self.init(unsafeCFILEHandle: fileHandle, closeWhenDone: true)
  }

  /// Initialize an instance of this type to read from the given path.
  ///
  /// - Parameters:
  ///   - path: The path to read from.
  ///
  /// - Throws: Any error preventing the stream from being opened.
  ///
  /// By default, the resulting file handle is not inherited by any child
  /// processes (that is, `FD_CLOEXEC` is set on POSIX-like systems and
  /// `HANDLE_FLAG_INHERIT` is cleared on Windows.).
  init(forReadingAtPath path: String) throws {
    try self.init(atPath: path, mode: "reb")
  }

  /// Initialize an instance of this type to write to the given path.
  ///
  /// - Parameters:
  ///   - path: The path to write to.
  ///
  /// - Throws: Any error preventing the stream from being opened.
  ///
  /// By default, the resulting file handle is not inherited by any child
  /// processes (that is, `FD_CLOEXEC` is set on POSIX-like systems and
  /// `HANDLE_FLAG_INHERIT` is cleared on Windows.).
  init(forWritingAtPath path: String) throws {
    try self.init(atPath: path, mode: "web")
  }

  /// Initialize an instance of this type with an existing C file handle.
  ///
  /// - Parameters:
  ///   - fileHandle: The C file handle to wrap. The caller is responsible for
  ///     ensuring that this file handle is open in the expected mode and that
  ///     another part of the system won't close it.
  ///   - closeWhenDone: Whether or not to close `fileHandle` when the resulting
  ///     instance is deinitialized. The caller is responsible for ensuring that
  ///     there are no other references to `fileHandle` when passing `true`.
  init(unsafeCFILEHandle fileHandle: SWT_FILEHandle, closeWhenDone: Bool) {
    _fileHandle = fileHandle
    _closeWhenDone = closeWhenDone
  }

  /// Initialize an instance of this type with an existing POSIX file descriptor
  /// for reading.
  ///
  /// - Parameters:
  ///   - fd: The POSIX file descriptor to wrap. The caller is responsible for
  ///     ensuring that this file handle is open in the expected mode and that
  ///     another part of the system won't close it.
  ///   - mode: The mode `fd` was opened with, such as `"wb"`.
  ///
  /// - Throws: Any error preventing the stream from being opened.
  ///
  /// The resulting file handle takes ownership of `fd` and closes it when it is
  /// deinitialized or if an error is thrown from this initializer.
  init(unsafePOSIXFileDescriptor fd: CInt, mode: String) throws {
#if os(Windows)
    let fileHandle = _fdopen(fd, mode)
#else
    let fileHandle = fdopen(fd, mode)
#endif
    guard let fileHandle else {
      let errorCode = swt_errno()
      Self._close(fd)
      throw CError(rawValue: errorCode)
    }
    self.init(unsafeCFILEHandle: fileHandle, closeWhenDone: true)
  }

  deinit {
    if _closeWhenDone {
      fclose(_fileHandle)
    }
  }

  /// Close this file handle.
  ///
  /// This function effectively deinitializes the file handle.
  ///
  /// - Warning: This function closes the underlying C file handle even if
  ///   `closeWhenDone` was `false` when this instance was initialized. Callers
  ///   must take care not to close file handles they do not own.
  consuming func close() {
    _closeWhenDone = true
  }

  /// Close a file descriptor.
  ///
  /// - Parameters:
  ///   - fd: The file descriptor to close. If the value of this argument is
  ///     less than `0`, this function does nothing.
  private static func _close(_ fd: CInt) {
    if fd >= 0 {
#if os(Windows)
      _TestingInternals._close(fd)
#else
      _TestingInternals.close(fd)
#endif
    }
  }

  /// Call a function and pass the underlying C file handle to it.
  ///
  /// - Parameters:
  ///   - body: A function to call.
  ///
  /// - Returns: Whatever is returned by `body`.
  ///
  /// - Throws: Whatever is thrown by `body`.
  ///
  /// Use this function when calling C I/O interfaces such as `fputs()` on the
  /// underlying C file handle.
  borrowing func withUnsafeCFILEHandle<R>(_ body: (SWT_FILEHandle) throws -> R) rethrows -> R {
    try body(_fileHandle)
  }

  /// Call a function and pass the underlying POSIX file descriptor to it.
  ///
  /// - Parameters:
  ///   - body: A function to call.
  ///
  /// - Returns: Whatever is returned by `body`.
  ///
  /// - Throws: Whatever is thrown by `body`.
  ///
  /// Use this function when calling interfaces on the underlying C file handle
  /// that require a file descriptor instead of the standard `FILE *`
  /// representation. If the file handle cannot be converted to a file
  /// descriptor, `nil` is passed to `body`.
  borrowing func withUnsafePOSIXFileDescriptor<R>(_ body: (CInt?) throws -> R) rethrows -> R {
    try withUnsafeCFILEHandle { handle in
#if SWT_TARGET_OS_APPLE || os(Linux) || os(FreeBSD) || os(OpenBSD) || os(Android) || os(WASI)
      let fd = fileno(handle)
#elseif os(Windows)
      let fd = _fileno(handle)
#else
#warning("Platform-specific implementation missing: cannot get file descriptor from a file handle")
      let fd: CInt = -1
#endif

      if Bool(fd >= 0) {
        return try body(fd)
      }
      return try body(nil)
    }
  }

#if os(Windows)
  /// Call a function and pass the underlying Windows file handle to it.
  ///
  /// - Parameters:
  ///   - body: A function to call.
  ///
  /// - Returns: Whatever is returned by `body`.
  ///
  /// - Throws: Whatever is thrown by `body`.
  ///
  /// Use this function when calling interfaces on the underlying C file handle
  /// that require the file's `HANDLE` representation instead of the standard
  /// `FILE *` representation. If the file handle cannot be converted to a
  /// Windows handle, `nil` is passed to `body`.
  borrowing func withUnsafeWindowsHANDLE<R>(_ body: (HANDLE?) throws -> R) rethrows -> R {
    try withUnsafePOSIXFileDescriptor { fd in
      guard let fd else {
        return try body(nil)
      }
      var handle = HANDLE(bitPattern: _get_osfhandle(fd))
      if handle == INVALID_HANDLE_VALUE || handle == .init(bitPattern: -2) {
        handle = nil
      }
      return try body(handle)
    }
  }
#endif

  /// Call a function while holding the file handle's lock.
  ///
  /// - Parameters:
  ///   - body: A function to call.
  ///
  /// - Returns: Whatever is returned by `body`.
  ///
  /// - Throws: Whatever is thrown by `body`.
  ///
  /// This function uses `flockfile()` and `funlockfile()` to synchronize access
  /// to the underlying file. It can be used when, for example, write operations
  /// are split across multiple calls but must not be interleaved with writes on
  /// other threads.
  borrowing func withLock<R>(_ body: () throws -> R) rethrows -> R {
    try withUnsafeCFILEHandle { handle in
#if SWT_TARGET_OS_APPLE || os(Linux) || os(FreeBSD) || os(OpenBSD) || os(Android)
      flockfile(handle)
      defer {
        funlockfile(handle)
      }
#elseif os(Windows)
      _lock_file(handle)
      defer {
        _unlock_file(handle)
      }
#elseif os(WASI)
      // No file locking on WASI yet.
#else
#warning("Platform-specific implementation missing: cannot lock a file handle")
#endif
      return try body()
    }
  }
}

// MARK: - Reading

extension FileHandle {
  /// Read to the end of the file handle.
  ///
  /// - Returns: A copy of the contents of the file handle starting at the
  ///   current offset and ending at the end of the file.
  ///
  /// - Throws: Any error that occurred while reading the file.
  func readToEnd() throws -> [UInt8] {
    var result = [UInt8]()

    // If possible, reserve enough space in the resulting buffer to contain
    // the contents of the file being read.
    var size: Int?
#if SWT_TARGET_OS_APPLE || os(Linux) || os(FreeBSD) || os(OpenBSD) || os(Android) || os(WASI)
    withUnsafePOSIXFileDescriptor { fd in
      var s = stat()
      if let fd, 0 == fstat(fd, &s) {
        size = Int(exactly: s.st_size)
      }
    }
#elseif os(Windows)
    withUnsafeWindowsHANDLE { handle in
      var liSize = LARGE_INTEGER(QuadPart: 0)
      if let handle, GetFileSizeEx(handle, &liSize) {
        size = Int(exactly: liSize.QuadPart)
      }
    }
#endif
    if let size, size > 0 {
      result.reserveCapacity(size)
    }

    try withUnsafeCFILEHandle { file in
      try withUnsafeTemporaryAllocation(byteCount: 1024, alignment: 1) { buffer in
        repeat {
          let countRead = fread(buffer.baseAddress!, 1, buffer.count, file)
          if 0 != ferror(file) {
            throw CError(rawValue: swt_errno())
          }
          if countRead > 0 {
            let endIndex = buffer.index(buffer.startIndex, offsetBy: countRead)
            result.append(contentsOf: buffer[..<endIndex])
          }
        } while 0 == feof(file)
      }
    }

    return result
  }
}

// MARK: - Writing

extension FileHandle {
  /// Write a sequence of bytes to this file handle.
  ///
  /// - Parameters:
  ///   - bytes: The bytes to write. This untyped buffer is interpreted as a
  ///     sequence of `UInt8` values.
  ///   - flushAfterward: Whether or not to flush the file (with `fflush()`)
  ///     after writing. If `true`, `fflush()` is called even if an error
  ///     occurred while writing.
  ///
  /// - Throws: Any error that occurred while writing `bytes`. If an error
  ///   occurs while flushing the file, it is not thrown.
  func write(_ bytes: UnsafeBufferPointer<UInt8>, flushAfterward: Bool = true) throws {
    try withUnsafeCFILEHandle { file in
      defer {
        if flushAfterward {
          _ = fflush(file)
        }
      }

      let countWritten = fwrite(bytes.baseAddress!, MemoryLayout<UInt8>.stride, bytes.count, file)
      if countWritten < bytes.count {
        throw CError(rawValue: swt_errno())
      }
    }
  }

  /// Write a sequence of bytes to this file handle.
  ///
  /// - Parameters:
  ///   - bytes: The bytes to write.
  ///   - flushAfterward: Whether or not to flush the file (with `fflush()`)
  ///     after writing. If `true`, `fflush()` is called even if an error
  ///     occurred while writing.
  ///
  /// - Throws: Any error that occurred while writing `bytes`. If an error
  ///   occurs while flushing the file, it is not thrown.
  ///
  /// - Precondition: `bytes` must provide contiguous storage.
  func write(_ bytes: some Sequence<UInt8>, flushAfterward: Bool = true) throws {
    let hasContiguousStorage: Void? = try bytes.withContiguousStorageIfAvailable { bytes in
      try write(bytes, flushAfterward: flushAfterward)
    }
    precondition(hasContiguousStorage != nil, "byte sequence must provide contiguous storage: \(bytes)")
  }

  /// Write a sequence of bytes to this file handle.
  ///
  /// - Parameters:
  ///   - bytes: The bytes to write. This untyped buffer is interpreted as a
  ///     sequence of `UInt8` values.
  ///   - flushAfterward: Whether or not to flush the file (with `fflush()`)
  ///     after writing. If `true`, `fflush()` is called even if an error
  ///     occurred while writing.
  ///
  /// - Throws: Any error that occurred while writing `bytes`. If an error
  ///   occurs while flushing the file, it is not thrown.
  func write(_ bytes: UnsafeRawBufferPointer, flushAfterward: Bool = true) throws {
    try bytes.withMemoryRebound(to: UInt8.self) { bytes in
      try write(bytes, flushAfterward: flushAfterward)
    }
  }

  /// Write a string to this file handle.
  ///
  /// - Parameters:
  ///   - string: The string to write.
  ///   - flushAfterward: Whether or not to flush the file (with `fflush()`)
  ///     after writing. If `true`, `fflush()` is called even if an error
  ///     occurred while writing.
  ///
  /// - Throws: Any error that occurred while writing `string`. If an error
  ///   occurs while flushing the file, it is not thrown.
  ///
  /// `string` is converted to a UTF-8 C string (UTF-16 on Windows) and written
  /// to this file handle.
  func write(_ string: String, flushAfterward: Bool = true) throws {
    try withUnsafeCFILEHandle { file in
      defer {
        if flushAfterward {
          _ = fflush(file)
        }
      }

      try string.withCString { string in
        if EOF == fputs(string, file) {
          throw CError(rawValue: swt_errno())
        }
      }
    }
  }
}

#if !SWT_NO_PIPES
// MARK: - Pipes

#if !SWT_TARGET_OS_APPLE && !os(Windows) && !SWT_NO_DYNAMIC_LINKING
/// Create a pipe with flags.
///
/// This function declaration is provided because `pipe2()` is only declared if
/// `_GNU_SOURCE` is set, but setting it causes build errors due to conflicts
/// with Swift's Glibc module.
private let _pipe2 = symbol(named: "pipe2").map {
  castCFunction(at: $0, to: (@convention(c) (UnsafeMutablePointer<CInt>, CInt) -> CInt).self)
}
#endif

extension FileHandle {
  /// Make a pipe connecting two new file handles.
  ///
  /// - Parameters:
  ///   - readEnd: On successful return, set to a file handle that can read
  ///     bytes written to `writeEnd`. On failure, set to `nil`.
  ///   - writeEnd: On successful return, set to a file handle that can write
  ///     bytes read by `writeEnd`. On failure, set to `nil`.
  ///
  /// - Throws: Any error preventing creation of the pipe or corresponding file
  ///   handles. If an error occurs, both `readEnd` and `writeEnd` are set to
  ///   `nil` to avoid an inconsistent state.
  ///
  /// - Bug: This function should return a tuple containing the file handles
  ///   instead of returning them via `inout` arguments. Swift does not support
  ///   tuples with move-only elements. ([104669935](rdar://104669935))
  ///
  /// By default, the resulting file handles are not inherited by any child
  /// processes (that is, `FD_CLOEXEC` is set on POSIX-like systems and
  /// `HANDLE_FLAG_INHERIT` is cleared on Windows.).
  static func makePipe(readEnd: inout FileHandle?, writeEnd: inout FileHandle?) throws {
#if !os(Windows)
    var pipe2Called = false
#endif

    var (fdReadEnd, fdWriteEnd) = try withUnsafeTemporaryAllocation(of: CInt.self, capacity: 2) { fds in
#if os(Windows)
      guard 0 == _pipe(fds.baseAddress, 0, _O_BINARY | _O_NOINHERIT) else {
        throw CError(rawValue: swt_errno())
      }
#else
#if !SWT_TARGET_OS_APPLE && !os(Windows) && !SWT_NO_DYNAMIC_LINKING
      if let _pipe2 {
        guard 0 == _pipe2(fds.baseAddress!, O_CLOEXEC) else {
          throw CError(rawValue: swt_errno())
        }
        pipe2Called = true
      }
#endif

      if !pipe2Called {
        // pipe2() is not available. Use pipe() instead and simulate O_CLOEXEC
        // to the best of our ability.
        guard 0 == pipe(fds.baseAddress!) else {
          throw CError(rawValue: swt_errno())
        }
      }
#endif
      return (fds[0], fds[1])
    }
    defer {
      Self._close(fdReadEnd)
      Self._close(fdWriteEnd)
    }

#if !os(Windows)
    if !pipe2Called {
      // pipe2() is not available. Use pipe() instead and simulate O_CLOEXEC
      // to the best of our ability.
      try setFD_CLOEXEC(true, onFileDescriptor: fdReadEnd)
      try setFD_CLOEXEC(true, onFileDescriptor: fdWriteEnd)
    }
#endif

    do {
      defer {
        fdReadEnd = -1
      }
      try readEnd = FileHandle(unsafePOSIXFileDescriptor: fdReadEnd, mode: "rb")
      defer {
        fdWriteEnd = -1
      }
      try writeEnd = FileHandle(unsafePOSIXFileDescriptor: fdWriteEnd, mode: "wb")
    } catch {
      // Don't leak file handles! Ensure we've cleared both pointers before
      // returning so the state is consistent in the caller.
      readEnd = nil
      writeEnd = nil

      throw error
    }
  }
}
#endif

// MARK: - Attributes

extension FileHandle {
  /// Is this file handle a TTY or PTY?
  var isTTY: Bool {
#if SWT_TARGET_OS_APPLE || os(Linux) || os(FreeBSD) || os(OpenBSD) || os(Android) || os(WASI)
    // If stderr is a TTY and TERM is set, that's good enough for us.
    withUnsafePOSIXFileDescriptor { fd in
      if let fd, 0 != isatty(fd), let term = Environment.variable(named: "TERM"), !term.isEmpty {
        return true
      }
      return false
    }
#elseif os(Windows)
    // If there is a console buffer associated with the file handle, then it's a
    // console.
    return withUnsafeWindowsHANDLE { handle in
      guard let handle else {
        return false
      }
      var screenBufferInfo = CONSOLE_SCREEN_BUFFER_INFO()
      return GetConsoleScreenBufferInfo(handle, &screenBufferInfo)
    }
#else
#warning("Platform-specific implementation missing: cannot tell if a file is a TTY")
    return false
#endif
  }

#if !SWT_NO_PIPES
  /// Is this file handle a pipe or FIFO?
  var isPipe: Bool {
#if SWT_TARGET_OS_APPLE || os(Linux) || os(FreeBSD) || os(OpenBSD) || os(Android)
    withUnsafePOSIXFileDescriptor { fd in
      guard let fd else {
        return false
      }
      var statStruct = stat()
      return (0 == fstat(fd, &statStruct) && swt_S_ISFIFO(mode_t(statStruct.st_mode)))
    }
#elseif os(Windows)
    return withUnsafeWindowsHANDLE { handle in
      guard let handle else {
        return false
      }
      return FILE_TYPE_PIPE == GetFileType(handle)
    }
#else
#warning("Platform-specific implementation missing: cannot tell if a file is a pipe")
    return false
#endif
  }
#endif
}

// MARK: - General path utilities

/// Append a path component to a path.
///
/// - Parameters:
///   - pathComponent: The path component to append.
///   - path: The path to which `pathComponent` should be appended.
///
/// - Returns: The full path to `pathComponent`, or `nil` if the resulting
///   string could not be created.
func appendPathComponent(_ pathComponent: String, to path: String) -> String {
#if os(Windows)
  path.withCString(encodedAs: UTF16.self) { path in
    pathComponent.withCString(encodedAs: UTF16.self) { pathComponent in
      withUnsafeTemporaryAllocation(of: wchar_t.self, capacity: (wcslen(path) + wcslen(pathComponent)) * 2 + 1) { buffer in
        _ = wcscpy_s(buffer.baseAddress, buffer.count, path)
        _ = PathCchAppendEx(buffer.baseAddress, buffer.count, pathComponent, ULONG(PATHCCH_ALLOW_LONG_PATHS.rawValue))
        return (String.decodeCString(buffer.baseAddress, as: UTF16.self)?.result)!
      }
    }
  }
#else
  "\(path)/\(pathComponent)"
#endif
}

/// Check if a file exists at a given path.
///
/// - Parameters:
///   - path: The path to check.
///
/// - Returns: Whether or not the path `path` exists on disk.
func fileExists(atPath path: String) -> Bool {
#if os(Windows)
  path.withCString(encodedAs: UTF16.self) { path in
    PathFileExistsW(path)
  }
#else
  0 == access(path, F_OK)
#endif
}

/// Resolve a relative path or a path containing symbolic links to a canonical
/// absolute path.
///
/// - Parameters:
///   - path: The path to resolve.
///
/// - Returns: A fully resolved copy of `path`. If `path` is already fully
///   resolved, the resulting string may differ slightly but refers to the same
///   file system object. If the path could not be resolved, returns `nil`.
func canonicalizePath(_ path: String) -> String? {
#if SWT_TARGET_OS_APPLE || os(Linux) || os(FreeBSD) || os(OpenBSD) || os(Android) || os(WASI)
  path.withCString { path in
    if let resolvedCPath = realpath(path, nil) {
      defer {
        free(resolvedCPath)
      }
      return String(validatingCString: resolvedCPath)
    }
    return nil
  }
#elseif os(Windows)
  path.withCString(encodedAs: UTF16.self) { path in
    if let resolvedCPath = _wfullpath(nil, path, 0) {
      defer {
        free(resolvedCPath)
      }
      return String.decodeCString(resolvedCPath, as: UTF16.self)?.result
    }
    return nil
  }
#else
#warning("Platform-specific implementation missing: cannot resolve paths")
  return nil
#endif
}

#if SWT_TARGET_OS_APPLE || os(Linux) || os(FreeBSD) || os(OpenBSD) || os(Android)
/// Set the given file descriptor's `FD_CLOEXEC` flag.
///
/// - Parameters:
///   - flag: The new value of `fd`'s `FD_CLOEXEC` flag.
///   - fd: The file descriptor.
///
/// - Throws: Any error that occurred while setting the flag.
func setFD_CLOEXEC(_ flag: Bool, onFileDescriptor fd: CInt) throws {
  switch swt_getfdflags(fd) {
  case -1:
    // An error occurred reading the flags for this file descriptor.
    throw CError(rawValue: swt_errno())
  case let oldValue:
    let newValue = if flag {
      oldValue | FD_CLOEXEC
    } else {
      oldValue & ~FD_CLOEXEC
    }
    if oldValue == newValue {
      // No need to make a second syscall as nothing has changed.
      return
    }
    if -1 == swt_setfdflags(fd, newValue) {
      // An error occurred setting the flags for this file descriptor.
      throw CError(rawValue: swt_errno())
    }
  }
}
#endif

/// The path to the root directory of the boot volume.
///
/// On Windows, this string is usually of the form `"C:\"`. On UNIX-like
/// platforms, it is always equal to `"/"`.
let rootDirectoryPath: String = {
#if os(Windows)
  var result: String?

  // The boot volume is, except in some legacy scenarios, the volume that
  // contains the system Windows directory. For an explanation of the difference
  // between the Windows directory and the _system_ Windows directory, see
  // https://devblogs.microsoft.com/oldnewthing/20140723-00/?p=423 .
  let count = GetSystemWindowsDirectoryW(nil, 0)
  if count > 0 {
    withUnsafeTemporaryAllocation(of: wchar_t.self, capacity: Int(count) + 1) { buffer in
      _ = GetSystemWindowsDirectoryW(buffer.baseAddress!, UINT(buffer.count))
      let rStrip = PathCchStripToRoot(buffer.baseAddress!, buffer.count)
      if rStrip == S_OK || rStrip == S_FALSE {
        result = String.decodeCString(buffer.baseAddress!, as: UTF16.self)?.result
      }
    }
  }

  // If we weren't able to get a path, fall back to "C:\" on the assumption that
  // it's the common case and most likely correct.
  return result ?? #"C:\"#
#else
  return "/"
#endif
}()
#endif
