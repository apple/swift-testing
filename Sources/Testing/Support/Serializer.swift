//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024–2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

private import _TestingInternals

#if !SWT_NO_UNSTRUCTURED_TASKS
/// The number of CPU cores on the current system, or `nil` if that
/// information is not available.
private var _cpuCoreCount: Int? {
#if SWT_TARGET_OS_APPLE || os(Linux) || os(FreeBSD) || os(OpenBSD) || os(Android)
  return Int(sysconf(Int32(_SC_NPROCESSORS_CONF)))
#elseif os(Windows)
  var siInfo = SYSTEM_INFO()
  GetSystemInfo(&siInfo)
  return Int(siInfo.dwNumberOfProcessors)
#elseif os(WASI)
  return 1
#else
#warning("Platform-specific implementation missing: CPU core count unavailable")
  return nil
#endif
}
#endif

/// The default parallelization width when parallelized testing is enabled.
var defaultParallelizationWidth: Int {
  // _cpuCoreCount.map { max(1, $0) * 2 } ?? .max
  .max
}

/// A type whose instances can run a series of work items in strict order.
///
/// When a work item is scheduled on an instance of this type, it runs after any
/// previously-scheduled work items. If it suspends, subsequently-scheduled work
/// items do not start running; they must wait until the suspended work item
/// either returns or throws an error.
///
/// This type is not part of the public interface of the testing library.
final actor Serializer {
  /// The maximum number of work items that may run concurrently.
  nonisolated let maximumWidth: Int

#if !SWT_NO_UNSTRUCTURED_TASKS
  /// The number of scheduled work items, including any currently running.
  private var _currentWidth = 0

  /// Continuations for any scheduled work items that haven't started yet.
  private var _continuations = [CheckedContinuation<Void, Never>]()
#endif

  init(maximumWidth: Int = 1) {
    precondition(maximumWidth >= 1, "Invalid serializer width \(maximumWidth).")
    self.maximumWidth = maximumWidth
  }

  /// Run a work item serially after any previously-scheduled work items.
  ///
  /// - Parameters:
  ///     - workItem: A closure to run.
  ///
  /// - Returns: Whatever is returned from `workItem`.
  ///
  /// - Throws: Whatever is thrown by `workItem`.
  func run<R>(_ workItem: @isolated(any) @Sendable () async throws -> R) async rethrows -> R where R: Sendable {
#if !SWT_NO_UNSTRUCTURED_TASKS
    _currentWidth += 1
    defer {
      // Resume the next scheduled closure.
      if !_continuations.isEmpty {
        let continuation = _continuations.removeFirst()
        continuation.resume()
      }

      _currentWidth -= 1
    }

    await withCheckedContinuation { continuation in
      if _currentWidth <= maximumWidth {
        // Nothing else was scheduled, so we can resume immediately.
        continuation.resume()
      } else {
        // Something was scheduled, so add the continuation to the
        // list. When it resumes, we can run.
        _continuations.append(continuation)
      }
    }
#endif

    return try await workItem()
  }
}

