# This source file is part of the Swift.org open source project
#
# Copyright (c) 2024 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

# The current version of the Swift Testing release. For release branches,
# remember to remove -dev.
set(SWT_TESTING_LIBRARY_VERSION "6.3-dev")

message(STATUS "Swift Testing version: ${SWT_TESTING_LIBRARY_VERSION}")
add_compile_definitions(
  "$<$<COMPILE_LANGUAGE:CXX>:SWT_TESTING_LIBRARY_VERSION=\"${SWT_TESTING_LIBRARY_VERSION}\">")
