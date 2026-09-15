#!/usr/bin/env python3
"""
Extract a specific file from asar archive correctly handling the pickle format.
"""
import struct, json, hashlib, math, sys, os

def read_asar_uint32(buf, offset):
    return struct.unpack_from('<I', buf, offset)[0]

def read_asar_header(asar_path):
    with open(asar_path, 'rb') as f:
        raw = f.read()
    
    # Read size pickle: first 8 bytes
    # Pickle: [4 bytes payload_size][4 bytes header][payload]
    size_pickle_payload = read_asar_uint32(raw, 0)  # 4
    # headerSize = 8 - 4 = 4
    # payload starts at offset 4
    header_json_size = read_asar_uint32(raw, 4)  # 0x0fd1c4
    
    # Now read header JSON pickle starting at offset 8
    # First 4 bytes: payload size of this pickle
    header_pickle_payload = read_asar_uint32(raw, 8)  # should be about header_json_size - 4
    
    # Next 4 bytes: string length (int)
    string_length = read_asar_uint32(raw, 12)
    
    # Then string data
    json_start = 16
    json_bytes = raw[json_start:json_start + string_length]
    header = json.loads(json_bytes.decode('utf-8'))
    
    # Header alignment: next 4-byte boundary after json_end
    json_end = json_start + string_length
    aligned_end = math.ceil(json_end / 4) * 4
    
    # File data starts at aligned_end
    data_start = aligned_end
    
    print(f"Header JSON size field: {header_json_size}")
    print(f"String length: {string_length}")
    print(f"JSON starts at byte: {json_start}")
    print(f"Aligned end: {aligned_end}")
    print(f"Data starts at: {data_start}")
    print(f"Total file size: {len(raw)}")
    print(f"Header algorithm: {header.get('algorithm')}")
    print(f"Header blockSize: {header.get('blockSize')}")
    
    return header, raw, data_start

def find_entry(header_dict, target_path):
    """Navigate header dict to find file entry"""
    parts = target_path.replace('\\', '/').split('/')
    current = header_dict.get('files', header_dict)
    for part in parts:
        current = current[part]
        if current is None:
            raise KeyError(f"Path part '{part}' not found")
    return current

if __name__ == '__main__':
    asar_path = r'C:\Users\<user>\AppData\Local\Programs\@opencode-aidesktop\resources\app.asar'
    target = 'out/renderer/assets/main-Cpm5Nopr.js'
    out_dir = r'C:\Users\<user>\AppData\Local\Temp\asar-patch'
    out_path = os.path.join(out_dir, 'main-Cpm5Nopr.orig.js')
    
    header, raw, data_start = read_asar_header(asar_path)
    
    entry = find_entry(header, target)
    offset = int(entry['offset'])  # offset within data section
    size = entry['size']
    file_start = data_start + offset
    
    print(f"\nTarget: {target}")
    print(f"File offset (within data): {offset}")
    print(f"File size: {size}")
    print(f"Absolute file position: {file_start}")
    
    if 'integrity' in entry:
        print(f"Integrity: {json.dumps(entry['integrity'], indent=2)}")
    
    file_data = raw[file_start:file_start + size]
    
    with open(out_path, 'wb') as f:
        f.write(file_data)
    
    print(f"\nExtracted {len(file_data)} bytes to {out_path}")
    print(f"SHA256: {hashlib.sha256(file_data).hexdigest()}")