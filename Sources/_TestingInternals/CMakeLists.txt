# This source file is part of the Swift.org open source project
#
# Copyright (c) 2024 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

set(CMAKE_CXX_SCAN_FOR_MODULES 0)

include(LibraryVersion)
add_library(_TestingInternals STATIC
  Discovery.cpp
  WillThrow.cpp)
target_include_directories(_TestingInternals PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_compile_options(_TestingInternals PRIVATE
  -fno-exceptions)
