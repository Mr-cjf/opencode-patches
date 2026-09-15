# Source-Level Patch: `constructMessageRows` Diff Deduplication

## What

Replaces O(d2) `reduceRight` + `Array.some` diff-file deduplication in
`constructMessageRows` with O(d) `Set`-based deduplication via a
`uniqueSummaryDiffs` helper.

## Target

- **Source**: `packages/app/src/pages/session/timeline/rows.ts`
- **Bundled equivalent**: `out/renderer/assets/main-Cpm5Nopr.js` -- function
  `constructMessageRows` (same `reduceRight` + `Array.some` pattern)

## Origin

- The performance issue: when a conversation accumulates many files over
  time, `constructMessageRows` scans the entire diff array for every
  candidate diff (`result.some((item) => item.file === diff.file)`),
  yielding O(dock2) agent-side reads.
- The fix was originally applied as a hot-patch on the bundled JS output
  (`main-Cpm5Nopr.js`) for OpenCode 1.17.20.
- OpenCode upstream adopted the same approach in 1.18.30 as
  `uniqueSummaryDiffs`, contributing to the `Timeline` namespace.

## Relationship to upstream 1.18.30

The applied logic is directly aligned with the upstream fix in 1.18.30.
The only difference is naming/placement context: the upstream version is
also called `uniqueSummaryDiffs` and operates identically (Set-based
deduplication during `reduceRight` traversal).

## Why source-level patch

- Makes the fix auditable in TypeScript rather than raw minified JS.
- Can be applied to the source tree before building, avoiding
  post-build string patching.
- Documents the exact change for version tracking / rebasing.

## Files

| File | Size | Description |
|------|------|-------------|
| `rows.ts.orig` | 9133 B | Original unmodified source |
| `rows.ts.patched` | 9298 B | Source with Set-based deduplication |
| `rows.patch` | 1469 B | Unified diff (git-apply compatible) |
| `README.md` | -- | This file |

## Applying

```bash
cd <opencode-repo>/packages/app/src/pages/session/timeline/
patch -p5 < /path/to/source-patch/rows.patch
```

Or from repo root:

```bash
patch -p1 < /path/to/source-patch/rows.patch
```