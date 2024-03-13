# Adding tags to tests

<!--
This source file is part of the Swift.org open source project

Copyright (c) 2023 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

Add tags to tests and customize their appearance.

## Overview

A complex package or project may contain hundreds or thousands of tests and
suites. Some subset of those tests may share some common facet, such as being
"critical" or "flaky". The testing library includes a type of trait called
"tags" that can be added to tests to group and categorize them.

Tags are different from test suites: test suites impose structure on test
functions at the source level, while tags provide semantic information for a
test that can be shared with any number of other tests across test suites,
source files, and even test targets.

## Adding tags

To add a tag to a test, use the ``Trait/tags(_:)-505n9`` trait. This trait takes
a sequence of tags as its argument, and those tags are then applied to the
corresponding test at runtime. If any tags are applied to a test suite, then all
tests in that suite inherit those tags.

The testing library does not assign any semantic meaning to any tags, nor does
the presence or absence of tags affect how the testing library runs tests.

Tags themselves are instances of ``Tag`` and can be expressed as string
literals directly in a test suite or test function's declaration. Tags can also
be expressed as named constants declared as static members of ``Tag``. To
declare a named constant tag, use the ``Tag()`` macro:

```swift
extension Tag {
  @Tag static var legallyRequired: Self
}

@Test("Vendor's license is valid", .tags("critical"), .tags(.legallyRequired))
func licenseValid() { ... }
```

If two tags with the same name (`legallyRequired` in the above example) are
declared in different files, modules, or other contexts, the testing library
treats them as equivalent.

If it is important for a tag to be distinguished from similar tags declared
elsewhere in a package or project (or its dependencies), use
 [reverse-DNS naming](https://en.wikipedia.org/wiki/Reverse_domain_name_notation)
to create a unique Swift symbol name for your tag:

```swift
extension Tag {
  enum com_example_foodtruck {}
}

extension Tag.com_example_foodtruck {
  @Tag static var extraSpecial: Self
}

@Test
  "Extra Special Sauce recipe is secret",
  .tags(.com_example_foodtruck.extraSpecial)
)
func secretSauce() { ... }
```

### Where tags can be declared

Tags must always be declared as members of ``Tag`` in an extension to that type
or in a type nested within ``Tag``. Redeclaring a tag under a second name has no
effect and the additional name will not be recognized by the testing library.
The following example is unsupported:

```swift
extension Tag {
  @Tag static var legallyRequired: Self // ✅ OK: declaring a new tag

  static var requiredByLaw: Self { // ❌ ERROR: this tag name will not be
                                   // recognized at runtime
    legallyRequired
  }
}
```

If a tag is declared as a named constant outside of an extension to the ``Tag``
type (for example, at the root of a file or in another unrelated type
declaration), it cannot be applied to test functions or test suites. The
following declarations are unsupported:

```swift
@Tag let needsKetchup: Self // ❌ ERROR: tags must be declared in an extension
                            // to Tag
struct Food {
  @Tag var needsMustard: Self // ❌ ERROR: tags must be declared in an extension
                              // to Tag
}
```

## Built-in tags

The testing library predefines the following symbolic tags that can be used in
any test target and applied to any test:

- ``Tag/red``
- ``Tag/orange``
- ``Tag/yellow``
- ``Tag/green``
- ``Tag/blue``
- ``Tag/purple``

The testing library does not assign any semantic meaning to these tags, nor does
the presence or absence of these tags affect how the testing library runs tests.

## Customizing a tag's appearance

By default, a tag does not appear in a test's output when the test is run. It is
possible to assign colors to tags defined in a package so that when the test is
run, the tag is visible in its output.

To add colors to tags, create a directory in your home directory named
`".swift-testing"` and add a file named `"tag-colors.json"` to it. This file
should contain a JSON object (a dictionary) whose keys are strings representing
tags and whose values represent tag colors.

- Note: On Windows, create the `".swift-testing"` directory in the
  `"AppData\Local"` directory inside your home directory instead of directly
  inside it.

Tag colors can be represented using several formats:

- The strings `"red"`, `"orange"`, `"yellow"`, `"green"`, `"blue"`, or
  `"purple"`, representing corresponding predefined instances of ``Tag``, i.e.
  ``Tag/red``, ``Tag/orange``, ``Tag/yellow``, ``Tag/green``, ``Tag/blue``, and
  ``Tag/purple``;
- A string of the form `"#RRGGBB"`, containing a hexadecimal representation of
  the color in a device-independent RGB color space; or
- The `null` literal value, representing "no color."

For example, to set the color of the tag `"critical"` to orange and the color of
the tag `.legallyRequired` to teal, the contents of `"tag-colors.json"` can
be set to:

```json
{
  "critical": "orange",
  ".legallyRequired": "#66FFCC"
}
```

## Topics

- ``Trait/tags(_:)-505n9``
- ``Trait/tags(_:)-yg0i``
- ``Tag``
- ``Tag/List``
- ``Tag()``
