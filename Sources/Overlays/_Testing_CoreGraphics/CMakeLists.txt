# This source file is part of the Swift.org open source project
#
# Copyright (c) 2024–2025 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See https://swift.org/LICENSE.txt for license information
# See https://swift.org/CONTRIBUTORS.txt for Swift project authors

if(APPLE)
  add_library(_Testing_CoreGraphics
    Attachments/_AttachableImageWrapper+AttachableWrapper.swift
    Attachments/AttachableAsCGImage.swift
    Attachments/AttachableImageFormat+UTType.swift
    Attachments/Attachment+AttachableAsCGImage.swift
    Attachments/CGImage+AttachableAsCGImage.swift
    ReexportTesting.swift)

  target_link_libraries(_Testing_CoreGraphics PUBLIC
    Testing)

  target_compile_options(_Testing_CoreGraphics PRIVATE
    -enable-library-evolution
    -emit-module-interface -emit-module-interface-path $<TARGET_PROPERTY:_Testing_CoreGraphics,Swift_MODULE_DIRECTORY>/_Testing_CoreGraphics.swiftinterface)

  _swift_testing_install_target(_Testing_CoreGraphics)
endif()
