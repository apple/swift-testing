//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024–2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

@_spi(Experimental) @_spi(ForToolsIntegrationOnly) private import _TestDiscovery
private import _TestingInternals

#if !SWT_NO_EXIT_TESTS
#if SWT_NO_FILE_IO
#error("Platform-specific misconfiguration: support for exit tests requires support for file I/O")
#endif
#if SWT_NO_PIPES
#error("Platform-specific misconfiguration: support for exit tests requires support for (anonymous) pipes")
#endif
#if SWT_NO_PROCESS_SPAWNING
#error("Platform-specific misconfiguration: support for exit tests requires support for process spawning")
#endif
#endif

/// A type describing an exit test.
///
/// Instances of this type describe exit tests you create using the
/// ``expect(processExitsWith:observing:_:sourceLocation:performing:)`` or
/// ``require(processExitsWith:observing:_:sourceLocation:performing:)`` macro.
/// You don't usually need to interact directly with an instance of this type.
///
/// @Metadata {
///   @Available(Swift, introduced: 6.2)
///   @Available(Xcode, introduced: 26.0)
/// }
#if SWT_NO_EXIT_TESTS
@available(*, unavailable, message: "Exit tests are not available on this platform.")
#endif
public struct ExitTest: Sendable, ~Copyable {
  /// A type whose instances uniquely identify instances of ``ExitTest``.
  ///
  /// An instance of this type uniquely identifies an exit test within the
  /// context of the current test target. You can get an exit test's unique
  /// identifier from its ``id`` property.
  ///
  /// The encoded form of an instance of this type is subject to change over
  /// time. Instances of this type are only guaranteed to be decodable by the
  /// same version of the testing library that encoded them.
  @_spi(ForToolsIntegrationOnly)
  public struct ID: Sendable, Equatable, Codable {
    /// Storage for the underlying bits of the ID.
    ///
    /// - Note: On Apple platforms, we deploy to OS versions that do not include
    ///   support for `UInt128`, so we use four `UInt64`s for storage instead.
    private var _0: UInt64
    private var _1: UInt64
    private var _2: UInt64
    private var _3: UInt64

    init(_ uuid: (UInt64, UInt64, UInt64, UInt64)) {
      self._0 = uuid.0
      self._1 = uuid.1
      self._2 = uuid.2
      self._3 = uuid.3
    }
  }

  /// A value that uniquely identifies this instance.
  @_spi(ForToolsIntegrationOnly)
  public var id: ID

  /// An exit test body function.
  ///
  /// - Parameters:
  ///   - exitTest: The exit test to which this body closure belongs.
  fileprivate typealias Body = @Sendable (_ exitTest: inout Self) async throws -> Void

  /// The body closure of the exit test.
  ///
  /// Do not invoke this closure directly. Instead, invoke ``callAsFunction()``
  /// to run the exit test. Running the exit test will always terminate the
  /// current process.
  fileprivate var body: Body = { _ in }

  /// Storage for ``observedValues``.
  ///
  /// Key paths are not sendable because the properties they refer to may or may
  /// not be, so this property needs to be `nonisolated(unsafe)`. It is safe to
  /// use it in this fashion because ``ExitTest/Result`` is sendable.
  fileprivate var _observedValues = [any PartialKeyPath<ExitTest.Result> & Sendable]()

  /// Key paths representing results from within this exit test that should be
  /// observed and returned to the caller.
  ///
  /// The testing library sets this property to match what was passed by the
  /// developer to the `#expect(processExitsWith:)` or `#require(processExitsWith:)`
  /// macro. If you are implementing an exit test handler, you can check the
  /// value of this property to determine what information you need to preserve
  /// from your child process.
  ///
  /// The value of this property always includes ``ExitTest/Result/exitStatus``
  /// even if the test author does not specify it.
  ///
  /// Within a child process running an exit test, the value of this property is
  /// otherwise unspecified.
  @_spi(ForToolsIntegrationOnly)
  public var observedValues: [any PartialKeyPath<ExitTest.Result> & Sendable] {
    get {
      var result = _observedValues
      if !result.contains(\.exitStatus) { // O(n), but n <= 3 (no Set needed)
        result.append(\.exitStatus)
      }
      return result
    }
    set {
      _observedValues = newValue
    }
  }

  /// The set of values captured in the parent process before the exit test is
  /// called.
  ///
  /// This property is automatically set by the testing library when using the
  /// built-in exit test handler and entry point functions. Do not modify the
  /// value of this property unless you are implementing a custom exit test
  /// handler or entry point function.
  ///
  /// The order of values in this array must be the same between the parent and
  /// child processes.
  @_spi(Experimental) @_spi(ForToolsIntegrationOnly)
  public var capturedValues = [CapturedValue]()

  /// Make a copy of this instance.
  ///
  /// - Returns: A copy of this instance.
  ///
  /// This function is unsafe because if the caller is not careful, it could
  /// invoke the same exit test twice.
  fileprivate borrowing func unsafeCopy() -> Self {
    var result = Self(id: id, body: body)
    result._observedValues = _observedValues
    result.capturedValues = capturedValues
    return result
  }
}

#if !SWT_NO_EXIT_TESTS
// MARK: - Current

extension ExitTest {
  /// Storage for ``current``.
  ///
  /// A pointer is used for indirection because `ManagedBuffer` cannot yet hold
  /// move-only types.
  private static nonisolated(unsafe) let _current: Locked<UnsafeMutablePointer<ExitTest?>> = {
    let current = UnsafeMutablePointer<ExitTest?>.allocate(capacity: 1)
    current.initialize(to: nil)
    return Locked(rawValue: current)
  }()

  /// The exit test that is running in the current process, if any.
  ///
  /// If the current process was created to run an exit test, the value of this
  /// property describes that exit test. If this process is the parent process
  /// of an exit test, or if no exit test is currently running, the value of
  /// this property is `nil`.
  ///
  /// The value of this property is constant across all tasks in the current
  /// process.
  ///
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.2)
  ///   @Available(Xcode, introduced: 26.0)
  /// }
  public static var current: ExitTest? {
    _read {
      // NOTE: Even though this accessor is `_read` and has borrowing semantics,
      // we must make a copy so that we don't yield lock-guarded memory to the
      // caller (which is not concurrency-safe.)
      let currentCopy = _current.withLock { current in
        return current.pointee?.unsafeCopy()
      }
      yield currentCopy
    }
  }
}

// MARK: - Invocation

@_spi(ForToolsIntegrationOnly)
extension ExitTest {
  /// Disable crash reporting, crash logging, or core dumps for the current
  /// process.
  private static func _disableCrashReporting() {
#if SWT_TARGET_OS_APPLE && !SWT_NO_MACH_PORTS
    // We don't need to create a crash log (a "corpse notification") for an exit
    // test. In the future, we might want to investigate actually setting up a
    // listener port in the parent process and tracking interesting exceptions
    // as separate exit conditions.
    //
    // BUG: The system may still opt to write crash logs to /Library/Logs
    // instead of the user's home folder. rdar://47982238
    _ = task_set_exception_ports(
      swt_mach_task_self(),
      exception_mask_t(EXC_MASK_CORPSE_NOTIFY),
      mach_port_t(MACH_PORT_NULL),
      EXCEPTION_DEFAULT,
      THREAD_STATE_NONE
    )
#elseif os(Linux)
    // On Linux, disable the generation of core files. They may or may not be
    // disabled by default; if they are enabled, they significantly slow down
    // the performance of exit tests. The kernel special-cases RLIMIT_CORE=1 to
    // mean core files should not be generated even if they are being written to
    // a pipe instead of a regular file; that gets us our performance back.
    // SEE: https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/fs/coredump.c#n610
    var rl = rlimit(rlim_cur: 1, rlim_max: 1)
    _ = setrlimit(CInt(RLIMIT_CORE.rawValue), &rl)
#elseif os(FreeBSD) || os(OpenBSD)
    // As with Linux, disable the generation core files. The BSDs do not, as far
    // as I can tell, special-case RLIMIT_CORE=1.
    var rl = rlimit(rlim_cur: 0, rlim_max: 0)
    _ = setrlimit(RLIMIT_CORE, &rl)
#elseif os(Windows)
    // On Windows, similarly disable Windows Error Reporting and the Windows
    // Error Reporting UI. Note we expect to be the first component to call
    // these functions, so we don't attempt to preserve any previously-set bits.
    _ = SetErrorMode(UINT(SEM_NOGPFAULTERRORBOX))
    _ = WerSetFlags(DWORD(WER_FAULT_REPORTING_NO_UI))
#else
#warning("Platform-specific implementation missing: unable to disable crash reporting")
#endif
  }

  /// The name of the environment variable used to identify the exit test to
  /// call in a spawned exit test process.
  private static let _idEnvironmentVariableName = "SWT_EXIT_TEST_ID"

  /// Call the exit test in the current process.
  ///
  /// This function invokes the closure originally passed to
  /// `#expect(processExitsWith:)` _in the current process_. That closure is
  /// expected to terminate the process; if it does not, the testing library
  /// will terminate the process as if its `main()` function returned naturally.
  public consuming func callAsFunction() async -> Never {
    Self._disableCrashReporting()

#if os(Windows)
    // Windows does not support signal handling to the degree UNIX-like systems
    // do. When a signal is raised in a Windows process, the default signal
    // handler simply calls `_exit()` and passes the constant value `3`. To
    // allow us to handle signals on Windows, we install signal handlers for all
    // signals supported on Windows. These signal handlers exit with a specific
    // exit code that is unlikely to be encountered "in the wild" and which
    // encodes the caught signal. Corresponding code in the parent process looks
    // for these special exit codes and translates them back to signals.
    //
    // Microsoft's documentation for `_Exit()` and `_exit()` indicates they
    // behave identically. Their documentation for abort() can be found at
    // https://learn.microsoft.com/en-us/cpp/c-runtime-library/reference/abort?view=msvc-170
    // and states: "[...] abort calls _exit to terminate the process with exit
    // code 3 [...]".
    //
    // The Wine project's implementation of raise() calls `_exit(3)` by default.
    // See https://github.com/wine-mirror/wine/blob/master/dlls/msvcrt/except.c
    //
    // Finally, an official copy of the UCRT sources (not up to date) is hosted
    // at https://www.nuget.org/packages/Microsoft.Windows.SDK.CRTSource . That
    // repository doesn't have an official GitHub mirror, but you can manually
    // navigate to misc/signal.cpp:481 to see the implementation of SIG_DFL
    // (which, again, calls `_exit(3)` unconditionally.)
    for sig in [SIGINT, SIGILL, SIGFPE, SIGSEGV, SIGTERM, SIGBREAK, SIGABRT, SIGABRT_COMPAT] {
      _ = signal(sig) { sig in
        _exit(STATUS_SIGNAL_CAUGHT_BITS | sig)
      }
    }
#endif

#if os(OpenBSD)
    // OpenBSD does not have posix_spawn_file_actions_addclosefrom_np().
    // However, it does have closefrom(2), which we call here as a best effort.
    if let from = Environment.variable(named: "SWT_CLOSEFROM").flatMap(CInt.init) {
      _ = closefrom(from)
    }
#endif

    // Set ExitTest.current before the test body runs.
    Self._current.withLock { current in
      precondition(current.pointee == nil, "Set the current exit test twice in the same process. Please file a bug report at https://github.com/swiftlang/swift-testing/issues/new")
      current.pointee = self.unsafeCopy()
    }

    let error = await Issue.withErrorRecording(at: nil) {
      try await body(&self)
    }
    if let error {
      _errorInMain(error)
    }

    // If we get to this point without terminating, then we simulate main()'s
    // behavior which is to exit with EXIT_SUCCESS.
    exit(EXIT_SUCCESS)
  }
}

// MARK: - Discovery

extension ExitTest {
  /// A type representing an exit test as a test content record.
  fileprivate struct Record: Sendable, DiscoverableAsTestContent {
    static var testContentKind: TestContentKind {
      "exit"
    }

    typealias TestContentAccessorHint = ID

    /// The ID of the represented exit test.
    var id: ExitTest.ID

    /// The body of the represented exit test.
    var body: ExitTest.Body

    /// The set of values captured in the parent process before the exit test is
    /// called.
    var capturedValues = [CapturedValue]()

    /// Make the exit test represented by this instance.
    ///
    /// - Returns: A new exit test as represented by this instance.
    func makeExitTest() -> ExitTest {
      var exitTest = ExitTest(id: id, body: body)
      exitTest.capturedValues = capturedValues
      return exitTest
    }
  }

  /// Store the exit test into the given memory.
  ///
  /// - Parameters:
  ///   - id: The unique identifier of the exit test to store.
  ///   - body: The body closure of the exit test to store.
  ///   - outValue: The uninitialized memory to store the exit test into.
  ///   - typeAddress: A pointer to the expected type of the exit test as passed
  ///     to the test content record calling this function.
  ///   - hintAddress: A pointer to an instance of ``ID`` to use as a hint.
  ///
  /// - Returns: Whether or not an exit test was stored into `outValue`.
  ///
  /// - Warning: This function is used to implement the
  ///   `#expect(processExitsWith:)` macro. Do not use it directly.
#if compiler(>=6.2)
  @safe
#endif
  public static func __store<each T>(
    _ id: (UInt64, UInt64, UInt64, UInt64),
    _ body: @escaping @Sendable (repeat each T) async throws -> Void,
    into outValue: UnsafeMutableRawPointer,
    asTypeAt typeAddress: UnsafeRawPointer,
    withHintAt hintAddress: UnsafeRawPointer? = nil
  ) -> CBool where repeat each T: Codable & Sendable {
#if !hasFeature(Embedded)
    // Check that the type matches.
    guard typeAddress.load(as: Any.Type.self) == Record.self else {
      return false
    }
#endif

    // Check that the ID matches if provided.
    let id = ID(id)
    if let hintedID = hintAddress?.load(as: ID.self), hintedID != id {
      return false
    }

    // Wrap the body function in a thunk that decodes any captured state and
    // passes it along.
    let body: ExitTest.Body = { exitTest in
      let values: (repeat each T) = try exitTest.capturedValues.takeCapturedValues()
      try await body(repeat each values)
    }

    // Construct and return the record.
    var record = Record(id: id, body: body)
    record.capturedValues = Array(repeat (each T).self)
    outValue.initializeMemory(as: Record.self, to: record)
    return true
  }

  /// Attempt to store an invalid exit test into the given memory.
  ///
  /// This overload of `__store()` is provided to suppress diagnostics when a
  /// value of an unsupported type is captured as an argument of `body`. It
  /// always terminates the current process.
  ///
  /// - Warning: This function is used to implement the
  ///   `#expect(processExitsWith:)` macro. Do not use it directly.
#if compiler(>=6.2)
  @safe
#endif
  public static func __store<T>(
    _ id: (UInt64, UInt64, UInt64, UInt64),
    _ body: T,
    into outValue: UnsafeMutableRawPointer,
    asTypeAt typeAddress: UnsafeRawPointer,
    withHintAt hintAddress: UnsafeRawPointer? = nil
  ) -> CBool {
    swt_unreachable()
  }
}

@_spi(ForToolsIntegrationOnly)
extension ExitTest {
  /// Find the exit test function at the given source location.
  ///
  /// - Parameters:
  ///   - id: The unique identifier of the exit test to find.
  ///
  /// - Returns: The specified exit test function, or `nil` if no such exit test
  ///   could be found.
  public static func find(identifiedBy id: ExitTest.ID) -> Self? {
    for record in Record.allTestContentRecords() {
      if let exitTest = record.load(withHint: id)?.makeExitTest() {
        return exitTest
      }
    }

#if !SWT_NO_LEGACY_TEST_DISCOVERY
    // Call the legacy lookup function that discovers tests embedded in types.
    for record in Record.allTypeMetadataBasedTestContentRecords() {
      if let exitTest = record.load(withHint: id)?.makeExitTest() {
        return exitTest
      }
    }
#endif

    return nil
  }
}

// MARK: -

/// Check that an expression always exits (terminates the current process) with
/// a given status.
///
/// - Parameters:
///   - exitTestID: The unique identifier of the exit test.
///   - capturedValues: Any values captured by the exit test.
///   - expectedExitCondition: The expected exit condition.
///   - observedValues: An array of key paths representing results from within
///     the exit test that should be observed and returned by this macro. The
///     ``ExitTest/Result/exitStatus`` property is always returned.
///   - expression: The expression, corresponding to `condition`, that is being
///     evaluated (if available at compile time.)
///   - comments: An array of comments describing the expectation. This array
///     may be empty.
///   - isRequired: Whether or not the expectation is required. The value of
///     this argument does not affect whether or not an error is thrown on
///     failure.
///   - isolation: The actor to which the exit test is isolated, if any.
///   - sourceLocation: The source location of the expectation.
///
/// This function contains the common implementation for all
/// `await #expect(processExitsWith:) { }` invocations regardless of calling
/// convention.
func callExitTest(
  identifiedBy exitTestID: (UInt64, UInt64, UInt64, UInt64),
  encodingCapturedValues capturedValues: [ExitTest.CapturedValue],
  processExitsWith expectedExitCondition: ExitTest.Condition,
  observing observedValues: [any PartialKeyPath<ExitTest.Result> & Sendable],
  expression: __Expression,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  isolation: isolated (any Actor)? = #isolation,
  sourceLocation: SourceLocation
) async -> Result<ExitTest.Result?, any Error> {
  guard let configuration = Configuration.current ?? Configuration.all.first else {
    preconditionFailure("A test must be running on the current task to use #expect(processExitsWith:).")
  }

  var result: ExitTest.Result
  do {
    // Construct a temporary/local exit test to pass to the exit test handler.
    var exitTest = ExitTest(id: ExitTest.ID(exitTestID))
    exitTest.observedValues = observedValues
    exitTest.capturedValues = capturedValues

    // Invoke the exit test handler and wait for the child process to terminate.
    result = try await configuration.exitTestHandler(exitTest)

#if os(Windows)
    // For an explanation of this magic, see the corresponding logic in
    // ExitTest.callAsFunction().
    if case let .exitCode(exitCode) = result.exitStatus, (exitCode & ~STATUS_CODE_MASK) == STATUS_SIGNAL_CAUGHT_BITS {
      result.exitStatus = .signal(exitCode & STATUS_CODE_MASK)
    }
#endif
  } catch {
    // An error here would indicate a problem in the exit test handler such as a
    // failure to find the process' path, to construct arguments to the
    // subprocess, or to spawn the subprocess. Such failures are system issues,
    // not test issues, because they constitute failures of the test
    // infrastructure rather than the test itself.
    //
    // But here's a philosophical question: should the exit test also fail with
    // an expectation failure? Arguably no, because the issue is a systemic one
    // and (presumably) not a bug in the test. But also arguably yes, because
    // the exit test did not do what the test author expected it to do.
    let backtrace = Backtrace(forFirstThrowOf: error) ?? .current()
    let issue = Issue(
      kind: .system,
      comments: comments() + CollectionOfOne(Comment(rawValue: String(describingForTest: error))),
      sourceContext: SourceContext(backtrace: backtrace, sourceLocation: sourceLocation)
    )
    issue.record(configuration: configuration)

    // For lack of a better way to handle an exit test failing in this way,
    // we record the system issue above, then let the expectation fail below by
    // reporting an exit condition that's the inverse of the expected one.
    let exitStatus: ExitStatus = if expectedExitCondition.isApproximatelyEqual(to: .exitCode(EXIT_FAILURE)) {
      .exitCode(EXIT_SUCCESS)
    } else {
      .exitCode(EXIT_FAILURE)
    }
    result = ExitTest.Result(exitStatus: exitStatus)
  }

  // Plumb the exit test's result through the general expectation machinery.
  return __checkValue(
    expectedExitCondition.isApproximatelyEqual(to: result.exitStatus),
    expression: expression,
    expressionWithCapturedRuntimeValues: expression.capturingRuntimeValues(result.exitStatus),
    mismatchedExitConditionDescription: String(describingForTest: expectedExitCondition),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  ).map { result }
}

// MARK: - SwiftPM/tools integration

extension ABI {
  /// The ABI version to use for encoding and decoding events sent over the back
  /// channel.
  ///
  /// The back channel always uses the experimental ABI version since both the
  /// producer and consumer use this exact version of the testing library.
  fileprivate typealias BackChannelVersion = ExperimentalVersion
}

@_spi(ForToolsIntegrationOnly)
extension ExitTest {
  /// A barrier value to insert into the standard output and standard error
  /// streams immediately before and after the body of an exit test runs in
  /// order to distinguish output produced by the host process.
  ///
  /// The value of this property was randomly generated. It could conceivably
  /// show up in actual output from an exit test, but the statistical likelihood
  /// of that happening is negligible.
  static var barrierValue: [UInt8] {
    [
      0x39, 0x74, 0x87, 0x6d, 0x96, 0xdd, 0xf6, 0x17,
      0x7f, 0x05, 0x61, 0x5d, 0x46, 0xeb, 0x37, 0x0c,
      0x90, 0x07, 0xca, 0xe5, 0xed, 0x0b, 0xc4, 0xc4,
      0x46, 0x36, 0xc5, 0xb8, 0x9c, 0xc7, 0x86, 0x57,
    ]
  }

  /// Remove the leading and trailing barrier values from the given array of
  /// bytes along.
  ///
  /// - Parameters:
  ///   - buffer: The buffer to trim.
  ///
  /// - Returns: A copy of `buffer`. If a barrier value (equal to
  ///   ``barrierValue``) is present in `buffer`, it and everything before it
  ///   are trimmed from the beginning of the copy. If there is more than one
  ///   barrier value present, the last one and everything after it are trimmed
  ///   from the end of the copy. If no barrier value is present, `buffer` is
  ///   returned verbatim.
  private static func _trimToBarrierValues(_ buffer: [UInt8]) -> [UInt8] {
    let barrierValue = barrierValue
    let firstBarrierByte = barrierValue[0]

    // If the buffer is too small to contain the barrier value, exit early.
    guard buffer.count > barrierValue.count else {
      return buffer
    }

    // Find all the indices where the first byte of the barrier is present.
    let splits = buffer.indices.filter { buffer[$0] == firstBarrierByte }

    // Trim off the leading barrier value. If we didn't find any barrier values,
    // we do nothing.
    let leadingIndex = splits.first { buffer[$0...].starts(with: barrierValue) }
    guard let leadingIndex else {
      return buffer
    }
    var trimmedBuffer = buffer[leadingIndex...].dropFirst(barrierValue.count)

    // If there's a trailing barrier value, trim it too. If it's at the same
    // index as the leading barrier value, that means only one barrier value
    // was present and we should assume it's the leading one.
    let trailingIndex = splits.last { buffer[$0...].starts(with: barrierValue) }
    if let trailingIndex, trailingIndex > leadingIndex {
      trimmedBuffer = trimmedBuffer[..<trailingIndex]
    }

    return Array(trimmedBuffer)
  }

  /// Write barrier values (equal to ``barrierValue``) to the standard output
  /// and standard error streams of the current process.
  private static func _writeBarrierValues() {
    let barrierValue = Self.barrierValue
    try? FileHandle.stdout.write(barrierValue)
    try? FileHandle.stderr.write(barrierValue)
  }

  /// A handler that is invoked when an exit test starts.
  ///
  /// - Parameters:
  ///   - exitTest: The exit test that is starting.
  ///
  /// - Returns: The result of the exit test including the condition under which
  ///   it exited.
  ///
  /// - Throws: Any error that prevents the normal invocation or execution of
  ///   the exit test.
  ///
  /// This handler is invoked when an exit test (i.e. a call to either
  /// ``expect(processExitsWith:observing:_:sourceLocation:performing:)`` or
  /// ``require(processExitsWith:observing:_:sourceLocation:performing:)``) is
  /// started. The handler is responsible for initializing a new child
  /// environment (typically a child process) and running `exitTest` there.
  ///
  /// In the child environment, you can find the exit test again by calling
  /// ``ExitTest/find(at:)`` and can run it by calling
  /// ``ExitTest/callAsFunction()``.
  ///
  /// The parent environment should suspend until the results of the exit test
  /// are available or the child environment is otherwise terminated. The parent
  /// environment is then responsible for interpreting those results and
  /// recording any issues that occur.
  public typealias Handler = @Sendable (_ exitTest: borrowing Self) async throws -> ExitTest.Result

  /// Make a file handle from the string contained in the given environment
  /// variable.
  ///
  /// - Parameters:
  ///   - name: The name of the environment variable to read. The value of this
  ///     environment variable should represent the file handle. The exact value
  ///     is platform-specific but is generally the file descriptor as a string.
  ///   - mode: The mode to open the file with, such as `"wb"`.
  ///
  /// - Returns: A new file handle, or `nil` if one could not be created.
  ///
  /// The effect of calling this function more than once for the same
  /// environment variable is undefined.
  private static func _makeFileHandle(forEnvironmentVariableNamed name: String, mode: String) -> FileHandle? {
    guard let environmentVariable = Environment.variable(named: name) else {
      return nil
    }

    // Erase the environment variable so that it cannot accidentally be opened
    // twice (nor, in theory, affect the code of the exit test.)
    Environment.setVariable(nil, named: name)

    var fd: CInt?
#if SWT_TARGET_OS_APPLE || os(Linux) || os(FreeBSD) || os(OpenBSD)
    fd = CInt(environmentVariable)
#elseif os(Windows)
    if let handle = UInt(environmentVariable).flatMap(HANDLE.init(bitPattern:)) {
      var flags: CInt = switch (mode.contains("r"), mode.contains("w")) {
      case (true, true):
        _O_RDWR
      case (true, false):
        _O_RDONLY
      case (false, true):
        _O_WRONLY
      case (false, false):
        0
      }
      flags |= _O_BINARY
      fd = _open_osfhandle(Int(bitPattern: handle), flags)
    }
#else
#warning("Platform-specific implementation missing: additional file descriptors unavailable")
#endif
    guard let fd, fd >= 0 else {
      return nil
    }

    return try? FileHandle(unsafePOSIXFileDescriptor: fd, mode: mode)
  }

  /// Make a string suitable for use as the value of an environment variable
  /// that describes the given file handle.
  ///
  /// - Parameters:
  ///   - fileHandle: The file handle to represent.
  ///
  /// - Returns: A string representation of `fileHandle` that can be converted
  ///   back to a (new) file handle with `_makeFileHandle()`, or `nil` if the
  ///   file handle could not be converted to a string.
  private static func _makeEnvironmentVariable(for fileHandle: borrowing FileHandle) -> String? {
#if SWT_TARGET_OS_APPLE || os(Linux) || os(FreeBSD) || os(OpenBSD)
    return fileHandle.withUnsafePOSIXFileDescriptor { fd in
      fd.map(String.init(describing:))
    }
#elseif os(Windows)
    return fileHandle.withUnsafeWindowsHANDLE { handle in
      handle.flatMap { String(describing: UInt(bitPattern: $0)) }
    }
#else
#warning("Platform-specific implementation missing: additional file descriptors unavailable")
    return nil
#endif
  }

  /// The ID of the exit test to run, if any, specified in the environment.
  static var environmentIDForEntryPoint: ID? {
    guard var idString = Environment.variable(named: Self._idEnvironmentVariableName) else {
      return nil
    }

    return try? idString.withUTF8 { idBuffer in
      try JSON.decode(ExitTest.ID.self, from: UnsafeRawBufferPointer(idBuffer))
    }
  }

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
    guard let id = environmentIDForEntryPoint, var result = find(identifiedBy: id) else {
      return nil
    }

    // Since an exit test was found, clear the environment variable. It's an
    // implementation detail and exit test code shouldn't be dependent on it.
    // Use ExitTest.current if needed!
    Environment.setVariable(nil, named: Self._idEnvironmentVariableName)

    // If an exit test was found, inject back channel handling into its body.
    // External tools authors should set up their own back channel mechanisms
    // and ensure they're installed before calling ExitTest.callAsFunction().
    guard let backChannel = _makeFileHandle(forEnvironmentVariableNamed: "SWT_BACKCHANNEL", mode: "wb") else {
      return result
    }

    // Set up the configuration for this process.
    var configuration = Configuration()

    // Encode events as JSON and write them to the back channel file handle.
    // Only forward issue-recorded events. (If we start handling other kinds of
    // events in the future, we can forward them too.)
    let eventHandler = ABI.BackChannelVersion.eventHandler(encodeAsJSONLines: true) { json in
      _ = try? backChannel.withLock {
        try backChannel.write(json)
        try backChannel.write("\n")
      }
    }
    configuration.eventHandler = { event, eventContext in
      switch event.kind {
      case .issueRecorded, .valueAttached, .testCancelled, .testCaseCancelled:
        eventHandler(event, eventContext)
      default:
        // Don't forward other kinds of event.
        break
      }
    }

    result.body = { [configuration, body = result.body] exitTest in
      Self._writeBarrierValues()
      defer {
        // We will generally not end up writing these values if the process
        // exits abnormally.
        Self._writeBarrierValues()
      }

      try await Configuration.withCurrent(configuration) {
        try exitTest._decodeCapturedValuesForEntryPoint()
        try await body(&exitTest)
      }
    }
    return result
  }

  /// The exit test handler used when integrating with Swift Package Manager via
  /// the `__swiftPMEntryPoint()` function.
  ///
  /// For a description of the inputs and outputs of this function, see the
  /// documentation for ``ExitTest/Handler``.
  static func handlerForEntryPoint() -> Handler {
    // The environment could change between invocations if a test calls setenv()
    // or unsetenv(), so we need to recompute the child environment each time.
    // The executable and XCTest bundle paths should not change over time, so we
    // can precompute them.
    let childProcessExecutablePath = Swift.Result { try CommandLine.executablePath }

    // Construct appropriate arguments for the child process. Generally these
    // arguments are going to be whatever's necessary to respawn the current
    // executable and get back into Swift Testing.
    let childArguments: [String] = {
      var result = [String]()

      let parentArguments = CommandLine.arguments
#if SWT_TARGET_OS_APPLE
      lazy var xctestTargetPath = Environment.variable(named: "XCTestBundlePath")
        ?? parentArguments.dropFirst().last
      // If the running executable appears to be the XCTest runner executable in
      // Xcode, figure out the path to the running XCTest bundle. If we can find
      // it, then we can re-run the host XCTestCase instance.
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
        result += ["-XCTest", "/", xctestTargetPath]
      }

      // When hosted by Swift Package Manager, forward all arguments to the
      // child process. (They aren't all meaningful in the context of an exit
      // test, but it keeps this code fairly simple!)
      lazy var isHostedBySwiftPM = parentArguments.contains("--test-bundle-path")
      if !isHostedByXCTest && isHostedBySwiftPM {
        result += parentArguments.dropFirst()
      }
#else
      // When hosted by Swift Package Manager, we'll need to specify exactly
      // which testing library to call into from the shared test executable.
      let hasTestingLibraryArgument: Bool = parentArguments.contains { $0.starts(with: "--testing-library") }
      if hasTestingLibraryArgument {
        result += ["--testing-library", "swift-testing"]
      }
#endif

      return result
    }()

    @Sendable func result(_ exitTest: borrowing ExitTest) async throws -> ExitTest.Result {
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
#endif

      if childEnvironment["SWIFT_BACKTRACE"] == nil {
        // Disable interactive backtraces unless explicitly enabled to reduce
        // the noise level during the exit test.
        childEnvironment["SWIFT_BACKTRACE"] = "enable=no"
      }

      // Insert a specific variable that tells the child process which exit test
      // to run.
      try JSON.withEncoding(of: exitTest.id) { json in
        childEnvironment[Self._idEnvironmentVariableName] = String(decoding: json, as: UTF8.self)
      }

      typealias ResultUpdater = @Sendable (inout ExitTest.Result) -> Void
      return try await withThrowingTaskGroup(of: ResultUpdater?.self) { taskGroup in
        // Set up stdout and stderr streams. By POSIX convention, stdin/stdout
        // are line-buffered by default and stderr is unbuffered by default.
        // SEE: https://en.cppreference.com/w/cpp/io/c/std_streams
        var stdoutReadEnd: FileHandle?
        var stdoutWriteEnd: FileHandle?
        if exitTest._observedValues.contains(\.standardOutputContent) {
          try FileHandle.makePipe(readEnd: &stdoutReadEnd, writeEnd: &stdoutWriteEnd)
          stdoutWriteEnd?.withUnsafeCFILEHandle { stdout in
            _ = setvbuf(stdout, nil, _IOLBF, Int(BUFSIZ))
          }
        }
        var stderrReadEnd: FileHandle?
        var stderrWriteEnd: FileHandle?
        if exitTest._observedValues.contains(\.standardErrorContent) {
          try FileHandle.makePipe(readEnd: &stderrReadEnd, writeEnd: &stderrWriteEnd)
          stderrWriteEnd?.withUnsafeCFILEHandle { stderr in
            _ = setvbuf(stderr, nil, _IONBF, Int(BUFSIZ))
          }
        }

        // Create a "back channel" pipe to handle events from the child process.
        var backChannelReadEnd: FileHandle!
        var backChannelWriteEnd: FileHandle!
        try FileHandle.makePipe(readEnd: &backChannelReadEnd, writeEnd: &backChannelWriteEnd)

        // Create another pipe to send captured values (and possibly other state
        // in the future) to the child process.
        var capturedValuesReadEnd: FileHandle!
        var capturedValuesWriteEnd: FileHandle!
        try FileHandle.makePipe(readEnd: &capturedValuesReadEnd, writeEnd: &capturedValuesWriteEnd)

        // Let the child process know how to find the back channel and
        // captured values channel by setting a known environment variable to
        // the corresponding file descriptor (HANDLE on Windows) for each.
        if let backChannelEnvironmentVariable = _makeEnvironmentVariable(for: backChannelWriteEnd) {
          childEnvironment["SWT_BACKCHANNEL"] = backChannelEnvironmentVariable
        }
        if let capturedValuesEnvironmentVariable = _makeEnvironmentVariable(for: capturedValuesReadEnd) {
          childEnvironment["SWT_CAPTURED_VALUES"] = capturedValuesEnvironmentVariable
        }

        // Spawn the child process.
        let processID = try withUnsafePointer(to: backChannelWriteEnd) { backChannelWriteEnd in
          try withUnsafePointer(to: capturedValuesReadEnd) { capturedValuesReadEnd in
            try spawnExecutable(
              atPath: childProcessExecutablePath,
              arguments: childArguments,
              environment: childEnvironment,
              standardOutput: stdoutWriteEnd,
              standardError: stderrWriteEnd,
              additionalFileHandles: [backChannelWriteEnd, capturedValuesReadEnd]
            )
          }
        }

        // Write the captured values blob over the back channel to the child
        // process. (If we end up needing to write additional data, we can
        // define a full schema for this stream. Fortunately, both endpoints are
        // implemented in the same copy of the testing library, so we don't have
        // to worry about backwards-compatibility.)
        try capturedValuesWriteEnd.withLock {
          try exitTest._withEncodedCapturedValuesForEntryPoint { capturedValuesJSON in
            try capturedValuesWriteEnd.write(capturedValuesJSON)
            try capturedValuesWriteEnd.write("\n")
          }
        }
        capturedValuesReadEnd.close()
        capturedValuesWriteEnd.close()

        // Await termination of the child process.
        taskGroup.addTask(name: decorateTaskName("exit test", withAction: "awaiting termination")) {
          let exitStatus = try await wait(for: processID)
          return { $0.exitStatus = exitStatus }
        }

        // Read back the stdout and stderr streams.
        if let stdoutReadEnd {
          stdoutWriteEnd?.close()
          taskGroup.addTask(name: decorateTaskName("exit test", withAction: "reading stdout")) {
            let standardOutputContent = try Self._trimToBarrierValues(stdoutReadEnd.readToEnd())
            return { $0.standardOutputContent = standardOutputContent }
          }
        }
        if let stderrReadEnd {
          stderrWriteEnd?.close()
          taskGroup.addTask(name: decorateTaskName("exit test", withAction: "reading stderr")) {
            let standardErrorContent = try Self._trimToBarrierValues(stderrReadEnd.readToEnd())
            return { $0.standardErrorContent = standardErrorContent }
          }
        }

        // Read back all data written to the back channel by the child process
        // and process it as a (minimal) event stream.
        backChannelWriteEnd.close()
        taskGroup.addTask(name: decorateTaskName("exit test", withAction: "processing events")) {
          Self._processRecords(fromBackChannel: backChannelReadEnd)
          return nil
        }

        // Collate the various bits of the result. The exit condition used here
        // is just a placeholder and will be replaced by the result of one of
        // the tasks above.
        var result = ExitTest.Result(exitStatus: .exitCode(EXIT_FAILURE))
        for try await update in taskGroup {
          update?(&result)
        }
        return result
      }
    }

    return result
  }

  /// Read lines from the given back channel file handle and process them as
  /// event records.
  ///
  /// - Parameters:
  ///   - backChannel: The file handle to read from. Reading continues until an
  ///     error is encountered or the end of the file is reached.
  private static func _processRecords(fromBackChannel backChannel: borrowing FileHandle) {
    let bytes: [UInt8]
    do {
      bytes = try backChannel.readToEnd()
    } catch {
      // NOTE: an error caught here indicates an I/O problem.
      // TODO: should we record these issues as systemic instead?
      Issue(for: error).record()
      return
    }

    for recordJSON in bytes.split(whereSeparator: \.isASCIINewline) where !recordJSON.isEmpty {
      do {
        try recordJSON.withUnsafeBufferPointer { recordJSON in
          try Self._processRecord(.init(recordJSON), fromBackChannel: backChannel)
        }
      } catch {
        // NOTE: an error caught here indicates a decoding problem.
        // TODO: should we record these issues as systemic instead?
        Issue(for: error).record()
      }
    }
  }

  /// Decode a line of JSON read from a back channel file handle and handle it
  /// as if the corresponding event occurred locally.
  ///
  /// - Parameters:
  ///   - recordJSON: The JSON to decode and process.
  ///   - backChannel: The file handle that `recordJSON` was read from.
  ///
  /// - Throws: Any error encountered attempting to decode or process the JSON.
  private static func _processRecord(_ recordJSON: UnsafeRawBufferPointer, fromBackChannel backChannel: borrowing FileHandle) throws {
    let record = try JSON.decode(ABI.Record<ABI.BackChannelVersion>.self, from: recordJSON)
    guard case let .event(event) = record.kind else {
      return
    }

    lazy var comments: [Comment] = event._comments?.map(Comment.init(rawValue:)) ?? []
    lazy var sourceContext = SourceContext(
      backtrace: nil, // A backtrace from the child process will have the wrong address space.
      sourceLocation: event._sourceLocation
    )
    lazy var skipInfo = SkipInfo(comment: comments.first, sourceContext: sourceContext)
    if let issue = event.issue {
      // Translate the issue back into a "real" issue and record it
      // in the parent process. This translation is, of course, lossy
      // due to the process boundary, but we make a best effort.
      let issueKind: Issue.Kind = if let error = issue._error {
        .errorCaught(error)
      } else {
        // TODO: improve fidelity of issue kind reporting (especially those without associated values)
        .unconditional
      }
      let severity: Issue.Severity = switch issue.severity {
      case .warning:
        .warning
      case .error, nil:
        // Prior to 6.3, all Issues are errors
        .error
      }
      var issueCopy = Issue(kind: issueKind, severity: severity, comments: comments, sourceContext: sourceContext)
      if issue.isKnown {
        // The known issue comment, if there was one, is already included in
        // the `comments` array above.
        issueCopy.knownIssueContext = Issue.KnownIssueContext()
      }
      issueCopy.record()
    } else if let attachment = event.attachment {
      Attachment.record(attachment, sourceLocation: event._sourceLocation!)
    } else if case .testCancelled = event.kind {
      _ = try? Test.cancel(with: skipInfo)
    } else if case .testCaseCancelled = event.kind {
      _ = try? Test.Case.cancel(with: skipInfo)
    }
  }

  /// Decode this exit test's captured values and update its ``capturedValues``
  /// property.
  ///
  /// - Throws: If a captured value could not be decoded.
  ///
  /// This function should only be used when the process was started via the
  /// `__swiftPMEntryPoint()` function. The effect of using it under other
  /// configurations is undefined.
  private mutating func _decodeCapturedValuesForEntryPoint() throws {
    // Read the content of the captured values stream provided by the parent
    // process above.
    guard let fileHandle = Self._makeFileHandle(forEnvironmentVariableNamed: "SWT_CAPTURED_VALUES", mode: "rb") else {
      return
    }
    let capturedValuesJSON = try fileHandle.readToEnd()
    let capturedValuesJSONLines = capturedValuesJSON.split(whereSeparator: \.isASCIINewline)
    assert(capturedValues.count == capturedValuesJSONLines.count, "Expected to decode \(capturedValues.count) captured value(s) for the current exit test, but received \(capturedValuesJSONLines.count). Please file a bug report at https://github.com/swiftlang/swift-testing/issues/new")

    // Walk the list of captured values' types, map them to their JSON blobs,
    // and decode them.
    capturedValues = try zip(capturedValues, capturedValuesJSONLines).map { capturedValue, capturedValueJSON in
      var capturedValue = capturedValue

      func open<T>(_ type: T.Type) throws -> T where T: Codable & Sendable {
        return try capturedValueJSON.withUnsafeBytes { capturedValueJSON in
          try JSON.decode(type, from: capturedValueJSON)
        }
      }
      capturedValue.wrappedValue = try open(capturedValue.typeOfWrappedValue)

      return capturedValue
    }
  }

  /// Encode this exit test's captured values in a format suitable for passing
  /// to the child process.
  ///
  /// - Parameters:
  ///   - body: A function to call. This function is called once per captured
  ///     value in the exit test.
  ///
  /// - Throws: Whatever is thrown by `body` or while encoding.
  ///
  /// This function produces a byte buffer representing each value in this exit
  /// test's ``capturedValues`` property and passes each buffer to `body`.
  ///
  /// This function should only be used when the process was started via the
  /// `__swiftPMEntryPoint()` function. The effect of using it under other
  /// configurations is undefined.
  private borrowing func _withEncodedCapturedValuesForEntryPoint(_ body: (UnsafeRawBufferPointer) throws -> Void) throws -> Void {
    for capturedValue in capturedValues {
      try JSON.withEncoding(of: capturedValue.wrappedValue!) { capturedValueJSON in
        try JSON.asJSONLine(capturedValueJSON, body)
      }
    }
  }
}
#endif
