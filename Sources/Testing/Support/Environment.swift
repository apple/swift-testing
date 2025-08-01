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

/// A type describing the environment of the current process.
///
/// This type can be used to access the current process' environment variables.
///
/// This type is not part of the public interface of the testing library.
package enum Environment {
#if SWT_NO_ENVIRONMENT_VARIABLES
  /// Storage for the simulated environment.
  ///
  /// The mechanism by which this dictionary is initially populated depends on
  /// platform-specific implementation details. Callers should not read from
  /// this dictionary directly; use ``variable(named:)`` or ``flag(named:)``
  /// instead.
  static let simulatedEnvironment = Locked<[String: String]>()
#endif

  /// Split a string containing an environment variable's name and value into
  /// two strings.
  ///
  /// - Parameters:
  ///   - row: The environment variable, of the form `"KEY=VALUE"`.
  ///
  /// - Returns: The name and value of the environment variable, or `nil` if it
  ///   could not be parsed.
  private static func _splitEnvironmentVariable(_ row: String) -> (key: String, value: String)? {
    row.firstIndex(of: "=").map { equalsIndex in
      let key = String(row[..<equalsIndex])
      let value = String(row[equalsIndex...].dropFirst())
      return (key, value)
    }
  }

#if SWT_TARGET_OS_APPLE || os(Linux) || os(FreeBSD) || os(OpenBSD) || os(Android) || os(WASI)
  /// Get all environment variables from a POSIX environment block.
  ///
  /// - Parameters:
  ///   - environ: The environment block, i.e. the global `environ` variable.
  ///
  /// - Returns: A dictionary of environment variables.
  private static func _get(fromEnviron environ: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> [String: String] {
    var result = [String: String]()

    for i in 0... {
      guard let rowp = environ[i] else {
        break
      }

      if let row = String(validatingCString: rowp),
         let (key, value) = _splitEnvironmentVariable(row) {
        result[key] = value
      }
    }

    return result
  }
#endif

#if SWT_TARGET_OS_APPLE && !SWT_NO_ENVIRONMENT_VARIABLES && !SWT_NO_DYNAMIC_LINKING
  /// A non-POSIX/non-portable function that locks for access to `environ`.
  ///
  /// If the `environ_lock_np()` function is not available on the current
  /// system, the value of this property is `nil`.
  private static let _environ_lock_np = {
    symbol(named: "environ_lock_np").map {
      castCFunction(at: $0, to: (@convention(c) () -> Void).self)
    }
  }()

  /// A non-POSIX/non-portable function that unlocks after access to `environ`.
  ///
  /// If the `environ_unlock_np()` function is not available on the current
  /// system, the value of this property is `nil`.
  private static let _environ_unlock_np = {
    symbol(named: "environ_unlock_np").map {
      castCFunction(at: $0, to: (@convention(c) () -> Void).self)
    }
  }()
#endif

  /// Get all environment variables in the current process.
  ///
  /// - Returns: A copy of the current process' environment dictionary.
  package static func get() -> [String: String] {
#if SWT_NO_ENVIRONMENT_VARIABLES
    simulatedEnvironment.rawValue
#elseif SWT_TARGET_OS_APPLE
#if !SWT_NO_DYNAMIC_LINKING
    _environ_lock_np?()
    defer {
      _environ_unlock_np?()
    }
#endif
    return _get(fromEnviron: _NSGetEnviron()!.pointee!)
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD) || os(Android)
    _get(fromEnviron: swt_environ())
#elseif os(WASI)
    _get(fromEnviron: __wasilibc_get_environ())
#elseif os(Windows)
    guard let environ = GetEnvironmentStringsW() else {
      return [:]
    }
    defer {
      FreeEnvironmentStringsW(environ)
    }

    var result = [String: String]()
    var rowp = environ
    while rowp.pointee != 0 {
      defer {
        rowp += wcslen(rowp) + 1
      }
      if let row = String.decodeCString(rowp, as: UTF16.self)?.result,
         let (key, value) = _splitEnvironmentVariable(row) {
        result[key] = value
      }
    }
    return result
#else
#warning("Platform-specific implementation missing: environment variables unavailable")
    return [:]
#endif
  }

  /// Get the environment variable with the specified name.
  ///
  /// - Parameters:
  ///   - name: The name of the environment variable.
  ///
  /// - Returns: The value of the specified environment variable, or `nil` if it
  ///   is not set for the current process.
  package static func variable(named name: String) -> String? {
#if SWT_NO_ENVIRONMENT_VARIABLES
    simulatedEnvironment.rawValue[name]
#elseif SWT_TARGET_OS_APPLE && !SWT_NO_DYNAMIC_LINKING
    // Acquire the `environ` lock if possible, then look for the right variable
    // in the block. This ensures we still hold the lock when we convert the
    // found C string to a Swift string, which we can't do with getenv(). If the
    // lock is unavailable, then this implementation is equivalent to Darwin's
    // getenv() implementation.
    _environ_lock_np?()
    defer {
      _environ_unlock_np?()
    }
    let environ = _NSGetEnviron()!.pointee!

    return name.withCString { name in
      for i in 0... {
        guard let rowp = environ[i] else {
          break
        }

        if let equals = strchr(rowp, CInt(UInt8(ascii: "="))) {
          let keyLength = UnsafeRawPointer(equals) - UnsafeRawPointer(rowp)
          if 0 == strncmp(rowp, name, keyLength) {
            return String(validatingCString: equals + 1)
          }
        }
      }
      return nil
    }
#elseif SWT_TARGET_OS_APPLE || os(Linux) || os(FreeBSD) || os(OpenBSD) || os(Android) || os(WASI)
    getenv(name).flatMap { String(validatingCString: $0) }
#elseif os(Windows)
    name.withCString(encodedAs: UTF16.self) { name in
      func getVariable(maxCount: Int) -> String? {
        withUnsafeTemporaryAllocation(of: wchar_t.self, capacity: maxCount) { buffer in
          SetLastError(DWORD(ERROR_SUCCESS))
          let count = GetEnvironmentVariableW(name, buffer.baseAddress!, DWORD(buffer.count))
          if count == 0 {
            switch GetLastError() {
            case DWORD(ERROR_SUCCESS):
              // Empty String
              return ""
            case DWORD(ERROR_ENVVAR_NOT_FOUND):
              // The environment variable wasn't set.
              return nil
            case let errorCode:
              let error = Win32Error(rawValue: errorCode)
              fatalError("Unexpected error when getting environment variable '\(name)': \(error) (\(errorCode))")
            }
          } else if count > buffer.count {
            // Try again with the larger count.
            return getVariable(maxCount: Int(count))
          }
          return String.decodeCString(buffer.baseAddress!, as: UTF16.self)?.result
        }
      }
      return getVariable(maxCount: 256)
    }
#else
#warning("Platform-specific implementation missing: environment variables unavailable")
    return nil
#endif
  }

  /// Get the boolean value of the environment variable with the specified name.
  ///
  /// - Parameters:
  ///   - name: The name of the environment variable.
  ///
  /// - Returns: The value of the specified environment variable, interpreted as
  ///   a boolean value, or `nil` if it is not set for the current process.
  ///
  /// If a value is set for the specified environment variable, it is parsed as
  /// a boolean value:
  ///
  /// - String values that can be parsed as instances of `Int64` or `UInt64` are
  ///   interpreted as `false` if they are equal to `0`, and `true` otherwise;
  /// - String values beginning with the letters `"t"`, `"T"`, `"y"`, or `"Y"`
  ///   are interpreted as `true`; and
  /// - All other non-`nil` string values are interpreted as `false`.
  package static func flag(named name: String) -> Bool? {
    variable(named: name).map {
      if let signedValue = Int64($0) {
        return signedValue != 0
      }
      if let unsignedValue = UInt64($0) {
        return unsignedValue != 0
      }

      let first = $0.first
      return first == "t" || first == "T" || first == "y" || first == "Y"
    }
  }
}

// MARK: - Setting variables

extension Environment {
  /// Set the environment variable with the specified name.
  ///
  /// - Parameters:
  ///   - value: The new value for the specified environment variable. Pass
  ///     `nil` to remove the variable from the current process' environment.
  ///   - name: The name of the environment variable.
  ///
  /// - Returns: Whether or not the environment variable was successfully set.
  @discardableResult
  package static func setVariable(_ value: String?, named name: String) -> Bool {
#if SWT_NO_ENVIRONMENT_VARIABLES
    simulatedEnvironment.withLock { environment in
      environment[name] = value
    }
    return true
#elseif SWT_TARGET_OS_APPLE || os(Linux) || os(FreeBSD) || os(OpenBSD) || os(Android) || os(WASI)
    if let value {
      return 0 == setenv(name, value, 1)
    }
    return 0 == unsetenv(name)
#elseif os(Windows)
    name.withCString(encodedAs: UTF16.self) { name in
      if let value {
        return value.withCString(encodedAs: UTF16.self) { value in
          SetEnvironmentVariableW(name, value)
        }
      }
      return SetEnvironmentVariableW(name, nil)
    }
#else
#warning("Platform-specific implementation missing: environment variables unavailable")
    return false
#endif
  }
}
