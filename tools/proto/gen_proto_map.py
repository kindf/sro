#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_proto_map.py
================
扫描 RO 服务端的协议头文件，生成 skynet 侧可直接 require 的协议映射表。

数据源:
    <root>/roserver/protocol/**/*.h

输出:
    <out>/proto_map.lua      id -> {name, cls, kind, req, res, from, to, flags}
    <out>/proto_map.csv      人类可读，给测试/策划
    <out>/proto_stats.txt    统计与自检报告

用法:
    python gen_proto_map.py                      # 默认扫描 F:/RO，输出到脚本所在目录
    python gen_proto_map.py --root F:/RO --check

说明:
    * 头文件是 GBK，但本工具只解析 ASCII 片段，因此按 latin-1 读取，避免中文注释解码失败。
    * RPC 的请求/应答取自头文件的 OnCall 签名（覆盖率 100%），
      .cpp 里的 RPC_SERVER_IMPLEMETION 只用于交叉校验。
    * 协议号方向优先取 id 高字节；老协议（id < 0x01000000）回退到名字前缀。
    * 本文件生成的是“老 C++ 服务端协议表”，与 sro/proto/proto_map.lua（新 sro 协议注册表）
      是两套东西，模块名不要混用。
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from collections import Counter
from pathlib import Path

# ---------------------------------------------------------------- 解析规则

RE_DEFINE = re.compile(r"#define\s+([A-Za-z_]\w*)_TYPE\s+(\d+)")
RE_CLASS = re.compile(r"class\s+(\w+)\s*:\s*public\s+(CRpc|CProtocol)\b")
RE_PTC_DATA = re.compile(r"KKSG::(\w+)\s+m_Data\s*;")
RE_RPC_CALL = re.compile(r"OnCall\s*\(\s*const\s+(\w+)\s*&[^,]*,\s*(\w+)\s*&")
RE_RPC_IMPL = re.compile(
    r"RPC_(?:SERVER|CLIENT)_IMPLEMETION\s*\(\s*(\w+)\s*,\s*(\w+)\s*,\s*(\w+)\s*\)"
)
RE_NAME_DIR = re.compile(r"^(?:PTC|RPC)([A-Z])2([A-Z])_")

# 方向码。只写有证据的；其余保留字母，不做臆测。
DIR_NAME = {
    "C": "client",
    "G": "gameserver",
    "T": "gateserver",
    "M": "masterserver",
    "N": "nameserver",
    "D": "dbserver",
    "R": "routerserver",
    "K": "worldserver",
    "A": "audioserver",
    "B": "battleserver",
    "E": "payserver",
    "F": "fmserver",
    "I": "idipserver",
    "L": "logserver",
    "P": "proxyserver",
}

KIND_PTC = 1
KIND_RPC = 2
KIND_NAME = {KIND_PTC: "ptc", KIND_RPC: "rpc"}

FLAG_EMPTY = 1 << 0
FLAG_CLIENT = 1 << 1

# 走游戏网关的客户端方向
GATE_DIRS = {("C", "G"), ("G", "C"), ("C", "T"), ("T", "C")}


def resolve_direction(pid: int, name: str) -> tuple[str, str, str]:
    """返回 (from, to, 来源)。来源: id / name / unknown。"""
    if pid >= 0x01000000:
        frm = chr((pid >> 24) & 0xFF)
        to = chr((pid >> 16) & 0xFF)
        if frm.isalpha() and to.isalpha():
            return frm, to, "id"

    m = RE_NAME_DIR.match(name)
    if m:
        return m.group(1), m.group(2), "name"
    return "?", "?", "unknown"


def parse_header(path: Path, root: Path) -> dict | None:
    """解析单个头文件；不合法则返回 None。"""
    text = path.read_bytes().decode("latin-1")

    m = RE_DEFINE.search(text)
    if not m:
        return None
    name, pid = m.group(1), int(m.group(2))

    c = RE_CLASS.search(text)
    if not c:
        return None
    cls, base = c.group(1), c.group(2)
    kind = KIND_RPC if base == "CRpc" else KIND_PTC

    req = None
    res = None
    empty = False

    if kind == KIND_RPC:
        call = RE_RPC_CALL.search(text)
        if call:
            req, res = call.group(1), call.group(2)
    else:
        data = RE_PTC_DATA.search(text)
        if data:
            req = data.group(1)
        else:
            empty = True

    frm, to, dir_src = resolve_direction(pid, name)

    flags = 0
    if empty:
        flags |= FLAG_EMPTY
    if frm == "C" or to == "C":
        flags |= FLAG_CLIENT

    return {
        "id": pid,
        "name": name,
        "cls": cls,
        "kind": kind,
        "req": ("KKSG." + req) if req else None,
        "res": ("KKSG." + res) if res else None,
        "from": frm,
        "to": to,
        "dir_src": dir_src,
        "flags": flags,
        "empty": empty,
        "file": path.relative_to(root).as_posix(),
    }


def scan(root: Path) -> tuple[list[dict], list[str], int]:
    proto_dir = root / "roserver" / "protocol"
    if not proto_dir.is_dir():
        raise SystemExit(f"找不到协议目录: {proto_dir}")

    entries: list[dict] = []
    warnings: list[str] = []

    for path in sorted(proto_dir.rglob("*.h")):
        entry = parse_header(path, root)
        if entry is None:
            warnings.append(f"跳过（无法识别）: {path.relative_to(root).as_posix()}")
            continue
        entries.append(entry)

    # 交叉校验：.cpp 里的 RPC 实现宏
    impl = 0
    impl_dir = root / "roserver" / "gameserver" / "protocol"
    if impl_dir.is_dir():
        for path in impl_dir.rglob("*.cpp"):
            impl += len(RE_RPC_IMPL.findall(path.read_bytes().decode("latin-1")))

    entries.sort(key=lambda e: e["id"])
    return entries, warnings, impl


def validate(entries: list[dict], warnings: list[str], impl_count: int) -> dict:
    ids = [e["id"] for e in entries]
    dup = [i for i, n in Counter(ids).items() if n > 1]

    rpc = [e for e in entries if e["kind"] == KIND_RPC]
    ptc = [e for e in entries if e["kind"] == KIND_PTC]
    empty = [e for e in entries if e["empty"]]
    client = [e for e in entries if e["flags"] & FLAG_CLIENT]
    client_gate = [e for e in entries if (e["from"], e["to"]) in GATE_DIRS]
    legacy = [e for e in entries if e["dir_src"] == "name"]
    unknown = [e for e in entries if e["dir_src"] == "unknown"]

    errors = []
    if dup:
        errors.append(f"协议号重复: {dup[:10]}")

    rpc_missing = [e["name"] for e in rpc if not e["req"] or not e["res"]]
    if rpc_missing:
        errors.append(f"RPC 缺 req/res: {rpc_missing[:10]}")

    ptc_missing = [e["name"] for e in ptc if not e["req"] and not e["empty"]]
    if ptc_missing:
        errors.append(f"PTC 缺 payload 且非空包: {ptc_missing[:10]}")

    client_missing = [e["name"] for e in client if not e["req"] and not e["empty"]]
    if client_missing:
        errors.append(f"客户端协议缺 req: {client_missing[:10]}")

    name_mismatch = [e["name"] for e in entries if e["cls"].upper() != e["name"]]
    if name_mismatch:
        warnings.append(f"类名与协议名不一致 {len(name_mismatch)} 个: {name_mismatch[:5]}")
    if unknown:
        warnings.append(f"无法判定方向 {len(unknown)} 个: {[e['name'] for e in unknown][:5]}")

    return {
        "total": len(entries),
        "ptc": len(ptc),
        "rpc": len(rpc),
        "empty": len(empty),
        "client": len(client),
        "client_gate": len(client_gate),
        "legacy": len(legacy),
        "unknown": len(unknown),
        "impl": impl_count,
        "by_dir": Counter(f'{e["from"]}->{e["to"]}' for e in entries),
        "by_module": Counter(
            e["file"].split("/")[2] if e["file"].count("/") >= 2 else "root"
            for e in entries
        ),
        "empty_list": sorted(e["name"] for e in empty),
        "legacy_list": sorted(e["name"] for e in legacy),
        "reused": reused_messages(entries),
        "errors": errors,
        "warnings": warnings,
    }


def reused_messages(entries: list[dict]) -> list[tuple[str, int]]:
    counter = Counter(e["req"] for e in entries if e["req"])
    return sorted(((k, v) for k, v in counter.items() if v > 1), key=lambda x: -x[1])


# ---------------------------------------------------------------- 输出

def emit_lua(entries: list[dict], stats: dict, out: Path) -> None:
    lines = [
        "-- Auto-generated by sro/tools/proto/gen_proto_map.py. DO NOT EDIT.",
        "-- source: roserver/protocol/**/*.h",
        f"-- total={stats['total']} ptc={stats['ptc']} rpc={stats['rpc']} "
        f"empty={stats['empty']} client={stats['client']} client_gate={stats['client_gate']}",
        "-- fields: name, cls, kind(1=ptc 2=rpc), req, res, from, to, flags(bit0=empty bit1=client)",
        "return {",
    ]
    for e in entries:
        req = f'"{e["req"]}"' if e["req"] else "false"
        res = f'"{e["res"]}"' if e["res"] else "false"
        lines.append(
            f'[{e["id"]}]={{"{e["name"]}","{e["cls"]}",{e["kind"]},'
            f'{req},{res},"{e["from"]}","{e["to"]}",{e["flags"]}}},'
        )
    lines.append("}")
    (out / "proto_map.lua").write_text("\n".join(lines) + "\n", encoding="utf-8")


def emit_csv(entries: list[dict], out: Path) -> None:
    with (out / "proto_map.csv").open("w", encoding="utf-8-sig", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow([
            "id", "hex", "name", "cls", "kind", "from", "to",
            "client_facing", "empty", "dir_src", "req", "res", "file",
        ])
        for e in entries:
            writer.writerow([
                e["id"], f'0x{e["id"]:08X}', e["name"], e["cls"],
                KIND_NAME[e["kind"]], e["from"], e["to"],
                int(bool(e["flags"] & FLAG_CLIENT)), int(e["empty"]),
                e["dir_src"], e["req"] or "", e["res"] or "", e["file"],
            ])


def emit_stats(stats: dict, out: Path) -> None:
    lines = [
        "== 协议清单统计 ==",
        f"总数          : {stats['total']}",
        f"PTC           : {stats['ptc']}",
        f"RPC           : {stats['rpc']}",
        f"空包 PTC      : {stats['empty']}",
        f"客户端协议    : {stats['client']}",
        f"走游戏网关    : {stats['client_gate']}（C<->G / C<->T）",
        f"老协议(名字判): {stats['legacy']}",
        f"方向未知      : {stats['unknown']}",
        f"RPC 实现宏    : {stats['impl']}",
        "",
        "== 按方向 ==",
    ]
    for k, v in sorted(stats["by_dir"].items(), key=lambda x: -x[1]):
        frm, to = k.split("->")
        lines.append(f"{k:8s} {v:5d}   ({DIR_NAME.get(frm, '?')} -> {DIR_NAME.get(to, '?')})")

    lines += ["", "== 客户端协议细分 =="]
    for k, v in sorted(stats["by_dir"].items(), key=lambda x: -x[1]):
        if "C" in k:
            lines.append(f"{k:8s} {v:5d}")

    lines += ["", "== 按模块 Top 15 =="]
    for k, v in stats["by_module"].most_common(15):
        lines.append(f"{k:20s} {v:5d}")

    lines += ["", f"== 空包 PTC（{len(stats['empty_list'])}）=="]
    lines += stats["empty_list"]

    lines += ["", f"== 老协议，方向取自名字前缀（{len(stats['legacy_list'])}）=="]
    lines += stats["legacy_list"]

    lines += ["", f"== 复用消息（同一 pb 消息被多个协议引用，{len(stats['reused'])}）=="]
    for name, count in stats["reused"][:30]:
        lines.append(f"{name:40s} {count}")

    lines += ["", "== 自检 =="]
    if stats["errors"]:
        lines += [f"ERROR: {e}" for e in stats["errors"]]
    else:
        lines.append("OK: id 唯一，RPC req/res 完整，客户端协议 req 完整")
    for w in stats["warnings"]:
        lines.append(f"WARN: {w}")

    (out / "proto_stats.txt").write_text("\n".join(lines) + "\n", encoding="utf-8-sig")


def print_summary(stats: dict) -> None:
    """控制台输出保持 ASCII，避免 Windows 代码页乱码。"""
    print(
        f"total={stats['total']} ptc={stats['ptc']} rpc={stats['rpc']} "
        f"empty={stats['empty']} client={stats['client']} "
        f"client_gate={stats['client_gate']} legacy={stats['legacy']} "
        f"unknown={stats['unknown']} impl={stats['impl']}"
    )
    for k, v in sorted(stats["by_dir"].items(), key=lambda x: -x[1])[:10]:
        print(f"  {k:6s} {v}")


# ---------------------------------------------------------------- main

def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

    parser = argparse.ArgumentParser(description="生成 RO 协议映射表")
    parser.add_argument("--root", default="F:/RO", help="仓库根目录")
    parser.add_argument("--out", default=None, help="输出目录，默认脚本所在目录")
    parser.add_argument("--check", action="store_true", help="只做自检，不写文件")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    out = Path(args.out).resolve() if args.out else Path(__file__).resolve().parent
    out.mkdir(parents=True, exist_ok=True)

    entries, warnings, impl_count = scan(root)
    stats = validate(entries, warnings, impl_count)
    print_summary(stats)

    if args.check:
        return 1 if stats["errors"] else 0

    emit_lua(entries, stats, out)
    emit_csv(entries, out)
    emit_stats(stats, out)

    print(f"written: {out / 'proto_map.lua'}")
    print(f"written: {out / 'proto_map.csv'}")
    print(f"written: {out / 'proto_stats.txt'}")
    return 1 if stats["errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
