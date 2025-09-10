//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

/// Make a (decorated) task name from the given undecorated task name.
///
/// - Parameters:
///   - taskName: The undecorated task name to modify.
///
/// - Returns: A copy of `taskName` with a common prefix applied, or `nil` if
///   `taskName` was `nil`.
func decorateTaskName(_ taskName: String?, withAction action: String?) -> String? {
  let prefix = "[Swift Testing]"
  return taskName.map { taskName in
#if DEBUG
    precondition(!taskName.hasPrefix(prefix), "Applied prefix '\(prefix)' to task name '\(taskName)' twice. Please file a bug report at https://github.com/swiftlang/swift-testing/issues/new")
#endif
    let action = action.map { " - \($0)" } ?? ""
    return "\(prefix) \(taskName)\(action)"
  }
}
