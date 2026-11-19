#!/usr/bin/env python3
"""Check native PT_LOAD, GNU_RELRO and ZIP offsets for 16 KiB Android APKs."""
import argparse
import io
import struct
import sys
import zipfile
from pathlib import Path

PAGE = 0x4000
PT_LOAD = 1
PT_GNU_RELRO = 0x6474E552
PF_W = 2
ABIS = {"arm64-v8a", "x86_64"}
REQUIRED_LIBRARIES = {f"lib/{abi}/libkelpie_jni.so" for abi in ABIS}


def segments(data, name):
    if len(data) < 64 or data[:4] != b"\x7fELF" or data[4] != 2 or data[5] != 1:
        raise ValueError(f"{name}: expected a little-endian ELF64 library")
    off = struct.unpack_from("<Q", data, 32)[0]
    size, count = struct.unpack_from("<HH", data, 54)
    if size < 56 or off + size * count > len(data):
        raise ValueError(f"{name}: invalid program header table")
    result = []
    for i in range(count):
        loc = off + i * size
        kind, flags, offset, addr, _physical, _filesz, memsz, align = struct.unpack_from(
            "<IIQQQQQQ", data, loc
        )
        result.append((kind, flags, offset, addr, memsz, align))
    return result


def check(path):
    errors = []
    seen = set()
    data = Path(path).read_bytes()
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        for item in archive.infolist():
            parts = item.filename.split("/")
            if len(parts) != 3 or parts[0] != "lib" or parts[1] not in ABIS or not parts[-1].endswith(".so"):
                continue
            name = item.filename
            seen.add(name)
            phdrs = segments(archive.read(item), name)
            loads = [p for p in phdrs if p[0] == PT_LOAD]
            if not loads:
                errors.append(f"{name}: missing PT_LOAD")
            for _kind, _flags, offset, addr, _size, alignment in loads:
                if alignment < PAGE or alignment & (alignment - 1):
                    errors.append(f"{name}: invalid PT_LOAD alignment {alignment:#x}, expected >= {PAGE:#x}")
                if (addr - offset) % PAGE:
                    errors.append(f"{name}: PT_LOAD file and memory offsets disagree at 16 KiB")
            if name in REQUIRED_LIBRARIES and not any(kind == PT_GNU_RELRO for kind, *_ in phdrs):
                errors.append(f"{name}: missing PT_GNU_RELRO")
            # RELRO end may be unaligned only if there is no writable LOAD tail.
            for kind, _flags, _offset, addr, size, _align in phdrs:
                if kind != PT_GNU_RELRO or (addr + size) % PAGE == 0:
                    continue
                for _, flags, _offset, start, length, _ in loads:
                    if (flags & PF_W) and start <= addr < start + length:
                        if addr + size < start + length:
                            errors.append(f"{name}: RELRO leaves writable data on a 16 KiB page")
                        break
            if item.compress_type == zipfile.ZIP_STORED:
                offset = item.header_offset
                if data[offset:offset + 4] != b"PK\x03\x04":
                    errors.append(f"{name}: corrupt ZIP local header")
                else:
                    name_length, extra_length = struct.unpack_from("<HH", data, offset + 26)
                    data_offset = offset + 30 + name_length + extra_length
                    if data_offset % PAGE:
                        errors.append(f"{name}: ZIP library offset {data_offset:#x} not 16 KiB-aligned")
            print(f"Checked {name}: {len(loads)} PT_LOAD segments")
    missing = REQUIRED_LIBRARIES - seen
    if missing:
        errors.append("Missing JNI libraries: " + ", ".join(sorted(missing)))
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    args = parser.parse_args()
    try:
        issues = check(args.apk)
    except (OSError, ValueError, struct.error, zipfile.BadZipFile) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    for issue in issues:
        print(f"FAIL: {issue}", file=sys.stderr)
    if issues:
        return 1
    print("PASS: ELF LOAD, RELRO and ZIP alignment meet 16 KiB constraints")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
