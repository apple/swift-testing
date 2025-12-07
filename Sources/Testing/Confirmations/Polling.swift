//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

/// Default values for polling confirmations.
@available(_clockAPI, *)
private let _defaultPollingConfiguration = (
  pollingDuration: Duration.seconds(1),
  pollingInterval: Duration.milliseconds(1)
)

/// A type defining when to stop polling.
/// This also determines what happens if the duration elapses during polling.
@_spi(Experimental)
public enum PollingStopCondition: Sendable, Equatable, Codable {
  /// Evaluates the expression until the first time it passes
  /// If it does not pass once by the time the duration is reached, then a
  /// failure will be reported.
  case firstPass

  /// Evaluates the expression until the first time it returns fails.
  /// If the expression fails, then a failure will be reported.
  /// If the expression only passes before the duration is reached, then
  /// no failure will be reported.
  /// If the expression does not finish evaluating before the duration is
  /// reached, then a failure will be reported.
  case stopsPassing
}

/// A type describing an error thrown when polling fails.
@_spi(Experimental)
public struct PollingFailedError: Error, Sendable, Codable {
  /// A type describing why polling failed
  public enum Reason: Sendable, Codable {
    /// The polling failed because it was cancelled using `Task.cancel`.
    case cancelled

    /// The polling failed because the stop condition failed.
    case stopConditionFailed(PollingStopCondition)
  }

  /// A user-specified comment describing this confirmation
  public var comment: Comment?

  /// Why polling failed, either cancelled, or because the stop condition failed.
  public var reason: Reason

  /// A ``SourceContext`` indicating where and how this confirmation was called
  @_spi(ForToolsIntegrationOnly)
  public var sourceContext: SourceContext

  /// Initialize an instance of this type with the specified details
  ///
  /// - Parameters:
  ///   - comment: A user-specified comment describing this confirmation.
  ///     Defaults to `nil`.
  ///   - reason: The reason why polling failed.
  ///   - sourceContext: A ``SourceContext`` indicating where and how this
  ///     confirmation was called.
  init(
    comment: Comment? = nil,
    reason: Reason,
    sourceContext: SourceContext,
  ) {
    self.comment = comment
    self.reason = reason
    self.sourceContext = sourceContext
  }
}

extension PollingFailedError: CustomIssueRepresentable {
  func customize(_ issue: consuming Issue) -> Issue {
    if let comment {
      issue.comments.append(comment)
    }
    issue.kind = .pollingConfirmationFailed(
      reason: reason
    )
    issue.sourceContext = sourceContext
    return issue
  }
}

/// Poll expression within the duration based on the given stop condition
///
/// - Parameters:
///   - comment: A user-specified comment describing this confirmation.
///   - stopCondition: When to stop polling.
///   - duration: The expected length of time to continue polling for.
///     This value does not incorporate the time to run `body`, and may not
///     correspond to the wall-clock time that polling lasts for, especially on
///     highly-loaded systems with a lot of tests running.
///     If nil, this uses whatever value is specified under the last
///     ``PollingConfirmationConfigurationTrait`` added to the test or suite
///     with a matching stopCondition.
///     If no such trait has been added, then polling will be attempted for
///     about 1 second before recording an issue.
///     `duration` must be greater than or equal to `interval`.
///   - interval: The minimum amount of time to wait between polling attempts.
///     If nil, this uses whatever value is specified under the last
///     ``PollingConfirmationConfigurationTrait`` added to the test or suite
///     with a matching stopCondition.
///     If no such trait has been added, then polling will wait at least
///     1 millisecond between polling attempts.
///     `interval` must be greater than 0.
///   - sourceLocation: The location in source where the confirmation was called.
///   - body: The function to invoke. The expression is considered to pass if
///     the `body` returns true. Similarly, the expression is considered to fail
///     if `body` returns false.
///
/// - Throws: A `PollingFailedError` if the `body` does not return true within
///   the polling duration.
///
/// Use polling confirmations to check that an event while a test is running in
/// complex scenarios where other forms of confirmation are insufficient. For
/// example, waiting on some state to change that cannot be easily confirmed
/// through other forms of `confirmation`.
@_spi(Experimental)
@available(_clockAPI, *)
public func confirmation(
  _ comment: Comment? = nil,
  until stopCondition: PollingStopCondition,
  within duration: Duration? = nil,
  pollingEvery interval: Duration? = nil,
  sourceLocation: SourceLocation = #_sourceLocation,
  _ body: nonisolated(nonsending) @escaping () async throws -> Bool
) async throws {
  let poller = Poller(
    stopCondition: stopCondition,
    duration: stopCondition.duration(with: duration),
    interval: stopCondition.interval(with: interval),
    comment: comment,
    sourceContext: SourceContext(
      backtrace: .current(),
      sourceLocation: sourceLocation
    )
  )
  try await poller.evaluate() {
    do {
      return try await body()
    } catch {
      return false
    }
  }
}

/// Confirm that some expression eventually returns a non-nil value
///
/// - Parameters:
///   - comment: A user-specified comment describing this confirmation.
///   - stopCondition: When to stop polling.
///   - duration: The expected length of time to continue polling for.
///     This value does not incorporate the time to run `body`, and may not
///     correspond to the wall-clock time that polling lasts for, especially on
///     highly-loaded systems with a lot of tests running.
///     If nil, this uses whatever value is specified under the last
///     ``PollingConfirmationConfigurationTrait`` added to the test or suite
///     with a matching stopCondition.
///     If no such trait has been added, then polling will be attempted for
///     about 1 second before recording an issue.
///     `duration` must be greater than or equal to `interval`.
///   - interval: The minimum amount of time to wait between polling attempts.
///     If nil, this uses whatever value is specified under the last
///     ``PollingConfirmationConfigurationTrait`` added to the test or suite
///     with a matching stopCondition.
///     If no such trait has been added, then polling will wait at least
///     1 millisecond between polling attempts.
///     `interval` must be greater than 0.
///   - sourceLocation: The location in source where the confirmation was called.
///   - body: The function to invoke. The expression is considered to pass if
///     the `body` returns a non-nil value. Similarly, the expression is
///     considered to fail if `body` returns nil.
///
/// - Throws: A `PollingFailedError` if the `body` does not return true within
///   the polling duration.
///
/// - Returns: The last non-nil value returned by `body`.
///
/// Use polling confirmations to check that an event while a test is running in
/// complex scenarios where other forms of confirmation are insufficient. For
/// example, waiting on some state to change that cannot be easily confirmed
/// through other forms of `confirmation`.
@_spi(Experimental)
@available(_clockAPI, *)
@discardableResult
public func confirmation<R>(
  _ comment: Comment? = nil,
  until stopCondition: PollingStopCondition,
  within duration: Duration? = nil,
  pollingEvery interval: Duration? = nil,
  sourceLocation: SourceLocation = #_sourceLocation,
  _ body: nonisolated(nonsending) @escaping () async throws -> sending R?
) async throws -> R {
  let poller = Poller(
    stopCondition: stopCondition,
    duration: stopCondition.duration(with: duration),
    interval: stopCondition.interval(with: interval),
    comment: comment,
    sourceContext: SourceContext(
      backtrace: .current(),
      sourceLocation: sourceLocation
    )
  )
  return try await poller.evaluateOptional() {
    do {
      return try await body()
    } catch {
      return nil
    }
  }
}

/// A helper function to de-duplicate the logic of grabbing configuration from
/// either the passed-in value (if given), the hardcoded default, and the
/// appropriate configuration trait.
///
/// The provided value, if non-nil is returned. Otherwise, this looks for
/// the last `TraitKind` specified, and if one exists, returns the value
/// as determined by `keyPath`.
/// If the provided value is nil, and no configuration trait has been applied,
/// then this returns the value specified in `default`.
///
/// - Parameters:
///   - providedValue: The value provided by the test author when calling
///     `confirmPassesEventually` or `confirmAlwaysPasses`.
///   - default: The harded coded default value, as defined in
///     `_defaultPollingConfiguration`.
///   - keyPath: The keyPath mapping from `TraitKind` to the value type.
///
/// - Returns: The value to use.
private func getValueFromTrait<TraitKind, Value>(
  providedValue: Value?,
  default: Value,
  _ keyPath: KeyPath<TraitKind, Value?>,
  where filter: (TraitKind) -> Bool
) -> Value {
  if let providedValue { return providedValue }
  guard let test = Test.current else { return `default` }
  let possibleTraits = test.traits.compactMap { $0 as? TraitKind }
    .filter(filter)
  let traitValues = possibleTraits.compactMap { $0[keyPath: keyPath] }
  return traitValues.last ?? `default`
}

extension PollingStopCondition {
  /// The result of processing polling.
  enum PollingProcessResult<R> {
    /// Continue to poll.
    case continuePolling
    /// Polling succeeded.
    case succeeded(R)
    /// Polling failed.
    case failed
  }
  /// Process the result of a polled expression and decide whether to continue
  /// polling.
  ///
  /// - Parameters:
  ///   - expressionResult: The result of the polled expression.
  ///   - wasLastPollingAttempt: If this was the last time we're attempting to
  ///     poll.
  ///
  /// - Returns: A process result. Whether to continue polling, stop because
  ///   polling failed, or stop because polling succeeded.
  fileprivate func process<R>(
    expressionResult result: R?,
    wasLastPollingAttempt: Bool
  ) -> PollingProcessResult<R> {
    switch self {
    case .firstPass:
      if let result {
        return .succeeded(result)
      } else if wasLastPollingAttempt {
        return .failed
      } else {
        return .continuePolling
      }
    case .stopsPassing:
      if let result {
        if wasLastPollingAttempt {
          return .succeeded(result)
        } else {
          return .continuePolling
        }
      } else {
        return .failed
      }
    }
  }

  /// Determine the polling duration to use for the given provided value.
  /// Based on ``getValueFromTrait``, this falls back using
  /// ``_defaultPollingConfiguration.pollingInterval`` and
  /// ``PollingUntilFirstPassConfigurationTrait``.
  @available(_clockAPI, *)
  fileprivate func duration(with provided: Duration?) -> Duration {
    getValueFromTrait(
      providedValue: provided,
      default: _defaultPollingConfiguration.pollingDuration,
      \PollingConfirmationConfigurationTrait.duration,
      where: { $0.stopCondition == self }
    )
  }

  /// Determine the polling interval to use for the given provided value.
  /// Based on ``getValueFromTrait``, this falls back using
  /// ``_defaultPollingConfiguration.pollingInterval`` and
  /// ``PollingUntilFirstPassConfigurationTrait``.
  @available(_clockAPI, *)
  fileprivate func interval(with provided: Duration?) -> Duration {
    getValueFromTrait(
      providedValue: provided,
      default: _defaultPollingConfiguration.pollingInterval,
      \PollingConfirmationConfigurationTrait.interval,
      where: { $0.stopCondition == self }
    )
  }
}

/// A type for managing polling
@available(_clockAPI, *)
private struct Poller {
  /// The stop condition to follow
  let stopCondition: PollingStopCondition

  /// Approximately how long to poll for
  let duration: Duration

  /// The minimum waiting period between polling
  let interval: Duration

  /// A user-specified comment describing this confirmation
  let comment: Comment?

  /// A ``SourceContext`` indicating where and how this confirmation was called
  let sourceContext: SourceContext

  /// Evaluate polling, throwing an error if polling fails.
  ///
  /// - Parameters:
  ///   - body: The expression to poll.
  ///
  /// - Throws: A ``PollingFailedError`` if polling doesn't pass.
  ///
  /// - Returns: Whether or not polling passed.
  ///
  /// - Side effects: If polling fails (see ``PollingStopCondition``), then
  ///   this will record an issue.
  @discardableResult func evaluate(
    _ body: nonisolated(nonsending) @escaping () async -> Bool
  ) async throws -> Bool {
    try await evaluateOptional() {
      if await body() {
        // return any non-nil value.
        return true
      } else {
        return nil
      }
    } != nil
  }

  /// Evaluate polling, throwing an error if polling fails.
  ///
  /// - Parameters:
  ///   - body: The expression to poll.
  ///
  /// - Throws: A ``PollingFailedError`` if polling doesn't pass.
  ///
  /// - Returns: the last non-nil value returned by `body`.
  ///
  /// - Side effects: If polling fails (see ``PollingStopCondition``), then
  ///   this will record an issue.
  @discardableResult func evaluateOptional<R>(
    _ body: nonisolated(nonsending) @escaping () async -> sending R?
  ) async throws -> R {
    precondition(interval > Duration.zero)
    precondition(duration >= interval)

    let iterations = Int(exactly:
        max(duration.seconds() / interval.seconds(), 1).rounded()
    ) ?? Int.max
    // if Int(exactly:) returns nil, then that generally means the value is too
    // large. In which case, we should fall back to Int.max.

    let failureReason: PollingFailedError.Reason
    switch await poll(
      iterations: iterations,
      expression: body
    ) {
    case let .succeeded(value):
      return value
    case .cancelled:
      failureReason = .cancelled
    case .failed:
      failureReason = .stopConditionFailed(stopCondition)
    }
    throw PollingFailedError(
      comment: comment,
      reason: failureReason,
      sourceContext: sourceContext
    )
  }

  /// The result of polling.
  private enum PollingResult<R> {
    /// Polling was cancelled using `Task.Cancel`. This is treated as a failure.
    case cancelled
    /// The stop condition failed.
    case failed
    /// The stop condition passed.
    case succeeded(R)
  }

  /// This function contains the logic for continuously polling an expression,
  /// as well as processing the results of that expression.
  ///
  /// - Parameters:
  ///   - iterations: The maximum amount of times to continue polling.
  ///   - expression: An expression to continuously evaluate.
  ///
  /// - Returns: The most recent value if the polling succeeded, else nil.
  private func poll<R>(
    iterations: Int,
    expression: nonisolated(nonsending) @escaping () async -> sending R?
  ) async -> PollingResult<R> {
    for iteration in 0..<iterations {
      switch stopCondition.process(
        expressionResult: await expression(),
        wasLastPollingAttempt: iteration == (iterations - 1)
      ) {
      case .continuePolling: break
      case let .succeeded(value):
        return .succeeded(value)
      case .failed:
        return .failed
      }
      do {
        try await Task.sleep(for: interval)
      } catch {
        // `Task.sleep` should only throw an error if it's cancelled
        // during the sleep period.
        return .cancelled
      }
    }
    // This is somewhat redundant and only here to satisfy the compiler.
    // `PollingStopCondition.process` will return either `.succeeded` or
    // `.failed` on the last polling attempt.
    return .failed
  }
}

@available(_clockAPI, *)
private extension Duration {
  /// The duration, as a ``Double``.
  func seconds() -> Double {
    let secondsComponent = Double(components.seconds)
    let attosecondsComponent = Double(components.attoseconds) * 1e-18
    return secondsComponent + attosecondsComponent
  }
}
