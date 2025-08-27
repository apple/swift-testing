# This source file is part of the Swift.org open source project
#
# Copyright (c) 2024–2025 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

if(APPLE)
  add_library(_Testing_CoreImage
    Attachments/CIImage+AttachableAsCGImage.swift
    ReexportTesting.swift)

  target_link_libraries(_Testing_CoreImage PUBLIC
    Testing
    _Testing_CoreGraphics)

  target_compile_options(_Testing_CoreImage PRIVATE
    -enable-library-evolution
    -emit-module-interface -emit-module-interface-path $<TARGET_PROPERTY:_Testing_CoreImage,Swift_MODULE_DIRECTORY>/_Testing_CoreImage.swiftinterface)

  _swift_testing_install_target(_Testing_CoreImage)
endif()
