#!/usr/bin/env python3
"""Searches a Godot 4.3 .pck export for strings that must be absent from a release (spec 21).

The PCK file table is read and each entry is searched on its own:
- every file name is searched for every needle;
- compiled scripts (.gdc) are zstd-compressed, so they are decompressed with the system libzstd
  (through ctypes) first; a needle counts when it occurs as a string or name in the script;
- text entries (.gd, .tscn, .tres, .cfg, .json, ...) are searched as plain text;
- every other entry (binary scenes and resources, textures, audio) is searched for the needle
  stored the way Godot stores strings: a 32-bit little-endian length followed by the UTF-8 bytes.
  A raw search would find two-letter needles such as F9 by chance inside binary data, so that
  form is not used for them.

Usage: pck_strings.py <file.pck> <needle> [<needle> ...]
Exit 0: no needle found. Exit 1: a needle was found (FOUND lines). Exit 2: the file is not a readable
PCK. Exit 3: the compiled scripts cannot be decompressed (libzstd is not available), so nothing is claimed.
"""
import ctypes
import ctypes.util
import struct
import sys

PCK_MAGIC = 0x43504447  # "GDPC"
ZSTD_MAGIC = b"\x28\xb5\x2f\xfd"
TEXT_SUFFIXES = (
    ".gd", ".tscn", ".tres", ".cfg", ".json", ".shader", ".gdshader",
    ".remap", ".import", ".uid", ".md", ".txt", ".godot", ".ini", ".csv", ".xml",
)
RAW_NEEDLE_MIN = 6


class LibzstdMissing(Exception):
    pass


def load_libzstd():
    candidates = ["libzstd.so.1", "libzstd.so", ctypes.util.find_library("zstd")]
    for name in candidates:
        if not name:
            continue
        try:
            lib = ctypes.CDLL(name)
        except OSError:
            continue
        lib.ZSTD_decompress.restype = ctypes.c_size_t
        lib.ZSTD_decompress.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t]
        lib.ZSTD_isError.restype = ctypes.c_uint
        lib.ZSTD_isError.argtypes = [ctypes.c_size_t]
        return lib
    raise LibzstdMissing("libzstd was not found")


def gdc_source(blob: bytes, lib) -> bytes:
    """A compiled script: 'GDSC', a version word, the uncompressed size, then a zstd frame."""
    if blob[:4] != b"GDSC":
        raise ValueError("not a compiled GDScript")
    size = struct.unpack_from("<I", blob, 8)[0]
    body = blob[12:]
    if body[:4] != ZSTD_MAGIC:
        raise ValueError("compiled GDScript without a zstd frame")
    out = ctypes.create_string_buffer(size)
    n = lib.ZSTD_decompress(out, size, body, len(body))
    if lib.ZSTD_isError(n) or n != size:
        raise ValueError("zstd decompression failed")
    return out.raw[:n]


def read_entries(data: bytes):
    """Returns [(path, absolute_offset, size)] from the PCK header and file table."""
    magic, version, _major, _minor, _rev, _pack_flags = struct.unpack_from("<6I", data, 0)
    if magic != PCK_MAGIC:
        raise ValueError("not a PCK file (bad magic)")
    if version != 2:
        raise ValueError("unsupported PCK format version %d" % version)
    file_base = struct.unpack_from("<Q", data, 24)[0]
    off = 32 + 16 * 4  # 16 reserved words
    count = struct.unpack_from("<I", data, off)[0]
    off += 4
    entries = []
    for _ in range(count):
        length = struct.unpack_from("<I", data, off)[0]
        off += 4
        path = data[off:off + length].split(b"\0")[0].decode("utf-8")
        off += length
        ofs, size = struct.unpack_from("<QQ", data, off)
        off += 16 + 16 + 4  # offset and size, md5, per-file flags
        if not path.startswith("res://") or file_base + ofs + size > len(data):
            raise ValueError("file table does not parse (entry %d: %r)" % (len(entries), path))
        entries.append((path, file_base + ofs, size))
    return entries


def hits_in(path: str, content: bytes, needle: str, lib) -> bool:
    raw = needle.encode("utf-8")
    if path.endswith(TEXT_SUFFIXES):
        return raw in content
    body = gdc_source(content, lib) if path.endswith(".gdc") else content
    if len(raw) >= RAW_NEEDLE_MIN and raw in body:
        return True
    return struct.pack("<I", len(raw)) + raw in body


def main(argv):
    if len(argv) < 3:
        print("usage: pck_strings.py <file.pck> <needle> [<needle> ...]")
        return 2
    try:
        with open(argv[1], "rb") as f:
            data = f.read()
        entries = read_entries(data)
    except (OSError, ValueError, struct.error) as err:
        print("PCK UNREADABLE: %s" % err)
        return 2
    try:
        lib = load_libzstd()
    except LibzstdMissing as err:
        print("PCK NOT CHECKED: %s, so compiled scripts cannot be read" % err)
        return 3
    needles = argv[2:]
    found = 0
    for path, start, size in entries:
        content = data[start:start + size]
        for needle in needles:
            if needle in path:
                print("FOUND   '%s' in the file name %s" % (needle, path))
                found += 1
            elif hits_in(path, content, needle, lib):
                print("FOUND   '%s' in %s" % (needle, path))
                found += 1
    print("PCK: %d entries (%d compiled scripts), %d needle(s), %d hit(s)" % (
        len(entries), sum(1 for e in entries if e[0].endswith(".gdc")), len(needles), found))
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
