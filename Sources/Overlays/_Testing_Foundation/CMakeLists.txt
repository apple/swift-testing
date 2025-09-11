# This source file is part of the Swift.org open source project
#
# Copyright (c) 2024 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See https://swift.org/LICENSE.txt for license information
# See https://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(_Testing_Foundation
  Attachments/_AttachableURLWrapper.swift
  Attachments/EncodingFormat.swift
  Attachments/Attachment+URL.swift
  Attachments/Attachable+NSSecureCoding.swift
  Attachments/Data+Attachable.swift
  Attachments/Attachable+Encodable+NSSecureCoding.swift
  Attachments/Attachable+Encodable.swift
  Events/Clock+Date.swift
  ReexportTesting.swift)

target_link_libraries(_Testing_Foundation PUBLIC
  Testing)

# Although this library links Foundation on all platforms, it only does so using
# `target_link_libraries()` when building for non-Apple platforms. This is
# because that command uses the `-lFoundation` linker flag, but on Apple
# platforms Foundation is a .framework and requires a different flag. However,
# we don't need to explicitly pass any linker flag since it's handled
# automatically on Apple platforms via auto-linking.
if(NOT APPLE)
  target_link_libraries(_Testing_Foundation PUBLIC
    Foundation)
endif()

# Note: This does not enable Library Evolution, despite emitting a module
# interface, because Foundation does not have Library Evolution enabled for all
# platforms.
target_compile_options(_Testing_Foundation PRIVATE
  -emit-module-interface -emit-module-interface-path $<TARGET_PROPERTY:_Testing_Foundation,Swift_MODULE_DIRECTORY>/_Testing_Foundation.swiftinterface)

_swift_testing_install_target(_Testing_Foundation)
