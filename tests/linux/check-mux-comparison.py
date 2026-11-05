#!/usr/bin/env python3
"""Check packet and decoded-frame counts and timestamps for the mux control."""
import json
import pathlib
import subprocess
import sys

mode, directory = sys.argv[1:]
root = pathlib.Path(directory)
file = root / (mode + ".mp4")
probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-count_packets",
                        "-count_frames", "-show_frames", "-show_entries",
                        "stream=nb_read_frames,nb_read_packets:frame=best_effort_timestamp_time",
                        "-of", "json", str(file)], check=True, capture_output=True, timeout=30)
(root / (mode + "-ffprobe.json")).write_bytes(probe.stdout)
(root / (mode + "-ffprobe.log")).write_bytes(probe.stderr)
value = json.loads(probe.stdout)
stream = value["streams"][0]
frames = int(stream["nb_read_frames"])
packets = int(stream["nb_read_packets"])
pts = [float(frame["best_effort_timestamp_time"]) for frame in value["frames"]]
if packets != 15 or len(pts) != frames:
    raise SystemExit("Unexpected packet or decoded count")
if mode == "fragmented":
    if frames != 14:
        raise SystemExit("Control did not reproduce the 15-packet/14-frame failure")
elif mode == "faststart":
    expected = json.loads((root / "input/manifest.json").read_text())["packets"]
    if frames != 15 or any(abs(t - item["ptsNs"] / 1e9) > 0.001 for t, item in zip(pts, expected)):
        raise SystemExit("Candidate did not preserve all 15 source PTS")
    if (root / "input/faststart-temp").exists():
        raise SystemExit("Faststart scratch was not removed")
    subprocess.run(["ffmpeg", "-v", "error", "-xerror", "-threads", "1", "-i", str(file),
                    "-f", "null", "-"], check=True, timeout=30)
else:
    raise SystemExit("Unknown mode")
print(json.dumps({"mode": mode, "packets": packets, "frames": frames, "pts": pts}))
