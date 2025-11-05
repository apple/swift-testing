# Attachments

<!--
This source file is part of the Swift.org open source project

Copyright (c) 2024–2025 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

Attach values to tests to help diagnose issues and gather feedback.

## Overview

Attach values such as strings and files to tests. Implement the ``Attachable``
protocol to create your own attachable types.

## Topics

### Attaching values to tests

- ``Attachment``
- ``Attachable``
- ``AttachableWrapper``


<!-- TODO: set up DocC content for overlays if possible
### Attaching files to tests

- ``Attachment/init(contentsOf:named:sourceLocation:)``
-->

### Attaching images to tests

- ``AttachableAsImage``
- ``AttachableImageFormat``
- ``Attachment/init(_:named:as:sourceLocation:)``
- ``Attachment/record(_:named:as:sourceLocation:)``
