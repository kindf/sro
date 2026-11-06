#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ro_bytes.py
===========
读取 roserver 的配置表二进制（.bytes）。

格式来自 rogamelibs/table/table_data.cpp 与 parser/*：

    int64   size                必须等于文件长度
    uint64  data_hash_value
    uint64  data_hash_time
    uint32  string_count
    string[string_count]        变长字符串（LEB128 长度 + 字节）
    uint32  field_count
    int16   bin_pos_id          -1 表示没有 bin 列
    field[field_count]:
        uint8  need_local
        uint8  field_name       列下标
        int16  type             TableTypeEnum
        uint8  seq_size
        <default value>         按 type 读一遍
    uint32  row_count
    row[row_count]:
        field_count 个值，按 head 顺序

TableTypeEnum:
    0..7    CHAR/BOOL/INT/UINT/FLOAT/DOUBLE/LONGLONG/STRING
    +100    VECTOR_*
    +200    SEQUENCE_*
    +300    VECTOR_SEQUENCE_*
    +400    VECTOR_VECTOR_*

用法:
    python ro_bytes.py --file F:/RO/config/Table/ServerBytes/GlobalTable.bytes
    python ro_bytes.py --file ... --json out.json
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

BASE = {
    0: ("char", "b", 1),
    1: ("bool", "B", 1),
    2: ("int", "i", 4),
    3: ("uint", "I", 4),
    4: ("float", "f", 4),
    5: ("double", "d", 8),
    6: ("long", "q", 8),
    7: ("string", None, 0),
}


class Reader:
    def __init__(self, data: bytes):
        self.data = data
        self.pos = 0
        self.end = len(data)

    def take(self, n: int) -> bytes:
        if self.pos + n > self.end:
            raise EOFError(f"read {n} at {self.pos}, size {self.end}")
        b = self.data[self.pos:self.pos + n]
        self.pos += n
        return b

    def unpack(self, fmt: str):
        size = struct.calcsize("<" + fmt)
        return struct.unpack("<" + fmt, self.take(size))[0]

    def u8(self):
        return self.unpack("B")

    def i8(self):
        return self.unpack("b")

    def u16(self):
        return self.unpack("H")

    def i16(self):
        return self.unpack("h")

    def u32(self):
        return self.unpack("I")

    def i32(self):
        return self.unpack("i")

    def u64(self):
        return self.unpack("Q")

    def i64(self):
        return self.unpack("q")

    def f32(self):
        return self.unpack("f")

    def f64(self):
        return self.unpack("d")

    def string(self) -> str:
        size = 0
        shift = 0
        for _ in range(5):
            b = self.u8()
            size |= (b & 0x7F) << shift
            if (b & 0x80) == 0:
                break
            shift += 7
        return self.take(size).decode("utf-8", errors="replace")


def read_value(r: Reader, typ: int, seq_size: int, strings: list[str]):
    base = typ % 100
    kind = typ // 100  # 0 scalar, 1 vector, 2 sequence, 3 vector_seq, 4 vector_vector
    name, fmt, _ = BASE[base]

    if kind == 0:
        if name == "string":
            # 标量 string 存的是 string_set 下标，不是内联字符串
            return _str_at(r, strings)
        return r.unpack(fmt)

    if kind == 1:  # vector
        n = r.u16()
        if name == "string":
            return [r.string() for _ in range(n)]
        return [r.unpack(fmt) for _ in range(n)]

    if kind == 2:  # sequence
        if name == "string":
            return [_str_at(r, strings) for _ in range(seq_size)]
        return [r.unpack(fmt) for _ in range(seq_size)]

    if kind == 3:  # vector<sequence>
        n = r.u16()
        out = []
        for _ in range(n):
            if name == "string":
                out.append([_str_at(r, strings) for _ in range(seq_size)])
            else:
                out.append([r.unpack(fmt) for _ in range(seq_size)])
        return out

    if kind == 4:  # vector<vector>
        n = r.u16()
        out = []
        for _ in range(n):
            m = r.u16()
            if name == "string":
                out.append([r.string() for _ in range(m)])
            else:
                out.append([r.unpack(fmt) for _ in range(m)])
        return out

    raise ValueError(f"unknown type {typ}")


def _str_at(r: Reader, strings: list[str]) -> str:
    idx = r.u32()
    return strings[idx] if idx < len(strings) else ""


def read_table(path: Path) -> dict:
    data = path.read_bytes()
    r = Reader(data)

    size = r.i64()
    if size != len(data):
        raise ValueError(f"size mismatch: header {size}, file {len(data)}")

    hash_value = r.u64()
    hash_time = r.u64()

    n_str = r.u32()
    strings = [r.string() for _ in range(n_str)]

    n_field = r.u32()
    if n_field > 120:
        raise ValueError(f"field_count {n_field} > 120")
    bin_pos = r.i16()

    fields = []
    for _ in range(n_field):
        need_local = r.u8()
        field_name = r.u8()
        typ = r.i16()
        seq_size = r.u8()
        default = read_value(r, typ, seq_size, strings)
        fields.append({
            "name_index": field_name,
            "type": typ,
            "seq_size": seq_size,
            "need_local": bool(need_local),
            "default": default,
        })

    n_row = r.u32()
    rows = []
    for _ in range(n_row):
        row = []
        for f in fields:
            row.append(read_value(r, f["type"], f["seq_size"], strings))
        rows.append(row)

    if r.pos != len(data):
        raise ValueError(f"trailing bytes: {len(data) - r.pos}")

    return {
        "size": size,
        "hash_value": hash_value,
        "hash_time": hash_time,
        "bin_pos": bin_pos,
        "fields": fields,
        "rows": rows,
        "strings": strings,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", required=True)
    ap.add_argument("--json", default=None)
    ap.add_argument("--limit", type=int, default=3)
    args = ap.parse_args()

    t = read_table(Path(args.file))
    print(f"fields={len(t['fields'])} rows={len(t['rows'])} strings={len(t['strings'])} "
          f"bin_pos={t['bin_pos']}")
    for f in t["fields"][:12]:
        print(f"  col {f['name_index']:3d} type={f['type']:4d} seq={f['seq_size']} "
              f"local={f['need_local']} default={f['default']!r}")
    for row in t["rows"][:args.limit]:
        print("  row:", row[:12])

    if args.json:
        Path(args.json).write_text(
            json.dumps(t, ensure_ascii=False, indent=1), encoding="utf-8"
        )
        print("written:", args.json)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
