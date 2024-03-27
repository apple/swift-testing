# Migrating a test from XCTest

<!--
This source file is part of the Swift.org open source project

Copyright (c) 2023 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

<!-- NOTE: The voice of this document is directed at the second person ("you")
because it provides instructions the reader must follow directly. -->

Migrate an existing test method or test class written using XCTest.

## Overview

The testing library provides much of the same functionality of XCTest, but uses
its own syntax to declare test functions and types. This document covers the
process of converting XCTest-based content to use the testing library instead.

### Adding the testing library as a dependency

Before the testing library can be used, it must be added as a dependency of your
Swift package or Xcode project. For more information on how to add it, see the
[Getting Started](doc:TemporaryGettingStarted) guide.

### Importing the testing library

XCTest and the testing library are available from different modules. Instead of 
importing the XCTest module, import the Testing module:

@Row {
  @Column {
    ```swift
    // Before
    import XCTest
    ```
  }
  @Column {
    ```swift
    // After
    import Testing
    ```
  }
}

A single source file can contain tests written with XCTest as well as other 
tests written with the testing library. Import both XCTest and Testing if a 
source file contains mixed test content.

### Converting test classes

XCTest groups related sets of test methods in test classes: classes that inherit
from the [`XCTestCase`](https://developer.apple.com/documentation/xctest/xctestcase)
class provided by the XCTest framework. The testing library does not require
that test functions be instance members of types. Instead, they can be _free_ or
_global_ functions, or can be `static` or `class` members of a type.

If you want to group your test functions together, you can do so by placing them
in a Swift type. The testing library refers to such a type as a _suite_. These
types do _not_ need to be classes, and they do not inherit from `XCTestCase`.

To convert a subclass of `XCTestCase` to a suite, remove the `XCTestCase`
conformance. It is also generally recommended that a Swift structure or actor be
used instead of a class because it allows the Swift compiler to better-enforce
concurrency safety:

@Row {
  @Column {
    ```swift
    // Before
    class FoodTruckTests: XCTestCase {
      ...
    }
    ```
  }
  @Column {
    ```swift
    // After
    struct FoodTruckTests {
      ...
    }
    ```
  }
}

If you use a class as a test suite, it must be declared `final`.

For more information about suites and how to declare and customize them, see
<doc:OrganizingTests>.

#### Converting setUp() and tearDown() functions

In XCTest, code can be scheduled to run before and after a test using the
[`setUp()`](https://developer.apple.com/documentation/xctest/xctest/3856481-setup)
and [`tearDown()`](https://developer.apple.com/documentation/xctest/xctest/3856482-teardown)
family of functions. When writing tests using the testing library, implement
`init()` and/or `deinit` instead:

@Row {
  @Column {
    ```swift
    // Before
    class FoodTruckTests: XCTestCase {
      var batteryLevel: NSNumber!
      override func setUp() async throws {
        batteryLevel = 100
      }
      ...
    }
    ```
  }
  @Column {
    ```swift
    // After
    struct FoodTruckTests {
      var batteryLevel: NSNumber
      init() async throws {
        batteryLevel = 100
      }
      ...
    }
    ```
  }
}

The use of `async` and `throws` is optional. If teardown is needed, declare your
test suite as a `final` class or as an actor rather than as a structure and
implement `deinit`:

@Row {
  @Column {
    ```swift
    // Before
    class FoodTruckTests: XCTestCase {
      var batteryLevel: NSNumber!
      override func setUp() async throws {
        batteryLevel = 100
      }
      override func tearDown() {
        batteryLevel = 0 // drain the battery
      }
      ...
    }
    ```
  }
  @Column {
    ```swift
    // After
    final class FoodTruckTests {
      var batteryLevel: NSNumber
      init() async throws {
        batteryLevel = 100
      }
      deinit {
        batteryLevel = 0 // drain the battery
      }
      ...
    }
    ```
  }
}

<!--
- Bug: `deinit` cannot be asynchronous or throwing, unlike `tearDown()`.
  ((103616215)[rdar://103616215])
-->

### Converting test methods

The testing library represents individual tests as functions, similar to how
they are represented in XCTest. However, the syntax for declaring a test
function is different. In XCTest, a test method must be a member of a test class
and its name must start with `test`. The testing library does not require a test
function to have any particular name. Instead, it identifies a test function by
the presence of the `@Test` attribute:

@Row {
  @Column {
    ```swift
    // Before
    class FoodTruckTests: XCTestCase {
      func testEngineWorks() { ... }
      ...
    }
    ```
  }
  @Column {
    ```swift
    // After
    struct FoodTruckTests {
      @Test func engineWorks() { ... }
      ...
    }
    ```
  }
}

As with XCTest, the testing library allows test functions to be marked `async`
and/or `throws` and to be isolated to a global actor (for example, by using the
`@MainActor` attribute.)

- Note: XCTest runs synchronous test methods on the main actor by default, while
  the testing library runs all test functions on an arbitrary task. If a test
  function must run on the main thread, isolate it to the main actor with
  `@MainActor`, or run the thread-sensitive code inside a call to
  [`MainActor.run(resultType:body:)`](https://developer.apple.com/documentation/swift/mainactor/run(resulttype:body:)).

For more information about test functions and how to declare and customize them,
see <doc:DefiningTests>.

#### Converting XCTAssert() XCTUnwrap(), and XCTFail() calls

XCTest uses a family of approximately 40 functions to assert test requirements.
These functions are collectively referred to as
[`XCTAssert()`](https://developer.apple.com/documentation/xctest/1500669-xctassert).
The testing library has two replacements, ``expect(_:_:sourceLocation:)`` and
``require(_:_:sourceLocation:)-5l63q``. They both behave similarly to
`XCTAssert()` except that ``require(_:_:sourceLocation:)-5l63q`` will throw an
error if its condition is not met:

@Row {
  @Column {
    ```swift
    // Before
    class FoodTruckTests: XCTestCase {
      func testEngineWorks() throws {
        let engine = FoodTruck.shared.engine
        XCTAssertNotNil(engine.parts.first)
        XCTAssertGreaterThan(engine.batteryLevel, 0)
        try engine.start()
        XCTAssertTrue(engine.isRunning)
      }
      ...
    }
    ```
  }
  @Column {
    ```swift
    // After
    struct FoodTruckTests {
      @Test func engineWorks() throws {
        let engine = FoodTruck.shared.engine
        try #require(engine.parts.first != nil)
        #expect(engine.batteryLevel > 0)
        try engine.start()
        #expect(engine.isRunning)
      }
      ...
    }
    ```
  }
}

XCTest also has a function, [`XCTUnwrap()`](https://developer.apple.com/documentation/xctest/3380195-xctunwrap),
that tests if an optional value is `nil` and throws an error if it is. When
using the testing library, you can use ``require(_:_:sourceLocation:)-6w9oo``
with optional expressions to unwrap them:

@Row {
  @Column {
    ```swift
    // Before
    class FoodTruckTests: XCTestCase {
      func testEngineWorks() throws {
        let engine = FoodTruck.shared.engine
        let part = try XCTUnwrap(engine.parts.first)
        ...
      }
      ...
    }
    ```
  }
  @Column {
    ```swift
    // After
    struct FoodTruckTests {
      @Test func engineWorks() throws {
        let engine = FoodTruck.shared.engine
        let part = try #require(engine.parts.first)
        ...
      }
      ...
    }
    ```
  }
}

Finally, XCTest has a function, [`XCTFail()`](https://developer.apple.com/documentation/xctest/1500970-xctfail),
that causes a test to fail immediately and unconditionally. This function is
useful when the syntax of the language prevents the use of an `XCTAssert()`
function. To record an unconditional issue using the testing library, use the
``Issue/record(_:fileID:filePath:line:column:)`` function:

@Row {
  @Column {
    ```swift
    // Before
    class FoodTruckTests: XCTestCase {
      func testEngineWorks() {
        let engine = FoodTruck.shared.engine
        guard case .electric = engine else {
          XCTFail("Engine is not electric")
          return
        }
        ...
      }
      ...
    }
    ```
  }
  @Column {
    ```swift
    // After
    struct FoodTruckTests {
      @Test func engineWorks() {
        let engine = FoodTruck.shared.engine
        guard case .electric = engine else {
          Issue.record("Engine is not electric")
          return
        }
        ...
      }
      ...
    }
    ```
  }
}

-----

The following table includes a list of the various `XCTAssert()` functions and
their equivalents in the testing library:

| XCTest | swift-testing |
|-|-|
| `XCTAssert(x)`, `XCTAssertTrue(x)` | `#expect(x)` |
| `XCTAssertFalse(x)` | `#expect(!x)` |
| `XCTAssertNil(x)` | `#expect(x == nil)` |
| `XCTAssertNotNil(x)` | `#expect(x != nil)` |
| `XCTAssertEqual(x, y)` | `#expect(x == y)` |
| `XCTAssertNotEqual(x, y)` | `#expect(x != y)` |
| `XCTAssertIdentical(x, y)` | `#expect(x === y)` |
| `XCTAssertNotIdentical(x, y)` | `#expect(x !== y)` |
| `XCTAssertGreaterThan(x, y)` | `#expect(x > y)` |
| `XCTAssertGreaterThanOrEqual(x, y)` | `#expect(x >= y)` |
| `XCTAssertLessThanOrEqual(x, y)` | `#expect(x <= y)` |
| `XCTAssertLessThan(x, y)` | `#expect(x < y)` |
| `XCTAssertThrowsError(try f())` | `#expect(throws: (any Error).self) { try f() }` |
| `XCTAssertThrowsError(try f()) { error in … }` | `#expect { try f() } throws: { error in return … }` |
| `XCTAssertNoThrow(try f())` | `#expect(throws: Never.self) { try f() }` |
| `try XCTUnwrap(x)` | `try #require(x)` |
| `XCTFail("…")` | `Issue.record("…")` |

- Note: When comparing two numeric values within a specified accuracy, i.e. the
analogue of [`XCTAssertEqual(_:_:accuracy:_:file:line:)`](https://developer.apple.com/documentation/xctest/3551607-xctassertequal)
, please import [the swift-numerics package](https://github.com/apple/swift-numerics)
and use the ``isApproximatelyEqual()`` function.

#### Continuing or halting after test failures

An instance of an `XCTestCase` subclass can set its
[`continueAfterFailure`](https://developer.apple.com/documentation/xctest/xctestcase/1496260-continueafterfailure)
property to `false` to cause a test to stop running after a failure occurs.
XCTest stops an affected test by throwing an Objective-C exception at the
time the failure occurs.

- Note: `continueAfterFailure` is not fully supported when using the
  [swift-corelibs-xctest](https://github.com/apple/swift-corelibs-xctest)
  library on non-Apple platforms.

The behavior of an exception thrown through a Swift stack frame is undefined. If
an exception is thrown through an `async` Swift function, it typically causes
the process to terminate abnormally, preventing other tests from running.

The testing library does not use exceptions to stop test functions. Instead, use
the ``require(_:_:sourceLocation:)-5l63q`` macro, which throws a Swift error on
failure:

@Row {
  @Column {
    ```swift
    // Before
    class FoodTruckTests: XCTestCase {
      func testTruck() async {
        continueAfterFailure = false
        XCTAssertTrue(FoodTruck.shared.isLicensed)
        ...
      }
      ...
    }
    ```
  }
  @Column {
    ```swift
    // After
    struct FoodTruckTests {
      @Test func truck() throws {
        try #require(FoodTruck.shared.isLicensed)
        ...
      }
      ...
    }
    ```
  }
}

When using either `continueAfterFailure` or
``require(_:_:sourceLocation:)-5l63q``, other tests will continue to run after
the failed test method or test function.

#### Converting XCTestExpectation and XCTWaiter

XCTest has a class, [`XCTestExpectation`](https://developer.apple.com/documentation/xctest/xctestexpectation),
that represents some asynchronous condition. A developer creates an instance of
this class (or a subclass like [`XCTKeyPathExpectation`](https://developer.apple.com/documentation/xctest/xctkeypathexpectation))
using an initializer or a convenience method on `XCTestCase`. When the condition
represented by an expectation occurs, the developer _fulfills_ the expectation.
Concurrently, the developer _waits for_ the expectation to be fulfilled using an
instance of [`XCTWaiter`](https://developer.apple.com/documentation/xctest/xctwaiter)
or using a convenience method on `XCTestCase`.

Wherever possible, prefer to use Swift concurrency to validate asynchronous
conditions. For example, if it is necessary to determine the result of an
asynchronous Swift function, it can be awaited with `await`. For a function that
takes a completion handler but which does not use `await`, a Swift
[continuation](https://developer.apple.com/documentation/swift/withcheckedcontinuation(function:_:))
can be used to convert the call into an `async`-compatible one.

Some tests, especially those that test asynchronously-delivered events, cannot
be readily converted to use Swift concurrency. The testing library offers
functionality called _confirmations_ which can be used to implement these tests.
Instances of ``Confirmation`` are created and used within the scope of the
function ``confirmation(_:expectedCount:fileID:filePath:line:column:_:)``.

Confirmations function similarly to XCTest's expectations, however they do not
block or suspend the caller while waiting for a condition to be fulfilled.
Instead, the requirement is expected to be _confirmed_ (the equivalent of
_fulfilling_ an expectation) before `confirmation()` returns, and an issue is
recorded otherwise:

@Row {
  @Column {
    ```swift
    // Before
    class FoodTruckTests: XCTestCase {
      func testTruckEvents() async {
        let soldFood = expectation(description: "…")
        FoodTruck.shared.eventHandler = { event in
          if case .soldFood = event {
            soldFood.fulfill()
          }
        }
        await Customer().buy(.soup)
        await fulfillment(of: [soldFood])
        ...
      }
      ...
    }
    ```
  }
  @Column {
    ```swift
    // After
    struct FoodTruckTests {
      @Test func truckEvents() async {
        await confirmation("…") { soldFood in
          FoodTruck.shared.eventHandler = { event in
            if case .soldFood = event {
              soldFood()
            }
          }
          await Customer().buy(.soup)
        }
        ...
      }
      ...
    }
    ```
  }
}

#### Converting XCTSkip(), XCTSkipIf(), and XCTSkipUnless() calls

When using XCTest, the [`XCTSkip`](https://developer.apple.com/documentation/xctest/xctskip)
error type can be thrown to bypass the remainder of a test function. As well,
the [`XCTSkipIf()`](https://developer.apple.com/documentation/xctest/3521325-xctskipif)
and [`XCTSkipUnless()`](https://developer.apple.com/documentation/xctest/3521326-xctskipunless)
functions can be used to conditionalize the same action. The testing library
allows developers to skip a test function or an entire test suite before it
starts running using the ``ConditionTrait`` trait type. Annotate a test suite or
test function with an instance of this trait type to control whether it runs:

@Row {
  @Column {
    ```swift
    // Before
    class FoodTruckTests: XCTestCase {
      func testArepasAreTasty() throws {
        try XCTSkipIf(CashRegister.isEmpty)
        try XCTSkipUnless(FoodTruck.sells(.arepas))
        ...
      }
      ...
    }
    ```
  }
  @Column {
    ```swift
    // After
    @Suite(.disabled(if: CashRegister.isEmpty))
    struct FoodTruckTests {
      @Test(.enabled(if: FoodTruck.sells(.arepas)))
      func arepasAreTasty() {
        ...
      }
      ...
    }
    ```
  }
}

#### Converting XCTExpectFailure() calls

A test may have a known issue that sometimes or always prevents it from passing.
When written using XCTest, such tests can call
[`XCTExpectFailure(_:options:failingBlock:)`](https://developer.apple.com/documentation/xctest/3727246-xctexpectfailure)
to tell XCTest and its infrastructure that the issue should not cause the test
to fail. The testing library has an equivalent function with synchronous and
asynchronous variants:

- ``withKnownIssue(_:isIntermittent:fileID:filePath:line:column:_:)-5pxnd``
- ``withKnownIssue(_:isIntermittent:fileID:filePath:line:column:_:)-30kgk``

This function can be used to annotate a section of a test as having a known
issue:

@Row {
  @Column {
    ```swift
    // Before
    class FoodTruckTests: XCTestCase {
      func testGrillWorks() async {
        XCTExpectFailure("Grill is out of fuel") {
          try FoodTruck.shared.grill.start()
        }
        ...
      }
      ...
    }
    ```
  }
  @Column {
    ```swift
    // After
    struct FoodTruckTests {
      @Test func grillWorks() async {
        withKnownIssue("Grill is out of fuel") {
          try FoodTruck.shared.grill.start()
        }
        ...
      }
      ...
    }
    ```
  }
}

- Note: The XCTest function [`XCTExpectFailure(_:options:)`](https://developer.apple.com/documentation/xctest/3727245-xctexpectfailure),
  which does not take a closure and which affects the remainder of the test,
  does not have a direct equivalent in the testing library. To mark an entire
  test as having a known issue, wrap its body in a call to `withKnownIssue()`. 

If a test may fail intermittently, the call to
`XCTExpectFailure(_:options:failingBlock:)` can be marked _non-strict_. When
using the testing library, specify that the known issue is _intermittent_
instead:

@Row {
  @Column {
    ```swift
    // Before
    class FoodTruckTests: XCTestCase {
      func testGrillWorks() async {
        XCTExpectFailure(
          "Grill may need fuel",
          options: .nonStrict()
        ) {
          try FoodTruck.shared.grill.start()
        }
        ...
      }
      ...
    }
    ```
  }
  @Column {
    ```swift
    // After
    struct FoodTruckTests {
      @Test func grillWorks() async {
        withKnownIssue(
          "Grill may need fuel", 
          isIntermittent: true
        ) {
          try FoodTruck.shared.grill.start()
        }
        ...
      }
      ...
    }
    ```
  }
}

Additional options can be specified when calling `XCTExpectFailure()`:

- [`isEnabled`](https://developer.apple.com/documentation/xctest/xctexpectedfailure/options/3726085-isenabled)
  can be set to `false` to skip known-issue matching (for instance, if a
  particular issue only occurs under certain conditions); and
- [`issueMatcher`](https://developer.apple.com/documentation/xctest/xctexpectedfailure/options/3726086-issuematcher)
  can be set to a closure to allow marking only certain issues as known and to
  allow other issues to be recorded as test failures.

The testing library includes overloads of `withKnownIssue()` that take
additional arguments with similar behavior:

- ``withKnownIssue(_:isIntermittent:fileID:filePath:line:column:_:when:matching:)-68e5g``
- ``withKnownIssue(_:isIntermittent:fileID:filePath:line:column:_:when:matching:)-7azqg``

To conditionally enable known-issue matching and/or to match only certain kinds
of issues:

@Row {
  @Column {
    ```swift
    // Before
    class FoodTruckTests: XCTestCase {
      func testGrillWorks() async {
        let options = XCTExpectedFailure.Options()
        options.isEnabled = FoodTruck.shared.hasGrill
        options.issueMatcher = { issue in
          issue.type == thrownError
        }
        XCTExpectFailure(
          "Grill is out of fuel",
          options: options
        ) {
          try FoodTruck.shared.grill.start()
        }
        ...
      }
      ...
    }
    ```
  }
  @Column {
    ```swift
    // After
    struct FoodTruckTests {
      @Test func grillWorks() async {
        withKnownIssue("Grill is out of fuel") {
          try FoodTruck.shared.grill.start()
        } when: {
          FoodTruck.shared.hasGrill
        } matching: { issue in
          issue.error != nil 
        }
        ...
      }
      ...
    }
    ```
  }
}

## See Also

- <doc:DefiningTests>
- <doc:OrganizingTests>
- <doc:Expectations>
