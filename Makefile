# fuse-swift release-gate harness. The per-PR matrix lives in CI and runs
# `swift build` / `swift test` directly; these targets are convenience
# wrappers plus the cross-runtime parity check that gates `make release`.

.PHONY: build test strict-test parity cli release clean help

# Default target prints the menu rather than silently doing the wrong thing.
help:
	@echo "fuse-swift make targets:"
	@echo "  build         swift build (Swift 5.9 default)"
	@echo "  test          swift test (no concurrency flags)"
	@echo "  strict-test   swift test with -strict-concurrency=complete -warnings-as-errors"
	@echo "  parity        cross-runtime parity check vs ../fuse-js (needs node + sibling checkout)"
	@echo "  cli           build + run the Examples/CLI demo"
	@echo "  release       full release gate: strict-test + parity"
	@echo "  clean         remove .build / Examples/CLI/.build / SwiftOracle/.build"
	@echo ""
	@echo "Environment:"
	@echo "  FUSE_JS_PATH  override path to ../fuse-js/dist/fuse.mjs (parity target only)"

build:
	swift build

test:
	swift test

strict-test:
	swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors

parity:
	@scripts/parity-check.sh

cli:
	@cd Examples/CLI && swift run -q FuseCLI

# Release gate: strict-concurrency test pass + cross-runtime parity match.
# Run this before tagging v2.0.0-rc.1 / v2.0.0. Output of the parity check
# is checked in alongside the tag.
release: strict-test parity
	@echo ""
	@echo "✓ release gate passed"

clean:
	rm -rf .build Examples/CLI/.build scripts/parity/SwiftOracle/.build
