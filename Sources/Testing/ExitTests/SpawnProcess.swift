//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024–2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

internal import _TestingInternals

#if !SWT_NO_PROCESS_SPAWNING
#if SWT_NO_FILE_IO
#error("Platform-specific misconfiguration: support for process spawning requires support for file I/O")
#endif

/// A platform-specific value identifying a process running on the current
/// system.
#if SWT_TARGET_OS_APPLE || os(Linux) || os(FreeBSD) || os(OpenBSD)
typealias ProcessID = pid_t
#elseif os(Windows)
typealias ProcessID = HANDLE
#else
#warning("Platform-specific implementation missing: process IDs unavailable")
typealias ProcessID = Never
#endif

#if os(Linux) && !SWT_NO_DYNAMIC_LINKING
/// Close file descriptors above a given value when spawing a new process.
///
/// This symbol is provided because the underlying function was added to glibc
/// relatively recently and may not be available on all targets. Checking
/// `__GLIBC_PREREQ()` is insufficient because `_DEFAULT_SOURCE` may not be
/// defined at the point spawn.h is first included.
private let _posix_spawn_file_actions_addclosefrom_np = symbol(named: "posix_spawn_file_actions_addclosefrom_np").map {
  castCFunction(at: $0, to: (@convention(c) (UnsafeMutablePointer<posix_spawn_file_actions_t>, CInt) -> CInt).self)
}
#endif

/// Spawn a child process.
///
/// - Parameters:
///   - executablePath: The path to the executable to spawn.
///   - arguments: The arguments to pass to the executable, not including the
///     executable path.
///   - environment: The environment block to pass to the executable.
///   - standardInput: If not `nil`, a file handle the child process should
///     inherit as its standard input stream. This file handle must be backed
///     by a file descriptor and be open for reading.
///   - standardOutput: If not `nil`, a file handle the child process should
///     inherit as its standard output stream. This file handle must be backed
///     by a file descriptor and be open for writing.
///   - standardError: If not `nil`, a file handle the child process should
///     inherit as its standard error stream. This file handle must be backed
///     by a file descriptor and be open for writing.
///   - additionalFileHandles: A collection of file handles to inherit in the
///     child process.
///
/// - Returns: A value identifying the process that was spawned. The caller must
///   eventually pass this value to ``wait(for:)`` to avoid leaking system
///   resources.
///
/// - Throws: Any error that prevented the process from spawning.
func spawnExecutable(
  atPath executablePath: String,
  arguments: [String],
  environment: [String: String],
  standardInput: borrowing FileHandle? = nil,
  standardOutput: borrowing FileHandle? = nil,
  standardError: borrowing FileHandle? = nil,
  additionalFileHandles: [UnsafePointer<FileHandle>] = []
) throws -> ProcessID {
  // Darwin and Linux differ in their optionality for the posix_spawn types we
  // use, so use this typealias to paper over the differences.
#if SWT_TARGET_OS_APPLE || os(FreeBSD) || os(OpenBSD)
  typealias P<T> = T?
#elseif os(Linux)
  typealias P<T> = T
#endif

#if SWT_TARGET_OS_APPLE || os(Linux) || os(FreeBSD) || os(OpenBSD)
  return try withUnsafeTemporaryAllocation(of: P<posix_spawn_file_actions_t>.self, capacity: 1) { fileActions in
    let fileActions = fileActions.baseAddress!
    let fileActionsInitialized = posix_spawn_file_actions_init(fileActions)
    guard 0 == fileActionsInitialized else {
      throw CError(rawValue: fileActionsInitialized)
    }
    defer {
      _ = posix_spawn_file_actions_destroy(fileActions)
    }

    return try withUnsafeTemporaryAllocation(of: P<posix_spawnattr_t>.self, capacity: 1) { attrs in
      let attrs = attrs.baseAddress!
      let attrsInitialized = posix_spawnattr_init(attrs)
      guard 0 == attrsInitialized else {
        throw CError(rawValue: attrsInitialized)
      }
      defer {
        _ = posix_spawnattr_destroy(attrs)
      }

      // Flags to set on the attributes value before spawning the process.
      var flags = CShort(0)

      // Reset signal handlers to their defaults.
      withUnsafeTemporaryAllocation(of: sigset_t.self, capacity: 1) { noSignals in
        let noSignals = noSignals.baseAddress!
        sigemptyset(noSignals)
        posix_spawnattr_setsigmask(attrs, noSignals)
        flags |= CShort(POSIX_SPAWN_SETSIGMASK)
      }
      withUnsafeTemporaryAllocation(of: sigset_t.self, capacity: 1) { allSignals in
        let allSignals = allSignals.baseAddress!
        sigfillset(allSignals)
        posix_spawnattr_setsigdefault(attrs, allSignals);
        flags |= CShort(POSIX_SPAWN_SETSIGDEF)
      }

      // Forward standard I/O streams and any explicitly added file handles.
      var highestFD = max(STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO)
      func inherit(_ fileHandle: borrowing FileHandle, as standardFD: CInt? = nil) throws {
        try fileHandle.withUnsafePOSIXFileDescriptor { fd in
          guard let fd else {
            throw SystemError(description: "A child process cannot inherit a file handle without an associated file descriptor. Please file a bug report at https://github.com/swiftlang/swift-testing/issues/new")
          }
          if let standardFD, standardFD != fd {
            _ = posix_spawn_file_actions_adddup2(fileActions, fd, standardFD)
          } else {
#if SWT_TARGET_OS_APPLE
            _ = posix_spawn_file_actions_addinherit_np(fileActions, fd)
#else
            // posix_spawn_file_actions_adddup2() will automatically clear
            // FD_CLOEXEC after forking but before execing even if the old and
            // new file descriptors are equal. This behavior is supported by
            // Glibc ≥ 2.29, FreeBSD, OpenBSD, and Android (Bionic) and is
            // standardized in POSIX.1-2024 (see https://pubs.opengroup.org/onlinepubs/9799919799/functions/posix_spawn_file_actions_adddup2.html
            // and https://www.austingroupbugs.net/view.php?id=411).
            _ = posix_spawn_file_actions_adddup2(fileActions, fd, fd)
#if canImport(Glibc) && !os(FreeBSD) && !os(OpenBSD)
            if _slowPath(glibcVersion.major < 2 || (glibcVersion.major == 2 && glibcVersion.minor < 29)) {
              // This system is using an older version of glibc that does not
              // implement FD_CLOEXEC clearing in posix_spawn_file_actions_adddup2(),
              // so we must clear it here in the parent process.
              try setFD_CLOEXEC(false, onFileDescriptor: fd)
            }
#endif
#endif
            highestFD = max(highestFD, fd)
          }
        }
      }
      func inherit(_ fileHandle: borrowing FileHandle?, as standardFD: CInt? = nil) throws {
        if fileHandle != nil {
          try inherit(fileHandle!, as: standardFD)
        } else if let standardFD {
          let mode = (standardFD == STDIN_FILENO) ? O_RDONLY : O_WRONLY
          _ = posix_spawn_file_actions_addopen(fileActions, standardFD, "/dev/null", mode, 0)
        }
      }

      try inherit(standardInput, as: STDIN_FILENO)
      try inherit(standardOutput, as: STDOUT_FILENO)
      try inherit(standardError, as: STDERR_FILENO)
      for additionalFileHandle in additionalFileHandles {
        try inherit(additionalFileHandle.pointee)
      }

#if SWT_TARGET_OS_APPLE
      // Close all other file descriptors open in the parent.
      flags |= CShort(POSIX_SPAWN_CLOEXEC_DEFAULT)
#elseif os(Linux)
#if !SWT_NO_DYNAMIC_LINKING
      // This platform doesn't have POSIX_SPAWN_CLOEXEC_DEFAULT, but we can at
      // least close all file descriptors higher than the highest inherited one.
      _ = _posix_spawn_file_actions_addclosefrom_np?(fileActions, highestFD + 1)
#endif
#elseif os(FreeBSD)
      // Like Linux, this platform doesn't have POSIX_SPAWN_CLOEXEC_DEFAULT.
      // Unlike Linux, all non-EOL FreeBSD versions (≥13.1) support
      // `posix_spawn_file_actions_addclosefrom_np`, and FreeBSD does not use
      // glibc nor guard symbols behind `_DEFAULT_SOURCE`.
      _ = posix_spawn_file_actions_addclosefrom_np(fileActions, highestFD + 1)
#elseif os(OpenBSD)
      // OpenBSD does not have posix_spawn_file_actions_addclosefrom_np().
      // However, it does have closefrom(2), which we can call from within the
      // spawned child process if we control its execution.
      var environment = environment
      environment["SWT_CLOSEFROM"] = String(describing: highestFD + 1)
#else
#warning("Platform-specific implementation missing: cannot close unused file descriptors")
#endif

#if SWT_TARGET_OS_APPLE && DEBUG
      // Start the process suspended so we can attach a debugger if needed.
      flags |= CShort(POSIX_SPAWN_START_SUSPENDED)
#endif

      // Set flags; make sure to keep this call below any code that might modify
      // the flags mask!
      _ = posix_spawnattr_setflags(attrs, flags)

      var argv: [UnsafeMutablePointer<CChar>?] = [strdup(executablePath)]
      argv += arguments.lazy.map { strdup($0) }
      argv.append(nil)
      defer {
        for arg in argv {
          free(arg)
        }
      }

      var environ: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") }
      environ.append(nil)
      defer {
        for environ in environ {
          free(environ)
        }
      }

      var pid = pid_t()
      let processSpawned = posix_spawn(&pid, executablePath, fileActions, attrs, argv, environ)
      guard 0 == processSpawned else {
        throw CError(rawValue: processSpawned)
      }
#if SWT_TARGET_OS_APPLE && DEBUG
      // Resume the process.
      _ = kill(pid, SIGCONT)
#endif
      return pid
    }
  }
#elseif os(Windows)
  return try _withStartupInfoEx(attributeCount: 1) { startupInfo in
    func inherit(_ fileHandle: borrowing FileHandle) throws -> HANDLE? {
      try fileHandle.withUnsafeWindowsHANDLE { windowsHANDLE in
        guard let windowsHANDLE else {
          throw SystemError(description: "A child process cannot inherit a file handle without an associated Windows handle. Please file a bug report at https://github.com/swiftlang/swift-testing/issues/new")
        }

        // Ensure the file handle can be inherited by the child process.
        guard SetHandleInformation(windowsHANDLE, DWORD(HANDLE_FLAG_INHERIT), DWORD(HANDLE_FLAG_INHERIT)) else {
          throw Win32Error(rawValue: GetLastError())
        }

        return windowsHANDLE
      }
    }
    func inherit(_ fileHandle: borrowing FileHandle?) throws -> HANDLE? {
      if fileHandle != nil {
        return try inherit(fileHandle!)
      } else {
        return nil
      }
    }

    // Forward standard I/O streams.
    startupInfo.pointee.StartupInfo.hStdInput = try inherit(standardInput)
    startupInfo.pointee.StartupInfo.hStdOutput = try inherit(standardOutput)
    startupInfo.pointee.StartupInfo.hStdError = try inherit(standardError)
    startupInfo.pointee.StartupInfo.dwFlags |= STARTF_USESTDHANDLES

    // Ensure standard I/O streams and any explicitly added file handles are
    // inherited by the child process.
    var inheritedHandles = [HANDLE?](repeating: nil, count: additionalFileHandles.count + 3)
    inheritedHandles[0] = startupInfo.pointee.StartupInfo.hStdInput
    inheritedHandles[1] = startupInfo.pointee.StartupInfo.hStdOutput
    inheritedHandles[2] = startupInfo.pointee.StartupInfo.hStdError
    for i in 0 ..< additionalFileHandles.count {
      inheritedHandles[i + 3] = try inherit(additionalFileHandles[i].pointee)
    }
    inheritedHandles = inheritedHandles.compactMap(\.self)

    return try inheritedHandles.withUnsafeMutableBufferPointer { inheritedHandles in
      _ = UpdateProcThreadAttribute(
        startupInfo.pointee.lpAttributeList,
        0,
        swt_PROC_THREAD_ATTRIBUTE_HANDLE_LIST(),
        inheritedHandles.baseAddress!,
        SIZE_T(MemoryLayout<HANDLE>.stride * inheritedHandles.count),
        nil,
        nil
      )

      let commandLine = _escapeCommandLine(CollectionOfOne(executablePath) + arguments)
      let environ = environment.map { "\($0.key)=\($0.value)" }.joined(separator: "\0") + "\0\0"

      var flags = DWORD(CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT | EXTENDED_STARTUPINFO_PRESENT)
#if DEBUG
      // Start the process suspended so we can attach a debugger if needed.
      flags |= DWORD(CREATE_SUSPENDED)
#endif

      return try commandLine.withCString(encodedAs: UTF16.self) { commandLine in
        try environ.withCString(encodedAs: UTF16.self) { environ in
          var processInfo = PROCESS_INFORMATION()

          guard CreateProcessW(
            nil,
            .init(mutating: commandLine),
            nil,
            nil,
            true, // bInheritHandles
            flags,
            .init(mutating: environ),
            nil,
            startupInfo.pointer(to: \.StartupInfo)!,
            &processInfo
          ) else {
            throw Win32Error(rawValue: GetLastError())
          }

#if DEBUG
          // Resume the process.
          _ = ResumeThread(processInfo.hThread!)
#endif

          _ = CloseHandle(processInfo.hThread)
          return processInfo.hProcess!
        }
      }
    }
  }
#else
#warning("Platform-specific implementation missing: process spawning unavailable")
  throw SystemError(description: "Exit tests are unimplemented on this platform.")
#endif
}

// MARK: -

#if os(Windows)
/// Create a temporary instance of `STARTUPINFOEXW` to pass to
/// `CreateProcessW()`.
///
/// - Parameters:
///   - attributeCount: The number of attributes to make space for in the
///     resulting structure's attribute list.
///   - body: A function to invoke. A temporary, mutable pointer to an instance
///     of `STARTUPINFOEXW` is passed to this function.
///
/// - Returns: Whatever is returned by `body`.
///
/// - Throws: Whatever is thrown while creating the startup info structure or
///   its attribute list, or whatever is thrown by `body`.
private func _withStartupInfoEx<R>(attributeCount: Int = 0, _ body: (UnsafeMutablePointer<STARTUPINFOEXW>) throws -> R) throws -> R {
  // Initialize the startup info structure.
  var startupInfo = STARTUPINFOEXW()
  startupInfo.StartupInfo.cb = DWORD(MemoryLayout.size(ofValue: startupInfo))

  guard attributeCount > 0 else {
    return try body(&startupInfo)
  }

  // Initialize an attribute list of sufficient size for the specified number of
  // attributes. Alignment is a problem because LPPROC_THREAD_ATTRIBUTE_LIST is
  // an opaque pointer and we don't know the alignment of the underlying data.
  // We *should* use the alignment of C's max_align_t, but it is defined using a
  // C++ using statement on Windows and isn't imported into Swift. So, 16 it is.
  var attributeListByteCount = SIZE_T(0)
  _ = InitializeProcThreadAttributeList(nil, DWORD(attributeCount), 0, &attributeListByteCount)
  return try withUnsafeTemporaryAllocation(byteCount: Int(attributeListByteCount), alignment: 16) { attributeList in
    let attributeList = LPPROC_THREAD_ATTRIBUTE_LIST(attributeList.baseAddress!)
    guard InitializeProcThreadAttributeList(attributeList, DWORD(attributeCount), 0, &attributeListByteCount) else {
      throw Win32Error(rawValue: GetLastError())
    }
    defer {
      DeleteProcThreadAttributeList(attributeList)
    }
    startupInfo.lpAttributeList = attributeList

    return try body(&startupInfo)
  }
}

/// Construct an escaped command line string suitable for passing to
/// `CreateProcessW()`.
///
/// - Parameters:
///   - arguments: The arguments, including the executable path, to include in
///     the command line string.
///
/// - Returns: A command line string. This string can later be parsed with
///   `CommandLineToArgvW()`.
///
/// Windows processes are responsible for handling their own command-line
/// escaping. This function is adapted from the code in
/// swift-corelibs-foundation (see `quoteWindowsCommandLine()`) which was
/// itself adapted from code [published by Microsoft](https://learn.microsoft.com/en-us/archive/blogs/twistylittlepassagesallalike/everyone-quotes-command-line-arguments-the-wrong-way)
/// (ADO 8992662).
private func _escapeCommandLine(_ arguments: [String]) -> String {
  return arguments.lazy
    .map { arg in
      if !arg.contains(where: {" \t\n\"".contains($0)}) {
        return arg
      }

      var quoted = "\""
      var unquoted = arg.unicodeScalars
      while !unquoted.isEmpty {
        guard let firstNonBackslash = unquoted.firstIndex(where: { $0 != "\\" }) else {
          let backslashCount = unquoted.count
          quoted.append(String(repeating: "\\", count: backslashCount * 2))
          break
        }
        let backslashCount = unquoted.distance(from: unquoted.startIndex, to: firstNonBackslash)
        if (unquoted[firstNonBackslash] == "\"") {
          quoted.append(String(repeating: "\\", count: backslashCount * 2 + 1))
          quoted.append(String(unquoted[firstNonBackslash]))
        } else {
          quoted.append(String(repeating: "\\", count: backslashCount))
          quoted.append(String(unquoted[firstNonBackslash]))
        }
        unquoted.removeFirst(backslashCount + 1)
      }
      quoted.append("\"")
      return quoted
    }.joined(separator: " ")
}
#endif

/// Spawn a child process and wait for it to terminate.
///
/// - Parameters:
///   - executablePath: The path to the executable to spawn.
///   - arguments: The arguments to pass to the executable, not including the
///     executable path.
///   - environment: The environment block to pass to the executable.
///
/// - Returns: The exit status of the spawned process.
///
/// - Throws: Any error that prevented the process from spawning or its exit
///   condition from being read.
///
/// This function is a convenience that spawns the given process and waits for
/// it to terminate. It is primarily for use by other targets in this package
/// such as its cross-import overlays.
package func spawnExecutableAtPathAndWait(
  _ executablePath: String,
  arguments: [String] = [],
  environment: [String: String] = [:]
) async throws -> ExitStatus {
  let processID = try spawnExecutable(atPath: executablePath, arguments: arguments, environment: environment)
  return try await wait(for: processID)
}
#endif
