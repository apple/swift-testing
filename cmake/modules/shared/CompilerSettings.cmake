# This source file is part of the Swift.org open source project
#
# Copyright (c) 2024 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

# Settings intended to be applied to every Swift target in this project.
# Analogous to project-level build settings in an Xcode project.
add_compile_options(
  "SHELL:$<$<COMPILE_LANGUAGE:Swift>:-Xfrontend -require-explicit-sendable>")
add_compile_options(
  "SHELL:$<$<COMPILE_LANGUAGE:Swift>:-Xfrontend -enable-experimental-feature -Xfrontend AccessLevelOnImport>")
add_compile_options(
  "SHELL:$<$<COMPILE_LANGUAGE:Swift>:-Xfrontend -enable-upcoming-feature -Xfrontend ExistentialAny>"
  "SHELL:$<$<COMPILE_LANGUAGE:Swift>:-Xfrontend -enable-upcoming-feature -Xfrontend InternalImportsByDefault>")

# Definitions applied unconditionally to files of all languages, in all targets.
add_compile_definitions("SWT_BUILDING_WITH_CMAKE")

# Platform-specific definitions.
if(APPLE)
  add_compile_definitions("SWT_TARGET_OS_APPLE")
endif()
if(WASI)
  add_compile_definitions("SWT_NO_FILE_IO")
endif()
if(CMAKE_SYSTEM_NAME IN_LIST "iOS;watchOS;tvOS;visionOS;WASI")
  add_compile_definitions("SWT_NO_EXIT_TESTS")
endif()
