#!/usr/bin/env python3
import struct, json, os, sys

p = r"C:\Users\<user>\AppData\Local\Programs\@opencode-aidesktop\resources\app.asar"
out_dir = r"C:\Users\<user>\AppData\Local\Temp\asar-inspect"

with open(p, 'rb') as f:
    data = f.read()

# --- Parse asar header ---
# Format: 4 bytes size_of_size (always 4), 4 bytes header_length, then header bytes
pos = 0
size_of_size = struct.unpack('<I', data[pos:pos+4])[0]
pos += 4
hdr_len = struct.unpack('<I', data[pos:pos+4])[0]
pos += 4
print(f"size_of_size: {size_of_size}, hdr_len: {hdr_len:,}")

hdr_raw = data[pos:pos+hdr_len]

# The first 8 header bytes are binary pickle metadata:
# First 4 = the header size repeated, next 4 = adjacent number
# JSON text starts at byte 8
print(f"\nFirst 64 header bytes: {hdr_raw[:64]!r}")

# Find the JSON start: look for the first '{'
json_start_byte = hdr_raw.find(b'{')
print(f"First '{{' at header byte offset: {json_start_byte}")

# First 8 bytes of header: [4-byte JSON length][4-byte JSON length (repeated)]
json_len = struct.unpack('<I', hdr_raw[0:4])[0]
print(f"JSON length from header metadata: {json_len:,}")

# JSON starts at byte 8 of header
hdr_raw_json = hdr_raw[8:8+json_len]
print(f"JSON string size: {len(hdr_raw_json):,} bytes")

# Try stripping trailing whitespace/trim
hdr_raw_json = hdr_raw_json.rstrip(b'\x00').rstrip()
print(f"After stripping: {len(hdr_raw_json):,} bytes")

hdr = json.loads(hdr_raw_json)
print(f"JSON parsed OK")

print(f"\n=== Header Top Keys ===")
print(f"Keys: {list(hdr.keys())}")
print(f"Has 'integrity': {'integrity' in hdr}")
print(f"Has 'files': {'files' in hdr}")

files = hdr.get('files', {})
if isinstance(files, dict):
    print(f"Files top-level keys: {len(files)}")

# Deep search for integrity
def deep_search(obj, depth=0, max_depth=6):
    results = {'integrity': [], 'unpacked': []}
    if depth > max_depth:
        return results
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k == 'integrity' and isinstance(v, (str, dict)):
                results['integrity'].append(str(v)[:120])
            if k == 'unpacked' and v:
                results['unpacked'].append(f"{'  '*depth}{k}={v}")
            if isinstance(v, (dict, list)):
                sub = deep_search(v, depth+1, max_depth)
                results['integrity'].extend(sub['integrity'])
                results['unpacked'].extend(sub['unpacked'])
    elif isinstance(obj, list):
        for item in obj:
            sub = deep_search(item, depth+1, max_depth)
            results['integrity'].extend(sub['integrity'])
            results['unpacked'].extend(sub['unpacked'])
    return results

sr = deep_search(files)
print(f"\n=== Integrity Check ===")
print(f"Integrity field count: {len(sr['integrity'])}")
for i, ih in enumerate(sr['integrity'][:10]):
    print(f"  integrity[{i}]: {ih}")

print(f"\nUnpacked count: {len(sr['unpacked'])}")
for u in sr['unpacked'][:10]:
    print(f"  {u}")

# Find JS files of interest
def find_files(obj, pattern, path=""):
    found = []
    if isinstance(obj, dict):
        for k, v in obj.items():
            cur = f"{path}/{k}" if path else k
            if pattern in cur and isinstance(v, dict) and 'offset' in v:
                found.append((cur, v))
            if isinstance(v, (dict, list)):
                found.extend(find_files(v, pattern, cur))
    elif isinstance(obj, list):
        for item in obj:
            found.extend(find_files(item, pattern, path))
    return found

# Find renderer bundle
renderer_js = find_files(files, "main-Cpm5Nopr.js")
print(f"\n=== Renderer Bundle Search ===")
if renderer_js:
    for name, info in renderer_js:
        print(f"  File: {name}")
        print(f"  offset: {info['offset']}")
        print(f"  size: {info['size']}")
        if 'integrity' in info:
            print(f"  integrity: {str(info['integrity'])[:80]}")
else:
    print("  Not found by exact name. Searching for renderer JS files...")
    all_js = find_files(files, ".js")
    for name, info in all_js[:30]:
        print(f"  {name}  offset={info.get('offset')}  size={info.get('size')}")

# Find source maps
maps = find_files(files, ".map")
print(f"\n=== Source Maps ===")
for name, info in maps:
    print(f"  {name}  offset={info.get('offset')}  size={info.get('size')}")

# Dump header to file
os.makedirs(out_dir, exist_ok=True)
hdr_path = os.path.join(out_dir, "header.json")
with open(hdr_path, "w", encoding="utf-8") as fout:
    json.dump(hdr, fout, indent=2)
print(f"\nHeader saved to {hdr_path}")