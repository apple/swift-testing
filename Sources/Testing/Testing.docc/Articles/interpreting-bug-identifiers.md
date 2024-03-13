# Interpreting bug identifiers

<!--
This source file is part of the Swift.org open source project

Copyright (c) 2023 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

How the testing library interprets bug identifiers provided by developers.

## Overview

As a convenience, the testing library assumes that bug identifiers with specific
formats are associated with some common bug-tracking systems.

- Note: "Bugs" as described in this document may also be referred to as
  "issues." To avoid confusion with the ``Issue`` type in the testing library,
  this document consistently refers to them as "bugs."

## Recognized formats

- If the bug identifier begins with `"rdar:"`, it is assumed to represent a bug
  filed with Apple's Radar system.
- If the bug identifier can be parsed as a URL according to
  [RFC 3986](https://www.ietf.org/rfc/rfc3986.txt), it is assumed to represent
  an issue tracked at that URL.
- All other bug identifiers, including those specified as integers rather than
  strings, are assumed to refer to bugs in an unspecified bug-tracking system.

<!--
Possible additional formats we could recognize (which would require special
handling to detect:

- If the bug identifier begins with `"FB"`, it is assumed to represent a bug
  filed with the [Apple Feedback Assistant](https://feedbackassistant.apple.com).
- If the bug identifier begins with `"#"` and can be parsed as a positive
  integer, it is assumed to represent a [GitHub](https://github.com) issue in
  the same repository as the test.
-->

## Examples

| Trait Function | Inferred Bug-Tracking System |
|-|-|
| `.bug(12345)` | None |
| `.bug("12345")` | None |
| `.bug("rdar:12345")` | Apple Radar |
| `.bug("https://github.com/apple/swift/pull/12345")` | [GitHub Issues for the Swift project](https://github.com/apple/swift/issues) |
| `.bug("https://bugs.webkit.org/show_bug.cgi?id=12345")` | [WebKit Bugzilla](https://bugs.webkit.org/) |
<!--
| `.bug("FB12345")` | Apple Feedback Assistant | // SEE ALSO: rdar://104582015
| `.bug("#12345")` | GitHub Issues for the current repository (if hosted there) |
-->
