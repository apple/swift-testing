# Exit testing

<!--
This source file is part of the Swift.org open source project

Copyright (c) 2023–2025 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

@Metadata {
  @Available(Swift, introduced: 6.2)
  @Available(Xcode, introduced: 26.0)
}

Use exit tests to test functionality that might cause a test process to exit.

## Overview

Your code might contain calls to [`precondition()`](https://developer.apple.com/documentation/swift/precondition(_:_:file:line:)),
[`fatalError()`](https://developer.apple.com/documentation/swift/fatalerror(_:file:line:)),
or other functions that can cause the current process to exit. For example:

```swift
extension Customer {
  func eat(_ food: consuming some Food) {
    precondition(food.isDelicious, "Tasty food only!")
    precondition(food.isNutritious, "Healthy food only!")
    ...
  }
}
```

In this function, if `food.isDelicious` or `food.isNutritious` is `false`, the
precondition fails and Swift forces the process to exit. You can write an exit
test to validate preconditions like the ones above and to make sure that your
functions correctly catch invalid inputs.

- Note: Exit tests are available on macOS, Linux, FreeBSD, OpenBSD, and Windows.

### Create an exit test

To create an exit test, call either the ``expect(processExitsWith:observing:_:sourceLocation:performing:)``
or the ``require(processExitsWith:observing:_:sourceLocation:performing:)``
macro:

```swift
@Test func `Customer won't eat food unless it's delicious`() async {
  let result = await #expect(processExitsWith: .failure) {
    var food = ...
    food.isDelicious = false
    Customer.current.eat(food)
  }
}
```

The closure or function reference you pass to the macro is the _body_ of the
exit test. When an exit test is performed at runtime, the testing library starts
a new process with the same executable as the current process. The current task
is then suspended (as with `await`) and waits for the child process to exit.

- Note: An exit test cannot run within another exit test.

The parent process doesn't call the body of the exit test. Instead, the child
process treats the body of the exit test as its `main()` function and calls it
directly.

<!-- TODO: discuss @MainActor isolation or lack thereof -->

If the body returns before the child process exits, the process exits as if
`main()` returned normally. If the body throws an error, Swift handles it as if
it were thrown from `main()` and forces the process to exit abnormally.

### Specify an exit condition

When you create an exit test, specify how you expect the child process exits by
passing an instance of ``ExitTest/Condition``:

- If you expect the exit test's body to run to completion or exit normally (for
  example, by calling [`exit(EXIT_SUCCESS)`](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/exit.3.html)
  from the C standard library), pass ``ExitTest/Condition/success``.
- If you expect the body to cause the child process to exit abnormally, but the
  exact status reported by the system is not important, pass
  ``ExitTest/Condition/failure``.
- If you need to check for a specific exit code or signal, pass
  ``ExitTest/Condition/exitCode(_:)`` or ``ExitTest/Condition/signal(_:)``.

When the child process exits, the parent process resumes and compares the exit
status of the child process against the expected exit condition you passed. If
they match, the exit test passes; otherwise, it fails and the testing library
records an issue.

### Capture state from the parent process

To pass information from the parent process to the child process, you specify
the Swift values you want to pass in a [capture list](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/closures/#Capturing-Values)
on the exit test's body:

```swift
@Test(arguments: Food.allJunkFood)
func `Customer won't eat food unless it's nutritious`(_ food: Food) async {
  await #expect(processExitsWith: .failure) { [food] in
    Customer.current.eat(food)
  }
}
```

- Note: If you use this macro with a Swift compiler version lower than 6.3, it
  doesn't support capturing state.

If a captured value is an argument to the current function or is `self`, its
type is inferred at compile time. Otherwise, explicitly specify the type of the
value using the `as` operator:

```swift
@Test func `Customer won't eat food unless it's nutritious`() async {
  var food = ...
  food.isNutritious = false
  await #expect(processExitsWith: .failure) { [self, food = food as Food] in
    self.prepare(food)
    Customer.current.eat(food)
  }
}
```

Every value you capture in an exit test must conform to [`Sendable`](https://developer.apple.com/documentation/swift/sendable)
and [`Codable`](https://developer.apple.com/documentation/swift/codable). Each
value is encoded by the parent process using [`encode(to:)`](https://developer.apple.com/documentation/swift/encodable/encode(to:))
and is decoded by the child process using [`init(from:)`](https://developer.apple.com/documentation/swift/decodable/init(from:))
before being passed to the exit test body.

If a captured value's type does not conform to both `Sendable` and `Codable`, or
if the value is not explicitly specified in the exit test body's capture list,
the compiler emits an error:

```swift
@Test func `Customer won't eat food unless it's nutritious`() async {
  var food = ...
  food.isNutritious = false
  await #expect(processExitsWith: .failure) {
    Customer.current.eat(food) // ❌ ERROR: implicitly capturing 'food'
  }
}
```

### Gather output from the child process

The ``expect(processExitsWith:observing:_:sourceLocation:performing:)`` and
``require(processExitsWith:observing:_:sourceLocation:performing:)`` macros
return an instance of ``ExitTest/Result`` that contains information about the
state of the child process. 

By default, the child process is configured without a standard output or
standard error stream. If your test needs to review the content of either of
these streams, pass the key path to the corresponding ``ExitTest/Result``
property to the macro:

```swift
extension Customer {
  func eat(_ food: consuming some Food) {
    print("Let's see if I want to eat \(food)...")
    precondition(food.isDelicious, "Tasty food only!")
    precondition(food.isNutritious, "Healthy food only!")
    ...
  }
}

@Test func `Customer won't eat food unless it's delicious`() async {
  let result = await #expect(
    processExitsWith: .failure,
    observing: [\.standardOutputContent]
  ) {
    var food = ...
    food.isDelicious = false
    Customer.current.eat(food)
  }
  if let result {
    #expect(result.standardOutputContent.contains(UInt8(ascii: "L")))
  }
}
```

- Note: The content of the standard output and standard error streams can
  contain any arbitrary sequence of bytes, including sequences that aren't valid
  UTF-8 and can't be decoded by [`String.init(cString:)`](https://developer.apple.com/documentation/swift/string/init(cstring:)-6kr8s).
  These streams are globally accessible within the child process, and any code
  running in an exit test may write to it including the operating system and any
  third-party dependencies you declare in your package description or Xcode
  project.

The testing library always sets ``ExitTest/Result/exitStatus`` to the actual
exit status of the child process (as reported by the system) even if you do not
observe `\.exitStatus`.
