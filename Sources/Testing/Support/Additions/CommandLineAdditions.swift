//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

private import _TestingInternals

extension CommandLine {
  /// The path to the current process' executable.
  static var executablePath: String {
    get throws {
#if SWT_TARGET_OS_APPLE
      var result: String?
#if DEBUG
      var bufferCount = UInt32(1) // force looping
#else
      var bufferCount = UInt32(PATH_MAX)
#endif
      while result == nil {
        withUnsafeTemporaryAllocation(of: CChar.self, capacity: Int(bufferCount)) { buffer in
          // _NSGetExecutablePath returns 0 on success and -1 if bufferCount is
          // too small. If that occurs, we'll return nil here and loop with the
          // new value of bufferCount.
          if 0 == _NSGetExecutablePath(buffer.baseAddress, &bufferCount) {
            result = String(cString: buffer.baseAddress!)
          }
        }
      }
      return result!
#elseif os(Linux) || os(Android)
      var result: String?
#if DEBUG
      var bufferCount = Int(1) // force looping
#else
      var bufferCount = Int(PATH_MAX)
#endif
      while result == nil {
        try withUnsafeTemporaryAllocation(of: CChar.self, capacity: bufferCount) { buffer in
          let readCount = readlink("/proc/self/exe", buffer.baseAddress!, buffer.count)
          guard readCount >= 0 else {
            throw CError(rawValue: swt_errno())
          }
          if readCount < buffer.count {
            buffer[readCount] = 0 // NUL-terminate the string.
            result = String(cString: buffer.baseAddress!)
          } else {
            bufferCount += Int(PATH_MAX) // add more space and try again
          }
        }
      }
      return result!
#elseif os(FreeBSD)
      var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PATHNAME, -1]
      return try mib.withUnsafeMutableBufferPointer { mib in
        var bufferCount = 0
        guard 0 == sysctl(mib.baseAddress!, .init(mib.count), nil, &bufferCount, nil, 0) else {
          throw CError(rawValue: swt_errno())
        }
        return try withUnsafeTemporaryAllocation(of: CChar.self, capacity: bufferCount) { buffer in
          guard 0 == sysctl(mib.baseAddress!, .init(mib.count), buffer.baseAddress!, &bufferCount, nil, 0) else {
            throw CError(rawValue: swt_errno())
          }
          return String(cString: buffer.baseAddress!)
        }
      }
#elseif os(OpenBSD)
      // OpenBSD does not have API to get a path to the running executable. Use
      // arguments[0]. We do a basic sniff test for a path-like string, and
      // prepend the early CWD if it looks like a relative path, but otherwise
      // return argv[0] verbatim.
      guard var argv0 = arguments.first, argv0.contains("/") else {
        throw CError(rawValue: ENOEXEC)
      }
      if argv0.first != "/",
         let earlyCWD = swt_getEarlyCWD().flatMap(String.init(validatingCString:)),
         !earlyCWD.isEmpty {
        argv0 = "\(earlyCWD)/\(argv0)"
      }
      return argv0
#elseif os(Windows)
      var result: String?
#if DEBUG
      var bufferCount = Int(1) // force looping
#else
      var bufferCount = Int(MAX_PATH)
#endif
      while result == nil {
        try withUnsafeTemporaryAllocation(of: CWideChar.self, capacity: bufferCount) { buffer in
          SetLastError(DWORD(ERROR_SUCCESS))
          _ = GetModuleFileNameW(nil, buffer.baseAddress!, DWORD(buffer.count))
          switch GetLastError() {
          case DWORD(ERROR_SUCCESS):
            result = String.decodeCString(buffer.baseAddress!, as: UTF16.self)?.result
            if result == nil {
              throw Win32Error(rawValue: DWORD(ERROR_ILLEGAL_CHARACTER))
            }
          case DWORD(ERROR_INSUFFICIENT_BUFFER):
            bufferCount += Int(MAX_PATH)
          case let errorCode:
            throw Win32Error(rawValue: errorCode)
          }
        }
      }
      return result!
#elseif os(WASI)
      // WASI does not really have the concept of a file system path to the main
      // executable, so simply return the first argument--presumably the program
      // name, but as you know this is not guaranteed by the C standard!
      return arguments[0]
#else
#warning("Platform-specific implementation missing: executable path unavailable")
      throw SystemError(description: "The executable path of the current process could not be determined.")
#endif
    }
  }
}
