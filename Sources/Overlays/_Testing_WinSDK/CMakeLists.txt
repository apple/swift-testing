# This source file is part of the Swift.org open source project
#
# Copyright (c) 2024–2025 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

if (CMAKE_SYSTEM_NAME STREQUAL "Windows")
  add_library(_Testing_WinSDK
    Attachments/_AttachableImageWrapper+AttachableWrapper.swift
    Attachments/AttachableAsIWICBitmapSource.swift
    Attachments/AttachableImageFormat+CLSID.swift
    Attachments/Attachment+AttachableAsIWICBitmapSource.swift
    Attachments/HBITMAP+AttachableAsIWICBitmapSource.swift
    Attachments/HICON+AttachableAsIWICBitmapSource.swift
    Attachments/IWICBitmapSource+AttachableAsIWICBitmapSource.swift
    Attachments/UnsafeMutablePointer+AttachableAsIWICBitmapSource.swift
    Support/Additions/GUIDAdditions.swift
    Support/Additions/IPropertyBag2Additions.swift
    Support/Additions/IWICImagingFactoryAdditions.swift
    ReexportTesting.swift)

  target_link_libraries(_Testing_WinSDK PUBLIC
    Testing)

  target_compile_options(_Testing_WinSDK PRIVATE
    -enable-library-evolution
    -emit-module-interface -emit-module-interface-path $<TARGET_PROPERTY:_Testing_WinSDK,Swift_MODULE_DIRECTORY>/_Testing_WinSDK.swiftinterface)

  _swift_testing_install_target(_Testing_WinSDK)
endif()
