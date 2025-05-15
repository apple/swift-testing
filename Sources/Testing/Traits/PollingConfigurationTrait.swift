//
//  PollingConfiguration.swift
//  swift-testing
//
//  Created by Rachel Brindle on 6/6/25.
//

/// A trait to provide a default polling configuration to all usages of
/// ``confirmation(_:until:within:pollingEvery:isolation:sourceLocation:_:)-455gr``
/// and
/// ``confirmation(_:until:within:pollingEvery:isolation:sourceLocation:_:)-5tnlk``
/// within a test or suite using the specified stop condition.
///
/// To add this trait to a test, use the ``Trait/pollingConfirmationDefaults``
/// function.
@_spi(Experimental)
@available(_clockAPI, *)
public struct PollingConfirmationConfigurationTrait: TestTrait, SuiteTrait {
  /// The stop condition to this configuration is valid for
  public var stopCondition: PollingStopCondition

  /// How long to continue polling for. If nil, this will fall back to the next
  /// inner-most `PollingUntilStopsPassingConfigurationTrait.duration` value.
  /// If no non-nil values are found, then it will use 1 second.
  public var duration: Duration?

  /// The minimum amount of time to wait between polling attempts. If nil, this
  /// will fall back to earlier `PollingUntilStopsPassingConfigurationTrait.interval`
  /// values. If no non-nil values are found, then it will use 1 millisecond.
  public var interval: Duration?

  public var isRecursive: Bool { true }

  public init(
    stopCondition: PollingStopCondition,
    duration: Duration?,
    interval: Duration?
  ) {
    self.stopCondition = stopCondition
    self.duration = duration
    self.interval = interval
  }
}

@_spi(Experimental)
@available(_clockAPI, *)
extension Trait where Self == PollingConfirmationConfigurationTrait {
  /// Specifies defaults for polling confirmations in the test or suite.
  ///
  /// - Parameters:
  ///   - stopCondition: The `PollingStopCondition` this trait applies to.
  ///   - duration: The expected length of time to continue polling for.
  ///     This value may not correspond to the wall-clock time that polling
  ///     lasts for, especially on highly-loaded systems with a lot of tests
  ///     running.
  ///     if nil, polling will be attempted for approximately 1 second.
  ///     `duration` must be greater than 0.
  ///   - interval: The minimum amount of time to wait between polling
  ///     attempts.
  ///     If nil, polling will wait at least 1 millisecond between polling
  ///     attempts.
  ///     `interval` must be greater than 0.
  public static func pollingConfirmationDefaults(
    until stopCondition: PollingStopCondition,
    within duration: Duration? = nil,
    pollingEvery interval: Duration? = nil
  ) -> Self {
    PollingConfirmationConfigurationTrait(
      stopCondition: stopCondition,
      duration: duration,
      interval: interval
    )
  }
}
