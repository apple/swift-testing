# Parameterized testing

<!--
This source file is part of the Swift.org open source project

Copyright (c) 2023 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

Run the same test multiple times with different inputs.

## Overview

Some tests need to be run over many different inputs. For instance, a test might
need to validate all cases of an enumeration. The testing library lets
developers specify one or more collections to iterate over during testing, with
the elements of those collections being forwarded to a test function. An
invocation of a test function with a particular set of argument values is called
a test _case_.

By default, the test cases of a test function will run in parallel with each
other. For more information about test parallelization, see
<doc:Parallelization>.

## Parameterizing over an array of values

It is very common to want to run a test _n_ times over an array containing the
values that should be tested. Consider the following test function:

```swift
enum Food {
  case burger, iceCream, burrito, noodleBowl, kebab
}

@Test("All foods available")
func foodsAvailable() async throws {
  for food: Food in [.burger, .iceCream, .burrito, .noodleBowl, .kebab] {
    let foodTruck = FoodTruck(selling: food)
    #expect(await foodTruck.cook(food))
  }
}
```

If this test function fails for one of the values in the array, it may be
unclear which value failed. Instead, the test function can be _parameterized
over_ the various inputs:

```swift
enum Food {
  case burger, iceCream, burrito, noodleBowl, kebab
}

@Test("All foods available", arguments: [Food.burger, .iceCream, .burrito, .noodleBowl, .kebab])
func foodAvailable(_ food: Food) async throws {
  let foodTruck = FoodTruck(selling: food)
  #expect(await foodTruck.cook(food))
}
```

When a collection is passed to the `@Test` attribute for parameterization, the
testing library passes each element in the collection, one at a time, to the
test function as its first (and only) argument. Then, if the test fails for one
or more inputs, the corresponding diagnostics can clearly indicate which inputs
need to be examined.

## Parameterizing over the cases of an enumeration

In the example above, we hard-coded the list of `Food` cases to test. If `Food`
is an enumeration conforming to `CaseIterable`, we can instead write:

```swift
enum Food: CaseIterable {
  case burger, iceCream, burrito, noodleBowl, kebab
}

@Test("All foods available", arguments: Food.allCases)
func foodAvailable(_ food: Food) async throws {
  let foodTruck = FoodTruck(selling: food)
  #expect(await foodTruck.cook(food))
}
```

This way, if a new case is added to the `Food` enumeration, it will
automatically be tested by this test function.

## Parameterizing over a range of integers

It is possible to parameterize a test function over a closed range of integers:

```swift
@Test("Can make large orders", arguments: 1 ... 100)
func makeLargeOrder(count: Int) async throws {
  let foodTruck = FoodTruck(selling: .burger)
  #expect(await foodTruck.cook(.burger, quantity: count))
}
```

- Note: Very large ranges such as `0 ..< .max` may take an excessive amount of
  time to test, or may never complete due to resource constraints.

## Testing more than one collection

It is possible to test more than one collection. Consider the following test
function:

```swift
@Test("Can make large orders", arguments: Food.allCases, 1 ... 100)
func makeLargeOrder(of food: Food, count: Int) async throws {
  let foodTruck = FoodTruck(selling: food)
  #expect(await foodTruck.cook(food, quantity: count))
}
```

Elements from the first collection are passed as the first argument to the test
function, elements from the second collection are passed as the second argument,
and so forth.

Assuming there are five cases in the `Food` enumeration, this test function
will, when run, be invoked 5 × 100 = 500 times with every possible combination
of food and order size. These combinations are referred to as the collections'
[Cartesian product](https://en.wikipedia.org/wiki/Cartesian_product).

To avoid the combinatoric semantics shown above, use
[`zip()`](https://developer.apple.com/documentation/swift/zip(_:_:)):

```swift
@Test("Can make large orders", arguments: zip(Food.allCases, 1 ... 100))
func makeLargeOrder(of food: Food, count: Int) async throws {
  let foodTruck = FoodTruck(selling: food)
  #expect(await foodTruck.cook(food, quantity: count))
}
```

The zipped sequence will be "destructured" into two arguments automatically,
then passed to the test function for evaluation.

This revised test function will be invoked once for each tuple in the zipped
sequence, for a total of five invocations instead of 500 invocations. In other
words, this test function will be passed the inputs `(.burger, 1)`,
`(.iceCream, 2)`, ..., `(.kebab, 5)` instead of `(.burger, 1)`, `(.burger, 2)`,
`(.burger, 3)`, ... `(.kebab, 99)`, `(.kebab, 100)`.

## Running selected test cases

If a parameterized test meets certain requirements, the testing library allows
users to run specific test cases it contains. This can be useful when a test
has many cases but only some are failing since it enables re-running and
debugging the failing cases in isolation.

To support running selected test cases, it must be possible to deterministically
match the test case's arguments. When a user attempts to run selected test cases
of a parameterized test function, the testing library evaluates each argument of
the tests' cases for conformance to one of several known protocols, and if all
arguments of a test case conform to one of those protocols, that test case can
be run selectively. The following lists the known protocols, in precedence order
(highest to lowest):

1. ``CustomTestArgumentEncodable``.
1. `RawRepresentable`, where `RawValue` conforms to `Encodable`.
1. `Encodable`.
1. `Identifiable`, where `ID` conforms to `Encodable`.

If any argument of a test case does not meet one of the above requirements, then
the overall test case cannot be run selectively.

## Topics

- ``Test(_:_:arguments:)-8kn7a``
- ``Test(_:_:arguments:_:)``
- ``Test(_:_:arguments:)-3rzok``
- ``CustomTestArgumentEncodable``

## See Also

- ``Test/Parameter``
- ``Test/Case``
