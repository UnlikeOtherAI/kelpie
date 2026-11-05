#!/usr/bin/env python3
"""Extract only the fixed, retained synthetic CI AVC fixture for mux comparison."""
import hashlib
import json
import pathlib
import struct
import subprocess
import sys

if len(sys.argv) != 3:
    raise SystemExit("Provide exact retained MP4 and fresh private output directory")
source = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
data = source.read_bytes()
expected = "df7a97cf8a9633f74a5906f9c63ec74b14549bd7abf1c30496a052fc2df24e4f"
if hashlib.sha256(data).hexdigest() != expected:
    raise SystemExit("Unexpected fixture hash")
if len(data) != 38756:
    raise SystemExit("Unexpected fixture length")
atom = data.find(b"avcC")
if atom < 4:
    raise SystemExit("Missing AVC configuration")
size = struct.unpack_from(">I", data, atom - 4)[0]
codec = data[atom + 4:atom - 4 + size]
if len(codec) < 7 or codec[0] != 1:
    raise SystemExit("Invalid AVC configuration")
mdat = []
pos = 0
while pos + 8 <= len(data):
    length, name = struct.unpack_from(">I4s", data, pos)
    if length < 8 or pos + length > len(data):
        raise SystemExit("Invalid MP4 box")
    if name == b"mdat":
        mdat.append(data[pos + 8:pos + length])
    pos += length
if pos != len(data) or len(mdat) != 14 or len(mdat[-1]) != 4005:
    raise SystemExit("Unexpected fixture fragments")
packets = mdat[:-1] + [mdat[-1][:2476], mdat[-1][2476:]]
for packet in packets:
    offset = 0
    found_vcl = False
    while offset < len(packet):
        if offset + 4 > len(packet):
            raise SystemExit("Invalid AVC length")
        length = struct.unpack_from(">I", packet, offset)[0]
        offset += 4
        if not length or offset + length > len(packet):
            raise SystemExit("Invalid AVC packet")
        found_vcl |= 1 <= (packet[offset] & 31) <= 5
        offset += length
    if not found_vcl:
        raise SystemExit("Missing AVC picture")
probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_packets",
                        "-show_entries", "packet=pts_time,duration_time", "-of", "json", str(source)],
                       check=True, capture_output=True, timeout=30)
metadata = json.loads(probe.stdout)["packets"]
if len(metadata) != len(packets):
    raise SystemExit("Unexpected demux packet count")
out.mkdir(mode=0o700)
(out / "codec.bin").write_bytes(codec)
manifest = {"sourceSHA256": expected, "packets": []}
for index, (packet, info) in enumerate(zip(packets, metadata)):
    (out / f"packet-{index}.bin").write_bytes(packet)
    manifest["packets"].append({"ptsNs": round(float(info["pts_time"]) * 1_000_000_000),
                                "durationNs": round(float(info["duration_time"]) * 1_000_000_000),
                                "sha256": hashlib.sha256(packet).hexdigest()})
(out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
