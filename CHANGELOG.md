# Version 1.2.0

 - Refactor files
 - Remove pods

# Version 1.1.0

- Added asynchronous searching in both `[String]` and `[Fusable]`.

### Results:

Tests based on searching over 1,303 book titles.

Using  `func search(_ text: String, in aList: [String]) -> [Fuse.SearchResult]`:

- *Average*: 0.437
- *Relative standard deviation*: 1.931%
- *Values*: [0.459132, 0.427943, 0.432988, 0.443308, 0.437132, 0.432230, 0.434008, 0.435256, 0.436999, 0.429986]

Using  `func search(_ text: String, in aList: [String], completion: @escaping ([Fuse.SearchResult]) -> Void)`:

- *Average*: 0.161
- *Relative standard deviation*: 2.073%
- *Values*: [0.155997, 0.157061, 0.161730, 0.158362, 0.161959, 0.167433, 0.162196, 0.165532, 0.161298, 0.161767]

**Improvement of ~ 65%**

# Version 1.0.0

- Changed ranges of matched characters to be represented by `CountableClosedRange` (#2). Thank you @gravicle
