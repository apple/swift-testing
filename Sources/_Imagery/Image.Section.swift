//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if SWT_BUILDING_WITH_CMAKE
@_implementationOnly import _ImageryInternals
#else
internal import _ImageryInternals
#endif

extension Image {
  /// A type representing a section in an image.
  ///
  /// A section is a relocatable subrange of an image loaded into memory. On
  /// platforms that use the Mach-O, ELF, or COFF image formats, sections can be
  /// identified by name (although the rules governing valid section names vary
  /// by platform.)
  ///
  /// An instance of this type can be looked up using ``Image/section(named:)``.
  ///
  /// The implementation of this type is inherently platform-specific.
  public struct Section: ~Copyable {
    /// The underlying C++ structure.
    var rawValue: SMLSection

    /// Initialize an instance of this type wrapping the given C++ structure.
    ///
    /// - Parameters:
    ///   - image: The C++ structure to wrap.
    ///   - name: The name of the section.
    fileprivate init(wrapping section: SMLSection, name: String) {
      rawValue = section
      self.name = name
    }

    /// The name of the section.
    ///
    /// The name of a section is implementation-defined. On platforms that use
    /// the Mach-O image format (namely Apple platforms), this string contains
    /// the segment name and section name separated by an ASCII comma character.
    public fileprivate(set) var name: String

    /// Call a function to access this section's contents.
    ///
    /// - Parameters:
    ///   - body: A function to call. A buffer pointer representing the section
    ///     in memory is passed to this function.
    ///
    /// - Returns: Whatever is returned by `body`.
    ///
    /// - Throws: Whatever is thrown by `body`.
    public borrowing func withUnsafeRawBufferPointer<R, E>(_ body: (UnsafeRawBufferPointer) throws(E) -> R) throws(E) -> R {
      let bufferPointer = UnsafeRawBufferPointer(start: rawValue.start, count: rawValue.size)
      return try body(bufferPointer)
    }
  }

  /// Find a section in this image by name.
  ///
  /// - Parameters:
  ///   - sectionName: The name of the section to find.
  ///
  /// - Returns: An instance of ``Section`` representing the requested section,
  ///   or `nil` if this image does not contain a valid section with the name
  ///   `sectionName`.
  ///
  /// The name of a section is implementation-defined. On platforms that use
  /// the Mach-O image format (namely Apple platforms), this string contains
  /// the segment name and section name separated by an ASCII comma character.
  ///
  /// On platforms that support dynamically unloading images at runtime, values
  /// returned by this function are not guaranteed to remain valid longer than
  /// the instance of ``Image`` that contains them.
  public borrowing func section(named sectionName: String) -> Section? {
    let section: SMLSection? = withUnsafeTemporaryAllocation(of: SMLSection.self, capacity: 1) { buffer in
      guard sml_findSection(rawValue, sectionName, buffer.baseAddress!) else {
        return nil
      }
      return buffer.baseAddress!.move()
    }
    guard let section else {
      return nil
    }
    return Section(wrapping: section, name: sectionName)
  }
}

// MARK: - Sendable

@available(*, unavailable)
extension Image.Section: Sendable {}

// MARK: - Equatable, Hashable

extension Image.Section {
  public static func ==(lhs: borrowing Self, rhs: borrowing Self) -> Bool {
    lhs.rawValue.start == rhs.rawValue.start
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(rawValue.start)
    hasher.combine(rawValue.size)
  }
}
