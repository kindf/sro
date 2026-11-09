#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_table_data.py
=================
把服务端配置表（.bytes）转成 skynet 可加载的 Lua 数据文件。

输出（简化版）：

    sro/gamedata/generated/
        allconfigfiles.lua          -- 所有表文件名
        tbscentable.lua             -- return { [id] = {Field=..., ...}, ... }

    * 文件名 = "tb" + 原表名全小写（无下划线）
    * 文件内注释保留原表名，便于对照

输入:
    config/Table/ServerBytes/*.bytes
    sro/tools/table/table_schema.json
    config/Table/CSV/**/*.csv（补列名）

用法:
    python gen_table_data.py --root F:/RO
    python gen_table_data.py --root F:/RO --only SceneTable,GlobalTable
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import math
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ro_bytes  # noqa: E402

NAME_OVERRIDE = {
    "GlobalTable": ["Key", "Value"],
}

BOOL_TYPES = {1, 101, 201, 301, 401}
IDENT = re.compile(r"^[A-Za-z_]\w*$")


# ---------------------------------------------------------------- 工具

def read_header(path: Path) -> list[str]:
    raw = path.read_bytes()
    for enc in ("utf-8-sig", "utf-8", "gbk"):
        try:
            text = raw.decode(enc)
            break
        except UnicodeDecodeError:
            continue
    else:
        text = raw.decode("latin-1")
    rows = list(csv.reader(io.StringIO(text)))
    return rows[0] if rows else []


def lua_str(s: str) -> str:
    s = s.replace("\\", "\\\\").replace('"', '\\"')
    s = s.replace("\r", "\\r").replace("\n", "\\n").replace("\t", "\\t")
    return '"' + s + '"'


def lua_key(name: str) -> str:
    return name if IDENT.match(name) else "[" + lua_str(name) + "]"


def lua_num(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        if math.isnan(v) or math.isinf(v):
            return "0.0"
        if v.is_integer():
            return f"{v:.1f}"
        return repr(v)
    return lua_str(str(v))


def lua_value(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return lua_num(v)
    if isinstance(v, list):
        return "{" + ",".join(lua_value(x) for x in v) + "}"
    return lua_str(str(v))


def to_bool(v):
    if isinstance(v, list):
        return [to_bool(x) for x in v]
    return bool(v)


def dedupe(names: list[str]) -> list[str]:
    seen: dict[str, int] = {}
    out = []
    for n in names:
        if n not in seen:
            seen[n] = 1
            out.append(n)
        else:
            seen[n] += 1
            out.append(f"{n}_{seen[n]}")
    return out


def file_name_of(table_name: str) -> str:
    return "tb" + table_name.strip().lower()


# ---------------------------------------------------------------- 构建

def build_table(name: str, root: Path, schema: dict) -> dict:
    data = ro_bytes.read_table(
        root / "config" / "Table" / "ServerBytes" / f"{name}.bytes"
    )

    by_index = {f["name_index"]: (pos, f) for pos, f in enumerate(data["fields"])}

    sch = schema.get(name)
    schema_names = {f["index"]: f["name"] for f in sch["fields"]} if sch else {}

    header = []
    if not sch:
        hits = list((root / "config" / "Table" / "CSV").rglob(f"{name}.csv"))
        if hits:
            header = read_header(hits[0])

    max_idx = max(by_index) if by_index else -1
    cols = []
    for idx in range(max_idx + 1):
        if idx not in by_index:
            continue
        pos, f = by_index[idx]
        if idx in schema_names:
            col_name = schema_names[idx]
        elif len(header) == max_idx + 1 and header[idx].strip():
            col_name = header[idx].strip()
        elif name in NAME_OVERRIDE and idx < len(NAME_OVERRIDE[name]):
            col_name = NAME_OVERRIDE[name][idx]
        else:
            col_name = f"_c{idx}"
        cols.append({"name": col_name, "index": idx, "pos": pos, "type": f["type"]})

    for c, n in zip(cols, dedupe([c["name"] for c in cols])):
        c["name"] = n

    rows = []
    for raw in data["rows"]:
        row = []
        for c in cols:
            v = raw[c["pos"]]
            if c["type"] in BOOL_TYPES:
                v = to_bool(v)
            row.append(v)
        rows.append(row)

    def is_scalar(v):
        return not isinstance(v, list)

    if not cols or not rows:
        return {
            "name": name,
            "cols": [],
            "rows": [],
            "id_pos": 0,
            "schema": bool(sch),
            "key_mode": "ordinal",
            "source": f"config/Table/ServerBytes/{name}.bytes",
            "unnamed": 0,
        }

    # 主键：优先 ID/Id/id/Key，否则第一个标量列
    id_pos = -1
    for i, c in enumerate(cols):
        if c["name"] in ("ID", "Id", "id", "Key") and is_scalar(rows[0][i]):
            id_pos = i
            break
    if id_pos < 0:
        for i in range(len(cols)):
            if is_scalar(rows[0][i]):
                id_pos = i
                break
    if id_pos < 0:
        id_pos = 0

    key_mode = "id"
    keys = [repr(r[id_pos]) for r in rows]
    if len(set(keys)) != len(keys):
        key_mode = "ordinal"

    return {
        "name": name,
        "cols": cols,
        "rows": rows,
        "id_pos": id_pos,
        "schema": bool(sch),
        "key_mode": key_mode,
        "source": f"config/Table/ServerBytes/{name}.bytes",
        "unnamed": sum(1 for c in cols if c["name"].startswith("_c")),
    }


# ---------------------------------------------------------------- 输出

def emit(table: dict, out_dir: Path, file_name: str) -> int:
    cols = table["cols"]
    rows = table["rows"]
    id_pos = table["id_pos"]
    keyed_by_id = table["key_mode"] == "id"

    lines = [
        "-- Auto-generated by sro/tools/table/gen_table_data.py. DO NOT EDIT.",
        f"-- table: {table['name']}",
        f"-- source: {table['source']}",
        f"-- rows: {len(rows)}  fields: {len(cols)}  "
        f"schema: {'yes' if table['schema'] else 'inferred'}  "
        f"unnamed: {table['unnamed']}  key: {table['key_mode']}",
        "return {",
    ]

    for i, row in enumerate(rows):
        key = row[id_pos] if keyed_by_id else i + 1
        fields = ",".join(
            f"{lua_key(c['name'])}={lua_value(v)}" for c, v in zip(cols, row)
        )
        lines.append(f"[{lua_value(key)}]={{{fields}}},")

    lines.append("}")
    text = "\n".join(lines) + "\n"
    (out_dir / f"{file_name}.lua").write_text(text, encoding="utf-8")
    return len(text)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="F:/RO")
    ap.add_argument("--out", default=None)
    ap.add_argument("--only", default=None)
    args = ap.parse_args()

    root = Path(args.root).resolve()
    out_dir = Path(args.out).resolve() if args.out else root / "sro" / "gamedata" / "generated"
    out_dir.mkdir(parents=True, exist_ok=True)

    schema = json.loads(
        (root / "sro" / "tools" / "table" / "table_schema.json").read_text(encoding="utf-8")
    )

    names = sorted(p.stem for p in (root / "config" / "Table" / "ServerBytes").glob("*.bytes"))
    if args.only:
        wanted = {x.strip() for x in args.only.split(",") if x.strip()}
        names = [n for n in names if n in wanted]

    files: list[str] = []
    used_files: dict[str, int] = {}
    total_rows = 0
    total_bytes = 0
    failed = []

    for i, name in enumerate(names, 1):
        try:
            table = build_table(name, root, schema)
        except Exception as e:  # noqa: BLE001
            failed.append((name, str(e)))
            continue
        if not table["rows"] or not table["cols"]:
            failed.append((name, "no rows/cols"))
            continue
        file_name = file_name_of(name)
        if file_name in used_files:
            # 例：RefineOrnamentTransfer / "RefineOrnamentTransfer " 小写后重名
            used_files[file_name] += 1
            file_name = f"{file_name}_{used_files[file_name]}"
        else:
            used_files[file_name] = 1
        total_bytes += emit(table, out_dir, file_name)
        total_rows += len(table["rows"])
        files.append(file_name)
        if i % 50 == 0:
            print(f"  ... {i}/{len(names)}", file=sys.stderr)

    # 所有表文件名
    alines = [
        "-- Auto-generated by sro/tools/table/gen_table_data.py. DO NOT EDIT.",
        f"-- {len(files)} tables",
        "return {",
    ]
    for f in files:
        alines.append(f'"{f}",')
    alines.append("}")
    (out_dir / "allconfigfiles.lua").write_text("\n".join(alines) + "\n", encoding="utf-8")

    print(f"tables={len(files)} rows={total_rows} lua={total_bytes/1024/1024:.1f}MB "
          f"failed={len(failed)}")
    for n, why in failed[:10]:
        print(f"  fail {n}: {why}")
    print(f"written: {out_dir}")
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
