# Traits

<!--
This source file is part of the Swift.org open source project

Copyright (c) 2023 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

Add traits to tests to annotate them or customize their behavior.

## Overview

Pass built-in traits to test functions or suite types to comment, categorize, 
classify, and modify runtime behaviors. You can also use the ``Trait``, ``TestTrait``, 
and ``SuiteTrait`` protocols to create your own types that that customize the 
behavior of test functions.

## Topics

### Customizing runtime behaviors

- <doc:enabling-and-disabling-tests>
- <doc:limiting-the-running-time-of-tests>
- <doc:running-tests-serially-or-in-parallel>
- ``ConditionTrait``
- ``TimeLimitTrait``

<!--
HIDDEN: .serial is experimental SPI pending feature review.
### Running tests serially or in parallel
- ``SerialTrait``
 -->

### Annotating tests

- <doc:associating-bugs-with-tests>
- <doc:interpreting-bug-identifiers>
- <doc:adding-comments-to-tests>
- <doc:categorizing-tests-and-customizing-their-appearance>
- ``Bug``
- ``Comment``
- ``Tag``
- ``Tag/List``
- ``Tag()``


### Creating a custom trait

- ``Trait``
- ``TestTrait``
- ``SuiteTrait``
