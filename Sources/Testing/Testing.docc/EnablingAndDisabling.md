# Enabling and disabling tests

<!--
This source file is part of the Swift.org open source project

Copyright (c) 2023-2024 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

Conditionally enable or disable individual tests before they run.

## Overview

Often, a test is only applicable in specific circumstances. For instance,
you might want to write a test that only runs on devices with particular
hardware capabilities, or performs locale-dependent operations. The testing
library allows you to add traits to your tests that cause runners to
automatically skip them if conditions like these are not met.

- Note: A condition may be evaluated multiple times during testing.

### Disable a test

If you need to disable a test unconditionally, use the
``Trait/disabled(_:sourceLocation:)`` function. Given the following test
function:

```swift
@Test("Food truck sells burritos")
func sellsBurritos() async throws { ... }
```

Add the trait _after_ the test's display name:

```swift
@Test("Food truck sells burritos", .disabled())
func sellsBurritos() async throws { ... }
```

The test will now always be skipped.

It's also possible to add a comment to the trait to present in the output from
the runner when it skips the test:

```swift
@Test("Food truck sells burritos", .disabled("We only sell Thai cuisine"))
func sellsBurritos() async throws { ... }
```

### Enable or disable a test conditionally

Sometimes, it makes sense to enable a test only when a certain condition is met. Consider
the following test function:

```swift
@Test("Ice cream is cold")
func isCold() async throws { ... }
```

If it's currently winter, then presumably ice cream won't be available for
sale and this test will fail. It therefore makes sense to only enable it if it's currently summer. You can conditionally enable a test with
``Trait/enabled(if:_:sourceLocation:)``:

```swift
@Test("Ice cream is cold", .enabled(if: Season.current == .summer))
func isCold() async throws { ... }
```

It's also possible to conditionally _disable_ a test and to combine multiple
conditions:

```swift
@Test(
  "Ice cream is cold",
  .enabled(if: Season.current == .summer),
  .disabled("We ran out of sprinkles")
)
func isCold() async throws { ... }
```

If a test is disabled because of a problem for which there is a corresponding
bug report, you can use one of these functions to show the relationship
between the test and the bug report:

- ``Trait/bug(_:_:)``
- ``Trait/bug(_:id:_:)-10yf5``
- ``Trait/bug(_:id:_:)-3vtpl``

For example, the following test cannot run due to bug number `"12345"`:

```swift
@Test(
  "Ice cream is cold",
  .enabled(if: Season.current == .summer),
  .disabled("We ran out of sprinkles"),
  .bug(id: "12345")
)
func isCold() async throws { ... }
```

If a test has multiple conditions applied to it, they must _all_ pass for it to
run. Otherwise, the test notes the first condition to fail as the reason the
test is skipped.

### Handle complex conditions

If a condition is complex, consider factoring it out into a helper function to
improve readability:

```swift
func allIngredientsAvailable(for food: Food) -> Bool { ... }

@Test(
  "Can make sundaes",
  .enabled(if: Season.current == .summer),
  .enabled(if: allIngredientsAvailable(for: .sundae))
)
func makeSundae() async throws { ... }
```

<!--
### End a test after it has already started

TODO: document Test.cancel() and Test.Case.cancel() here

If a test has already started running and you determine it cannot complete and
should end early without failing, use ``Test/cancel(_:sourceLocation:)`` to
cancel the test:

```swift
...
```

If the test is parameterized and you only want to cancel the current test case
rather than the entire test, use ``Test/Case/cancel(_:sourceLocation:)``.
-->
