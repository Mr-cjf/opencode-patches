#!/usr/bin/env python3
"""
Repack app.asar with a patched file, properly handling offsets and integrity.

Usage:
    python repack_asar.py <original.asar> <patched_file> <output.asar> [--target TARGET_PATH]

    --target TARGET_PATH    Path inside asar to replace (default: out/renderer/assets/main-Cpm5Nopr.js)
    --verify-only           Instead of repacking, verify two asar files are equivalent
                            (all files except target must be byte-identical).

    python repack_asar.py --verify-only <asar_a> <asar_b> [--target TARGET_PATH]

Algorithm:
    1. Parse original asar header (JSON inside pickle format)
    2. Find target entry, update its size and recalculate integrity
    3. Adjust offsets for all entries after the target (shift by size_diff)
    4. Serialize new header JSON (same format as original)
    5. Build new asar: [size_pickle][header_pickle][data_section]
       - Data section = [data_before_target][patched_data][data_after_target shifted]
    6. In --verify mode: compare every file between two asar archives
"""
import struct, json, math, hashlib, os, sys, argparse

DEFAULT_TARGET = 'out/renderer/assets/main-Cpm5Nopr.js'


def parse_asar(raw):
    """Parse asar bytes, return (header_dict, json_str, header_json_size, data_section_start)."""
    # Format (from electron/asar disk.js):
    #   offset 0: 8-byte size pickle = [4:payload_size=4][4:header_buf_len]
    #   header_buf_len = raw.readUInt32LE(4)  -> header_json_size
    #   offset 8: header pickle = [4:payload_size][4:string_length][string_data][padding]
    #   Then data section follows at aligned offset
    header_json_size = struct.unpack_from('<I', raw, 4)[0]
    header_data_start = 8

    # Parse header pickle
    string_length = struct.unpack_from('<I', raw, header_data_start + 4)[0]
    json_start = header_data_start + 8  # offset 16
    json_bytes = raw[json_start:json_start + string_length]
    json_str = json_bytes.decode('utf-8')
    header = json.loads(json_str)

    # Header end aligned to 4 bytes; also compute from header_json_size field
    expected_data_start = header_data_start + header_json_size
    data_start = math.ceil(expected_data_start / 4) * 4

    return header, json_str, header_json_size, data_start


def collect_entries(header_dict, prefix=''):
    """Flatten all file entries from header dict with their paths."""
    entries = []
    if isinstance(header_dict, dict):
        if 'size' in header_dict and ('offset' in header_dict or 'unpacked' in header_dict):
            entries.append((prefix, header_dict))
            return entries
        if 'link' in header_dict:
            entries.append((prefix, header_dict))
            return entries
        if 'files' in header_dict:
            for key, val in header_dict['files'].items():
                sub = f"{prefix}/{key}" if prefix else key
                entries.extend(collect_entries(val, sub))
        else:
            for key, val in header_dict.items():
                if key != 'files':
                    sub = f"{prefix}/{key}" if prefix else key
                    entries.extend(collect_entries(val, sub))
    return entries


def find_entry(header, path):
    """Navigate header dict to find entry by path."""
    parts = path.split('/')
    cur = header.get('files', header)
    for part in parts:
        if 'files' in cur:
            cur = cur['files']
        cur = cur[part]
    return cur


def calc_integrity(data, algorithm='SHA256', block_size=4194304):
    """Calculate integrity metadata for file data."""
    blocks = []
    for i in range(0, len(data), block_size):
        chunk = data[i:i + block_size]
        h = hashlib.sha256(chunk).hexdigest()
        blocks.append(h)
    full_hash = hashlib.sha256(data).hexdigest()
    return {
        'algorithm': algorithm,
        'hash': full_hash,
        'blockSize': block_size,
        'blocks': blocks
    }


def make_header_pickle(json_str):
    """Create a pickle containing the header JSON string.
    Pickle format: [4:payload_size][4:string_length][string_data][zero_pad_to_4]"""
    str_bytes = json_str.encode('utf-8')
    str_len = len(str_bytes)
    aligned_str_len = math.ceil(str_len / 4) * 4
    payload_size = 4 + aligned_str_len

    buf = bytearray(4 + payload_size)
    struct.pack_into('<I', buf, 0, payload_size)
    struct.pack_into('<I', buf, 4, str_len)
    struct.pack_into(f'{str_len}s', buf, 8, str_bytes)
    return bytes(buf)


def make_size_pickle(header_buf_len):
    """Create the outer size pickle: [4:payload_size=4][4:header_buf_length]"""
    buf = bytearray(8)
    struct.pack_into('<I', buf, 0, 4)
    struct.pack_into('<I', buf, 4, header_buf_len)
    return bytes(buf)


def repack(asar_src, patched_file, output_path, target_path=DEFAULT_TARGET):
    """Repack asar with patched file. Returns True on success."""
    # Read original asar
    print(f"[1] Reading original asar: {asar_src}")
    with open(asar_src, 'rb') as f:
        raw = f.read()
    total_orig_size = len(raw)

    header, json_str, header_json_size, data_start = parse_asar(raw)
    print(f"  Header JSON: {len(json_str)} bytes, data section at offset {data_start}")

    # Read patched file
    print(f"[2] Reading patched file: {patched_file}")
    with open(patched_file, 'rb') as f:
        new_data = f.read()
    print(f"  Patched file size: {len(new_data)} bytes")

    # Find target entry
    print(f"[3] Locating target: {target_path}")
    target_entry = find_entry(header, target_path)
    old_offset = int(target_entry['offset'])
    old_size = target_entry['size']
    print(f"  Old offset: {old_offset}, old size: {old_size}")

    size_diff = len(new_data) - old_size
    print(f"  Size change: {size_diff:+d} bytes")

    # Collect all entries with offsets
    all_entries = collect_entries(header)
    offset_entries = [(p, e) for p, e in all_entries if 'offset' in e]

    # Update target entry
    target_entry['size'] = len(new_data)
    new_integrity = calc_integrity(new_data)
    target_entry['integrity'] = new_integrity
    print(f"[4] Updated target entry: size={len(new_data)}, hash={new_integrity['hash']}")

    # Adjust offsets for entries after the target
    shifted_count = 0
    for path, entry in offset_entries:
        cur_off = int(entry['offset'])
        if cur_off > old_offset:
            entry['offset'] = str(cur_off + size_diff)
            shifted_count += 1
    print(f"[5] Shifted {shifted_count} entries by {size_diff:+d} bytes")

    # Serialize new header
    print("[6] Serializing new header...")
    new_json_str = json.dumps(header, separators=(',', ':'))
    print(f"  Original header JSON: {len(json_str)} bytes")
    print(f"  New header JSON: {len(new_json_str)} bytes")

    # Build pickle buffers
    header_buf = make_header_pickle(new_json_str)
    size_buf = make_size_pickle(len(header_buf))

    print(f"[7] Header pickle: {len(header_buf)} bytes, Size pickle: {len(size_buf)} bytes")

    # Build new data section
    print("[8] Building new data section...")
    region_before = raw[data_start:data_start + old_offset]
    region_after_start = data_start + old_offset + old_size
    region_after = raw[region_after_start:] if region_after_start < len(raw) else b''

    print(f"  Region before target: {len(region_before)} bytes")
    print(f"  Region after target: {len(region_after)} bytes")

    new_data_section = region_before + new_data + region_after

    # Write output
    print(f"[9] Writing patched asar to {output_path}")
    os.makedirs(os.path.dirname(os.path.abspath(output_path)) or '.', exist_ok=True)
    with open(output_path, 'wb') as f:
        f.write(size_buf)
        f.write(header_buf)
        f.write(new_data_section)

    output_size = len(size_buf) + len(header_buf) + len(new_data_section)
    print(f"  Written {output_size} bytes")
    print(f"  Original: {total_orig_size} bytes")
    print(f"  Difference: {output_size - total_orig_size:+d} bytes")

    return True


def verify(asar_a_path, asar_b_path, target_path=DEFAULT_TARGET):
    """Compare two asar archives. All files except target must be byte-identical."""
    for apath, label in [(asar_a_path, 'A'), (asar_b_path, 'B')]:
        if not os.path.isfile(apath):
            print(f"Error: {label} file not found: {apath}")
            return False

    print(f"Verifying asar files:")
    print(f"  A: {asar_a_path}")
    print(f"  B: {asar_b_path}")
    print(f"  Target (skipped from comparison): {target_path}")

    with open(asar_a_path, 'rb') as f:
        raw_a = f.read()
    with open(asar_b_path, 'rb') as f:
        raw_b = f.read()

    header_a, _, _, ds_a = parse_asar(raw_a)
    header_b, _, _, ds_b = parse_asar(raw_b)

    entries_a = {p: e for p, e in collect_entries(header_a)}
    entries_b = {p: e for p, e in collect_entries(header_b)}

    passed = 0
    failed = 0
    skipped = 0

    for path, entry_a in entries_a.items():
        if path not in entries_b:
            print(f"  MISSING in B: {path}")
            failed += 1
            continue

        entry_b = entries_b[path]

        # Skip unpacked files
        if entry_a.get('unpacked', False):
            skipped += 1
            continue

        if target_path and path == target_path:
            skipped += 1
            continue

        if 'offset' in entry_a:
            off_a = int(entry_a['offset'])
            sz_a = entry_a['size']
            off_b = int(entry_b['offset'])
            sz_b = entry_b['size']

            data_a = raw_a[ds_a + off_a:ds_a + off_a + sz_a]
            data_b = raw_b[ds_b + off_b:ds_b + off_b + sz_b]

            if data_a != data_b:
                print(f"  FAIL (content mismatch): {path}")
                print(f"    A size={sz_a}, B size={sz_b}, A off={off_a}, B off={off_b}")
                print(f"    A SHA256: {hashlib.sha256(data_a).hexdigest()}")
                print(f"    B SHA256: {hashlib.sha256(data_b).hexdigest()}")
                failed += 1
            else:
                passed += 1
        elif 'link' in entry_a:
            if entry_a.get('link') != entry_b.get('link'):
                print(f"  FAIL (link mismatch): {path}")
                failed += 1
            else:
                passed += 1

    # Check for extra entries in B
    for path in entries_b:
        if path not in entries_a:
            print(f"  EXTRA in B: {path}")
            failed += 1

    print(f"\n=== Verification Results ===")
    print(f"  Total entries in A: {len(entries_a)}")
    print(f"  Total entries in B: {len(entries_b)}")
    print(f"  Passed: {passed}")
    print(f"  Skipped: {skipped}")
    print(f"  Failed: {failed}")

    if failed == 0:
        print(f"  ALL VERIFICATIONS PASSED!")
        return True
    else:
        print(f"  VERIFICATION FAILED! {failed} failures.")
        return False


def main():
    parser = argparse.ArgumentParser(
        description='Repack or verify asar archives with a patched bundle file.')
    parser.add_argument('--target', default=DEFAULT_TARGET,
                        help=f'Path inside asar to replace (default: {DEFAULT_TARGET})')
    parser.add_argument('--verify-only', action='store_true',
                        help='Verify two asar archives instead of repacking')

    args, remaining = parser.parse_known_args()

    if args.verify_only:
        if len(remaining) < 2:
            print("Usage: repack_asar.py --verify-only <asar_a> <asar_b> [--target TARGET]")
            sys.exit(1)
        success = verify(remaining[0], remaining[1], args.target)
        sys.exit(0 if success else 1)

    if len(remaining) < 3:
        print("Usage: repack_asar.py <original.asar> <patched_file> <output.asar> [--target TARGET]")
        sys.exit(1)

    asar_src = remaining[0]
    patched_file = remaining[1]
    output_path = remaining[2]

    repack(asar_src, patched_file, output_path, args.target)

    # Auto-verify after repack
    print(f"\n{'=' * 60}")
    print("Auto-verifying repacked asar...")
    print(f"{'=' * 60}")
    success = verify(asar_src, output_path, args.target)

    if success:
        print(f"\n  Repack complete and verified: {output_path}")
    else:
        print(f"\n  REPACK VERIFICATION FAILED!")
        sys.exit(1)


if __name__ == '__main__':
    main()