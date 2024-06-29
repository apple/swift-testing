# Public Issues API

* Proposal: [SWT-NNNN](NNNN-public-issues-api.md)
* Authors: [Rachel Brindle](https://github.com/younata)
* Status: **Awaiting review**
* Bug: [apple/swift-testing#474](https://github.com/apple/swift-testing/issues/474)
* Implementation: [apple/swift-testing#481](https://github.com/apple/swift-testing/pull/481)
* Review: n/a

## Introduction

Swift Testing should provide a more robust Issue-reporting API, to facilitate
better integration with third-party assertion tools.

## Motivation

There are several third-party assertion libraries that developers are used to
using, and Swift Testing should make it as easy as possible for the developers
and maintainers of these third-party assertion libraries to integrate with
Swift Testing.

Swift Testing currently offers the `Issue.record` family of static methods,
which provides an acceptable interface for one-off/custom assertions without
using the `#expect` or `#require` macros. Unfortunately, `Issue.record` is not
robust enough for dedicated assertion libraries like Nimble. For example,
there is no current way to provide an `Issue.Kind` to `Issue.record`.


## Proposed solution

I propose making the initializer for `Issue` public, and provide a public
`Issue.record()` instance method to report that Issue. This provides a clean,
easy to maintain way to create and record custom Issues that assertion tools
are already used to because it is analogous to the XCTIssue API in XCTest.

To help support this, I also propose making a public initializer for
`Expectation`. This public initializer will not take in an `Expression`.
Instead, the public initializer will create an empty `Expression`, in order to
maintain compatibility with the current JSON ABI.

## Detailed design

Create a public initializer for `Issue`, which is not gated by
`@_spi(ForToolsIntegrationOnly)`:

```swift
public struct Issue: Sendable {
  // ...

  /// Initialize an issue instance with the specified details.
  ///
  /// - Parameters:
  ///   - kind: The kind of issue this value represents.
  ///   - comments: An array of comments describing the issue. This array may
  ///     be empty.
  ///   - sourceContext: A ``SourceContext`` indicating where and how this
  ///     issue occurred. This defaults to a default source context returned by
  ///     calling ``SourceContext/init(backtrace:sourceLocation:)`` with zero
  ///     arguments.
  public init(
    kind: Kind,
    comments: [Comment] = [],
    sourceContext: SourceContext = .init()
  ) {}

  // ...
}
```

Additionally, create a public `record()` method on Issue, which takes no
arguments, and simply calls the `Issue.record(configuration:)` instance
method with nil:

```swift
extension Issue {
  /// Record this issue by wrapping it in an ``Event`` and passing it to the
  /// current event handler.
  ///
  /// - Returns: The issue that was recorded (`self` or a modified copy of it.)
  @discardableResult
  public func record() -> Self {}
}
```

This change requires us to eliminate the default value of `nil` for the
`Issue.record(configuration:)` instance method:

```swift
extension Issue {
  func record(configuration: Configuration?)  -> Self {}
}
```

Furthermore, to support passing in any `Issue.Kind` to `Issue`, `Expectation`
needs to have a public initializer. This initializer will not take in an
`Expression`, but instead directly create an empty `Expression`. To continue
supporting the existing internal API, there will be a second internal
initializer that does take in an `Expression`:

```public struct Expectation: Sendable {
  // ...
  public init(
    mismatchedErrorDescription: String? = nil,
    differenceDescription: String? = nil,
    isPassing: Bool,
    isRequired: Bool,
    sourceLocation: SourceLocation
  ) {}

  init(
    evaluatedExpression: Expression,
    mismatchedErrorDescription: String? = nil,
    differenceDescription: String? = nil,
    isPassing: Bool,
    isRequired: Bool,
    sourceLocation: SourceLocation
  )
}
```

This also accompanies a change to make the
`Expectation.mismatchedErrorDescription` and
`Expectation.differenceDescription` properties publicly accessible. Which is
done so that third party tools do not need to pass in an `Expression`.

## Source compatibility

This is strictly an additive change. No deletion of code, nothing is being made
private. Only new code and making existing code public.

## Integration with supporting tools

Third-party assertion tools would be able to directly create an `Issue`
and then report it using the `Issue.record()` instance method. `Issue.record()`
would then work similarly to how it does now. This flow is analogous to
reporting an issue in XCTest using the XCTIssue API.

## Future directions

Also necessary for supporting third-party assertion tools is providing a stable
and reliable API for accessing the current test. This somewhat exists with the
current `Test.current` static property, but that returns the
semantically-incorrect value of nil if you access it from a detached task. This
will be defined in a future proposal.

## Alternatives considered

One potential approach is to extend or provide overloads to `Issue.record` that
allows developers to specify every property on an `Issue`. However, this is
undesirable from a maintenance point of view: every time a property is added to
or removed from `Issue`, we would similarly have to update `Issue.record`.
While trivial, having that extra source of truth is mildly annoying.

Another approach discussed in
[apple/swift-testing#474](https://github.com/apple/swift-testing/issues/474)
is making `Issue` public, but tagged with `@_spi(ForToolsIntegrationOnly)`.
Which is also not desirable because that limits third party integrations to
only supporting Swift Testing when managed through Swift Package Manager.
Which means that third party integrations would not be able to support Swift
Testing when managed using Cocoapods, Carthage, or even just by depending on
the raw code. This increases the support burden on those third party tools
because they then have to explain why they only support Swift Testing when
managed through Swift Package Manager.

I also considered combining this with a proposal to provide a more reliable
API for accessing the current test, as mentioned in the Future Directions
section. I decided against this because while that problem is motivation by the
same motivation behind this proposal, it is also a significantly harder
problem. Which is deserving of a full document describing the problem and the
solution. Additionally, the concern behind this proposal is to provide the same
access to issue reporting that `#expect` and `#require` enjoy, while making
accessing the current test more reliable and robust is a separate concern.

## Acknowledgments

I'd like to thank [Jonathon Grynspan](https://github.com/grynspan) and
[Stuart Montgomery](https://github.com/stmontgomery) for fielding my Issue
report and encouraging me to contribute more to this community.
