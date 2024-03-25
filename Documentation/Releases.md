# How to create swift-testing releases

This document describes how to create a new release of swift-testing using git
tags.

> [!IMPORTANT]
> You must have administrator privileges to create a new release in this
> repository.

## Version numbering

swift-testing uses [semantic versioning](https://semver.org) numbers for its 
open source releases. We use git _tags_ to publish new releases; we do not use
the GitHub [releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)
feature.

At this time, all swift-testing releases are experimental, so the major version
is always `0`. We are not using the patch component, so it is usually (if not
always) `0`. The minor component should be incremented by one for each release.

For example, if the current release is version `0.1.0` and you are publishing
the next release, it should be `0.2.0`.

> [!NOTE]
> Where you see `x.y.z` in this document, substitute the semantic version you
> are deploying.

## Creating a branch for the release

Before a release can be published, a branch must be created so that the
repository can be configured correctly. Ensure any local changes have been saved
and cleared from the repository (e.g. with `git stash` or `git reset --hard`),
then run the following commands from within the repository's root directory:

```sh
git checkout main # or other branch as appropriate
git pull
git checkout -b release/x.y.z
```

## Preparing the repository's contents

The package manifest files (Package.swift _and_ Package@swift-6.0.swift) must
be updated so that the release can be used as a package dependency:

1. Change the `isBuildingForDistribution` constant from `false` to `true`.
1. Open the "Documentation/Testing.docc/TemporaryGettingStarted.md" file and
   update the line:

    ```diff
    -  .package(url: "https://github.com/apple/swift-testing.git", branch: "main"),
    +  .package(url: "https://github.com/apple/swift-testing.git", from: "x.y.z"),
    ```

The repository's local state is now updated. To commit it to your branch, run
the typical commit command:

```sh
git commit -a -m "Deploy x.y.z"
```

## Smoke-testing the branch

Before deploying the tag publicly, test it by creating a simple package locally.
For example, you can initialize a new package in an empty directory with:

```sh
swift package init --enable-experimental-swift-testing
```

And then modify the package's `Package.swift` file to point at your local clone
of the swift-testing repository. Ensure that the package's test target builds
and runs successfully with:

```sh
swift test
```

> [!NOTE]
> Be sure to test changes on both macOS and Linux using the most recent
> main-branch Swift toolchain.   

If changes to swift-testing are necessary for the build to succeed, open
appropriate pull requests on GitHub, then rebase your tag branch after they are
merged.

## Committing changes and pushing the release

Run the following commands to push the release and make it publicly visible:

```sh
git tag x.y.z
git push -u origin x.y.z
```

The release is now live and publicly visible [here](https://github.com/apple/swift-testing/tags).
Developers using Swift Package Manager and listing swift-testing as a dependency
will automatically update to it.

## Oh no, I made a mistake…

Don't panic. We all make mistakes.

### … but I haven't pushed the release yet.

If you've already created the release's tag locally, but haven't pushed it yet,
delete it with `git tag -d x.y.z`, resolve the issue, and recreate the tag by
following the steps above.

### … but I can fix it.

If the release is usable, but contains a bug that _cannot_ wait until the next
planned release to be fixed, a patch release can be deployed. First, fix the
issue locally. Then, follow the steps above to create a new release. Where you
would normally increment the _minor_ version component, increment the _patch_
version component instead. For example, if the most recent release was `0.1.2`,
the fix should be released as `0.1.3`.

### … and the release is completely unusable!

If the release is broken and will not be usable by developers, delete the
release's tag from GitHub using `git push --delete origin x.y.z` so that
developers do not inadvertently download it.

> [!IMPORTANT]
> Deleting a release or tag is often considered bad form, so only do so if the
> release is truly unusable.
