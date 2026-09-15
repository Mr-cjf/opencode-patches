# OpenCode Desktop 性能补丁集（opencode-patches）

A curated collection of performance patches and troubleshooting documentation for [anomalyco/opencode](https://github.com/anomalyco/opencode) Desktop (v1.17.20). Each patch is verified, benchmarked, and documented with root-cause analysis.

> **Disclaimer**: This is an unofficial, community-maintained project. Patches target OpenCode Desktop v1.17.20 specifically. Use at your own risk. Always back up original files and verify integrity after patching.

## Directory Structure

```
opencode-patches/
├── README.md                       # This file
├── bundle-patch/                   # Patches applied to the packaged asar bundle
│   ├── README.md
│   ├── patch.sh                    # One-click asar patching script
│   └── source-patch/               # Mirror of source-level patches (for inspection)
├── source-patch/                   # Source-level patches (git-friendly, human-readable)
│   ├── README.md
│   ├── v1.17.20-uniqueSummaryDiffs/
│   │   └── uniqueSummaryDiffs.diff
│   └── v1.17.20-database-time-fields/
│       └── time-fields-compat.diff (SQL script)
└── docs/
    ├── 01-root-cause.md            # Root-cause analysis of the unresponsive renderer
    ├── 02-official-fix.md          # Study of the official fix in v1.18.30
    ├── 03-benchmark.md             # Benchmark data and correctness tests
    ├── 04-environment-notes.md     # Why v1.17.20 and how to freeze updates safely
    └── 05-database-time-field-fix.md # SQL migration for time field after downgrade
```

## Quick Start

1. **Bundle patch** (recommended): Run `bundle-patch/patch.sh` to apply the uniqueSummaryDiffs fix directly to the asar bundle.
2. **Source patch**: Inspect `source-patch/` for the raw diff against the v1.17.20 source tree.
3. **Database fix**: If you downgraded from v1.18.x and see `Cannot read properties of undefined (reading 'time')`, apply the SQL script in `source-patch/v1.17.20-database-time-fields/`.
4. **Environment**: See `docs/04-environment-notes.md` before patching — you may need to freeze auto-updates.

## English Summary

This repository documents and patches a severe performance regression in OpenCode Desktop v1.17.20: opening a session with thousands of file diffs causes a 1--15 second renderer freeze (`renderer unresponsive`). Root cause is an `O(d²)` deduplication loop in `constructMessageRows` exacerbated by SolidJS Store Proxy overhead (700x slower than plain arrays with proxy wrappers). The fix replaces the inner `Array.some` linear scan with a `Set`-based lookup, reducing `d=6,400` proxy-wrapped dedup from 714ms to 0.98ms (726x speedup). Also includes a SQL migration to restore missing `time` fields on `part` rows after downgrading from v1.18.x.