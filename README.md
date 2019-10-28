# Fuse

[![CI Status](http://img.shields.io/travis/krisk/fuse-swift.svg?style=flat)](https://travis-ci.org/krisk/fuse-swift)
[![Version](https://img.shields.io/cocoapods/v/Fuse.svg?style=flat)](http://cocoapods.org/pods/Fuse)
[![License](https://img.shields.io/cocoapods/l/Fuse.svg?style=flat)](http://cocoapods.org/pods/Fuse)
[![Platform](https://img.shields.io/cocoapods/p/Fuse.svg?style=flat)](http://cocoapods.org/pods/Fuse)
[![Donate](https://img.shields.io/badge/Donate-PayPal-red.svg)](https://www.paypal.me/kirorisk)
[![Donate](https://img.shields.io/badge/patreon-donate-red.svg)](https://www.patreon.com/fusejs)

## What is Fuse?

Fuse is a super lightweight library which provides a simple way to do fuzzy searching.

<!-- ![Demo](https://s17.postimg.org/47a90nmvj/bitap-search-demo.gif) -->

## Usage

#### Searching in a string

[Reference](Fuse/Classes/Fuse.swift#L265)

```swift
let fuse = Fuse()
let result = fuse.search("od mn war", in: "Old Man's War")

print(result?.score)  // 0.44444444444444442
print(result?.ranges) // [CountableClosedRange(0...0), CountableClosedRange(2...6), CountableClosedRange(9...12)]
```

#### Searching in an array of strings

[Reference](Fuse/Classes/Fuse.swift#L275)

```swift
let books = ["The Silmarillion", "The Lock Artist", "The Lost Symbol"]
let fuse = Fuse()

let results = fuse.search("Te silm", in: books)

results.forEach { item in
    print("index: " + item.index)
    print("score: " + item.score)
    print("ranges: " + item.ranges)
}
```

##### Asynchronous version

[Reference](Fuse/Classes/Fuse.swift#L296)

```swift
fuse.search("Te silm", in: books, completion: { results in
    results.forEach { item in
        print("index: " + item.index)
        print("score: " + item.score)
        print("ranges: " + item.ranges)
    }
})
```

#### Searching in an array of `Fuseable` objects.

[Reference](Fuse/Classes/Fuse.swift#L360)

```swift
struct Book: Fuseable {
    let title: String
    let author: String

    var properties: [FuseProperty] {
        return [
            FuseProperty(name: title, weight: 0.3),
            FuseProperty(name: author, weight: 0.7),
        ]
    }
}

let books: [Book] = [
    Book(author: "John X", title: "Old Man's War fiction"),
    Book(author: "P.D. Mans", title: "Right Ho Jeeves")
]
let fuse = Fuse()
let results = fuse.search("man", in: books)

results.forEach { item in
    print("index: " + item.index)
    print("score: " + item.score)
    print("results: " + item.results)
    print("---------------")
}

// Output:
//
// index: 1
// score: 0.015
// results: [(key: "author", score: 0.015000000000000003, ranges: [CountableClosedRange(5...7)])]
// ---------------
// index: 0
// score: 0.028
// results: [(key: "title", score: 0.027999999999999997, ranges: [CountableClosedRange(4...6)])]
```

##### Asynchronous version

[Reference](Fuse/Classes/Fuse.swift#L447)

```swift
fuse.search("Man", in: books, completion: { results in
    results.forEach { item in
        print("index: " + item.index)
        print("score: " + item.score)
        print("results: " + item.results)
        print("---------------")
    }
})
```

### Options

`Fuse` takes the following options:

- `location`: Approximately where in the text is the pattern expected to be found. Defaults to `0`
- `distance`: Determines how close the match must be to the fuzzy `location` (specified above). An exact letter match which is `distance` characters away from the fuzzy location would score as a complete mismatch. A distance of `0` requires the match be at the exact `location` specified, a `distance` of `1000` would require a perfect match to be within `800` characters of the fuzzy location to be found using a `0.8` threshold. Defaults to `100`
- `threshold`: At what point does the match algorithm give up. A threshold of `0.0` requires a perfect match (of both letters and location), a threshold of `1.0` would match anything. Defaults to `0.6`
- `maxPatternLength`: The maximum valid pattern length. The longer the pattern, the more intensive the search operation will be. If the pattern exceeds the `maxPatternLength`, the `search` operation will return `nil`. Why is this important? [Read this](https://en.wikipedia.org/wiki/Word_(computer_architecture)#Word_size_choice). Defaults to `32`
- `isCaseSensitive`: Indicates whether comparisons should be case sensitive. Defaults to `false`

## Example Project

To run the example project, clone the repo, and run `pod install` from the Example directory first.

## Requirements

## Installation

1. Add a dependency on Fuse:
- CocoaPods: add `pod 'Fuse'` to your `Podfile`. 
- Carthage: add `github "krisk/fuse-swift"` to your `Cartfile`.

2. Add `import Fuse` to your source files.

## License

Fuse is available under the MIT license. See the LICENSE file for more info.
