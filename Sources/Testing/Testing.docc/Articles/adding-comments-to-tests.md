# Adding comments to tests

<!--
This source file is part of the Swift.org open source project

Copyright (c) 2024 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

Add comments to provide useful information about tests.

## Overview

It is often useful to add comments to code in order:

- to provide context or background information about the code's purpose;
- to explain how complex code implemented; or
- to include details which may be helpful when diagnosing issues.

Test code is no different and can benefit from explanatory code comments, but
often test issues are shown in places where the source code of the test is
unavailable such as in continuous integration (CI) interfaces or in log files.

Seeing comments related to tests in these contexts can help diagnose issues more
quickly. Comments can be added to test declarations and the testing library will
automatically capture and show them when issues are recorded.

## Adding a code comment to a test

To include a comment on a test or suite, write an ordinary Swift code comment
immediately before its `@Test` or `@Suite` attribute:

```swift
// Assumes the standard lunch menu includes a taco
@Test func lunchMenu() {
  let foodTruck = FoodTruck(
    menu: .lunch,
    ingredients: [.tortillas, .cheese]
  )
  #expect(foodTruck.menu.contains { $0 is Taco })
}
```

The comment `"// Assumes the standard lunch menu includes a taco"` will be added
to the test.

The following language comment styles are supported:

| Syntax | Style |
|-|-|
| `// ...` | Line comment |
| `/// ...` | Documentation line comment |
| `/* ... */` | Block comment |
| `/** ... */` | Documentation block comment |

### Comment formatting

Test comments which are automatically added from source code comments preserve
their original formatting, including any prefixes like `//` or `/**`. This
is because the whitespace and formatting of comments can be meaningful in some
circumstances or aid in understanding the comment—for example, when a comment
includes an example code snippet or diagram.

<!-- FIXME: Uncomment this section if/when the `.comment(...)` trait is promoted
  to non-experimental SPI

## Adding a comment to a test programmatically

For more precise control over a comment's content, comments can be added to a
test programmatically by explicitly specifying them as trait arguments to the
`@Test` attribute. Programmatically adding comments allows for more precise
control of the comments' content or formatting. It can also help to reduce
repetition by allowing developers to define comments in one place and reference
them from multiple tests.

To add a comment to a test programmatically, use the ``Trait/comment(_:)``
function and specify a comment string:

```swift
@Test(.comment("Assumes the standard lunch menu includes a taco"))
func lunchMenu() {
  ...
}
``` -->

## Using test comments effectively

As in normal code, comments on tests are generally most useful when:

- they add information that isn't obvious from reading the code; or
- they provide useful information about the operation or motivation of a test.

If a test is related to a bug or issue, consider using the ``Bug`` trait instead
of comments. For more information, review <doc:AssociatingBugs>.


## Topics

- ``Comment``
<!-- FIXME: Uncomment this section if/when the `.comment(...)` trait is promoted
  to non-experimental SPI.
- ``Trait/comment(_:)`` -->
