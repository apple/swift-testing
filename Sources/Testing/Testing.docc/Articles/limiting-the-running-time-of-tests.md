# Limiting the execution time of a test

<!--
This source file is part of the Swift.org open source project

Copyright (c) 2023 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

Set limits on how long a test can run for until it fails.

## Overview

Some tests may naturally run slowly: they may require significant system
resources to complete, may rely on downloaded data from a server, or may
otherwise be dependent on external factors.

If a test may hang indefinitely or may consume too many system resources to
complete effectively, consider setting a time limit for it so that it will
be marked as failing if it runs for an excessive amount of time. Use the
``Trait/timeLimit(_:)`` trait as an upper bound:

```swift
@Test(.timeLimit(.seconds(60 * 60))
func serve100CustomersInOneHour() async {
  for _ in 0 ..< 100 {
    let customer = await Customer.next()
    await customer.order()
    ...
  }
}
```

If the above test function takes longer than 60 &times; 60 seconds (i.e. one
hour) to execute, the task in which it is running will be
[cancelled](https://developer.apple.com/documentation/swift/task/cancel())
and the test will fail with an issue of kind
``Issue/Kind-swift.enum/timeLimitExceeded(timeLimitComponents:)``.

- Note: if multiple time limit traits apply to a test, the shortest time limit
  is used.

The testing library may adjust the specified time limit for performance reasons
or to ensure tests have enough time to run. In particular, a granularity of (by
default) one minute is applied to tests. The testing library can also be
configured with a maximum time limit per test that overrides any applied time
limit traits.

### Time limits applied to test suites

When a time limit is applied to a test suite, it is recursively applied to all
test functions and child test suites within that suite.

### Time limits applied to parameterized tests

When a time limit is applied to a parameterized test function, it is applied to
each invocation _separately_ so that if only some arguments cause failures, then
successful arguments are not incorrectly marked as failing too.

## Topics

- ``Trait/timeLimit(_:)``
- ``TimeLimitTrait``
