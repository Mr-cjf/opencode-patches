#!/usr/bin/env python3
"""
Apply the uniqueDiffs performance patch to a main-Cpm5Nopr.js bundle.

Replaces the O(n^2) reduceRight + Array.some pattern with O(n) Set-based dedup.

Old:
    const diffs2 = (userMessage.summary?.diffs ?? []).reduceRight((result, diff2) => {
      if (!isSummaryDiff(diff2)) return result;
      if (result.some((item) => item.file === diff2.file)) return result;
      result.push(diff2);
      return result;
    }, []).reverse();

New:
    const uniqueDiffs = new Set();
    const diffs2 = (userMessage.summary?.diffs ?? []).reduceRight((result, diff2) => {
      if (!isSummaryDiff(diff2) || uniqueDiffs.has(diff2.file)) return result;
      uniqueDiffs.add(diff2.file);
      result.push(diff2);
      return result;
    }, []).reverse();

Usage:
    python patch_bundle.py <input.js> [output.js]
    If output.js is omitted, input.js is patched in place.
"""

import sys, os, hashlib

OLD = (
    '    const diffs2 = (userMessage.summary?.diffs ?? []).reduceRight((result, diff2) => {\n'
    '      if (!isSummaryDiff(diff2)) return result;\n'
    '      if (result.some((item) => item.file === diff2.file)) return result;\n'
    '      result.push(diff2);\n'
    '      return result;\n'
    '    }, []).reverse();'
)

NEW = (
    '    const uniqueDiffs = new Set();\n'
    '    const diffs2 = (userMessage.summary?.diffs ?? []).reduceRight((result, diff2) => {\n'
    '      if (!isSummaryDiff(diff2) || uniqueDiffs.has(diff2.file)) return result;\n'
    '      uniqueDiffs.add(diff2.file);\n'
    '      result.push(diff2);\n'
    '      return result;\n'
    '    }, []).reverse();'
)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) > 2 else input_path

    if not os.path.isfile(input_path):
        print(f"Error: input file not found: {input_path}")
        sys.exit(1)

    with open(input_path, 'r', encoding='utf-8') as f:
        content = f.read()

    count = content.count(OLD)
    if count == 0:
        print("Error: old block not found in input file. "
              "The file may already be patched or uses a different version.")
        sys.exit(1)
    if count > 1:
        print(f"Error: old block found {count} times (expected exactly 1). "
              "Cannot safely apply patch.")
        sys.exit(1)

    content = content.replace(OLD, NEW, 1)

    os.makedirs(os.path.dirname(os.path.abspath(output_path)) or '.', exist_ok=True)
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(content)

    input_sha = hashlib.sha256(open(input_path, 'rb').read()).hexdigest()
    output_sha = hashlib.sha256(open(output_path, 'rb').read()).hexdigest()

    print(f"Patch applied successfully.")
    print(f"  Input:  {input_path}")
    print(f"  Output: {output_path}")
    print(f"  SHA256 (input):  {input_sha}")
    print(f"  SHA256 (output): {output_sha}")

    # Compare with known patched hash for verification
    EXPECTED = "975bd893224933c82486aeded7ee70a0fafc3081da483d08f3f01f658bb432ec"
    if output_sha == EXPECTED:
        print(f"  *** SHA256 matches expected patched file ***")
    else:
        print(f"  Expected patched SHA256: {EXPECTED}")
        print(f"  NOTE: SHA256 differs (may be different bundle version or content)")


if __name__ == '__main__':
    main()