# Exit tests

* Proposal: [SWT-NNNN](NNNN-exit-tests.md)
* Authors: [Jonathan Grynspan](https://github.com/grynspan)
* Status: **Awaiting review**
* Bug: [apple/swift-testing#157](https://github.com/apple/swift-testing/issues/157)
* Implementation: [apple/swift-testing#307](https://github.com/apple/swift-testing/pull/307)
* Review: TBD <!-- ([pitch](https://forums.swift.org/...)) -->

## Introduction

One of the first enhancement requests we received for swift-testing was the
ability to test for precondition failures and other critical failures that
terminate the current process when they occur. This feature is also frequently
requested for XCTest. With swift-testing, we have the opportunity to build such
a feature in an ergonomic way.

> [!NOTE]
> This feature has various names in the relevant literature, e.g. "exit tests",
> "death tests", "death assertions", "termination tests", etc. We consistently
> use the term "exit tests" to refer to them.

## Motivation

Imagine a function, implemented in a package, that includes a precondition:

```swift
func eat(_ taco: consuming Taco) {
  precondition(taco.isDelicious, "Tasty tacos only!")
  ...
}
```

Today, a test author can write unit tests for this function, but there is no way
to make sure that the function rejects a taco whose `isDelicious` property is
`false` because a test that passes such a taco as input will crash (correctly!)
when it calls `precondition()`.

An exit test allows testing this sort of functionality. The mechanism by which
an exit test is implemented varies between testing libraries and languages, but
a common implementation involves spawning a new process, performing the work
there, and checking that the spawned process ultimately terminates with a
particular (possibly platform-specific) exit status.

Adding exit tests to swift-testing would allow an entirely new class of tests
and would improve code coverage for existing test targets that adopt them.

## Proposed solution

This proposal introduces a new variant of the `#expect()` and `#require()`
macros that take, as an argument, a closure to be executed in a child process.
When called, these macros spawn a new process using the relevant
platform-specific interface (`posix_spawn()`, `CreateProcessW()`, etc.), call
the closure from within that process, and suspend the caller until that process
terminates. The exit status of the process is then compared against a known
value passed to the macro, allowing the test to pass or fail as appropriate.

## Detailed design

We will introduce the following new interfaces to the testing library:

```swift
/// An enumeration describing possible conditions under which an exit test will
/// succeed or fail.
///
/// Values of this type can be passed to
/// ``expect(exitsWith:_:sourceLocation:performing:)`` or
/// ``require(exitsWith:_:sourceLocation:performing:)`` to configure which exit
/// statuses should be considered successful.
#if SWT_NO_EXIT_TESTS
@available(*, unavailable, message: "Exit tests are not available on this platform.")
#endif
public enum ExitCondition: Sendable {
  /// The process terminated successfully with status `EXIT_SUCCESS`.
  public static var success: Self { get }

  /// The process terminated abnormally with any status other than
  /// `EXIT_SUCCESS` or with any signal.
  case failure

  /// The process terminated with the given exit code.
  ///
  /// - Parameters:
  ///   - exitCode: The exit code yielded by the process.
  ///
  /// The C programming language defines two standard exit codes, `EXIT_SUCCESS`
  /// and `EXIT_FAILURE`. Platforms may additionally define their own
  /// non-standard exit codes:
  ///
  /// | Platform | Header |
  /// |-|-|
  /// | macOS | `<stdlib.h>`, `<sysexits.h>` |
  /// | Linux | `<stdlib.h>`, `<sysexits.h>` |
  /// | Windows | `<stdlib.h>` |
  ///
  /// On POSIX-like systems including macOS and Linux, only the low unsigned 8
  /// bits (0&ndash;255) of the exit code are reliably preserved and reported to
  /// a parent process.
  case exitCode(_ exitCode: CInt)

  /// The process terminated with the given signal.
  ///
  /// - Parameters:
  ///   - signal: The signal that terminated the process.
  ///
  /// The C programming language defines a number of standard signals. Platforms
  /// may additionally define their own non-standard signal codes:
  ///
  /// | Platform | Header |
  /// |-|-|
  /// | macOS | `<signal.h>` |
  /// | Linux | `<signal.h>` |
  /// | Windows | `<signal.h>` |
  ///
  /// On Windows, by default, the C runtime will terminate a process with exit
  /// code `-3` if a raised signal is not handled, exactly as if `exit(-3)` were
  /// called. As a result, this case is unavailable on that platform. Developers
  /// should use ``failure`` instead when testing signal handling on Windows.
#if os(Windows)
  @available(*, unavailable, message: "On Windows, use .failure instead.")
#endif
  case signal(_ signal: CInt)
}

/// Check that an expression causes the process to terminate in a given fashion.
///
/// - Parameters:
///   - exitCondition: The expected exit condition.
///   - comment: A comment describing the expectation.
///   - sourceLocation: The source location to which recorded expectations and
///     issues should be attributed.
///   - expression: The expression to be evaluated.
///
/// Use this overload of `#expect()` when an expression will cause the current
/// process to terminate and the nature of that termination will determine if
/// the test passes or fails.
#if SWT_NO_EXIT_TESTS
@available(*, unavailable, message: "Exit tests are not available on this platform.")
#endif
@freestanding(expression) public macro expect(
  exitsWith exitCondition: ExitCondition,
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = SourceLocation(),
  performing expression: @convention(thin) () async -> Void
)

/// Check that an expression causes the process to terminate in a given fashion.
///
/// - Parameters:
///   - exitCondition: The expected exit condition.
///   - comment: A comment describing the expectation.
///   - sourceLocation: The source location to which recorded expectations and
///     issues should be attributed.
///   - expression: The expression to be evaluated.
///
/// Use this overload of `#require()` when an expression will cause the current
/// process to terminate and the nature of that termination will determine if
/// the test passes or fails.
#if SWT_NO_EXIT_TESTS
@available(*, unavailable, message: "Exit tests are not available on this platform.")
#endif
@freestanding(expression) public macro require(
  exitsWith exitCondition: ExitCondition,
  _ comment: @autoclosure () -> Comment? = nil,
  sourceLocation: SourceLocation = SourceLocation(),
  performing expression: @convention(thin) () async -> Void
)
```

> [!NOTE]
> `SWT_NO_EXIT_TESTS` is defined by the testing library when building for
> platforms that do not have the ability to spawn child processes (including
> iOS, watchOS, tvOS, visionOS, and WASI.) In other words, these interfaces are
> available on **macOS**, **Linux**, and **Windows**. `SWT_NO_EXIT_TESTS` is not
> defined during test target builds.

These macros can be used within a test function:

```swift
@Test("We only eat delicious tacos") func deliciousOnly() async {
  await #expect(exitsWith: .failure) {
    var taco = Taco()
    taco.isDelicious = false
    eat(taco)
  }
}
```

Given the definition of `eat(_:)` above, this test can be expected to hit a
precondition failure and crash the process; because `.failure` was the specified
exit condition, this is treated as a successful test.

There are some constraints on valid exit tests:

1. Because exit tests are run in child processes, they cannot capture any state
   from the calling context (hence their body closures are `@convention(thin)`
   or `@convention(c)`.)
1. Because exit tests need to know the current test in order to configure their
   child processes, they must run on a task where `Test.current` is not `nil`.
   Calling them from a detached task or from a native thread created outside the
   Swift concurrency domain will result in a runtime error.
1. Exit tests cannot recursively invoke other exit tests; this is a constraint
   that could potentially be lifted in the future, but it would be technically
   complex to do so.

## Source compatibility

This is a new interface that is unlikely to collide with any existing
client-provided interfaces. The typical Swift disambiguation tools can be used
if needed.

## Integration with supporting tools

SPI is provided to allow testing environments other than Swift Package Manager
to detect and run exit tests:

```swift
/// A type describing an exit test.
///
/// Instances of this type describe an exit test defined by the test author and
/// discovered or called at runtime.
@_spi(ForToolsIntegrationOnly)
public struct ExitTest: Sendable {
  /// The expected exit condition of the exit test.
  public var expectedExitCondition: ExitCondition

  /// The source location of the exit test.
  ///
  /// The source location is unique to each exit test and is consistent between
  /// processes, so it can be used to uniquely identify an exit test at runtime.
  public var sourceLocation: SourceLocation

  /// Call the exit test in the current process.
  public func callAsFunction() async -> Void

  /// Find the exit test function at the given source location.
  ///
  /// - Parameters:
  ///   - sourceLocation: The source location of the exit test to find.
  ///
  /// - Returns: The specified exit test function, or `nil` if no such exit test
  ///   could be found.
  public static func find(at sourceLocation: SourceLocation) -> Self?

  /// A handler that is invoked when an exit test starts.
  ///
  /// - Parameters:
  ///   - exitTest: The exit test that is starting.
  ///
  /// - Returns: The condition under which the exit test exited, or `nil` if the
  ///   exit test was not invoked.
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
  public typealias Handler = @Sendable (_ exitTest: borrowing ExitTest) async throws -> ExitCondition?
}

@_spi(ForToolsIntegrationOnly)
extension Configuration {
  /// A handler that is invoked when an exit test starts.
  ///
  /// For an explanation of how this property is used, see ``ExitTest/Handler``.
  ///
  /// When using the `swift test` command from Swift Package Manager, this
  /// property is pre-configured. Otherwise, the default value of this property
  /// records an issue indicating that it has not been configured.
  public var exitTestHandler: ExitTest.Handler
}
```

Any tools that use `swift build --build-tests`, `swift test`, or equivalent to
compile executables for testing will inherit the functionality provided for
`swift test` and do not need to implement their own exit test handlers. Tools
that directly compile test targets or otherwise do not leverage Swift Package
Manager will need to provide an implementation.

### Updated C entry point

To facilitate tools that handle test process lifetimes directly (instead of
relying on Swift Package Manager, Xcode, etc.) an updated ABI entry point
function will be provided. For more information about the ABI entry point, see
the previous [SWT-0002](0002-json-abi.md) proposal. Documentation for this entry
point function will be added to the [Documentation/ABI](../ABI) folder in the
Swift Testing repository.

## Future directions

### Support for iOS, WASI, etc.

The need for exit tests on other platforms is just as strong as it is on the
supported platforms (macOS, Linux, and Windows). These platforms do not support
spawning new processes, so a different mechanism for running exit tests would be
needed.

### Recursive exit tests

The technical constraints preventing recursive exit test invocation can be
resolved if there is a need to do so. However, we don't anticipate that this
constraint will be a serious issue for developers.

### Support for events in child processes

Test events generated in child processes (such as expectation failures other
than that of the exit test itself) are not propagated back to the parent process
because there is no dedicated communications channel for doing so. A future
direction sees us implementing such a channel so that those events are
communicated properly.

### Support for passing state

Arbitrary state is necessarily not preserved between the parent and child
processes, but there is little to prevent us from adding a variadic `arguments:`
argument and passing values whose types conform to `Codable`.

The blocker right now is that there is no type information during macro
expansion, meaning that the testing library can emit the glue code to _encode_
arguments, but does not know what types to use when _decoding_ those arguments.
If generic types were made available during macro expansion via the macro
expansion context, then it would be possible to synthesize the correct logic.

### Support for parsing standard output/error

The current proposal does not provide a mechanism for checking the contents of
the standard output or standard error streams in the child process. Such a
mechanism needs to be carefully considered as the size of each stream is
unbounded, but a general design might look like:

```swift
await #expect {
  var taco = Taco()
  taco.isDelicious = false
  eat(taco)
} exitsWith: { exitCondition, stdout, stderr in
  // stdout and stderr would be sequences of bytes that could be searched
  guard exitCondition ~= .failure,
        let stdout = String(validatingUTF8: stdout) else {
    return false
  }
  return stdout.contains("Tasty tacos only!")
}
```

This overload of `#expect()` is similar to `#expect(_:throws:)` which can be
used when the requirements for a thrown error are complex.

### Support for throwing errors from exit test bodies

Currently, throwing an error from an exit test is disallowed (exit test body
closures not having the `throws` keyword) because it is unclear what the effect
ought to be. A natural choice might be to propagate the error through the test
process' main function and allow the Swift runtime to handle it, but not all
configurations are created equal and it is not possible to do so consistently.

Since a thrown error is, by design, not necessarily a fatal condition in Swift,
it is reasonable to require exit tests to catch thrown errors (or, at least, use
`try!` to force the Swift runtime to handle them.) Error handling is an area we
can expand upon in the future if it proves to be important to exit test authors.

## Alternatives considered

- Doing nothing.

- Marking exit tests using a trait rather than a new `#expect()` overload:

  ```swift
  @Test("We only eat delicious tacos", .exits(with: .failure))
  func deliciousOnly() {
    var taco = Taco()
    taco.isDelicious = false
    eat(taco)
  }
  ```

  This syntax would require separate test functions for each exit test, while
  reusing the same function for relatively concise tests may be preferable.

  It would also potentially conflict with parameterized tests, as it is not
  possible to pass arbitrary parameters to the child process. It would be
  necessary to teach the testing library's macro target about the
  `.exits(with:)` trait so that it could produce a diagnostic when used with a
  parameterized test function.

- Inferring exit tests from test functions that return `Never`:

  ```swift
  @Test("No seafood for me, thanks!")
  func noSeafood() -> Never {
    var taco = Taco()
    taco.toppings.append(.shrimp)
    eat(taco)
    fatalError("Should not have eaten that!")
  }
  ```

  There's a certain synergy in inferring that a test function that returns
  `Never` must necessarily be a crasher and should be handled out of process.
  However, this forces the test author to add a call to `fatalError()` or
  similar in the event that the code under test does _not_ terminate, and there
  is no obvious way to express that a specific exit code, signal, or other
  condition is expected (as opposed to just "it exited".)

  We might want to support that sort of inference in the future (i.e. "don't run
  this test in-process because it will terminate the test run"), but without
  also inferring success or failure from the process' exit status.

- Naming the macro something else such as:

  - `#exits(with:_:)`;
  - `#exits(because:_:)`;
  - `#expect(exitsBecause:_:)`;
  - `#expect(terminatesBecause:_:)`; etc.

  While "with" is normally avoided in symbol names in Swift, it sometimes really
  is the best preposition for the job. "Because", "due to", and others don't
  sound "right" when the entire expression is read out loud. For example, you
  probably wouldn't say "exits due to success" in English.

- Changing the implementation of `precondition()`, `fatalError()`, etc. in the
  standard library so that they do not terminate the current process while
  testing, thus removing the need to spawn a child process for an exit test.

  Most of the functions in this family return `Never`, and changing their return
  types would be ABI-breaking (as well as a pessimization in production code.)
  Even if we did modify these functions in the Swift standard library, other
  ways to terminate the process exist and would not be covered:

  - Calling the C standard function `exit()`;
  - Throwing an uncaught Objective-C or C++ exception;
  - Sending a signal to the process; or
  - Misusing memory (e.g. trying to write to `0x0000_0000_0000_0000`.)

  Modifying the C or C++ standard library, or modifying the Objective-C runtime,
  would be well beyond the scope of this proposal.

## Acknowledgments

Many thanks to the XCTest and swift-testing team.
