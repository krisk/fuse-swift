# fuse-swift

<!-- Badges: CI, SPM, platforms, license -->

The official Swift port of [fuse.js](https://github.com/krisk/fuse), a lightweight fuzzy-search library.

> Status: pre-release. v1 is in active development. See `.plans/active/PLAN.md` for scope.

## Install

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/krisk/fuse-swift.git", from: "2.0.0"),
]
```

## Quick start: string array search

```swift
// TODO: 30-second example lands with phase 6.
```

## Quick start: keyed search with weights

```swift
// TODO: 30-second example lands with phase 8.
```

## Options reference

| Option | Default | Notes |
|---|---|---|
| _TODO_ | | Filled in during phase 11 polish. |

_Coming in v1.1:_ `useExtendedSearch`, `useTokenSearch`, `tokenize`.

## Index persistence

`Fuse.createIndex` and `Fuse.parseIndex` round-trip the index through JSON. Details land with phase 7.

## Parity and version policy

Each fuse-js release triggers a `chore(sync): fuse-js vX.Y.Z` PR. A version-mapping table tracks which fuse-js version each fuse-swift release targets.

| fuse-swift | fuse-js | Notes |
|---|---|---|
| _TBD_ | | |

## Migrating from `krisk/fuse-swift` 1.x

The 1.x line is frozen on the `legacy` branch. See [`docs/MIGRATION.md`](docs/MIGRATION.md) for the branch story and upgrade path.

## fuse.js → fuse-swift cheat sheet

See [`docs/MIGRATION.md`](docs/MIGRATION.md).

## Contributing

See `CONTRIBUTING.md`.

## License

TBD. See `LICENSE` once added.
