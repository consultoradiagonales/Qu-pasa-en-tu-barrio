import json
import struct
import sys
import zipfile

failures = []
checked = []
with zipfile.ZipFile(sys.argv[1]) as bundle:
    for name in bundle.namelist():
        if not name.startswith('base/lib/arm64-v8a/') or not name.endswith('.so'):
            continue
        data = bundle.read(name)
        if data[:4] != b'\x7fELF' or data[4] != 2:
            failures.append({'library': name, 'reason': 'ELF64 inválido'})
            continue
        endian = '<' if data[5] == 1 else '>'
        phoff = struct.unpack_from(endian + 'Q', data, 32)[0]
        size, count = struct.unpack_from(endian + 'HH', data, 54)
        aligns = []
        for index in range(count):
            pos = phoff + index * size
            kind = struct.unpack_from(endian + 'I', data, pos)[0]
            if kind == 1:
                align = struct.unpack_from(endian + 'Q', data, pos + 48)[0]
                aligns.append(align)
                if align < 16384:
                    failures.append({'library': name, 'alignment': align})
        checked.append({'library': name, 'alignments': aligns})
print(json.dumps({'arm64_libraries': checked, 'failures': failures}, indent=2))
sys.exit(1 if failures or not checked else 0)
