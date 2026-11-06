#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
scan_tables.py
==============
配置表资产盘点：把三套来源对到一起，回答“哪张表能从哪拿数据”。

来源:
    A. config/LuaServer/Table/*.lua        —— 运行时访问器（ProtoGen 生成，非数据）
    B. config/Table/CSV/**/*.csv           —— 策划导出 CSV（3 行表头：字段/注释/数据）
    C. config/Table/ServerBytes/*.bytes    —— 服务端二进制（4 字节长度头 + 数据）
    D. roserver/exe/gsconf/rogameslib_table/*.bytes —— 线上实际加载的二进制

输出:
    table_inventory.csv    每张表一行，标出四套来源是否存在
    table_inventory.md     人读的汇总
    table_stats.txt        统计

用法:
    python scan_tables.py --root F:/RO
"""

from __future__ import annotations

import argparse
import csv
import io
import struct
import sys
from collections import Counter
from pathlib import Path

HEADER_ROWS = 2  # 字段行 + 注释行


def read_text(path: Path) -> str:
    raw = path.read_bytes()
    for enc in ("utf-8-sig", "utf-8", "gbk"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return raw.decode("latin-1")


def scan_lua(root: Path) -> dict[str, dict]:
    out: dict[str, dict] = {}
    d = root / "config" / "LuaServer" / "Table"
    for f in sorted(d.glob("*.lua")):
        text = f.read_text(encoding="latin-1", errors="replace")
        if "TableDataMgrLuaProxy" in text or "TableDataLuaProxy" in text:
            kind = "accessor"
        elif "module(" in text:
            kind = "module"
        else:
            kind = "plain"
        out[f.stem] = {
            "lua": True,
            "lua_kind": kind,
            "lua_size": f.stat().st_size,
            "lua_module": "module(" in text,
            "lua_proxy": "ROGameLibs." in text,
        }
    return out


def scan_csv(root: Path) -> tuple[dict[str, dict], list[str]]:
    out: dict[str, dict] = {}
    dups: list[str] = []
    d = root / "config" / "Table" / "CSV"
    for f in sorted(d.rglob("*.csv")):
        key = f.stem
        try:
            rows = list(csv.reader(io.StringIO(read_text(f))))
        except Exception as e:  # noqa: BLE001
            rows = []
            print(f"WARN csv parse failed {f}: {e}", file=sys.stderr)

        cols = len(rows[0]) if rows else 0
        data_rows = max(0, len(rows) - HEADER_ROWS)
        rel = f.relative_to(root).as_posix()
        if key in out:
            dups.append(f"{key}: {out[key]['csv_path']} | {rel}")
            # 保留行数更多的那个
            if data_rows <= out[key]["csv_rows"]:
                continue
        out[key] = {
            "csv": True,
            "csv_path": rel,
            "csv_rows": data_rows,
            "csv_cols": cols,
            "csv_size": f.stat().st_size,
        }
    return out, dups


def scan_bytes(path: Path) -> dict[str, dict]:
    out: dict[str, dict] = {}
    if not path.is_dir():
        return out
    for f in sorted(path.glob("*.bytes")):
        size = f.stat().st_size
        head = f.read_bytes()[:4]
        ok = len(head) == 4 and struct.unpack("<I", head)[0] == size
        out[f.stem] = {"size": size, "header_ok": ok}
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="F:/RO")
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    root = Path(args.root).resolve()
    out_dir = Path(args.out).resolve() if args.out else Path(__file__).resolve().parent
    out_dir.mkdir(parents=True, exist_ok=True)

    lua = scan_lua(root)
    csv_map, dup_csv = scan_csv(root)
    srv = scan_bytes(root / "config" / "Table" / "ServerBytes")
    game = scan_bytes(root / "roserver" / "exe" / "gsconf" / "rogameslib_table")

    keys = sorted(set(lua) | set(csv_map) | set(srv) | set(game))
    rows = []
    for k in keys:
        l = lua.get(k, {})
        c = csv_map.get(k, {})
        s = srv.get(k, {})
        g = game.get(k, {})
        rows.append({
            "table": k,
            "lua": int(bool(l)),
            "lua_kind": l.get("lua_kind", ""),
            "lua_module": int(bool(l.get("lua_module"))),
            "lua_proxy": int(bool(l.get("lua_proxy"))),
            "csv": int(bool(c)),
            "csv_path": c.get("csv_path", ""),
            "csv_rows": c.get("csv_rows", ""),
            "csv_cols": c.get("csv_cols", ""),
            "csv_size": c.get("csv_size", ""),
            "server_bytes": int(bool(s)),
            "server_bytes_size": s.get("size", ""),
            "game_bytes": int(bool(g)),
            "game_bytes_size": g.get("size", ""),
            "notes": "",
        })

    # 统计
    total = len(rows)
    both_data = sum(1 for r in rows if r["csv"] and r["server_bytes"])
    csv_only = sum(1 for r in rows if r["csv"] and not r["server_bytes"])
    bytes_only = sum(1 for r in rows if r["server_bytes"] and not r["csv"])
    lua_only = sum(1 for r in rows if r["lua"] and not r["csv"] and not r["server_bytes"])
    all_three = sum(1 for r in rows if r["lua"] and r["csv"] and r["server_bytes"])
    kinds = Counter(r["lua_kind"] for r in rows if r["lua"])

    stats = [
        "== 配置表资产盘点 ==",
        f"表名总数            : {total}",
        f"Lua 访问器          : {sum(1 for r in rows if r['lua'])}",
        f"CSV                 : {sum(1 for r in rows if r['csv'])}",
        f"ServerBytes         : {sum(1 for r in rows if r['server_bytes'])}",
        f"GameBytes           : {sum(1 for r in rows if r['game_bytes'])}",
        f"三套齐全            : {all_three}",
        f"CSV + Bytes         : {both_data}",
        f"只有 CSV            : {csv_only}",
        f"只有 Bytes          : {bytes_only}",
        f"只有 Lua（无数据）  : {lua_only}",
        f"CSV 重名            : {len(dup_csv)}",
        "",
        "== Lua 类型 ==",
    ]
    for k, v in kinds.most_common():
        stats.append(f"{k:12s} {v}")
    stats += ["", "== CSV 重名 =="] + (dup_csv or ["(none)"])

    with (out_dir / "table_inventory.csv").open("w", encoding="utf-8-sig", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    (out_dir / "table_stats.txt").write_text("\n".join(stats) + "\n", encoding="utf-8-sig")

    # Markdown 汇总
    biggest = sorted(
        (r for r in rows if r["csv"]),
        key=lambda r: r["csv_rows"] if isinstance(r["csv_rows"], int) else 0,
        reverse=True,
    )[:20]
    md = [
        "# 配置表资产盘点",
        "",
        f"- 表名总数：**{total}**",
        f"- Lua 访问器：**{sum(1 for r in rows if r['lua'])}**（其中 {kinds.get('accessor', 0)} 个是 C++ Proxy 访问器，不是数据）",
        f"- CSV：**{sum(1 for r in rows if r['csv'])}**",
        f"- ServerBytes：**{sum(1 for r in rows if r['server_bytes'])}**",
        f"- 三套齐全：**{all_three}**；只有 CSV：{csv_only}；只有 Bytes：{bytes_only}；只有 Lua：{lua_only}",
        "",
        "## 行数 Top 20（CSV）",
        "",
        "| 表 | 行 | 列 | CSV 大小 | 有 Bytes |",
        "|---|---:|---:|---:|---|",
    ]
    for r in biggest:
        md.append(f"| {r['table']} | {r['csv_rows']} | {r['csv_cols']} | "
                  f"{r['csv_size']} | {r['server_bytes']} |")
    (out_dir / "table_inventory.md").write_text("\n".join(md) + "\n", encoding="utf-8-sig")

    print(f"tables={total} lua={sum(1 for r in rows if r['lua'])} "
          f"csv={sum(1 for r in rows if r['csv'])} "
          f"bytes={sum(1 for r in rows if r['server_bytes'])} "
          f"all3={all_three} csv_only={csv_only} bytes_only={bytes_only} lua_only={lua_only}")
    print(f"written: {out_dir/'table_inventory.csv'}")
    print(f"written: {out_dir/'table_inventory.md'}")
    print(f"written: {out_dir/'table_stats.txt'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
