//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if SWT_BUILDING_WITH_CMAKE
@_implementationOnly import _TestingInternals
#else
private import _TestingInternals
#endif

#if !SWT_NO_EXIT_TESTS
/// A type describing an exit test.
///
/// Instances of this type describe an exit test defined by the test author and
/// discovered or called at runtime.
@_spi(Experimental) @_spi(ForToolsIntegrationOnly)
public struct ExitTest: Sendable {
  /// The expected exit condition of the exit test.
  public var expectedExitCondition: ExitCondition

  /// The body closure of the exit test.
  fileprivate var body: @Sendable () async -> Void

  /// The source location of the exit test.
  ///
  /// The source location is unique to each exit test and is consistent between
  /// processes, so it can be used to uniquely identify an exit test at runtime.
  public var sourceLocation: SourceLocation

  /// Call the exit test in the current process.
  ///
  /// This function invokes the closure originally passed to
  /// `#expect(exitsWith:)` _in the current process_. That closure is expected
  /// to terminate the process; if it does not, the testing library will
  /// terminate the process in a way that causes the corresponding expectation
  /// to fail.
  public func callAsFunction() async -> Never {
    await body()

    // Run some glue code that terminates the process with an exit condition
    // that does not match the expected one. If the exit test's body doesn't
    // terminate, we'll manually call exit() and cause the test to fail.
    let expectingFailure = expectedExitCondition.matches(.failure)
    exit(expectingFailure ? EXIT_SUCCESS : EXIT_FAILURE)
  }
}

// MARK: - Discovery

/// A protocol describing a type that contains an exit test.
///
/// - Warning: This protocol is used to implement the `#expect(exitsWith:)`
///   macro. Do not use it directly.
@_alwaysEmitConformanceMetadata
@_spi(Experimental)
public protocol __ExitTestContainer {
  /// The expected exit condition of the exit test.
  static var __expectedExitCondition: ExitCondition { get }

  /// The source location of the exit test.
  static var __sourceLocation: SourceLocation { get }

  /// The body function of the exit test.
  static var __body: @Sendable () async -> Void { get }
}

extension ExitTest {
  /// A string that appears within all auto-generated types conforming to the
  /// `__ExitTestContainer` protocol.
  private static let _exitTestContainerTypeNameMagic = "__🟠$exit_test_body__"

  /// Find the exit test function at the given source location.
  ///
  /// - Parameters:
  ///   - sourceLocation: The source location of the exit test to find.
  ///
  /// - Returns: The specified exit test function, or `nil` if no such exit test
  ///   could be found.
  public static func find(at sourceLocation: SourceLocation) -> Self? {
    var result: Self?

    struct Stop: Error {}
    try? enumerateTypes(withNamesContaining: _exitTestContainerTypeNameMagic) { type in
      if let type = type as? any __ExitTestContainer.Type, type.__sourceLocation == sourceLocation {
        result = ExitTest(
          expectedExitCondition: type.__expectedExitCondition,
          body: type.__body,
          sourceLocation: type.__sourceLocation
        )
        throw Stop()
      }
    }

    return result
  }
}

// MARK: -

/// Check that an expression always exits (terminates the current process) with
/// a given status.
///
/// - Parameters:
///   - expectedExitCondition: The expected exit condition.
///   - body: The exit test body.
///   - expression: The expression, corresponding to `condition`, that is being
///     evaluated (if available at compile time.)
///   - comments: An array of comments describing the expectation. This array
///     may be empty.
///   - isRequired: Whether or not the expectation is required. The value of
///     this argument does not affect whether or not an error is thrown on
///     failure.
///   - sourceLocation: The source location of the expectation.
///
/// This function contains the common implementation for all
/// `await #expect(exitsWith:) { }` invocations regardless of calling
/// convention.
func callExitTest(
  exitsWith expectedExitCondition: ExitCondition,
  performing body: @escaping @Sendable () async -> Void,
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) async -> Result<Void, any Error> {
  guard let configuration = Configuration.current ?? Configuration.all.first else {
    preconditionFailure("A test must be running on the current task to use #expect(exitsWith:).")
  }

  let actualExitCondition: ExitCondition
  do {
    let exitTest = ExitTest(expectedExitCondition: expectedExitCondition, body: body, sourceLocation: sourceLocation)
    actualExitCondition = try await configuration.exitTestHandler(exitTest)
  } catch {
    // An error here would indicate a problem in the exit test handler such as a
    // failure to find the process' path, to construct arguments to the
    // subprocess, or to spawn the subprocess. These are not expected to be
    // common issues, however they would constitute a failure of the test
    // infrastructure rather than the test itself and perhaps should not cause
    // the test to terminate early.
    Issue.record(.errorCaught(error), comments: comments(), backtrace: .current(), sourceLocation: sourceLocation, configuration: configuration)
    return __checkValue(
      false,
      expression: expression,
      comments: comments(),
      isRequired: isRequired,
      sourceLocation: sourceLocation
    )
  }

  lazy var actualValue: CInt? = switch actualExitCondition {
  case .failure:
    nil
  case let .exitCode(exitCode):
    exitCode
#if !os(Windows)
  case let .signal(signal):
    signal
#endif
  }

  return __checkValue(
    expectedExitCondition.matches(actualExitCondition),
    expression: expression,
    expressionWithCapturedRuntimeValues: expression.capturingRuntimeValues(actualValue),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

// MARK: - SwiftPM/tools integration

extension ExitTest {
  /// A handler that is invoked when an exit test starts.
  ///
  /// - Parameters:
  ///   - exitTest: The exit test that is starting.
  ///
  /// - Returns: The condition under which the exit test exited.
  ///
  /// - Throws: Any error that prevents the normal invocation or execution of
  ///   the exit test.
  ///
  /// This handler is invoked when an exit test (i.e. a call to either
  /// ``expect(exitsWith:_:sourceLocation:performing:)`` or
  /// ``require(exitsWith:_:sourceLocation:performing:)``) is started. The
  /// handler is responsible for initializing a new child environment (typically
  /// a child process) and running the exit test identified by `sourceLocation`
  /// there. The exit test's body can be found using ``ExitTest/find(at:)``.
  ///
  /// The parent environment should suspend until the results of the exit test
  /// are available or the child environment is otherwise terminated. The parent
  /// environment is then responsible for interpreting those results and
  /// recording any issues that occur.
  public typealias Handler = @Sendable (_ exitTest: borrowing ExitTest) async throws -> ExitCondition

  /// Find the exit test function specified in the environment of the current
  /// process, if any.
  ///
  /// - Returns: The exit test this process should run, or `nil` if it is not
  ///   expected to run any.
  ///
  /// This function should only be used when the process was started via the
  /// `__swiftPMEntryPoint()` function. The effect of using it under other
  /// configurations is undefined.
  static func findInEnvironmentForEntryPoint() -> Self? {
    if var sourceLocationString = Environment.variable(named: "SWT_EXPERIMENTAL_EXIT_TEST_SOURCE_LOCATION") {
      return try? sourceLocationString.withUTF8 { sourceLocationBuffer in
        let sourceLocationBuffer = UnsafeRawBufferPointer(sourceLocationBuffer)
        let sourceLocation = try JSON.decode(SourceLocation.self, from: sourceLocationBuffer)
        return find(at: sourceLocation)
      }
    }
    return nil
  }

  /// The exit test handler used when integrating with Swift Package Manager via
  /// the `__swiftPMEntryPoint()` function.
  ///
  /// - Parameters:
  ///   - xcTestCaseIdentifier: The identifier of the XCTest-based test hosting
  ///     the testing library (when using ``XCTestScaffold``.)
  ///
  /// For a description of the inputs and outputs of this function, see the
  /// documentation for ``ExitTest/Handler``.
  static func handlerForEntryPoint(forXCTestCaseIdentifiedBy xcTestCaseIdentifier: String? = nil) -> Handler {
    // The environment could change between invocations if a test calls setenv()
    // or unsetenv(), so we need to recompute the child environment each time.
    // The executable and XCTest bundle paths should not change over time, so we
    // can precompute them.
    let childProcessExecutablePath = Result { try CommandLine.executablePath }

    // We only need to pass arguments when hosted by XCTest.
    let childArguments: [String] = {
      var result = [String]()
      lazy var xctestTargetPath = Environment.variable(named: "XCTestBundlePath")
        ?? CommandLine.arguments().dropFirst().last
#if SWT_TARGET_OS_APPLE
      // If the running executable appears to be the XCTest runner executable in
      // Xcode, figure out the path to the running XCTest bundle. If we can find
      // it, then we can re-run the host XCTestCase instance.
      // TODO: use basename_r() instead of parsing the path.
      var isHostedByXCTest = false
      if let executablePath = try? childProcessExecutablePath.get() {
        executablePath.withCString { childProcessExecutablePath in
          withUnsafeTemporaryAllocation(of: CChar.self, capacity: strlen(childProcessExecutablePath) + 1) { baseName in
            if nil != basename_r(childProcessExecutablePath, baseName.baseAddress!) {
              isHostedByXCTest = 0 == strcmp(baseName.baseAddress!, "xctest")
            }
          }
        }
      }

      if isHostedByXCTest, let xctestTargetPath {
        // HACK: if the current test is being run from within Xcode, we don't
        // always know we're being hosted by an XCTestCase instance. In cases
        // where we don't, but the XCTest environment variable specifying the
        // test bundle is set, assume we _are_ being hosted and specify a
        // blank test identifier ("/") to force the xctest command-line tool
        // to run.
        let xcTestCaseIdentifier = xcTestCaseIdentifier ?? "/"
        result += ["-XCTest", xcTestCaseIdentifier, xctestTargetPath]
      }
#else
      if let xcTestCaseIdentifier {
        result.append(xcTestCaseIdentifier)
        if let xctestTargetPath {
          result.append(xctestTargetPath)
        }
      }
#endif
      return result
    }()

    return { exitTest in
      let childProcessExecutablePath = try childProcessExecutablePath.get()

      // Inherit the environment from the parent process and make any necessary
      // platform-specific changes.
      var childEnvironment = Environment.get()
#if SWT_TARGET_OS_APPLE
      // We need to remove Xcode's environment variables from the child
      // environment to avoid accidentally accidentally recursing.
      for key in childEnvironment.keys where key.starts(with: "XCTest") {
        childEnvironment.removeValue(forKey: key)
      }
#elseif os(Linux)
      if childEnvironment["SWIFT_BACKTRACE"] == nil {
        // Disable interactive backtraces unless explicitly enabled to reduce
        // the noise level during the exit test. Only needed on Linux.
        childEnvironment["SWIFT_BACKTRACE"] = "enable=no"
      }
#endif
      // Insert a specific variable that tells the child process which exit test
      // to run.
      try JSON.withEncoding(of: exitTest.sourceLocation) { json in
        childEnvironment["SWT_EXPERIMENTAL_EXIT_TEST_SOURCE_LOCATION"] = String(decoding: json, as: UTF8.self)
      }

      return try await _spawnAndWait(
        forExecutableAtPath: childProcessExecutablePath,
        arguments: childArguments,
        environment: childEnvironment
      )
    }
  }

  /// Spawn a process and wait for it to terminate.
  ///
  /// - Parameters:
  ///   - executablePath: The path to the executable to spawn.
  ///   - arguments: The arguments to pass to the executable, not including the
  ///     executable path.
  ///   - environment: The environment block to pass to the executable.
  ///
  /// - Returns: The exit condition of the spawned process.
  ///
  /// - Throws: Any error that prevented the process from spawning or its exit
  ///   condition from being read.
  private static func _spawnAndWait(
    forExecutableAtPath executablePath: String,
    arguments: [String],
    environment: [String: String]
  ) async throws -> ExitCondition {
    // Darwin and Linux differ in their optionality for the posix_spawn types we
    // use, so use this typealias to paper over the differences.
#if SWT_TARGET_OS_APPLE
    typealias P<T> = T?
#elseif os(Linux)
    typealias P<T> = T
#endif

#if SWT_TARGET_OS_APPLE || os(Linux)
    let pid = try withUnsafeTemporaryAllocation(of: P<posix_spawn_file_actions_t>.self, capacity: 1) { fileActions in
      guard 0 == posix_spawn_file_actions_init(fileActions.baseAddress!) else {
        throw CError(rawValue: swt_errno())
      }
      defer {
        _ = posix_spawn_file_actions_destroy(fileActions.baseAddress!)
      }

      // Do not forward standard I/O.
      _ = posix_spawn_file_actions_addopen(fileActions.baseAddress!, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
      _ = posix_spawn_file_actions_addopen(fileActions.baseAddress!, STDOUT_FILENO, "/dev/null", O_WRONLY, 0)
      _ = posix_spawn_file_actions_addopen(fileActions.baseAddress!, STDERR_FILENO, "/dev/null", O_WRONLY, 0)

      return try withUnsafeTemporaryAllocation(of: P<posix_spawnattr_t>.self, capacity: 1) { attrs in
        guard 0 == posix_spawnattr_init(attrs.baseAddress!) else {
          throw CError(rawValue: swt_errno())
        }
        defer {
          _ = posix_spawnattr_destroy(attrs.baseAddress!)
        }
#if SWT_TARGET_OS_APPLE
        // Close all other file descriptors open in the parent. Note that Linux
        // does not support this flag and, unlike Foundation.Process, we do not
        // attempt to emulate it.
        _ = posix_spawnattr_setflags(attrs.baseAddress!, CShort(POSIX_SPAWN_CLOEXEC_DEFAULT))
#endif

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
        guard 0 == posix_spawn(&pid, executablePath, fileActions.baseAddress!, attrs.baseAddress, argv, environ) else {
          throw CError(rawValue: swt_errno())
        }
        return pid
      }
    }

    return try await wait(for: pid)
#elseif os(Windows)
    // NOTE: Windows processes are responsible for handling their own
    // command-line escaping. This code is adapted from the code in
    // swift-corelibs-foundation (SEE: quoteWindowsCommandLine()) which was
    // itself adapted from the code published by Microsoft at
    // https://learn.microsoft.com/en-gb/archive/blogs/twistylittlepassagesallalike/everyone-quotes-command-line-arguments-the-wrong-way
    let commandLine = (CollectionOfOne(executablePath) + arguments).lazy
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
    let environ = environment.map { "\($0.key)=\($0.value)"}.joined(separator: "\0") + "\0\0"

    let processHandle: HANDLE! = try commandLine.withCString(encodedAs: UTF16.self) { commandLine in
      try environ.withCString(encodedAs: UTF16.self) { environ in
        var processInfo = PROCESS_INFORMATION()

        var startupInfo = STARTUPINFOW()
        startupInfo.cb = DWORD(MemoryLayout.size(ofValue: startupInfo))
        guard CreateProcessW(
          nil,
          .init(mutating: commandLine),
          nil,
          nil,
          false,
          DWORD(CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT),
          .init(mutating: environ),
          nil,
          &startupInfo,
          &processInfo
        ) else {
          throw Win32Error(rawValue: GetLastError())
        }
        _ = CloseHandle(processInfo.hThread)

        return processInfo.hProcess
      }
    }
    defer {
      CloseHandle(processHandle)
    }

    return try await wait(for: processHandle)
#else
#warning("Platform-specific implementation missing: process spawning unavailable")
    throw SystemError(description: "Exit tests are unimplemented on this platform.")
#endif
  }
}
#endif
