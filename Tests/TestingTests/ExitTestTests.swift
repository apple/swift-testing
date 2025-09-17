//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

@testable @_spi(Experimental) @_spi(ForToolsIntegrationOnly) import Testing
private import _TestingInternals

#if !SWT_NO_EXIT_TESTS
@Suite("Exit test tests") struct ExitTestTests {
  @Test("Signal names are reported (where supported)") func signalName() {
    var hasSignalNames = false
#if SWT_TARGET_OS_APPLE || os(FreeBSD) || os(OpenBSD) || os(Android)
    hasSignalNames = true
#elseif os(Linux) && !SWT_NO_DYNAMIC_LINKING
    hasSignalNames = (symbol(named: "sigabbrev_np") != nil)
#endif

    let exitStatus = ExitStatus.signal(SIGABRT)
    if Bool(hasSignalNames) {
      #expect(String(describing: exitStatus) == ".signal(SIGABRT → \(SIGABRT))")
    } else {
      #expect(String(describing: exitStatus) == ".signal(\(SIGABRT))")
    }
  }

  @Test("Exit tests (passing)") func passing() async {
    await #expect(processExitsWith: .failure) {
      exit(EXIT_FAILURE)
    }
    if EXIT_SUCCESS != EXIT_FAILURE + 1 {
      await #expect(processExitsWith: .failure) {
        exit(EXIT_FAILURE + 1)
      }
    }
    await #expect(processExitsWith: .success) {}
    await #expect(processExitsWith: .success) {
      exit(EXIT_SUCCESS)
    }
    await #expect(processExitsWith: .exitCode(123)) {
      exit(123)
    }
    await #expect(processExitsWith: .exitCode(123)) {
      await Task.yield()
      exit(123)
    }
    await #expect(processExitsWith: .signal(SIGSEGV)) {
      _ = raise(SIGSEGV)
      // Allow up to 1s for the signal to be delivered. On some platforms,
      // raise() delivers signals fully asynchronously and may not terminate the
      // child process before this closure returns.
      if #available(_clockAPI, *) {
        try await Test.Clock.sleep(for: .seconds(1))
      } else {
        try await Task.sleep(nanoseconds: 1_000_000_000)
      }
    }
    await #expect(processExitsWith: .signal(SIGABRT)) {
      abort()
    }
#if !SWT_NO_UNSTRUCTURED_TASKS
#if false
    // Test the detached (no task-local configuration) path. Disabled because,
    // like other tests using Task.detached, it can interfere with other tests
    // running concurrently.
    #expect(Test.current != nil)
    await Task.detached {
      #expect(Test.current == nil)
      await #expect(processExitsWith: .failure) {
        fatalError()
      }
    }.value
#endif
#endif
  }

  @Test("Exit tests (failing)") func failing() async {
    await confirmation("Exit tests failed", expectedCount: 9) { failed in
      var configuration = Configuration()
      configuration.eventHandler = { event, _ in
        if case .issueRecorded = event.kind {
          failed()
        }
      }
      configuration.exitTestHandler = ExitTest.handlerForEntryPoint()

      await runTest(for: FailingExitTests.self, configuration: configuration)
    }
  }

  @Test("Mock exit test handlers (passing)") func passingMockHandler() async {
    await confirmation("System issue recorded", expectedCount: 0) { issueRecorded in
      var configuration = Configuration()
      configuration.eventHandler = { event, _ in
        if case .issueRecorded = event.kind {
          issueRecorded()
        }
      }

      // Mock an exit test where the process exits successfully.
      configuration.exitTestHandler = { _ in
        return ExitTest.Result(exitStatus: .exitCode(EXIT_SUCCESS))
      }
      await Test {
        await #expect(processExitsWith: .success) {}
      }.run(configuration: configuration)

      // Mock an exit test where the process exits with a particular error code.
      configuration.exitTestHandler = { _ in
        return ExitTest.Result(exitStatus: .exitCode(123))
      }
      await Test {
        await #expect(processExitsWith: .failure) {}
      }.run(configuration: configuration)

      // Mock an exit test where the process exits with a signal.
      configuration.exitTestHandler = { _ in
        return ExitTest.Result(exitStatus: .signal(SIGABRT))
      }
      await Test {
        await #expect(processExitsWith: .signal(SIGABRT)) {}
      }.run(configuration: configuration)
      await Test {
        await #expect(processExitsWith: .failure) {}
      }.run(configuration: configuration)
    }
  }

  @Test("Mock exit test handlers (failing)") func failingMockHandlers() async {
    await confirmation("Issue recorded", expectedCount: 6) { issueRecorded in
      var configuration = Configuration()
      configuration.eventHandler = { event, _ in
        if case .issueRecorded = event.kind {
          issueRecorded()
        }
      }

      // Mock exit tests that were expected to fail but passed.
      configuration.exitTestHandler = { _ in
        return ExitTest.Result(exitStatus: .exitCode(EXIT_SUCCESS))
      }
      await Test {
        await #expect(processExitsWith: .failure) {}
      }.run(configuration: configuration)
      await Test {
        await #expect(processExitsWith: .exitCode(EXIT_FAILURE)) {}
      }.run(configuration: configuration)
      await Test {
        await #expect(processExitsWith: .signal(SIGABRT)) {}
      }.run(configuration: configuration)

      // Mock exit tests that unexpectedly signalled.
      configuration.exitTestHandler = { _ in
        return ExitTest.Result(exitStatus: .signal(SIGABRT))
      }
      await Test {
        await #expect(processExitsWith: .exitCode(EXIT_SUCCESS)) {}
      }.run(configuration: configuration)
      await Test {
        await #expect(processExitsWith: .exitCode(EXIT_FAILURE)) {}
      }.run(configuration: configuration)
      await Test {
        await #expect(processExitsWith: .success) {}
      }.run(configuration: configuration)
    }
  }

  @Test("Exit test without configured exit test handler") func noHandler() async {
    await confirmation("System issue recorded") { issueRecorded in
      var configuration = Configuration()
      configuration.eventHandler = { event, _ in
        if case let .issueRecorded(issue) = event.kind, case .system = issue.kind {
          issueRecorded()
        }
      }

      await Test {
        await #expect(processExitsWith: .success) {}
      }.run(configuration: configuration)
    }
  }

  @Test("Exit test forwards issues") func forwardsIssues() async {
    await confirmation("Issue recorded") { issueRecorded in
      await confirmation("Error caught") { errorCaught in
        var configuration = Configuration()
        configuration.eventHandler = { event, _ in
          guard case let .issueRecorded(issue) = event.kind else {
            return
          }
          if case .unconditional = issue.kind, issue.comments.contains("Something went wrong!") {
            issueRecorded()
          } else if issue.error != nil {
            errorCaught()
          }
        }
        configuration.exitTestHandler = ExitTest.handlerForEntryPoint()

        await Test {
          await #expect(processExitsWith: .success) {
            #expect(Bool(false), "Something went wrong!")
            exit(0)
          }
          await #expect(processExitsWith: .failure) {
            Issue.record(MyError())
          }
        }.run(configuration: configuration)
      }
    }
  }

  private static let attachmentPayload = [UInt8](0...255)

  @Test("Exit test forwards attachments") func forwardsAttachments() async {
    await confirmation("Value attached") { valueAttached in
      var configuration = Configuration()
      configuration.eventHandler = { event, _ in
        guard case let .valueAttached(attachment) = event.kind else {
          return
        }
        #expect(throws: Never.self) {
          try attachment.withUnsafeBytes { bytes in
            #expect(Array(bytes) == Self.attachmentPayload)
          }
        }
        #expect(attachment.preferredName == "my attachment.bytes")
        valueAttached()
      }
      configuration.exitTestHandler = ExitTest.handlerForEntryPoint()

      await Test {
        await #expect(processExitsWith: .success) {
          Attachment.record(Self.attachmentPayload, named: "my attachment.bytes")
        }
      }.run(configuration: configuration)
    }
  }

#if !os(Linux)
  @Test("Exit test reports > 8 bits of the exit code")
  func fullWidthExitCode() async {
    // On POSIX-like platforms, we use waitid() which per POSIX should report
    // the full exit code, not just the low 8 bits. This behaviour is not
    // well-documented and not all platforms (as of this writing) report the
    // full value:
    //
    // | Platform             |  Bits Reported |
    // |----------------------|----------------|
    // | Darwin               |             32 |
    // | Linux                |              8 |
    // | Windows              | 32 (see below) |
    // | FreeBSD              |             32 |
    //
    // Other platforms may also have issues reporting the full value. This test
    // serves as a canary when adding new platforms that we need to document the
    // difference.
    //
    // Windows does not have the 8-bit exit code restriction and always reports
    // the full CInt value back to the testing library.
    await #expect(processExitsWith: .exitCode(512)) {
      exit(512)
    }
  }
#endif

  @MainActor static func someMainActorFunction() {
    MainActor.assertIsolated()
  }

  @Test("Exit test can be main-actor-isolated")
  @MainActor
  func mainActorIsolation() async {
    await #expect(processExitsWith: .success) {
      await Self.someMainActorFunction()
      _ = 0
      exit(EXIT_SUCCESS)
    }
  }

  @Test("Result is set correctly on success")
  func successfulArtifacts() async throws {
    // Test that basic passing exit tests produce the correct results (#expect)
    var result = await #expect(processExitsWith: .success) {
      exit(EXIT_SUCCESS)
    }
    #expect(result?.exitStatus == .exitCode(EXIT_SUCCESS))
    result = await #expect(processExitsWith: .exitCode(123)) {
      exit(123)
    }
    #expect(result?.exitStatus == .exitCode(123))

    // Test that basic passing exit tests produce the correct results (#require)
    result = try await #require(processExitsWith: .success) {
      exit(EXIT_SUCCESS)
    }
    #expect(result?.exitStatus == .exitCode(EXIT_SUCCESS))
    result = try await #require(processExitsWith: .exitCode(123)) {
      exit(123)
    }
    #expect(result?.exitStatus == .exitCode(123))
  }

  @Test("Result is nil on failure")
  func nilArtifactsOnFailure() async {
    // Test that an exit test that produces the wrong exit condition reports it
    // as an expectation failure, but also returns the exit condition (#expect)
    await confirmation("Expectation failed") { expectationFailed in
      var configuration = Configuration()
      configuration.eventHandler = { event, _ in
        if case let .issueRecorded(issue) = event.kind {
          if case .expectationFailed = issue.kind {
            expectationFailed()
          } else {
            issue.record()
          }
        }
      }
      configuration.exitTestHandler = { _ in
        ExitTest.Result(exitStatus: .exitCode(123))
      }

      await Test {
        let result = await #expect(processExitsWith: .success) {}
        #expect(result == nil)
      }.run(configuration: configuration)
    }

    // Test that an exit test that produces the wrong exit condition throws an
    // ExpectationFailedError (#require)
    await confirmation("Expectation failed") { expectationFailed in
      var configuration = Configuration()
      configuration.eventHandler = { event, _ in
        if case let .issueRecorded(issue) = event.kind {
          if case .expectationFailed = issue.kind {
            expectationFailed()
          } else {
            issue.record()
          }
        }
      }
      configuration.exitTestHandler = { _ in
        ExitTest.Result(exitStatus: .exitCode(EXIT_FAILURE))
      }

      await Test {
        try await #require(processExitsWith: .success) {}
        Issue.record("#require(processExitsWith:) should have thrown an error")
      }.run(configuration: configuration)
    }
  }

  @Test("Result is nil on system failure")
  func nilArtifactsOnSystemFailure() async {
    // Test that an exit test that fails to start due to a system error produces
    // a .system issue and reports .failure as its exit condition.
    await confirmation("System issue recorded") { systemIssueRecorded in
      await confirmation("Expectation failed") { expectationFailed in
        var configuration = Configuration()
        configuration.eventHandler = { event, _ in
          if case let .issueRecorded(issue) = event.kind {
            if case .system = issue.kind {
              systemIssueRecorded()
            } else if case .expectationFailed = issue.kind {
              expectationFailed()
            } else {
              issue.record()
            }
          }
        }
        configuration.exitTestHandler = { _ in
          throw MyError()
        }

        await Test {
          let result = await #expect(processExitsWith: .success) {}
          #expect(result == nil)
        }.run(configuration: configuration)
      }
    }
  }

  @Test("Result contains stdout/stderr")
  func exitTestResultContainsStandardStreams() async throws {
    var result = try await #require(processExitsWith: .success, observing: [\.standardOutputContent]) {
      try FileHandle.stdout.write("STANDARD OUTPUT")
      try FileHandle.stderr.write(String("STANDARD ERROR".reversed()))
      exit(EXIT_SUCCESS)
    }
    #expect(result.exitStatus == .exitCode(EXIT_SUCCESS))
    #expect(result.standardOutputContent.contains("STANDARD OUTPUT".utf8))
    #expect(!result.standardOutputContent.contains(ExitTest.barrierValue))
    #expect(result.standardErrorContent.isEmpty)

    result = try await #require(processExitsWith: .success, observing: [\.standardErrorContent]) {
      try FileHandle.stdout.write("STANDARD OUTPUT")
      try FileHandle.stderr.write(String("STANDARD ERROR".reversed()))
      exit(EXIT_SUCCESS)
    }
    #expect(result.exitStatus == .exitCode(EXIT_SUCCESS))
    #expect(result.standardOutputContent.isEmpty)
    #expect(result.standardErrorContent.contains("STANDARD ERROR".utf8.reversed()))
    #expect(!result.standardErrorContent.contains(ExitTest.barrierValue))
  }

  @Test("Arguments to the macro are not captured during expansion (do not need to be literals/const)")
  func argumentsAreNotCapturedDuringMacroExpansion() async throws {
    let unrelatedSourceLocation = #_sourceLocation
    func nonConstExitCondition() async throws -> ExitTest.Condition {
      .failure
    }
    await #expect(processExitsWith: try await nonConstExitCondition(), sourceLocation: unrelatedSourceLocation) {
      fatalError()
    }
  }

  @Test("ExitTest.current property")
  func currentProperty() async {
    #expect((ExitTest.current == nil) as Bool)
    await #expect(processExitsWith: .success) {
      #expect((ExitTest.current != nil) as Bool)
    }
  }

  @Test("Issue severity")
  func issueSeverity() async {
    await confirmation("Recorded issue had warning severity") { wasWarning in
      var configuration = Configuration()
      configuration.eventHandler = { event, _ in
        if case let .issueRecorded(issue) = event.kind, issue.severity == .warning {
          wasWarning()
        }
      }

      // Mock an exit test where the process exits successfully.
      configuration.exitTestHandler = ExitTest.handlerForEntryPoint()
      await Test {
        await #expect(processExitsWith: .success) {
          Issue.record("Issue recorded", severity: .warning)
        }
      }.run(configuration: configuration)
    }
  }

  @Test("Capture list")
  func captureList() async {
    let i = 123
    let s = "abc" as Any
    await #expect(processExitsWith: .success) { [i = i as Int, s = s as! String, t = (s as Any) as? String?] in
      #expect(i == 123)
      #expect(s == "abc")
      #expect(t == "abc")
    }
  }

  @Test("Capture list (very long encoded form)")
  func longCaptureList() async {
    let count = 1 * 1024 * 1024
    let buffer = Array(repeatElement(0 as UInt8, count: count))
    await #expect(processExitsWith: .success) { [count = count as Int, buffer = buffer as [UInt8]] in
      #expect(buffer.count == count)
    }
  }

  struct CapturableSuite: Codable {
    var property = 456

    @Test("self in capture list")
    func captureListWithSelf() async {
      await #expect(processExitsWith: .success) { [self, x = self, y = self as Self] in
        #expect(self.property == 456)
        #expect(x.property == 456)
        #expect(y.property == 456)
      }
    }
  }

  class CapturableBaseClass: @unchecked Sendable, Codable {
    init() {}

    required init(from decoder: any Decoder) throws {}
    func encode(to encoder: any Encoder) throws {}
  }

  final class CapturableDerivedClass: CapturableBaseClass, @unchecked Sendable {
    let x: Int

    init(x: Int) {
      self.x = x
      super.init()
    }

    required init(from decoder: any Decoder) throws {
      let container = try decoder.singleValueContainer()
      self.x = try container.decode(Int.self)
      super.init()
    }

    override func encode(to encoder: any Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(x)
    }
  }

  @Test("Capturing an instance of a subclass")
  func captureSubclass() async {
    let instance = CapturableDerivedClass(x: 123)
    await #expect(processExitsWith: .success) { [instance = instance as CapturableBaseClass] in
      #expect((instance as AnyObject) is CapturableBaseClass)
      // However, because the static type of `instance` is not Derived, we won't
      // be able to cast it to Derived.
      #expect(!((instance as AnyObject) is CapturableDerivedClass))
    }
    await #expect(processExitsWith: .success) { [instance = instance as CapturableDerivedClass] in
      #expect((instance as AnyObject) is CapturableBaseClass)
      #expect((instance as AnyObject) is CapturableDerivedClass)
      #expect(instance.x == 123)
    }
  }

  @Test("Capturing a parameter to the test function")
  func captureListWithParameter() async {
    let i = Int.random(in: 0 ..< 1000)

    func f(j: Int) async {
      await #expect(processExitsWith: .success) { [i = i as Int, j] in
        #expect(i == j)
        #expect(j >= 0)
        #expect(j < 1000)
      }
    }
    await f(j: i)

    await { (j: Int) in
      _ = await #expect(processExitsWith: .success) { [i = i as Int, j] in
        #expect(i == j)
        #expect(j >= 0)
        #expect(j < 1000)
      }
    }(i)

#if false // intentionally fails to compile
    // FAILS TO COMPILE: shadowing `i` with a variable of a different type will
    // prevent correct expansion (we need an equivalent of decltype() for that.)
    func g(i: Int) async {
      let i = String(i)
      await #expect(processExitsWith: .success) { [i] in
        #expect(!i.isEmpty)
      }
    }
#endif
  }

  @Test("Capturing a literal expression")
  func captureListWithLiterals() async {
    await #expect(processExitsWith: .success) { [i = 0, f = 1.0, s = "", b = true] in
      #expect(i == 0)
      #expect(f == 1.0)
      #expect(s == "")
      #expect(b == true)
    }
  }

  @Test("Capturing #_sourceLocation")
  func captureListPreservesSourceLocationMacro() async {
    func sl(_ sl: SourceLocation = #_sourceLocation) -> SourceLocation {
      sl
    }
    await #expect(processExitsWith: .success) { [sl = sl() as SourceLocation] in
      #expect(sl.fileID == #fileID)
    }
  }

  @Test("Capturing an optional value")
  func captureListWithOptionalValue() async throws {
    await #expect(processExitsWith: .success) { [x = nil as Int?] in
      #expect(x != 1)
    }
    await #expect(processExitsWith: .success) { [x = (0 as Any) as? String] in
      #expect(x == nil)
    }
  }

  @Test("Capturing an effectful expression")
  func captureListWithEffectfulExpression() async throws {
    func f() async throws -> Int { 0 }
    try await #require(processExitsWith: .success) { [f = try await f() as Int] in
      #expect(f == 0)
    }
    try await #expect(processExitsWith: .success) { [f = f() as Int] in
      #expect(f == 0)
    }
  }

#if false // intentionally fails to compile
  @Test("Capturing a tuple")
  func captureListWithTuple() async throws {
    // A tuple whose elements conform to Codable does not itself conform to
    // Codable, so we cannot actually express this capture list in a way that
    // works with #expect().
    await #expect(processExitsWith: .success) { [x = (0 as Int, 1 as Double, "2" as String)] in
      #expect(x.0 == 0)
      #expect(x.1 == 1)
      #expect(x.2 == "2")
    }
  }
#endif

#if false // intentionally fails to compile
  struct NonCodableValue {}

  // We can't capture a value that isn't Codable. A unit test is not possible
  // for this case as the type checker needs to get involved.
  @Test("Capturing a move-only value")
  func captureListWithMoveOnlyValue() async {
    let x = NonCodableValue()
    await #expect(processExitsWith: .success) { [x = x as NonCodableValue] in
      _ = x
    }
  }
#endif
}

// MARK: - Fixtures

@Suite(.hidden) struct FailingExitTests {
  @Test(.hidden) func failingExitTests() async {
    await #expect(processExitsWith: .failure) {}
    await #expect(processExitsWith: .exitCode(123)) {}
    await #expect(processExitsWith: .failure) {
      exit(EXIT_SUCCESS)
    }
    await #expect(processExitsWith: .success) {
      exit(EXIT_FAILURE)
    }
    await #expect(processExitsWith: .exitCode(123)) {
      exit(0)
    }

    await #expect(processExitsWith: .exitCode(SIGABRT)) {
      // abort() raises on Windows, but we don't handle that yet and it is
      // reported as .failure (which will fuzzy-match with SIGABRT.)
      abort()
    }
    await #expect(processExitsWith: .signal(123)) {}
    await #expect(processExitsWith: .signal(123)) {
      exit(123)
    }
    await #expect(processExitsWith: .signal(SIGSEGV)) {
      abort() // sends SIGABRT, not SIGSEGV
    }
  }
}

#if false // intentionally fails to compile
@Test(.hidden, arguments: 100 ..< 200)
func sellIceCreamCones(count: Int) async throws {
  try await #require(processExitsWith: .failure) {
    precondition(count < 10, "Too many ice cream cones")
  }
}
#endif
#endif
