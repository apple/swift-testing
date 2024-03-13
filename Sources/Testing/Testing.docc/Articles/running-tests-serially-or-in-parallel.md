# Parallelizing test execution

<!--
This source file is part of the Swift.org open source project

Copyright (c) 2024 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

Control whether tests run serially or in parallel.

## Overview

By default, tests run in parallel with respect to each other. Parallelization is
accomplished by the testing library using task groups, and tests generally all
run in the same process. The number of tests that run concurrently is controlled
by the Swift runtime.

<!--
HIDDEN: .serial is experimental SPI pending feature review.

## Disabling parallelization

Parallelization can be disabled on a per-function or per-suite basis using the
``Trait/serial`` trait:

```swift
@Test(.serial, arguments: Food.allCases) func prepare(food: Food) {
  // This function will be invoked serially, once per food, because it has the
  // .serial trait.
}

@Suite(.serial) struct FoodTruckTests {
  @Test(arguments: Condiment.allCases) func refill(condiment: Condiment) {
    // This function will be invoked serially, once per condiment, because the
    // containing suite has the .serial trait.
  }

  @Test func startEngine() async throws {
    // This function will not run while refill(condiment:) is running. One test
    // must end before the other will start.
  }
}
```

When added to a parameterized test function, this trait causes that test to run
its cases serially instead of in parallel. When applied to a non-parameterized
test function, this trait has no effect. When applied to a test suite, this
trait causes that suite to run its contained test functions and sub-suites
serially instead of in parallel.

This trait is recursively applied: if it is applied to a suite, any
parameterized tests or test suites contained in that suite are also serialized
(as are any tests contained in those suites, and so on.)

This trait does not affect the execution of a test relative to its peers or to
unrelated tests. This trait has no effect if test parallelization is globally
disabled (by, for example, passing `--no-parallel` to the `swift test` command.)

## Topics

- ``Trait/serial``
- ``SerialTrait``
-->

## See Also

- <doc:OrganizingTests>
- <doc:ParameterizedTesting>
