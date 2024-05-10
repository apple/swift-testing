# Testing asynchronous code

<!--
This source file is part of the Swift.org open source project

Copyright (c) 2024 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

Validate whether your code causes expected events to happen.

## Overview

`swift-testing` integrates with Swift concurrency, meaning that in many
situations you can test asynchronous code using standard Swift
features.  Mark your test function as `async` and, in the function
body, `await` any asynchronous interactions:

```swift
@Test func asynchronousCalculationYieldsExpectedValue() async {
    let result = await asynchronousCalculation(with: 10)
    #expect(result == 12)
}
```

In more complex situations, where the code you test doesn't use Swift
concurrency, you use ``Confirmation`` to discover whether an expected
event happens.

### Confirm that an event happens

If your code under test doesn't use Swift concurrency, call
``confirmation(_:expectedCount:fileID:filePath:line:column:_:)`` in
your asynchronous test function to create a `Confirmation` for the
expected event.  In the trailing block parameter, call the code under
test.  Swift Testing passes a `Confirmation` as the parameter to the
block, which you call as a function in the completion or event handler
for the code under test when the event you're testing for occurs:

```swift
@Test func asynchronousCalculatorCompletesSuccessfully() async {
    let calculator = AsynchronousCalculator()
    await confirmation() { confirmation in
        calculator.successHandler = { _ in confirmation() }
        calculator.doCalculation(with: 0)
    }
}
```

If you expect the event to happen more than once, set the
`expectedCount` parameter to the number of expected occurrences.  The
test passes if the number of occurrences during the test matches the
expected count, and fails otherwise.

### Confirm that an event doesn't happen

To validate that a particular event doesn't occur during a test,
create a `Confirmation` with an expected count of `0`:

```swift
@Test func asynchronousCalculatorEncountersNoErrors() async {
    let calculator = AsynchronousCalculator()
    await confirmation(expectedCount:0) { confirmation in
        calculator.errorHandler = { _ in confirmation() }
        calculator.doCalculation(with: 0)
    }
}
```