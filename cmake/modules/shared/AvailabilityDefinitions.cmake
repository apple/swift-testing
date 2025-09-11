##
## This source file is part of the Swift.org open source project
##
## Copyright (c) 2024 Apple Inc. and the Swift project authors
## Licensed under Apache License v2.0 with Runtime Library Exception
##
## See https://swift.org/LICENSE.txt for license information
## See https://swift.org/CONTRIBUTORS.txt for Swift project authors
##

# Settings which define commonly-used OS availability macros.
add_compile_options(
  "SHELL:$<$<COMPILE_LANGUAGE:Swift>:-Xfrontend -define-availability -Xfrontend \"_mangledTypeNameAPI:macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0\">"
  "SHELL:$<$<COMPILE_LANGUAGE:Swift>:-Xfrontend -define-availability -Xfrontend \"_uttypesAPI:macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0\">"
  "SHELL:$<$<COMPILE_LANGUAGE:Swift>:-Xfrontend -define-availability -Xfrontend \"_backtraceAsyncAPI:macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0\">"
  "SHELL:$<$<COMPILE_LANGUAGE:Swift>:-Xfrontend -define-availability -Xfrontend \"_clockAPI:macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0\">"
  "SHELL:$<$<COMPILE_LANGUAGE:Swift>:-Xfrontend -define-availability -Xfrontend \"_regexAPI:macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0\">"
  "SHELL:$<$<COMPILE_LANGUAGE:Swift>:-Xfrontend -define-availability -Xfrontend \"_swiftVersionAPI:macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0\">"
  "SHELL:$<$<COMPILE_LANGUAGE:Swift>:-Xfrontend -define-availability -Xfrontend \"_typedThrowsAPI:macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0\">"
  "SHELL:$<$<COMPILE_LANGUAGE:Swift>:-Xfrontend -define-availability -Xfrontend \"_distantFuture:macOS 99.0, iOS 99.0, watchOS 99.0, tvOS 99.0, visionOS 99.0\">")
