//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if canImport(Foundation)
public import Testing
public import Foundation

#if !SWT_NO_PROCESS_SPAWNING && os(Windows)
private import WinSDK
#endif

#if !SWT_NO_FILE_IO
extension Attachment where AttachableValue == _AttachableURLWrapper {
#if SWT_TARGET_OS_APPLE
  /// An operation queue to use for asynchronously reading data from disk.
  private static let _operationQueue = OperationQueue()
#endif

  /// Initialize an instance of this type with the contents of the given URL.
  ///
  /// - Parameters:
  ///   - url: The URL containing the attachment's data.
  ///   - preferredName: The preferred name of the attachment when writing it to
  ///     a test report or to disk. If `nil`, the name of the attachment is
  ///     derived from the last path component of `url`.
  ///   - sourceLocation: The source location of the call to this initializer.
  ///     This value is used when recording issues associated with the
  ///     attachment.
  ///
  /// - Throws: Any error that occurs attempting to read from `url`.
  ///
  /// Use this initializer to create an instance of ``Attachment`` that
  /// represents a local file or directory:
  ///
  /// ```swift
  /// let url = try await FoodTruck.saveMenu(as: .pdf)
  /// let attachment = try await Attachment(contentsOf: url)
  /// Attachment.record(attachment)
  /// ```
  ///
  /// When you call this initializer and pass it the URL of a file, it reads or
  /// maps the contents of that file into memory. When you call this initializer
  /// and pass it the URL of a directory, it creates a temporary zip file of the
  /// directory before reading or mapping it into memory. These operations may
  /// take some time, so this initializer suspends the calling task until they
  /// are complete.
  ///
  /// - Important: This initializer supports creating attachments from file URLs
  ///   only. If you pass it a URL other than a file URL, such as an HTTPS URL,
  ///   the testing library throws an error.
  ///
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.2)
  ///   @Available(Xcode, introduced: 26.0)
  /// }
  public init(
    contentsOf url: URL,
    named preferredName: String? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async throws {
    guard url.isFileURL else {
      // TODO: network URLs?
      throw CocoaError(.featureUnsupported, userInfo: [NSLocalizedDescriptionKey: "Attaching downloaded files is not supported"])
    }

    // If the user did not provide a preferred name, derive it from the URL.
    let preferredName = preferredName ?? url.lastPathComponent

    let url = url.resolvingSymlinksInPath()
    let isDirectory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory!

#if SWT_TARGET_OS_APPLE && !SWT_NO_FOUNDATION_FILE_COORDINATION
    let data: Data = try await withCheckedThrowingContinuation { continuation in
      let fileCoordinator = NSFileCoordinator()
      let fileAccessIntent = NSFileAccessIntent.readingIntent(with: url, options: [.forUploading])

      fileCoordinator.coordinate(with: [fileAccessIntent], queue: Self._operationQueue) { error in
        let result = Result {
          if let error {
            throw error
          }
          return try Data(contentsOf: fileAccessIntent.url, options: [.mappedIfSafe])
        }
        continuation.resume(with: result)
      }
    }
#else
    let data = if isDirectory {
      try await _compressContentsOfDirectory(at: url)
    } else {
      // Load the file.
      try Data(contentsOf: url, options: [.mappedIfSafe])
    }
#endif

    let urlWrapper = _AttachableURLWrapper(url: url, data: data, isCompressedDirectory: isDirectory)
    self.init(urlWrapper, named: preferredName, sourceLocation: sourceLocation)
  }
}

#if !SWT_NO_PROCESS_SPAWNING && os(Windows)
/// The filename of the archiver tool.
private let _archiverName = "tar.exe"

/// The path to the archiver tool.
///
/// This path refers to a file (named `_archiverName`) within the `"System32"`
/// folder of the current system, which is not always located in `"C:\Windows."`
///
/// If the path cannot be determined, the value of this property is `nil`.
private let _archiverPath: String? = {
  let bufferCount = GetSystemDirectoryW(nil, 0)
  guard bufferCount > 0 else {
    return nil
  }

  return withUnsafeTemporaryAllocation(of: wchar_t.self, capacity: Int(bufferCount)) { buffer -> String? in
    let bufferCount = GetSystemDirectoryW(buffer.baseAddress!, UINT(buffer.count))
    guard bufferCount > 0 && bufferCount < buffer.count else {
      return nil
    }

    return _archiverName.withCString(encodedAs: UTF16.self) { archiverName -> String? in
      var result: UnsafeMutablePointer<wchar_t>?

      let flags = ULONG(PATHCCH_ALLOW_LONG_PATHS.rawValue)
      guard S_OK == PathAllocCombine(buffer.baseAddress!, archiverName, flags, &result) else {
        return nil
      }
      defer {
        LocalFree(result)
      }

      return result.flatMap { String.decodeCString($0, as: UTF16.self)?.result }
    }
  }
}()
#endif

/// Compress the contents of a directory to an archive, then map that archive
/// back into memory.
///
/// - Parameters:
///   - directoryURL: A URL referring to the directory to attach.
///
/// - Returns: An instance of `Data` containing the compressed contents of the
///   given directory.
///
/// - Throws: Any error encountered trying to compress the directory, or if
///   directories cannot be compressed on this platform.
///
/// This function asynchronously compresses the contents of `directoryURL` into
/// an archive (currently of `.zip` format, although this is subject to change.)
private func _compressContentsOfDirectory(at directoryURL: URL) async throws -> Data {
#if !SWT_NO_PROCESS_SPAWNING
  let temporaryName = "\(UUID().uuidString).zip"
  let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(temporaryName)
  defer {
    try? FileManager().removeItem(at: temporaryURL)
  }

  // The standard version of tar(1) does not (appear to) support writing PKZIP
  // archives. FreeBSD's (AKA bsdtar) was long ago rebased atop libarchive and
  // knows how to write PKZIP archives, while Windows inherited FreeBSD's tar
  // tool in Windows 10 Build 17063 (per https://techcommunity.microsoft.com/blog/containers/tar-and-curl-come-to-windows/382409).
  //
  // On Linux and OpenBSD (which do not have FreeBSD's version of tar(1)), we
  // can use zip(1) instead. This tool compresses paths relative to the current
  // working directory, and posix_spawn_file_actions_addchdir_np() is not always
  // available for us to call (not present on OpenBSD, requires glibc ≥ 2.28 on
  // Linux), so we'll spawn a shell that calls cd before calling zip(1).
  //
  // OpenBSD's tar(1) does not support writing PKZIP archives, and /usr/bin/zip
  // tool is an optional install, so we check if it's present before trying to
  // execute it.
#if os(Linux) || os(OpenBSD)
  let archiverPath = "/bin/sh"
#if os(Linux)
  let trueArchiverPath = "/usr/bin/zip"
#else
  let trueArchiverPath = "/usr/local/bin/zip"
  var isDirectory = false
  if !FileManager.default.fileExists(atPath: trueArchiverPath, isDirectory: &isDirectory) || isDirectory {
    throw CocoaError(.fileNoSuchFile, userInfo: [
      NSLocalizedDescriptionKey: "The 'zip' package is not installed.",
      NSFilePathErrorKey: trueArchiverPath
    ])
  }
#endif
#elseif SWT_TARGET_OS_APPLE || os(FreeBSD)
  let archiverPath = "/usr/bin/tar"
#elseif os(Windows)
  guard let archiverPath = _archiverPath else {
    throw CocoaError(.fileWriteUnknown, userInfo: [
      NSLocalizedDescriptionKey: "Could not determine the path to '\(_archiverName)'.",
    ])
  }
#else
#warning("Platform-specific implementation missing: tar or zip tool unavailable")
  let archiverPath = ""
  throw CocoaError(.featureUnsupported, userInfo: [NSLocalizedDescriptionKey: "This platform does not support attaching directories to tests."])
#endif

  let sourcePath = directoryURL.path
  let destinationPath = temporaryURL.path
  let arguments = {
#if os(Linux) || os(OpenBSD)
    // The zip command constructs relative paths from the current working
    // directory rather than from command-line arguments.
    ["-c", #"cd "$0" && "$1" "$2" --recurse-paths ."#, sourcePath, trueArchiverPath, destinationPath]
#elseif SWT_TARGET_OS_APPLE || os(FreeBSD)
    ["--create", "--auto-compress", "--directory", sourcePath, "--file", destinationPath, "."]
#elseif os(Windows)
    // The Windows version of bsdtar can handle relative paths for other archive
    // formats, but produces empty archives when inferring the zip format with
    // --auto-compress, so archive with absolute paths here.
    //
    // An alternative may be to use PowerShell's Compress-Archive command,
    // however that comes with a security risk as we'd be responsible for two
    // levels of command-line argument escaping.
    ["--create", "--auto-compress", "--file", destinationPath, sourcePath]
#endif
  }()

  let exitStatus = try await spawnExecutableAtPathAndWait(archiverPath, arguments: arguments)
  guard case .exitCode(EXIT_SUCCESS) = exitStatus else {
    throw CocoaError(.fileWriteUnknown, userInfo: [
      NSLocalizedDescriptionKey: "The directory at '\(sourcePath)' could not be compressed (\(exitStatus)).",
    ])
  }

  return try Data(contentsOf: temporaryURL, options: [.mappedIfSafe])
#else
  throw CocoaError(.featureUnsupported, userInfo: [NSLocalizedDescriptionKey: "This platform does not support attaching directories to tests."])
#endif
}
#endif
#endif
