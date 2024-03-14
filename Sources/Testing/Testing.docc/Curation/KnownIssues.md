# Known issues

<!--
This source file is part of the Swift.org open source project

Copyright (c) 2023 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

Call-out expected failures or warnings in tests.

## Overview

The testing library provides a function, `withKnownIssue()`, that you
use to mark issues as known. In other words, if you know a test records an
issue, might record an issue intermittently (a "flaky" test), or tests code in 
your project that is incomplete, use this function to inform the testing library 
at runtime not to mark the test as failing when those issues occur.

## Topics

### Recording known issues in tests

- ``withKnownIssue(_:isIntermittent:fileID:filePath:line:column:_:)-5pxnd``
- ``withKnownIssue(_:isIntermittent:fileID:filePath:line:column:_:)-30kgk``
- ``withKnownIssue(_:isIntermittent:fileID:filePath:line:column:_:when:matching:)-68e5g``
- ``withKnownIssue(_:isIntermittent:fileID:filePath:line:column:_:when:matching:)-7azqg``

### Describing a failure or warning

- ``Issue``

### Matching issues

- ``KnownIssueMatcher``

