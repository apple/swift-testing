# Adding traits to tests

<!--
This source file is part of the Swift.org open source project

Copyright (c) 2023 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

Add traits to tests to annotate them or customize their behavior.

## Overview

This article describes the ``Trait``, ``TestTrait``, and ``SuiteTrait``
protocols, lists the traits provided by the testing library, and lists functions
that can be used to create them.

The ``Trait``, ``TestTrait``, and ``SuiteTrait`` protocols are used to define
types that customize the behavior of test functions and test suites.

## Topics

- <doc:EnablingAndDisabling>
- <doc:AddingTags>
- <doc:AddingComments>
- <doc:AssociatingBugs>
- <doc:LimitingExecutionTime>
- <doc:Parallelization>

### Creating a custom trait

- ``Trait``
- ``TestTrait``
- ``SuiteTrait``
