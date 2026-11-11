#!/usr/bin/env python3
"""Test harness: packs a Godot project folder into a .pck runnable by the Godot 4.4 web export template.
Scripts/scenes stay text; PNGs become .import + .ctex (GST2, embedded PNG). Not a replacement for a real Godot export."""
import hashlib, io, os, struct, sys
from pathlib import Path
from PIL import Image
root = Path(sys.argv[1]).resolve(); out = Path(sys.argv[2])
files = {}  # pck path (no res://) -> bytes
SKIP_DIRS = {".git", ".godot", "tests", "tools", "docs", "server_python", "build", "__pycache__"}
TEXT_EXT = {".gd", ".tscn", ".tres", ".json", ".cfg", ".txt", ".ttf", ".otf", ".svg"}
def ctex(png_path):
    im = Image.open(png_path).convert("RGBA"); w, h = im.size
    b = io.BytesIO(); im.save(b, "PNG"); png = b"PNG " + b.getvalue()
    hdr = b"GST2" + struct.pack("<IIIIiIII", 1, w, h, 0, -1, 0, 0, 0)
    img = struct.pack("<IHHII", 1, w, h, 0, 5) + struct.pack("<I", len(png)) + png
    return hdr + img
for p in root.rglob("*"):
    if p.is_dir(): continue
    rel = p.relative_to(root).as_posix()
    if rel.split("/")[0] in SKIP_DIRS: continue
    if p.suffix == ".import": continue
    if p.name == "project.godot": files["project.godot"] = p.read_bytes(); continue
    if p.suffix.lower() == ".png":
        h = hashlib.md5(rel.encode()).hexdigest()
        ip = f".godot/imported/{p.name}-{h}.ctex"
        files[ip] = ctex(p)
        files[rel + ".import"] = f'[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\npath="res://{ip}"\n'.encode()
        continue
    if p.suffix.lower() in TEXT_EXT: files[rel] = p.read_bytes()
names = sorted(files)
def padname(n):
    b = n.encode(); pad = (4 - len(b) % 4) % 4; return b + b"\0" * pad
table_size = 4 + sum(4 + len(padname(n)) + 8 + 8 + 16 + 4 for n in names)
header_size = 4 + 16 + 4 + 8 + 64
base = (header_size + table_size + 31) // 32 * 32
data = bytearray(); entries = bytearray(struct.pack("<I", len(names)))
for n in names:
    blob = files[n]; off = len(data); data += blob; data += b"\0" * ((32 - len(data) % 32) % 32)
    pn = padname(n)
    entries += struct.pack("<I", len(pn)) + pn + struct.pack("<QQ", off, len(blob)) + hashlib.md5(blob).digest() + struct.pack("<I", 0)
hdr = b"GDPC" + struct.pack("<IIII", 2, 4, 4, 1) + struct.pack("<IQ", 0, base) + b"\0" * 64
blob = hdr + entries; blob += b"\0" * (base - len(blob))
out.write_bytes(blob + data)
print(f"packed {len(names)} files -> {out} ({len(blob)+len(data)} bytes)")
