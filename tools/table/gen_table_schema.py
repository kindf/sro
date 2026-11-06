#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_table_schema.py
===================
从 Lua 访问器里提取配置表 schema。

背景:
    config/LuaServer/Table/*.lua 不是数据，是 ProtoGen 生成的“访问器”：
        local _GetSceneType = function(rowPoint)
            return ROGameLibs.RowDataLuaProxy:GetValueUInt(rowPoint, 1)
        end
    每个 getter 同时给出了三件事：
        字段名、字段类型、字段在服务器行里的下标

    这正是 CSV -> Lua 转换所需要的 schema，不需要猜类型。

输出:
    table_schema.json    { table: { fields:[{name,type,index,csv_col}], ... } }
    table_schema.md      人读汇总
    table_schema_stats.txt

用法:
    python gen_table_schema.py --root F:/RO
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import re
import sys
from collections import Counter
from pathlib import Path

RE_GETTER = re.compile(
    r"_Get(\w+)\s*=\s*function\s*\(\s*rowPoint\s*\).*?"
    r"RowDataLuaProxy:(GetValue\w+)\s*\(\s*rowPoint\s*,\s*(\d+)\s*\)",
    re.S,
)

TYPE_SUFFIX = [
    ("VectorVector", "vv"),
    ("SequenceVector", "sv"),
    ("Vector", "v"),
    ("Sequence", "s"),
]
TYPE_BASE = {
    "Char": "char",
    "Bool": "bool",
    "Int": "int",
    "UInt": "uint",
    "Long": "long",
    "Float": "float",
    "Double": "double",
    "String": "string",
}


def norm(name: str) -> str:
    return re.sub(r"[^a-z0-9]", "", name.lower())


def parse_type(raw: str) -> str:
    """GetValueUIntSequenceVector -> sv<uint>"""
    body = raw[len("GetValue"):] if raw.startswith("GetValue") else raw
    for suffix, prefix in TYPE_SUFFIX:
        if body.endswith(suffix):
            base = body[: -len(suffix)]
            return f"{prefix}<{TYPE_BASE.get(base, base.lower())}>"
    return TYPE_BASE.get(body, body.lower())


def read_csv_header(path: Path) -> list[str]:
    raw = path.read_bytes()
    for enc in ("utf-8-sig", "utf-8", "gbk"):
        try:
            text = raw.decode(enc)
            break
        except UnicodeDecodeError:
            continue
    else:
        text = raw.decode("latin-1")
    try:
        rows = list(csv.reader(io.StringIO(text)))
    except Exception:  # noqa: BLE001
        return []
    return rows[0] if rows else []


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="F:/RO")
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    root = Path(args.root).resolve()
    out_dir = Path(args.out).resolve() if args.out else Path(__file__).resolve().parent
    out_dir.mkdir(parents=True, exist_ok=True)

    table_dir = root / "config" / "LuaServer" / "Table"
    csv_dir = root / "config" / "Table" / "CSV"

    schema: dict[str, dict] = {}
    errors: list[str] = []
    type_counter: Counter[str] = Counter()
    no_proxy: list[str] = []

    for f in sorted(table_dir.glob("*.lua")):
        text = f.read_text(encoding="latin-1", errors="replace")
        if "RowDataLuaProxy" not in text:
            continue

        fields = []
        for m in RE_GETTER.finditer(text):
            name, raw_type, index = m.group(1), m.group(2), int(m.group(3))
            fields.append({
                "name": name,
                "type": parse_type(raw_type),
                "index": index,
                "raw_type": raw_type,
                "csv_col": None,
            })
        if not fields:
            no_proxy.append(f.stem)
            continue

        fields.sort(key=lambda x: x["index"])
        # 下标必须从 0 连续递增，否则访问器形状异常
        indexes = [x["index"] for x in fields]
        if indexes != list(range(len(fields))):
            errors.append(f"{f.stem}: index 不连续 {indexes[:12]}")

        # 与 CSV 表头按名字对齐（CSV 可能多出 Comment 等策划列）
        csv_path = None
        candidates = list(csv_dir.rglob(f"{f.stem}.csv"))
        if candidates:
            csv_path = candidates[0]
            header = read_csv_header(csv_path)
            by_norm = {norm(h): i for i, h in enumerate(header)}
            for fld in fields:
                fld["csv_col"] = by_norm.get(norm(fld["name"]))
                if fld["csv_col"] is None:
                    errors.append(f"{f.stem}: CSV 缺列 {fld['name']}")
            extras = [h for h in header if norm(h) not in {norm(x['name']) for x in fields}]
        else:
            extras = []

        schema[f.stem] = {
            "source": f.relative_to(root).as_posix(),
            "csv": csv_path.relative_to(root).as_posix() if csv_path else None,
            "field_count": len(fields),
            "csv_cols": len(header) if csv_path else None,
            "extra_csv_cols": extras,
            "fields": fields,
        }
        for fld in fields:
            type_counter[fld["type"]] += 1

    (out_dir / "table_schema.json").write_text(
        json.dumps(schema, ensure_ascii=False, indent=1), encoding="utf-8"
    )

    total_fields = sum(v["field_count"] for v in schema.values())
    with_csv = sum(1 for v in schema.values() if v["csv"])
    mismatch = sorted({e.split(":")[0] for e in errors if "CSV 缺列" in e})

    stats = [
        "== 表 schema ==",
        f"解析表数        : {len(schema)}",
        f"字段总数        : {total_fields}",
        f"有 CSV 的表     : {with_csv}",
        f"CSV 缺列的表    : {len(mismatch)}",
        f"无 Proxy 的文件 : {len(no_proxy)}",
        "",
        "== 字段类型分布 ==",
    ]
    for k, v in type_counter.most_common():
        stats.append(f"{k:14s} {v}")
    stats += ["", "== CSV 缺列 =="] + (mismatch[:50] or ["(none)"])
    stats += ["", "== 异常 =="] + (errors[:50] or ["(none)"])
    (out_dir / "table_schema_stats.txt").write_text("\n".join(stats) + "\n", encoding="utf-8-sig")

    print(f"tables={len(schema)} fields={total_fields} with_csv={with_csv} "
          f"csv_missing={len(mismatch)} errors={len(errors)}")
    print(f"written: {out_dir/'table_schema.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
