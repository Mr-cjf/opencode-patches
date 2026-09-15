#!/usr/bin/env python3
"""
Extract a specific file from asar archive.
Usage: python extract_asar.py <asar_path> <target_path_in_asar> <output_path>
Also prints the entry's JSON metadata.
"""
import struct, json, hashlib, sys, os

def extract_asar(asar_path, target_path, output_path):
    with open(asar_path, 'rb') as f:
        # 4 bytes: pickled header size? Actually: 4 bytes size of header size? Let's read spec.
        # Node asar format:
        #   uint32   - header_size (4 bytes little endian)
        #   header JSON (header_size bytes, padded to 4-byte alignment)
        # Then file data follows.
        raw = f.read(4)
        header_size = struct.unpack('<I', raw)[0]
        print(f"Header size field: {header_size} bytes")
        
        # Read header JSON
        header_json = f.read(header_size)
        # Align to 4 bytes
        import math
        aligned = math.ceil(header_size / 4) * 4
        pad = aligned - header_size
        if pad > 0:
            f.read(pad)
        
        header = json.loads(header_json)
        print(f"Header keys: {list(header.keys())}")
        print(f"algorithm (integrity): {header.get('algorithm')}")
        print(f"Files (top level): {list(header.get('files', {}).keys())}")
        
        # Navigate to target file entry
        # target_path = "out/renderer/assets/main-Cpm5Nopr.js"
        parts = target_path.replace('\\', '/').split('/')
        entry = header['files']
        for part in parts:
            entry = entry[part]
        
        print(f"\nTarget entry: {json.dumps(entry, indent=2)}")
        
        offset = entry['offset']
        size = entry['size']
        integrity = entry.get('integrity', None)
        print(f"Offset: {offset}, Size: {size}")
        if integrity:
            print(f"Integrity algorithm: {integrity.get('algorithm')}")
            print(f"Integrity blockSize: {integrity.get('blockSize')}")
            print(f"Integrity blocks (first 2): {integrity.get('blocks', [])[:2]}")
        
        # Read file data
        f.seek(offset)
        data = f.read(size)
        
        with open(output_path, 'wb') as out:
            out.write(data)
        
        print(f"\nExtracted {size} bytes to {output_path}")
        return header, entry, data

if __name__ == '__main__':
    asar = r'C:\Users\<user>\AppData\Local\Programs\@opencode-aidesktop\resources\app.asar'
    target = 'out/renderer/assets/main-Cpm5Nopr.js'
    out = r'C:\Users\<user>\AppData\Local\Temp\asar-patch\main-Cpm5Nopr.orig.js'
    extract_asar(asar, target, out)