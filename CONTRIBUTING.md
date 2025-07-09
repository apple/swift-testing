# Contributing to Swift Testing

There are many ways to contribute to this project. If you are making changes
that don't materially affect the user-facing semantics of Swift Testing, such
as fixing bugs or writing documentation, feel free to open a pull request (PR)
directly.

Larger changes that _do_ materially change the semantics of Swift Testing,
such as new APIs or modifications to existing APIs, must undergo community
discussion prior to being accepted.

## Reporting issues

Issues are tracked using the testing library's
[GitHub Issue Tracker](https://github.com/swiftlang/swift-testing/issues).

Fill in the fields of the relevant template form offered on that page when
creating new issues. For bug report issues, please include a minimal example
which reproduces the issue. Where possible, attach the example as a Swift
package, or include a URL to the package hosted on GitHub or another public
hosting service.

## Setting up the development environment

First, clone the Swift Testing repository from
[https://github.com/swiftlang/swift-testing](https://github.com/swiftlang/swift-testing).

If you're preparing to make a contribution, you should fork the repository first
and clone the fork which will make opening PRs easier.

### Using Xcode (easiest)

1. Install Xcode 16 or newer from the [Apple Developer](https://developer.apple.com/xcode/)
   website.
1. Open the `Package.swift` file from the cloned Swift Testing repository in
   Xcode.
1. Select the `swift-testing-Package` scheme (if not already selected) and the
   "My Mac" run destination.
1. Use Xcode to inspect, edit, build, or test the code.

### Using the command line

If you are using macOS and have Xcode installed, you can use Swift from the
command line immediately.

If you aren't using macOS or do not have Xcode installed, you need to download
and install a toolchain.

#### Installing a toolchain

1. Download a toolchain. A recent **development snapshot** toolchain is required
   to build the testing library. Visit [swift.org](https://swift.org/install),
   select your platform, and download the most recent toolchain from the section
   titled **release/6.x** under **Development Snapshots**.

   Be aware that development snapshot toolchains aren't intended for day-to-day
   development and may contain defects that affect the programs built with them.
1. Install the toolchain and confirm it can be located successfully:

   **macOS with Xcode installed**:
   
   ```bash
   $> export TOOLCHAINS=swift
   $> xcrun --find swift
   /Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift
   ```
   
   **Non-macOS or macOS without Xcode**:
   
   ```bash
   $> export PATH=/path/to/swift-toolchain/usr/bin:"${PATH}"
   $> which swift
   /path/to/swift-toolchain/usr/bin/swift
   ```

## Local development

With a Swift toolchain installed and the Swift Testing repository cloned, you
are ready to make changes and test them locally.

### Building

```bash
$> swift build
```

### Testing

```bash
$> swift test
```

<!-- FIXME: Uncomment this once the the `swift test` command support running
  specific Swift Testing tests.

To learn how to run only specific tests or other testing options, run `swift
test --help` to view the usage documentation.
-->

## Using CMake to build the project for macOS

1. Install [CMake](https://cmake.org/) and [Ninja](https://ninja-build.org/).
   - See the [Installing Dependencies](https://github.com/swiftlang/swift/blob/main/docs/HowToGuides/GettingStarted.md#macos)
     section of the Swift [Getting Started](https://github.com/swiftlang/swift/blob/main/docs/HowToGuides/GettingStarted.md)
     guide for instructions.

1. Run the following command from the root of this repository to configure the
   project to build using CMake (using the Ninja generator):

   ```bash
   cmake -G Ninja -B build
   ```

1. Run the following command to perform the build:

   ```bash
   cmake --build build
   ```

### Installing built content using CMake

You can use the steps in this section to perform an install. This is primarily
useful to validate the built content from this project which will be included in
a Swift toolchain.

1. Run the following command to (re-)configure the project with an install
   prefix specified:

   ```bash
   cmake -G Ninja --install-prefix "$(pwd)/build/install" -B build
   ```

1. Perform the CMake build step as described in the previous section.

1. Run the following command to install the built content into the
   `build/install/` subdirectory:

   ```bash
   cmake --install build
   ```

## Using Docker on macOS to test for Linux

1. Install [Docker Desktop for Mac](https://www.docker.com/products/docker-desktop).

1. Run the following command from the root of this repository to build the
   Docker image:

    ```bash
    $> docker build -t swift-testing:latest .
    ```

1. Run the following command to run the test suite:

    ```bash
    $> docker run -v "$(pwd)":/swift-testing -w /swift-testing swift-testing swift test --skip-update
    ```

1. To interactively run the test suite or do other development, first log into
   the container with:

    ```bash
    $> docker run -i -t -v "$(pwd)":/swift-testing swift-testing /bin/bash
    ```

    And then run `swift test` or other commands within the container:

    ```bash
    $> cd /swift-testing
    $> swift test
    ```

## Creating Pull Requests (PRs)

1. Fork [https://github.com/swiftlang/swift-testing](https://github.com/swiftlang/swift-testing).
1. Clone a working copy of your fork.
1. Create a new branch.
1. Make your code changes.
1. Commit your changes. Include a description of the changes in the commit
   message, followed by the GitHub Issue ID or Apple Radar link if there is one.
1. Push your changes to your fork.
1. Create a PR from the branch on your fork targeting the `main` branch of the
   original repository.
1. Follow the PR template to provide information about the motivation and
   details of the changes.

Reviewers will be automatically added to the PR once it is created. The PR will
be merged by the maintainers after it passes continuous integration (CI) testing
and receives approval from one or more reviewers. Merge timing may be impacted
by release schedule considerations.

By submitting a PR, you represent that you have the right to license your
contribution to Apple and the community, and agree by submitting the patch that
your contributions are licensed under the
[Swift license](https://swift.org/LICENSE.txt).

## Continuous integration

Swift Testing uses the [`swift-ci`](https://ci.swift.org/) infrastructure for
its continuous integration (CI) testing. The bots can be triggered on PRs if you
have commit access. Otherwise, ask one of the code owners to trigger them for
you.

To request CI, add a comment in the PR containing:

```
@swift-ci test
```

## Code style

Code should use two spaces for indentation. Block comments including markup
should be limited to 80 columns.

Refer to the testing library's
[documentation style guide](Documentation/StyleGuide.md) for more information.

## Community and support

To connect with the Swift community:

* Use the [Swift Forums](https://forums.swift.org)
* Contact the [code owners](CODEOWNERS)

## Additional resources

* [Swift.org Contributing page](https://swift.org/contributing/)
* [License](https://swift.org/LICENSE.txt)
* [Code of Conduct](https://swift.org/community/#code-of-conduct)
