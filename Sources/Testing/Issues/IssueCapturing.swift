//
//  IssueCapturing.swift
//  swift-testing
//
//  Created by Rachel Brindle on 8/24/26.
//

/// A type that represents an active
/// ``captureIssues(sourceLocation:_:matching:)``
/// call and any parent calls.
///
/// A stack of these is stored in `IssueCapturingContext.current`.
struct IssueCapturingScope: Sendable {
  /// A function which determines if an issue matches an issue capturing scope
  /// or any of its ancestor scopes.
  ///
  /// - Parameters:
  ///   - issue: The issue being matched
  ///
  /// - Returns: An issue capturing context containing information about the
  ///   captured issue, if the issue is "captured" by this this issue capturing
  ///   scope or any ancestor scope, or `nil` otherwise.
  typealias Matcher = @Sendable (_ issue: Issue) -> Issue.KnownIssueContext?

  /// The matcher function for this issue capturing scope.
  var matcher: Matcher

  /// The issues this scope has matched.
  let issues: Locked<[Issue]>

  let captureSilently: Bool

  /// Create a new ``IssueCapturingScope`` by companing a new issue matcher
  /// with any already-active scope
  ///
  /// - Parameters:
  ///   - Parent: The context that should be checked next if `issueMatcher` fails
  ///     to match an issue. Defaults to ``IssueCapturingScope.current``.
  ///   - issueMatcher: A function to invoke when an issue occurs that is used
  ///     to determine if the issue should be captured by this scope.
  ///   - context: The context to be associated with issues matched by
  ///     `issueMatcher`.
  init(parent: IssueCapturingScope? = .current, captureSilently: Bool, issueMatcher: @escaping KnownIssueMatcher, context: Issue.KnownIssueContext) {
    let issues = Locked(rawValue: [Issue]())
    self.issues = issues
    self.captureSilently = captureSilently

    matcher = { issue in
      let matchedContext = if issueMatcher(issue) {
        context
      } else {
        parent?.matcher(issue)
      }
      if matchedContext != nil {
        issues.withLock { issues in
          issues.append(issue)
        }
      }
      return matchedContext
    }
  }

  /// The active issue capturing scope for the current task, if any.
  ///
  /// If there is no call to
  /// ``captureIssues(sourceLocation:_:matching:)``
  /// executing on the current taks, the value of this property is `nil`.
  @TaskLocal
  static var current: IssueCapturingScope?
}

/// Invoke a function, and return any issues recorded during its execution.
///
/// - Parameters:
///   - comment: An optional comment describing the context around this issue.
///   - sourceLocation: The source location to which any recorded issues should
///     be attributed.
///   - body: The function to invoke.
///   - issueMatcher: A function to invoke when an issue occurs that is used to
///     determine if the issue should be captured. By default, all issues match.
///
/// - Throws: Whatever is thrown by `body`, unless it is matched by
///   `issueMatcher`.
///
/// Library authors use this function to capture and analyze any issues for
/// later analysis. This is particularly useful for verifying that test helpers
/// correctly record issues.
/// Test authors should probably use
/// ``withKnownIssue(_:isIntermittent:sourceLocation:_:when:matching:)``.
///
/// - Note: `issueMatcher` may be invoked more than once for the same issue.
func captureIssues<R>(
  _ comment: Comment? = nil,
  silently: Bool,
  sourceLocation: SourceLocation = #_sourceLocation,
  _ body: () throws -> sending R,
  matching issueMatcher: @escaping KnownIssueMatcher = { _ in true }
) rethrows -> (R, [Issue]) {
  let scope = IssueCapturingScope(
    captureSilently: silently,
    issueMatcher: issueMatcher,
    context: Issue.KnownIssueContext(comment: comment)
  )
  let value = try IssueCapturingScope.$current.withValue(scope) {
    try body()
  }
  return (value, scope.issues.withLock { $0 })
}

/// Invoke a function, and return any issues recorded during its execution.
///
/// - Parameters:
///   - comment: An optional comment describing the context around this issue.
///   - sourceLocation: The source location to which any recorded issues should
///     be attributed.
///   - body: The function to invoke.
///   - issueMatcher: A function to invoke when an issue occurs that is used to
///     determine if the issue should be captured. By default, all issues match.
///
/// - Throws: Whatever is thrown by `body`, unless it is matched by
///   `issueMatcher`.
///
/// Library authors use this function to capture and analyze any issues for
/// later analysis. This is particularly useful for verifying that test helpers
/// correctly record issues.
/// Test authors should probably use
/// ``withKnownIssue(_:isIntermittent:sourceLocation:_:when:matching:)``.
///
/// - Note: `issueMatcher` may be invoked more than once for the same issue.
func captureIssues<R>(
  _ comment: Comment? = nil,
  silently: Bool,
  isolation: isolated (any Actor)? = #isolation,
  sourceLocation: SourceLocation = #_sourceLocation,
  _ body: () async throws -> sending R,
  matching issueMatcher: @escaping KnownIssueMatcher = { _ in true }
) async rethrows -> (R, [Issue]) {
  let scope = IssueCapturingScope(
    captureSilently: silently,
    issueMatcher: issueMatcher,
    context: Issue.KnownIssueContext(comment: comment)
  )
  let value = try await IssueCapturingScope.$current.withValue(scope) {
    try await body()
  }
  return (value, scope.issues.withLock { $0 })
}
