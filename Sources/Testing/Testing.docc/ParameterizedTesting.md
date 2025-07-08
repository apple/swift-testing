# Implementing parameterized tests

<!--
This source file is part of the Swift.org open source project

Copyright (c) 2023-2024 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

Specify different input parameters to generate multiple test cases from a test function.

## Overview

Some tests need to be run over many different inputs. For instance, a test might
need to validate all cases of an enumeration. The testing library lets
developers specify one or more collections to iterate over during testing, with
the elements of those collections being forwarded to a test function. An
invocation of a test function with a particular set of argument values is called
a test _case_.

By default, the test cases of a test function run in parallel with each
other. For more information about test parallelization, see
<doc:Parallelization>.

### Parameterize over an array of values

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

When passing a collection to the `@Test` attribute for parameterization, the
testing library passes each element in the collection, one at a time, to the
test function as its first (and only) argument. Then, if the test fails for one
or more inputs, the corresponding diagnostics can clearly indicate which inputs
to examine.

### Parameterize over the cases of an enumeration

The previous example includes a hard-coded list of `Food` cases to test. If `Food`
is an enumeration that conforms to `CaseIterable`, you can instead write:

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

This way, if a new case is added to the `Food` enumeration, it's
automatically tested by this function.

### Parameterize over a range of integers

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

### Pass the same arguments to multiple test functions

If you want to pass the same collection of arguments to two or more
parameterized test functions, you can extract the arguments to a separate
function or property and pass it to each `@Test` attribute. For example:

```swift
extension Food {
  static var bestSelling: [Food] {
    get async throws { /* ... */ }
  }
}

@Test(arguments: try await Food.bestSelling)
func `Order entree`(food: Food) {
  let foodTruck = FoodTruck()
  #expect(foodTruck.order(food))
}

@Test(arguments: try await Food.bestSelling)
func `Package leftovers`(food: Food) throws {
  let foodTruck = FoodTruck()
  let container = try #require(foodTruck.container(fitting: food))
  try container.add(food)
}
```

> Tip: You can prefix expressions passed to `arguments:` with `try` or `await`.
> The testing library evaluates them lazily only if it determines that the
> associated test will run.

### Test with more than one collection

It's possible to test more than one collection. Consider the following test
function:

```swift
@Test("Can make large orders", arguments: Food.allCases, 1 ... 100)
func makeLargeOrder(of food: Food, count: Int) async throws {
  let foodTruck = FoodTruck(selling: food)
  #expect(await foodTruck.cook(food, quantity: count))
}
```

Elements from the first collection are passed as the first argument to the test
function, and elements from the second collection are passed as the second
argument.

Assuming there are five cases in the `Food` enumeration, this test function
will, when run, be invoked 500 times (5 x 100) with every possible combination
of food and order size. These combinations are referred to as the collections'
Cartesian product.

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

This revised test function is invoked once for each tuple in the zipped
sequence, for a total of five invocations instead of 500 invocations. In other
words, this test function is passed the inputs `(.burger, 1)`,
`(.iceCream, 2)`, ..., `(.kebab, 5)` instead of `(.burger, 1)`, `(.burger, 2)`,
`(.burger, 3)`, ..., `(.kebab, 99)`, `(.kebab, 100)`.

### Run selected test cases

If a parameterized test meets certain requirements, the testing library allows
people to run specific test cases it contains. This can be useful when a test
has many cases but only some are failing since it enables re-running and
debugging the failing cases in isolation.

To support running selected test cases, it must be possible to deterministically
match the test case's arguments. When someone attempts to run selected test cases
of a parameterized test function, the testing library evaluates each argument of
the tests' cases for conformance to one of several known protocols, and if all
arguments of a test case conform to one of those protocols, that test case can
be run selectively. The following lists the known protocols, in precedence order
(highest to lowest):

1. ``CustomTestArgumentEncodable``
1. `RawRepresentable`, where `RawValue` conforms to `Encodable`
1. `Encodable`
1. `Identifiable`, where `ID` conforms to `Encodable`

If any argument of a test case doesn't meet one of the above requirements, then
the overall test case cannot be run selectively.
