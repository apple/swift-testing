# Code and documentation style guide

<!--
This source file is part of the Swift.org open source project

Copyright (c) 2023-2024 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

Write code and documentation that matches the style and voice in the rest of the
testing library.

## Overview

The testing library has a specific style used in its code and documentation.
When preparing code or documentation for submission to the testing library,
developers should take care to match this style and ensure that developers using
it have a consistent experience.

### Code

#### Indentation and spacing

When writing code for the testing library, use two spaces for indentation. Wrap
comments (especially long block comments) at 80 columns. Code doesn't need to
be wrapped at 80 columns, however, it's recommended that you break up long 
argument lists up across multiple lines if doing so improves readability.

#### Symbol names and API design

New API should follow the rules documented in the Swift
[API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).

Swift symbols that, for technical reasons, must be `public` but which are not
meant to be part of the testing library's public interface should be given two
leading underscores. For example:

```swift
public func __check()
```

Symbols marked `private` should be given a leading underscore to emphasize that
they are private. Symbols marked `fileprivate`, `internal`, etc. should not have
a leading underscore (except for those `public` symbols mentioned above.)

Symbols that provide storage for higher-visibility symbols can be underscored if
their preferred names would otherwise conflict. For example:

```swift
private var _errorCount: Int

public var errorCount: Int {
  get {
    _errorCount
  }
  set {
    precondition(newValue >= 0, "Error count cannot be negative")
    _errorCount = newValue
  }
}
```

Properties, variables, and constants in Swift whose access level is `public` or
greater, or which have the `@usableFromInline` attribute, must have an
explicitly specified type even if they have an initialization expression and the
compiler could infer their type. This is meant to protect against future changes
to the code called by the initialization expression causing the inferred type of
its property to change unknowingly, which could break clients. Properties with
lower access levels may have an inferred type.

C and C++ symbols that are used by the testing library should be given the
prefix `swt_` and should otherwise be named using the same lowerCamelCase naming
rules as in Swift. Use the `SWT_EXTERN` macro to ensure that symbols are
consistently visible in C, C++, and Swift. For example:

```c
SWT_EXTERN bool swt_isDebugModeEnabled(void);

SWT_EXTERN void swt_setDebugModeEnabled(bool isEnabled);
```

> [!NOTE]
> If a symbol is meant to be **publicly visible** and can be called by modules
> other than Swift Testing, use the prefix `swift_testing_` instead of `swt_`
> for consistency with the Swift standard library:
>
> ```c
> SWT_EXTERN void swift_testing_debugIfNeeded(void);
> ```

C and C++ types should be given the prefix `SWT` and should otherwise be named
using the same UpperCamelCase naming rules as in Swift. For example:

```c
typedef intmax_t SWTBigInteger;

typedef struct SWTContainer {
  ...
} SWTContainer;
```

#### Documenting symbols

Most symbols, including symbols marked `private`, should be given markup-style
documentation. Symbols that fulfill protocol requirements don't need to be
given additional documentation (the documentation in the protocol declaration is
generally sufficient).

When writing an symbol abstracts, follow these general guidelines: 

**Limit abstracts to a single sentence that's 150 characters or fewer.** 
Abstracts consist of a single sentence or sentence fragment. Move any additional 
information or explanation to other sections, such as the Overview (for 
articles, classes, protocols, structures) or the Discussion (for methods, 
properties, constants).

**Don't repeat the technical terms in an entity's name.** Abstracts are concise 
but descriptive, and provide more information than a simple repetition of the 
symbol name.

**Don't include links to other symbols in the abstract.** Avoid making the 
reader leave the abstract to investigate terms. Provide links to other symbols 
in the Overview, Discussion, See Also, or other sections.

**Don't include symbol names or technical terms in code font.** Use “plain 
English” rather than the literal names to describe symbols. Specify the related 
symbols in the Overview, Discussion, or other sections. 

**Avoid parentheses or slashes in abstracts.** Don't add alternative versions of
terms or parenthetical asides in an abstract. If a task or topic requires
explanation, include the information in the Overview or Discussion. Acronyms are
an exception; spell out the full name on first use and include the acronym in
parentheses, such as: *Your computer can transfer information to devices that
use Bluetooth Low Energy (BLE) wireless technology.*

**Avoid language like *the following* or *below* or *these 
examples* in your abstract.** Abstracts can appear without context in a search 
result, so locational modifiers can be confusing.

**Use the correct grammatical style for the symbol.** Abstracts start 
with a noun phrase or a verb phrase --- either a verb ending in *s* or an 
imperative statement that conveys the symbol's action. Refer to the following 
table when constructing your abstract:

| Noun                 | Imperative verb       | Verb ending in *s*        |
|----------------------|-----------------------|---------------------------|
| Associated type      | API collection pages  | Enumerations |
| Class                | Articles              | Function and function macro |
| Constant             | Sample code projects  | Initializer |
| Entitlement          |                       | Macro |
| Enumerated types     |                       | Method |
| Information property list key |              | Notification |
| Property             |                       | Subscript |
| Protocol             |  |  |
| Structure            |  |  |
| Type alias           |  |  |
| Variable             |  |  |

For instance, when writing the abstract for a class `Order`, you could write:

> An object that stores the details for a specific order from a vendor.

Or, when writing the abstract for an enumeration `Flavor`, you could write:

> Describes the flavors of an ingredient.

To organize symbols under types, place them in topic groups organized by usage.
Begin topic group headings inside types with a noun or noun phrase.

#### Writing compile-time diagnostics

The macro target of this package produces a number of different compile-time
diagnostics. These diagnostics should be written according to the Swift style
guide for compiler diagnostics [here](https://github.com/swiftlang/swift/blob/main/docs/Diagnostics.md).

### Documentation

Documentation for the testing library should follow the
[Swift Book style guide](https://github.com/swiftlang/swift-book/blob/main/Style.md)
and [Apple Style Guide](https://support.apple.com/guide/applestyleguide/) as
contextually appropriate.

#### Example applications, projects, and packages

In general, when an application, project, or package is needed for example code,
use "FoodTruck", an imaginary application that is based around the concept of a
mobile restaurant that sells various foods. When referencing foods in example
code, prefer foods that are recognizable to an international audience, or use a
set of different foods from multiple cultures.

Example code must be syntactically correct and the author should confirm it can
compile and run within an appropriate context. It can rely on external
dependencies that you exclude as long as those dependencies are easy for
the reader to understand, and create or replace.

#### Language

Documentation should be written in U.S. English for an international audience.
Avoid culturally specific references unless they are specifically relevant to
the documentation.

- Note: Culturally insensitive and inappropriate language will not be tolerated.
  Refer to the [Swift Code of Conduct](https://swift.org/code-of-conduct) for
  more information.

#### Voice

Documentation should be written in a professional voice. The author and the
reader are not expected to know each other personally, so avoid overly familiar
terms or colloquialisms such as _we_, _our_, or _let's_.

When writing specific instructions that a reader must follow exactly to
accomplish a task, use the second person (_you_, _your_, and so on).

#### Articles

When writing articles or curating content, keep the structure simple and
relatively flat. Place articles in topic groups alongside the symbols. Follow
these guidelines when creating an article:

- Begin an article title with a _gerund_ (a verb ending in _-ing_).
- After the title, include a single sentence that begins with a verb and quickly
  describes what the article covers.
- Include an overview to serve as an introduction to the article. If required,
  include any setup or configuration tasks as a part of your overview.
- Start section headings with an imperative verb.
- Always follow a section heading with some text to setup the code or problem
  you want to solve.
- Ensure that your filename adheres to the guidance in the 
[Filenames](#filenames) section, below.

#### API collections

To organize related subsets of symbols, articles, and other content, use an API
collection. Follow these guidelines when creating an API collection:

- Begin the collection title with a noun that describes what the items in the 
collection have in common.
- After the title, include a single sentence abstract that describes the items 
in the collection.
- Optionally, include an overview to the collection.
- Organize the symbols under topic group headings. Begin a topic group heading
with a gerund.
- Ensure that your filename adheres to the guidance in the 
[Filenames](#filenames) section, below.

#### Filenames

The filenames used for articles and API collections should match the titles of
those documents. For consistency with other Swift documentation, articles and
API collections in DocC bundles should use [kebab-case](https://en.wikipedia.org/wiki/Letter_case#Kebab_case).
The DocC compiler will preserve your kebab-case filenames in the resulting
documentation archive.

For example, if the title of your article is _Adding tags to tests_, the
filename would be `adding-tags-to-tests.md`, or if the title of the collection
page is _Event tags_, the filename would be `event-tags.md`.

The DocC compiler lowercases URL paths, so filenames converted from
[UpperCamelCase](https://en.wikipedia.org/wiki/Camel_case) may be difficult to
read. UpperCamelCase should still be used for Markdown files in the repository
such as this one that aren't part of a DocC bundle.

For more information, see [Adding Supplemental Content to a Documentation Catalog](https://www.swift.org/documentation/docc/adding-supplemental-content-to-a-documentation-catalog).

#### Technical details

Documentation is encoded as UTF-8 using Markdown where possible.

Documentation should be wrapped at 80 columns, including code samples in
documentation where possible, so the reader doesn't need to scroll
horizontally. If documentation includes a long link, it doesn't need to be
split up over multiple lines, and a URL shortener should _not_ be used.
