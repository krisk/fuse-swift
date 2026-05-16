#!/usr/bin/env node
// fuse-js side of the parity harness. Loads queries.json + fixtures/,
// runs each case through Fuse, and emits canonicalized JSON to stdout.
// Output shape is documented in scripts/parity/README.md.

import { readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)

// Resolve fuse-js sibling checkout. Default is ../fuse-js relative to
// the fuse-swift repo root; override with $FUSE_JS_PATH.
const fuseJsPath = process.env.FUSE_JS_PATH
  || resolve(__dirname, '../../../fuse-js/dist/fuse.mjs')
const Fuse = (await import(pathToFileURL(fuseJsPath).href)).default

const root = resolve(__dirname)
const queries = JSON.parse(readFileSync(join(root, 'queries.json'), 'utf8'))
const fixtureCache = new Map()

function loadFixture(name) {
  if (!fixtureCache.has(name)) {
    const data = JSON.parse(readFileSync(join(root, 'fixtures', `${name}.json`), 'utf8'))
    fixtureCache.set(name, data)
  }
  return fixtureCache.get(name)
}

function canonicalizeMatch(m, includeMatches) {
  if (!includeMatches) return undefined
  const sortedIndices = [...(m.indices || [])]
    .map(([s, e]) => [s, e])
    .sort((a, b) => a[0] - b[0] || a[1] - b[1])
  const out = {
    key: m.key ?? null,
    value: m.value ?? null,
    indices: sortedIndices,
    refIndex: typeof m.refIndex === 'number' ? m.refIndex : null
  }
  return out
}

function canonicalizeResult(r, options) {
  const out = { refIndex: r.refIndex }
  if (options.includeScore) {
    out.score = r.score
  }
  if (options.includeMatches) {
    out.matches = (r.matches || [])
      .map(m => canonicalizeMatch(m, true))
      .filter(Boolean)
  }
  return out
}

const output = []

for (const c of queries.cases) {
  const fixture = loadFixture(c.fixture)
  // Hoist `limit` (a search-option in fuse-js) out of the index-build
  // options object so the Fuse constructor doesn't reject it.
  const { limit, ...indexOpts } = c.options
  const fuse = new Fuse(fixture, indexOpts)
  for (const q of c.queries) {
    const searchOpts = (typeof limit === 'number') ? { limit } : undefined
    const raw = fuse.search(q, searchOpts)
    output.push({
      case: c.name,
      fixture: c.fixture,
      query: q,
      results: raw.map(r => canonicalizeResult(r, indexOpts))
    })
  }
}

process.stdout.write(JSON.stringify(output, null, 2))
process.stdout.write('\n')
