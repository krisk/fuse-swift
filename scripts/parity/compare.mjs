#!/usr/bin/env node
// Compare two canonicalized oracle outputs. Reads two JSON files passed
// on the command line, asserts structural equality with score tolerance,
// and exits non-zero on mismatch with a diff to stdout.

import { readFileSync } from 'node:fs'

const SCORE_REL_TOLERANCE = 1e-9
const SCORE_ABS_TOLERANCE_AT_ZERO = 1e-12

const [, , jsPath, swiftPath] = process.argv
if (!jsPath || !swiftPath) {
  console.error('usage: compare.mjs <js-oracle.json> <swift-oracle.json>')
  process.exit(2)
}

const js = JSON.parse(readFileSync(jsPath, 'utf8'))
const sw = JSON.parse(readFileSync(swiftPath, 'utf8'))

const issues = []

function scoresClose(a, b) {
  if (a === b) return true
  if (typeof a !== 'number' || typeof b !== 'number') return false
  if (Math.abs(a) < SCORE_ABS_TOLERANCE_AT_ZERO && Math.abs(b) < SCORE_ABS_TOLERANCE_AT_ZERO) {
    return true
  }
  const denom = Math.max(Math.abs(a), Math.abs(b), Number.MIN_VALUE)
  return Math.abs(a - b) / denom < SCORE_REL_TOLERANCE
}

function indicesEqual(a, b) {
  if (a === b) return true
  if (!Array.isArray(a) || !Array.isArray(b)) return false
  if (a.length !== b.length) return false
  for (let i = 0; i < a.length; i++) {
    if (a[i][0] !== b[i][0] || a[i][1] !== b[i][1]) return false
  }
  return true
}

function keysEqual(a, b) {
  // KeySource canonical form: string or array (or null). Compare structurally.
  if (a === b) return true
  if (a == null || b == null) return a == null && b == null
  if (Array.isArray(a) && Array.isArray(b)) {
    return a.length === b.length && a.every((v, i) => v === b[i])
  }
  return false
}

function compareMatch(jsM, swM, rowTag, ri, mi) {
  const jsHasMatches = jsM != null
  const swHasMatches = swM != null
  if (jsHasMatches !== swHasMatches) {
    issues.push(`${rowTag} result[${ri}] match[${mi}] presence: js=${jsHasMatches} swift=${swHasMatches}`)
    return
  }
  if (!keysEqual(jsM.key ?? null, swM.key ?? null)) {
    issues.push(`${rowTag} result[${ri}] match[${mi}] key: js=${JSON.stringify(jsM.key)} swift=${JSON.stringify(swM.key)}`)
  }
  if ((jsM.value ?? null) !== (swM.value ?? null)) {
    issues.push(`${rowTag} result[${ri}] match[${mi}] value: js=${JSON.stringify(jsM.value)} swift=${JSON.stringify(swM.value)}`)
  }
  if (!indicesEqual(jsM.indices ?? [], swM.indices ?? [])) {
    issues.push(`${rowTag} result[${ri}] match[${mi}] indices: js=${JSON.stringify(jsM.indices)} swift=${JSON.stringify(swM.indices)}`)
  }
  if ((jsM.refIndex ?? null) !== (swM.refIndex ?? null)) {
    issues.push(`${rowTag} result[${ri}] match[${mi}] refIndex: js=${jsM.refIndex} swift=${swM.refIndex}`)
  }
}

function compareResult(jsR, swR, rowTag, ri) {
  if (jsR.refIndex !== swR.refIndex) {
    issues.push(`${rowTag} result[${ri}] refIndex: js=${jsR.refIndex} swift=${swR.refIndex}`)
    return  // ordering already diverged; further per-field diff is noisy
  }
  if ('score' in jsR || 'score' in swR) {
    if (!scoresClose(jsR.score, swR.score)) {
      issues.push(`${rowTag} result[${ri}] score: js=${jsR.score} swift=${swR.score}`)
    }
  }
  const jsMatches = jsR.matches
  const swMatches = swR.matches
  if ((jsMatches == null) !== (swMatches == null)) {
    issues.push(`${rowTag} result[${ri}] matches presence: js=${jsMatches != null} swift=${swMatches != null}`)
    return
  }
  if (jsMatches == null) return
  if (jsMatches.length !== swMatches.length) {
    issues.push(`${rowTag} result[${ri}] matches length: js=${jsMatches.length} swift=${swMatches.length}`)
    return
  }
  for (let i = 0; i < jsMatches.length; i++) {
    compareMatch(jsMatches[i], swMatches[i], rowTag, ri, i)
  }
}

if (js.length !== sw.length) {
  issues.push(`row count: js=${js.length} swift=${sw.length}`)
} else {
  for (let i = 0; i < js.length; i++) {
    const jsRow = js[i]
    const swRow = sw[i]
    const rowTag = `[${jsRow.case} q="${jsRow.query}"]`
    if (jsRow.case !== swRow.case || jsRow.query !== swRow.query) {
      issues.push(`${rowTag} row identity drift: swift=[${swRow.case} q="${swRow.query}"]`)
      continue
    }
    if (jsRow.results.length !== swRow.results.length) {
      issues.push(`${rowTag} result count: js=${jsRow.results.length} swift=${swRow.results.length}`)
      continue
    }
    for (let r = 0; r < jsRow.results.length; r++) {
      compareResult(jsRow.results[r], swRow.results[r], rowTag, r)
    }
  }
}

if (issues.length) {
  console.error(`✘ parity check failed (${issues.length} ${issues.length === 1 ? 'issue' : 'issues'})`)
  for (const i of issues) console.error('  ' + i)
  process.exit(1)
}
const totalRows = js.length
const totalResults = js.reduce((n, r) => n + r.results.length, 0)
console.log(`✓ parity OK — ${totalRows} rows, ${totalResults} result records`)
